/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Built without GNUstep's headers: see the GNUmakefile.
 */

#include "wlan_mig_types.h"

#include <mach/mach.h>
#include <servers/bootstrap.h>

#include "wlanUser.h"			/* MIG user stubs, made by the build */

#include <stdint.h>
#include <string.h>
#include <strings.h>

#include "NWWiFi.h"

#define NWWiFiServiceName "org.nextbsd.wlan"

static mach_port_t
NWWiFiPort (void)
{
  mach_port_t port = MACH_PORT_NULL;

  if (bootstrap_look_up (bootstrap_port, NWWiFiServiceName, &port)
      != KERN_SUCCESS)
    return MACH_PORT_NULL;
  return port;
}

static void
NWWiFiRelease (mach_port_t port)
{
  if (port != MACH_PORT_NULL)
    (void) mach_port_deallocate (mach_task_self (), port);
}

/* A string into a fixed wire field, zero-filled; 0 if it doesn't fit. */
static int
NWWiFiField (char *field, size_t size, const char *s)
{
  memset (field, 0, size);
  if (s == NULL)
    return 1;
  return strlcpy (field, s, size) < size;
}

int
NWWiFiInterfaces (char names[][16], int max)
{
  mach_port_t port = NWWiFiPort ();
  int count = 0, i, n = 0;

  if (port == MACH_PORT_NULL)
    return 0;
  if (wlan_if_count (port, &count) != KERN_SUCCESS)
    count = 0;
  for (i = 0; i < count && n < max; i++)
    {
      WLANInterfaceName name;
      wlan_status_t st;

      if (wlan_if_name (port, i, name, &st) != KERN_SUCCESS
          || st != wlan_status_success_e)
        continue;
      name[sizeof (name) - 1] = '\0';
      strlcpy (names[n++], name, 16);
    }
  NWWiFiRelease (port);
  return n;
}

int
NWWiFiScan (const char *interface, unsigned *generation)
{
  mach_port_t port;
  WLANInterfaceName name;
  wlan_status_t st = wlan_status_internal_error_e;
  uint32_t baseline = 0;
  boolean_t failed;

  *generation = 0;
  if (!NWWiFiField (name, sizeof (name), interface))
    return wlan_status_invalid_parameter_e;
  port = NWWiFiPort ();
  if (port == MACH_PORT_NULL)
    return NWWiFiUnavailable;
  /* Read this before asking, so only a sweep that ends later counts
     (wlan(8) does the same). */
  if (wlan_scan_generation (port, name, &baseline, &failed, &st)
      != KERN_SUCCESS)
    st = NWWiFiUnavailable;
  else if (st == wlan_status_success_e
           && wlan_scan (port, name, &st) != KERN_SUCCESS)
    st = NWWiFiUnavailable;
  NWWiFiRelease (port);
  *generation = baseline;
  return st;
}

int
NWWiFiScanFinished (const char *interface, unsigned generation, int *failed)
{
  mach_port_t port;
  WLANInterfaceName name;
  wlan_status_t st;
  uint32_t now = 0;
  boolean_t f = FALSE;
  int result = -1;

  *failed = 0;
  if (!NWWiFiField (name, sizeof (name), interface))
    return -1;
  port = NWWiFiPort ();
  if (port == MACH_PORT_NULL)
    return -1;
  if (wlan_scan_generation (port, name, &now, &f, &st) == KERN_SUCCESS
      && st == wlan_status_success_e)
    {
      /* Signed difference: right across a counter wrap. */
      result = (int32_t) (now - generation) > 0;
      *failed = result && f;
    }
  NWWiFiRelease (port);
  return result;
}

int
NWWiFiScanResults (const char *interface, NWNetwork *networks, int max)
{
  mach_port_t port;
  WLANInterfaceName name;
  wlan_status_t st;
  int count = 0, i, j, n = 0;

  if (!NWWiFiField (name, sizeof (name), interface))
    return 0;
  port = NWWiFiPort ();
  if (port == MACH_PORT_NULL)
    return 0;
  if (wlan_scan_count (port, name, &count, &st) != KERN_SUCCESS
      || st != wlan_status_success_e)
    count = 0;
  for (i = 0; i < count; i++)
    {
      NWNetwork net;
      WLANSSID ssid;
      WLANBSSID bssid;
      wlan_security_t security;
      int seen = -1;

      if (wlan_scan_entry (port, name, i, ssid, bssid, &net.rssi,
                           &net.channel, &security, &st) != KERN_SUCCESS
          || st != wlan_status_success_e)
        continue;
      ssid[sizeof (ssid) - 1] = '\0';
      bssid[sizeof (bssid) - 1] = '\0';
      if (ssid[0] == '\0')
        continue;		/* a hidden network */
      strlcpy (net.ssid, ssid, sizeof (net.ssid));
      strlcpy (net.bssid, bssid, sizeof (net.bssid));
      net.security = (int) security;
      /* One entry per name: its strongest access point. */
      for (j = 0; j < n && seen < 0; j++)
        if (strcmp (networks[j].ssid, net.ssid) == 0)
          seen = j;
      if (seen >= 0)
        {
          if (net.rssi > networks[seen].rssi)
            networks[seen] = net;
          continue;
        }
      if (n < max)
        networks[n++] = net;
    }
  NWWiFiRelease (port);

  /* Strongest first; a handful, so insertion sort. */
  for (i = 1; i < n; i++)
    {
      NWNetwork net = networks[i];

      for (j = i; j > 0 && networks[j - 1].rssi < net.rssi; j--)
        networks[j] = networks[j - 1];
      networks[j] = net;
    }
  return n;
}

