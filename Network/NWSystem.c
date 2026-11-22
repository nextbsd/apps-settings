/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Built without GNUstep's headers: see the GNUmakefile.
 */

#include <sys/types.h>
#include <sys/socket.h>

#include <net/if.h>
#include <net/if_dl.h>
#include <ifaddrs.h>

#include <CoreFoundation/CoreFoundation.h>
#include <SystemConfiguration/SystemConfiguration.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "NWSystem.h"

typedef struct
{
  SCDynamicStoreRef store;
} NWSystem;

void *
NWSystemOpen (void)
{
  NWSystem *system;
  SCDynamicStoreRef store = SCDynamicStoreCreate (NULL, CFSTR ("Network"),
                                                  NULL, NULL);

  if (store == NULL)
    return NULL;
  system = calloc (1, sizeof (*system));
  if (system == NULL)
    {
      CFRelease (store);
      return NULL;
    }
  system->store = store;
  return system;
}

void
NWSystemClose (void *handle)
{
  NWSystem *system = handle;

  if (system == NULL)
    return;
  CFRelease (system->store);
  free (system);
}

/* ---- reading CF values ---- */

static void
CopyString (CFTypeRef v, char *out, size_t size)
{
  out[0] = '\0';
  if (v != NULL && CFGetTypeID (v) == CFStringGetTypeID ())
    CFStringGetCString ((CFStringRef) v, out, (CFIndex) size,
                        kCFStringEncodingUTF8);
}

static void
CopyKey (CFDictionaryRef d, CFStringRef key, char *out, size_t size)
{
  CopyString (d != NULL ? CFDictionaryGetValue (d, key) : NULL, out, size);
}

static int
CopyInt (CFDictionaryRef d, CFStringRef key)
{
  CFTypeRef v = d != NULL ? CFDictionaryGetValue (d, key) : NULL;
  int result = 0;

  if (v != NULL && CFGetTypeID (v) == CFNumberGetTypeID ())
    CFNumberGetValue ((CFNumberRef) v, kCFNumberIntType, &result);
  else if (v != NULL && CFGetTypeID (v) == CFBooleanGetTypeID ())
    result = CFBooleanGetValue ((CFBooleanRef) v) ? 1 : 0;
  return result;
}

/* An array's first string (Addresses, SubnetMasks). */
static void
CopyFirst (CFDictionaryRef d, CFStringRef key, char *out, size_t size)
{
  CFTypeRef v = d != NULL ? CFDictionaryGetValue (d, key) : NULL;

  out[0] = '\0';
  if (v != NULL && CFGetTypeID (v) == CFArrayGetTypeID ()
      && CFArrayGetCount ((CFArrayRef) v) > 0)
    CopyString (CFArrayGetValueAtIndex ((CFArrayRef) v, 0), out, size);
}

/* An array of strings, one a line. A string on its own counts as one. */
static void
CopyList (CFDictionaryRef d, CFStringRef key, char *out, size_t size)
{
  CFTypeRef v = d != NULL ? CFDictionaryGetValue (d, key) : NULL;
  char entry[NWAddressSize * 2];
  CFIndex i, n;

  out[0] = '\0';
  if (v != NULL && CFGetTypeID (v) == CFStringGetTypeID ())
    {
      CopyString (v, out, size);
      return;
    }
  if (v == NULL || CFGetTypeID (v) != CFArrayGetTypeID ())
    return;
  n = CFArrayGetCount ((CFArrayRef) v);
  for (i = 0; i < n; i++)
    {
      CopyString (CFArrayGetValueAtIndex ((CFArrayRef) v, i), entry,
                  sizeof (entry));
      if (entry[0] == '\0')
        continue;
      if (out[0] != '\0')
        strlcat (out, "\n", size);
      strlcat (out, entry, size);
    }
}

/* The dynamic store's dictionary at a key, or NULL. Release it. */
static CFDictionaryRef
CopyStoreValue (SCDynamicStoreRef store, CFStringRef key)
{
  CFPropertyListRef v = SCDynamicStoreCopyValue (store, key);

  if (v != NULL && CFGetTypeID (v) != CFDictionaryGetTypeID ())
    {
      CFRelease (v);
      v = NULL;
    }
  return v;
}

static CFDictionaryRef
CopyServiceState (SCDynamicStoreRef store, CFStringRef serviceID,
                  CFStringRef entity)
{
  CFStringRef key = SCDynamicStoreKeyCreateNetworkServiceEntity (
      NULL, kSCDynamicStoreDomainState, serviceID, entity);
  CFDictionaryRef d = CopyStoreValue (store, key);

  CFRelease (key);
  return d;
}

