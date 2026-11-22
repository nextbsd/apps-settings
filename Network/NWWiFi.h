/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * NWWiFi: Network's client of wland (org.nextbsd.wlan, nextbsd-userland
 * src/WLAN), over the MIG stubs the build makes from mig/wlan.defs: the
 * interfaces wland manages, scanning, and joining a network, with a
 * passphrase or WPA Enterprise (802.1X). Any local user may join a
 * network, so nothing here needs the helper.
 *
 * The Dock's Wi-Fi extra drives wland through wlan(8); Network calls it
 * directly, so a passphrase or an 802.1X password never appears in a
 * command line. What wland has joined comes from its AirPort entry in
 * the dynamic store (NWSystem), as the Dock reads it.
 *
 * Each call returns a wlan_status_t (0 for success), or
 * NWWiFiUnavailable when wland can't be reached.
 */

#ifndef _NW_WIFI_H_
#define _NW_WIFI_H_

#define NWWiFiUnavailable 100

/* wlan_security_t. */
enum
{
  NWWiFiOpen = 0,
  NWWiFiWEP = 1,
  NWWiFiWPA = 2,
  NWWiFiWPA2 = 3,
  NWWiFiWPA3 = 4,
  NWWiFiEnterprise = 5,
  NWWiFiUnknown = 6
};

/* EAP methods: wlan.defs' eap_type (Darwin's EAPType). */
enum
{
  NWEAPTLS = 13,
  NWEAPTTLS = 21,
  NWEAPPEAP = 25
};

typedef struct
{
  char ssid[33];
  char bssid[18];
  int rssi;			/* dBm */
  int channel;
  int security;			/* NWWiFi* */
} NWNetwork;

typedef struct
{
  int method;			/* NWEAP* */
  int ttlsInner;		/* wlan_ttls_inner_t: 0 MSCHAPv2, 1 PAP, 2 CHAP */
  const char *identity;
  const char *anonymousIdentity;
  const char *password;		/* PEAP and TTLS */
  const char *caCertificate;	/* a PEM file, or hash://server/sha256/... */
  const char *serverName;
  const char *clientCertificate;	/* TLS */
  const char *privateKey;	/* TLS */
  const char *keyPassphrase;
  int noVerifyServer;
} NWEAPSettings;

/* The interfaces wland manages ("wlan0"); returns how many. */
int NWWiFiInterfaces (char names[][16], int max);

/* Ask for a scan. *generation gets the count of sweeps finished before
 * it; NWWiFiScanFinished says when another has finished. */
int NWWiFiScan (const char *interface, unsigned *generation);
/* 1 once a sweep after `generation` has finished (*failed: it failed),
 * 0 while it hasn't, -1 if wland can't be asked. */
int NWWiFiScanFinished (const char *interface, unsigned generation,
                        int *failed);
/* wland's cache, strongest first, one entry per network name (hidden
 * networks left out); returns how many. */
int NWWiFiScanResults (const char *interface, NWNetwork *networks, int max);

/* Join: an empty passphrase for an open network. */
int NWWiFiConnect (const char *interface, const char *ssid,
                   const char *passphrase);
int NWWiFiConnectEAP (const char *interface, const char *ssid,
                      const NWEAPSettings *eap);
/* Leave the network, and don't join it again by itself. */
int NWWiFiDisconnect (const char *interface);

/* A sentence for a status, for alerts. */
const char *NWWiFiMessage (int status);

#endif
