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

#endif