static CFDictionaryRef
CopyInterfaceState (SCDynamicStoreRef store, const char *device,
                    CFStringRef entity)
{
  CFStringRef name, key;
  CFDictionaryRef d;

  name = CFStringCreateWithCString (NULL, device, kCFStringEncodingUTF8);
  key = SCDynamicStoreKeyCreateNetworkInterfaceEntity (
      NULL, kSCDynamicStoreDomainState, name, entity);
  d = CopyStoreValue (store, key);
  CFRelease (key);
  CFRelease (name);
  return d;
}

/* ---- the settings ---- */

static int
IPv4Method (CFDictionaryRef config)
{
  CFTypeRef m = config != NULL
    ? CFDictionaryGetValue (config, kSCPropNetIPv4ConfigMethod) : NULL;

  if (m == NULL || CFEqual (m, kSCValNetIPv4ConfigMethodDHCP))
    return NWIPv4DHCP;
  if (CFEqual (m, kSCValNetIPv4ConfigMethodINFORM))
    return NWIPv4DHCPManualAddress;
  if (CFEqual (m, kSCValNetIPv4ConfigMethodManual))
    return NWIPv4Manual;
  return NWIPv4Other;
}

static int
IPv6Method (CFDictionaryRef config)
{
  CFTypeRef m = config != NULL
    ? CFDictionaryGetValue (config, kSCPropNetIPv6ConfigMethod) : NULL;

  if (m == NULL || CFEqual (m, kSCValNetIPv6ConfigMethodAutomatic))
    return NWIPv6Automatic;
  if (CFEqual (m, kSCValNetIPv6ConfigMethodManual))
    return NWIPv6Manual;
  if (CFEqual (m, CFSTR ("LinkLocal")))
    return NWIPv6LinkLocal;
  return NWIPv6Other;
}

/* A protocol's configuration (NULL for none), and whether it's on. */
static CFDictionaryRef
ProtocolConfig (SCNetworkServiceRef service, CFStringRef type, int *enabled)
{
  SCNetworkProtocolRef p = SCNetworkServiceCopyProtocol (service, type);
  CFDictionaryRef config = NULL;

  *enabled = 1;
  if (p == NULL)
    return NULL;
  *enabled = SCNetworkProtocolGetEnabled (p) ? 1 : 0;
  config = SCNetworkProtocolGetConfiguration (p);
  if (config != NULL)
    CFRetain (config);
  CFRelease (p);
  return config;
}

static void
ReadSettings (SCNetworkServiceRef service, NWService *s)
{
  CFDictionaryRef v4, v6, dns;
  CFTypeRef v;
  int on;

  v4 = ProtocolConfig (service, kSCNetworkProtocolTypeIPv4, &on);
  s->ipv4Method = on ? IPv4Method (v4) : NWIPv4Off;
  CopyFirst (v4, kSCPropNetIPv4Addresses, s->ipv4Address,
             sizeof (s->ipv4Address));
  CopyFirst (v4, kSCPropNetIPv4SubnetMasks, s->ipv4Mask,
             sizeof (s->ipv4Mask));
  CopyKey (v4, kSCPropNetIPv4Router, s->ipv4Router, sizeof (s->ipv4Router));

  v6 = ProtocolConfig (service, kSCNetworkProtocolTypeIPv6, &on);
  s->ipv6Method = on ? IPv6Method (v6) : NWIPv6Off;
  CopyFirst (v6, kSCPropNetIPv6Addresses, s->ipv6Address,
             sizeof (s->ipv6Address));
  s->ipv6Prefix = 64;
  v = v6 != NULL ? CFDictionaryGetValue (v6, kSCPropNetIPv6PrefixLength)
                 : NULL;
  if (v != NULL && CFGetTypeID (v) == CFArrayGetTypeID ()
      && CFArrayGetCount (v) > 0)
    {
      CFTypeRef n = CFArrayGetValueAtIndex (v, 0);

      if (CFGetTypeID (n) == CFNumberGetTypeID ())
        CFNumberGetValue (n, kCFNumberIntType, &s->ipv6Prefix);
    }
  CopyKey (v6, kSCPropNetIPv6Router, s->ipv6Router, sizeof (s->ipv6Router));

  dns = ProtocolConfig (service, kSCNetworkProtocolTypeDNS, &on);
  CopyList (dns, kSCPropNetDNSServerAddresses, s->dnsServers,
            sizeof (s->dnsServers));
  CopyList (dns, kSCPropNetDNSSearchDomains, s->searchDomains,
            sizeof (s->searchDomains));

  if (v4 != NULL)
    CFRelease (v4);
  if (v6 != NULL)
    CFRelease (v6);
  if (dns != NULL)
    CFRelease (dns);
}

