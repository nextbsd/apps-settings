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
/* The Users & Login operations; form as above. password: "" for none;
 * user: "" turns automatic login off. */
int NBHelperCreateUser (const char *form, const char *user,
                        const char *fullName, const char *password,
                        int admin);
int NBHelperDeleteUser (const char *form, const char *user, int keepHome);
int NBHelperSetPassword (const char *form, const char *user,
                         const char *password);
int NBHelperSetAdmin (const char *form, const char *user, int admin);
int NBHelperSetAutoLogin (const char *form, const char *user);
int NBHelperSetLoginWindowOptions (const char *form, int showNameFields,
                                   int showPowerButtons);
/* CUPSAdmin: op is SH_CUPS_ADD or SH_CUPS_DELETE; uri, info and
 * location are "" for a delete. */
int NBHelperCUPSAdmin (const char *form, int op, const char *printer,
                       const char *uri, const char *info,
                       const char *location);

#endif