int
NWWiFiConnect (const char *interface, const char *ssid,
               const char *passphrase)
{
  mach_port_t port;
  WLANInterfaceName name;
  WLANSSID s;
  WLANPassphrase psk;
  wlan_status_t st = wlan_status_invalid_parameter_e;

  if (!NWWiFiField (name, sizeof (name), interface)
      || !NWWiFiField (s, sizeof (s), ssid)
      || !NWWiFiField (psk, sizeof (psk), passphrase))
    {
      explicit_bzero (psk, sizeof (psk));
      return wlan_status_invalid_parameter_e;
    }
  port = NWWiFiPort ();
  if (port == MACH_PORT_NULL)
    st = NWWiFiUnavailable;
  else if (wlan_connect (port, name, s, psk, &st) != KERN_SUCCESS)
    st = NWWiFiUnavailable;
  explicit_bzero (psk, sizeof (psk));
  NWWiFiRelease (port);
  return st;
}

int
NWWiFiConnectEAP (const char *interface, const char *ssid,
                  const NWEAPSettings *eap)
{
  mach_port_t port;
  WLANInterfaceName name;
  WLANSSID s;
  WLANEAPName identity, anonymous, server;
  WLANEAPSecret password, keyPassphrase;
  WLANEAPPath ca, cert, key;
  wlan_status_t st = wlan_status_invalid_parameter_e;

  if (NWWiFiField (name, sizeof (name), interface)
      && NWWiFiField (s, sizeof (s), ssid)
      && NWWiFiField (identity, sizeof (identity), eap->identity)
      && NWWiFiField (anonymous, sizeof (anonymous), eap->anonymousIdentity)
      && NWWiFiField (password, sizeof (password), eap->password)
      && NWWiFiField (ca, sizeof (ca), eap->caCertificate)
      && NWWiFiField (server, sizeof (server), eap->serverName)
      && NWWiFiField (cert, sizeof (cert), eap->clientCertificate)
      && NWWiFiField (key, sizeof (key), eap->privateKey)
      && NWWiFiField (keyPassphrase, sizeof (keyPassphrase),
                      eap->keyPassphrase))
    {
      port = NWWiFiPort ();
      if (port == MACH_PORT_NULL)
        st = NWWiFiUnavailable;
      else if (wlan_connect_eap (port, name, s, eap->method,
                                 (wlan_ttls_inner_t) eap->ttlsInner,
                                 identity, anonymous, password, ca, server,
                                 cert, key, keyPassphrase,
                                 eap->noVerifyServer ? TRUE : FALSE, &st)
               != KERN_SUCCESS)
        st = NWWiFiUnavailable;
      NWWiFiRelease (port);
    }
  explicit_bzero (password, sizeof (password));
  explicit_bzero (keyPassphrase, sizeof (keyPassphrase));
  return st;
}

int
NWWiFiDisconnect (const char *interface)
{
  mach_port_t port;
  WLANInterfaceName name;
  wlan_status_t st;

  if (!NWWiFiField (name, sizeof (name), interface))
    return wlan_status_invalid_parameter_e;
  port = NWWiFiPort ();
  if (port == MACH_PORT_NULL)
    return NWWiFiUnavailable;
  if (wlan_disconnect (port, name, &st) != KERN_SUCCESS)
    st = NWWiFiUnavailable;
  NWWiFiRelease (port);
  return st;
}

/* wlan(8)'s messages, in the window's words. */
const char *
NWWiFiMessage (int status)
{
  switch (status)
    {
    case wlan_status_success_e:
      return "Done.";
    case wlan_status_invalid_parameter_e:
      return "Wi-Fi didn't accept the network's settings.";
    case wlan_status_interface_does_not_exist_e:
      return "The Wi-Fi interface has gone away.";
    case wlan_status_no_supplicant_e:
      return "Wi-Fi isn't ready (wpa_supplicant isn't running).";
    case wlan_status_not_associated_e:
      return "Wi-Fi isn't connected to a network.";
    case wlan_status_operation_not_supported_e:
      return "Wi-Fi can't do that.";
    case wlan_status_enterprise_required_e:
      return "This is a WPA Enterprise network: join it with a user "
             "name and password (Join Other Network).";
    case wlan_status_no_trust_anchor_e:
      return "Say how to check the network's server: a CA certificate or "
             "the server's name (or choose not to check it).";
    case wlan_status_ca_bundle_missing_e:
      return "Checking the server by its name needs the system's "
             "certificates (/etc/ssl/cert.pem), which are missing. Choose a "
             "CA certificate instead.";
    case wlan_status_credential_file_e:
      return "A certificate or key file is missing or unreadable.";
    case wlan_status_key_file_insecure_e:
      return "The private key file can be read by other users. Make it "
             "readable only by you (chmod 600).";
    case NWWiFiUnavailable:
      return "Wi-Fi isn't available: wland isn't running.";
    default:
      return "Wi-Fi couldn't do that.";
    }
}