/* The interface's link-level address, from the kernel. */
static void
ReadHardwareAddress (const char *device, char *out, size_t size)
{
  struct ifaddrs *list, *ifa;

  out[0] = '\0';
  if (device[0] == '\0' || getifaddrs (&list) == -1)
    return;
  for (ifa = list; ifa != NULL; ifa = ifa->ifa_next)
    {
      const struct sockaddr_dl *sdl = (const void *) ifa->ifa_addr;
      const unsigned char *a;

      if (sdl == NULL || sdl->sdl_family != AF_LINK
          || strcmp (ifa->ifa_name, device) != 0 || sdl->sdl_alen != 6)
        continue;
      a = (const unsigned char *) LLADDR (sdl);
      snprintf (out, size, "%02x:%02x:%02x:%02x:%02x:%02x", a[0], a[1],
                a[2], a[3], a[4], a[5]);
      break;
    }
  freeifaddrs (list);
}

/* ---- what it has now ---- */

static void
ReadState (SCDynamicStoreRef store, CFStringRef serviceID,
           CFStringRef primary, NWService *s)
{
  CFDictionaryRef d;
  CFTypeRef v;

  s->primary = primary != NULL && CFEqual (primary, serviceID);

  d = CopyServiceState (store, serviceID, kSCEntNetIPv4);
  CopyFirst (d, kSCPropNetIPv4Addresses, s->addressNow,
             sizeof (s->addressNow));
  CopyFirst (d, kSCPropNetIPv4SubnetMasks, s->maskNow, sizeof (s->maskNow));
  CopyKey (d, kSCPropNetIPv4Router, s->routerNow, sizeof (s->routerNow));
  if (d != NULL)
    CFRelease (d);

  /* The service's IPv6, else the interface's addresses. */
  d = CopyServiceState (store, serviceID, kSCEntNetIPv6);
  if (d == NULL && s->device[0] != '\0')
    d = CopyInterfaceState (store, s->device, kSCEntNetIPv6);
  CopyList (d, kSCPropNetIPv6Addresses, s->ipv6Now, sizeof (s->ipv6Now));
  CopyKey (d, kSCPropNetIPv6Router, s->ipv6RouterNow,
           sizeof (s->ipv6RouterNow));
  if (d != NULL)
    CFRelease (d);
  /* Link-local addresses last: the others are the ones people want. */
  if (strncmp (s->ipv6Now, "fe80:", 5) == 0 && strchr (s->ipv6Now, '\n'))
    {
      char first[NWAddressSize], *nl = strchr (s->ipv6Now, '\n');
      size_t n = (size_t) (nl - s->ipv6Now);

      if (n < sizeof (first))
        {
          memcpy (first, s->ipv6Now, n);
          first[n] = '\0';
          memmove (s->ipv6Now, nl + 1, strlen (nl + 1) + 1);
          strlcat (s->ipv6Now, "\n", sizeof (s->ipv6Now));
          strlcat (s->ipv6Now, first, sizeof (s->ipv6Now));
        }
    }

  d = CopyServiceState (store, serviceID, kSCEntNetDNS);
  CopyList (d, kSCPropNetDNSServerAddresses, s->dnsServersNow,
            sizeof (s->dnsServersNow));
  CopyList (d, kSCPropNetDNSSearchDomains, s->searchDomainsNow,
            sizeof (s->searchDomainsNow));
  if (s->searchDomainsNow[0] == '\0')
    CopyKey (d, kSCPropNetDNSDomainName, s->searchDomainsNow,
             sizeof (s->searchDomainsNow));
  if (d != NULL)
    CFRelease (d);

  d = CopyServiceState (store, serviceID, kSCEntNetDHCP);
  s->dhcp = d != NULL;
  if (d != NULL)
    CFRelease (d);

  s->linkActive = -1;
  if (s->device[0] == '\0')
    return;
  d = CopyInterfaceState (store, s->device, kSCEntNetLink);
  if (d != NULL)
    {
      v = CFDictionaryGetValue (d, kSCPropNetLinkActive);
      if (v != NULL && CFGetTypeID (v) == CFBooleanGetTypeID ())
        s->linkActive = CFBooleanGetValue (v) ? 1 : 0;
      CFRelease (d);
    }
  d = CopyInterfaceState (store, s->device, kSCEntNetAirPort);
  if (d != NULL)
    {
      s->airport = 1;
      s->wifi = 1;
      s->authenticated = CopyInt (d, CFSTR ("Authenticated"));
      CopyKey (d, CFSTR ("SSID"), s->ssid, sizeof (s->ssid));
      CopyKey (d, CFSTR ("BSSID"), s->bssid, sizeof (s->bssid));
      s->rssi = CopyInt (d, CFSTR ("RSSI"));
      s->channel = CopyInt (d, CFSTR ("Channel"));
      CopyKey (d, CFSTR ("Security"), s->security, sizeof (s->security));
      CFRelease (d);
    }
}

