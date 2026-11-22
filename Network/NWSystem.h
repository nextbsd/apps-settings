/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * NWSystem: what Network shows, read as the user from configd
 * (nextbsd-userland src/configd and libSystemConfiguration):
 *   - the network services of the current set, in their service order,
 *     and each one's settings, from SCPreferences
 *     (/Local/Library/Preferences/SystemConfiguration/preferences.plist):
 *     the IPv4, IPv6 and DNS entities;
 *   - what each service has now, from SCDynamicStore: its addresses,
 *     router and DNS (State:/Network/Service/<id>/...), its link
 *     (State:/Network/Interface/<if>/Link), whether it's the primary
 *     service (State:/Network/Global/IPv4), and for Wi-Fi the network
 *     wland has joined (State:/Network/Interface/<if>/AirPort);
 *   - the computer's names, as hostnamed publishes them (Setup:/System
 *     and Setup:/Network/HostNames).
 * Plain C, compiled without GNUstep's headers (see the GNUmakefile):
 * GNUstep has a CoreFoundation of its own.
 *
 * Nothing secret is read: the Wi-Fi passphrases wland keeps in the same
 * file (KnownNetworks) are never looked at.
 */

#ifndef _NW_SYSTEM_H_
#define _NW_SYSTEM_H_

#define NWMaxServices 16
#define NWAddressSize 64
/* A list (addresses, domains): one entry a line. */
#define NWListSize 512

/* The IPv4 and IPv6 methods: SettingsHelper's SH_NET_V4_* and
 * SH_NET_V6_* (NBSettingsHelper.h's NBNetIPv4* and NBNetIPv6*). */
enum
{
  NWIPv4DHCP = 0,
  NWIPv4DHCPManualAddress = 1,
  NWIPv4Manual = 2,
  NWIPv4Off = 3,
  NWIPv4Other = 4		/* BOOTP, LinkLocal...: shown, not offered */
};
enum
{
  NWIPv6Automatic = 0,
  NWIPv6Manual = 1,
  NWIPv6LinkLocal = 2,
  NWIPv6Off = 3,
  NWIPv6Other = 4
};

typedef struct
{
  char serviceID[64];
  char name[64];		/* UserDefinedName: "Wi-Fi", "Ethernet" */
  char device[16];		/* the interface: "wlan0", "em0" */
  char hardwareAddress[24];	/* "04:cf:4b:0d:11:eb", or "" */
  int wifi;			/* an IEEE 802.11 interface */
  int enabled;			/* the service isn't inactive */

  /* Its settings, from SCPreferences. */
  int ipv4Method;		/* NWIPv4* */
  char ipv4Address[NWAddressSize];
  char ipv4Mask[NWAddressSize];
  char ipv4Router[NWAddressSize];
  int ipv6Method;		/* NWIPv6* */
  char ipv6Address[NWAddressSize];
  int ipv6Prefix;
  char ipv6Router[NWAddressSize];
  char dnsServers[NWListSize];
  char searchDomains[NWListSize];

  /* What it has now, from the dynamic store. */
  int linkActive;		/* 1 up, 0 down, -1 unknown */
  int primary;			/* the primary service (default route) */
  char addressNow[NWAddressSize];
  char maskNow[NWAddressSize];
  char routerNow[NWAddressSize];
  char ipv6Now[NWListSize];	/* every address, link-local last */
  char ipv6RouterNow[NWAddressSize];
  char dnsServersNow[NWListSize];
  char searchDomainsNow[NWListSize];
  int dhcp;			/* State:...DHCP: it has a lease */

  /* Wi-Fi: the network wland has joined. */
  int airport;			/* wland publishes this interface */
  int authenticated;		/* keyed: the 4-way handshake is done */
  char ssid[33];
  char bssid[18];
  int rssi;			/* dBm */
  int channel;
  char security[32];
} NWService;

typedef struct
{
  char computerName[256];
  char localHostName[64];
} NWNames;

/* Connect to configd. NULL if it can't be reached. */
void *NWSystemOpen (void);
/* Fill up to max services, in service order; returns how many. */
int NWSystemReadServices (void *system, NWService *services, int max);
/* Fill *names; 0 if configd has none. */
int NWSystemReadNames (void *system, NWNames *names);
void NWSystemClose (void *system);

#endif
