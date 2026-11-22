/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * NBHelperClient: the plain C client of SettingsHelper
 * (org.nextbsd.SettingsHelper, nextbsd-userland src/SettingsHelper), over
 * the MIG stubs the build makes from mig/settingshelper.defs. It is C so
 * that the Mach headers stay out of the Objective-C files; the apps use it
 * through NBAuthorization and NBSettingsHelper.
 *
 * Every call looks the service up (launchd starts the helper on demand)
 * and returns an SH_* status from settingshelper_types.h, or
 * NBHelperUnavailable when there is no helper to ask.
 */

#ifndef _NB_HELPER_CLIENT_H_
#define _NB_HELPER_CLIENT_H_

#include <stdint.h>

#define NBHelperUnavailable 100

typedef struct
{
  int rule;			/* SH_RULE_* */
  int timeout;			/* seconds */
  int authorized;
  int secondsLeft;
  char consoleUser[256];
  int userIsAdmin;
  int userHasPassword;
} NBHelperRightInfo;

int NBHelperRightInfoGet (const char *right, NBHelperRightInfo *info);
int NBHelperAuthorize (const char *right, const char *user,
                       const char *password, int *secondsLeft);
int NBHelperDeauthorize (void);
/* form: SH_AUTH_FORM_SIZE bytes; values: SH_PM_VALUES entries. */
int NBHelperSetPMPreferences (const char *form, int source,
                              const int32_t *values);
/* The Date & Time operations; form as above. server: "" leaves
 * ntp.conf's servers alone. */
int NBHelperSetTimeZone (const char *form, const char *zone);
int NBHelperSetDate (const char *form, int64_t seconds, int microseconds);
int NBHelperSetNetworkTime (const char *form, int enabled,
                            const char *server);
/* The Network operations; form as above. Each string must fit its wire
 * field (settingshelper_types.h); a list has one entry a line, and NULL
 * is empty. */
typedef struct
{
  const char *serviceID;
  int ipv4Method;		/* SH_NET_V4_* */
  const char *ipv4Address, *ipv4Mask, *ipv4Router;
  int ipv6Method;		/* SH_NET_V6_* */
  const char *ipv6Address;
  int ipv6Prefix;
  const char *ipv6Router;
  const char *dnsServers;
  const char *searchDomains;
} NBHelperNetworkService;

int NBHelperCommitNetworkPreferences (const char *form,
                                      const NBHelperNetworkService *service);
int NBHelperSetComputerName (const char *form, const char *computerName,
                             const char *localHostName);

#endif