static void
ReadService (SCDynamicStoreRef store, SCNetworkServiceRef service,
             CFStringRef primary, NWService *s)
{
  SCNetworkInterfaceRef interface = SCNetworkServiceGetInterface (service);
  CFStringRef serviceID = SCNetworkServiceGetServiceID (service);

  memset (s, 0, sizeof (*s));
  CopyString (serviceID, s->serviceID, sizeof (s->serviceID));
  CopyString (SCNetworkServiceGetName (service), s->name, sizeof (s->name));
  s->enabled = SCNetworkServiceGetEnabled (service) ? 1 : 0;
  if (interface != NULL)
    {
      CFStringRef type = SCNetworkInterfaceGetInterfaceType (interface);

      CopyString (SCNetworkInterfaceGetBSDName (interface), s->device,
                  sizeof (s->device));
      s->wifi = type != NULL
        && CFEqual (type, kSCNetworkInterfaceTypeIEEE80211);
      if (s->name[0] == '\0')
        CopyString (SCNetworkInterfaceGetLocalizedDisplayName (interface),
                    s->name, sizeof (s->name));
    }
  if (s->name[0] == '\0')
    strlcpy (s->name, s->device[0] != '\0' ? s->device : "Service",
             sizeof (s->name));
  ReadHardwareAddress (s->device, s->hardwareAddress,
                       sizeof (s->hardwareAddress));
  ReadSettings (service, s);
  ReadState (store, serviceID, primary, s);
}

/* Where a service is in the order; services not in it go last. */
static CFIndex
OrderOf (CFArrayRef order, CFStringRef serviceID)
{
  CFIndex i;

  if (order == NULL)
    return 1000;
  i = CFArrayGetFirstIndexOfValue (order,
                                   CFRangeMake (0, CFArrayGetCount (order)),
                                   serviceID);
  return i == kCFNotFound ? 1000 : i;
}

int
NWSystemReadServices (void *handle, NWService *services, int max)
{
  NWSystem *system = handle;
  SCPreferencesRef prefs;
  SCNetworkSetRef set;
  CFArrayRef list, order = NULL;
  CFDictionaryRef global;
  CFStringRef primary = NULL;
  CFIndex i, count;
  CFIndex rank[NWMaxServices];
  int n = 0, j, k;

  if (system == NULL)
    return 0;
  /* A new one every time: SCPreferences reads its file once. */
  prefs = SCPreferencesCreate (NULL, CFSTR ("Network"), NULL);
  if (prefs == NULL)
    return 0;
  set = SCNetworkSetCopyCurrent (prefs);
  if (set != NULL)
    {
      list = SCNetworkSetCopyServices (set);
      order = SCNetworkSetGetServiceOrder (set);
    }
  else
    list = SCNetworkServiceCopyAll (prefs);

  {
    CFStringRef key = SCDynamicStoreKeyCreateNetworkGlobalEntity (
        NULL, kSCDynamicStoreDomainState, kSCEntNetIPv4);

    global = CopyStoreValue (system->store, key);
    CFRelease (key);
    if (global != NULL)
      {
        primary = CFDictionaryGetValue (global, CFSTR ("PrimaryService"));
        if (primary != NULL && CFGetTypeID (primary) != CFStringGetTypeID ())
          primary = NULL;
      }
  }

  count = list != NULL ? CFArrayGetCount (list) : 0;
  for (i = 0; i < count && n < max && n < NWMaxServices; i++)
    {
      SCNetworkServiceRef service = (SCNetworkServiceRef)
        CFArrayGetValueAtIndex (list, i);
      CFIndex r = OrderOf (order, SCNetworkServiceGetServiceID (service));
      NWService s;

      ReadService (system->store, service, primary, &s);
      /* Insert by order: there are only a few. */
      for (j = n; j > 0 && rank[j - 1] > r; j--)
        ;
      for (k = n; k > j; k--)
        {
          services[k] = services[k - 1];
          rank[k] = rank[k - 1];
        }
      services[j] = s;
      rank[j] = r;
      n++;
    }

  if (global != NULL)
    CFRelease (global);
  if (list != NULL)
    CFRelease (list);
  if (set != NULL)
    CFRelease (set);
  CFRelease (prefs);
  return n;
}

int
NWSystemReadNames (void *handle, NWNames *names)
{
  NWSystem *system = handle;
  CFStringRef computer, local;

  memset (names, 0, sizeof (*names));
  if (system == NULL)
    return 0;
  computer = SCDynamicStoreCopyComputerName (system->store, NULL);
  local = SCDynamicStoreCopyLocalHostName (system->store);
  CopyString (computer, names->computerName, sizeof (names->computerName));
  CopyString (local, names->localHostName, sizeof (names->localHostName));
  if (computer != NULL)
    CFRelease (computer);
  if (local != NULL)
    CFRelease (local);
  return names->computerName[0] != '\0' || names->localHostName[0] != '\0';
}
