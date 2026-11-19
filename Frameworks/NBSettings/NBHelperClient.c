/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#include "settingshelper_types.h"

#include <mach/mach.h>
#include <servers/bootstrap.h>

#include "settingshelperUser.h"	/* MIG user stubs, made by the build */

#include <string.h>
#include <strings.h>

#include "NBHelperClient.h"

static mach_port_t
NBHelperPort (void)
{
  mach_port_t port = MACH_PORT_NULL;

  if (bootstrap_look_up (bootstrap_port, SH_SERVICE_NAME, &port)
      != KERN_SUCCESS)
    return MACH_PORT_NULL;
  return port;
}

static void
NBHelperRelease (mach_port_t port)
{
  if (port != MACH_PORT_NULL)
    (void) mach_port_deallocate (mach_task_self (), port);
}

int
NBHelperRightInfoGet (const char *right, NBHelperRightInfo *info)
{
  mach_port_t port = NBHelperPort ();
  SHRightName r;
  SHUserName user;
  boolean_t authorized = FALSE, admin = FALSE, password = TRUE;
  int status = NBHelperUnavailable;

  memset (info, 0, sizeof (*info));
  info->userHasPassword = 1;
  if (port == MACH_PORT_NULL)
    return NBHelperUnavailable;
  memset (r, 0, sizeof (r));
  memset (user, 0, sizeof (user));
  strlcpy (r, right, sizeof (r));
  if (sh_right_info (port, r, &info->rule, &info->timeout, &authorized,
                     &info->secondsLeft, user, &admin, &password, &status)
      != KERN_SUCCESS)
    status = NBHelperUnavailable;
  NBHelperRelease (port);
  user[sizeof (user) - 1] = '\0';
  strlcpy (info->consoleUser, user, sizeof (info->consoleUser));
  info->authorized = authorized ? 1 : 0;
  info->userIsAdmin = admin ? 1 : 0;
  info->userHasPassword = password ? 1 : 0;
  return status;
}

int
NBHelperAuthorize (const char *right, const char *user, const char *password,
                   int *secondsLeft)
{
  mach_port_t port = NBHelperPort ();
  SHRightName r;
  SHUserName u;
  SHPassword p;
  int status = NBHelperUnavailable;

  *secondsLeft = 0;
  if (port == MACH_PORT_NULL)
    return NBHelperUnavailable;
  memset (r, 0, sizeof (r));
  memset (u, 0, sizeof (u));
  memset (p, 0, sizeof (p));
  strlcpy (r, right, sizeof (r));
  strlcpy (u, user, sizeof (u));
  strlcpy (p, password, sizeof (p));
  if (sh_authorize (port, r, u, p, secondsLeft, &status) != KERN_SUCCESS)
    status = NBHelperUnavailable;
  explicit_bzero (p, sizeof (p));
  NBHelperRelease (port);
  return status;
}

int
NBHelperDeauthorize (void)
{
  mach_port_t port = NBHelperPort ();
  int status = NBHelperUnavailable;

  if (port == MACH_PORT_NULL)
    return NBHelperUnavailable;
  if (sh_deauthorize (port, &status) != KERN_SUCCESS)
    status = NBHelperUnavailable;
  NBHelperRelease (port);
  return status;
}

int
NBHelperSetPMPreferences (const char *form, int source, const int32_t *values)
{
  mach_port_t port = NBHelperPort ();
  SHAuthForm f;
  SHPMValues v;
  int status = NBHelperUnavailable;

  if (port == MACH_PORT_NULL)
    return NBHelperUnavailable;
  memcpy (f, form, sizeof (f));
  memcpy (v, values, sizeof (v));
  if (sh_set_pm_preferences (port, f, source, v, &status) != KERN_SUCCESS)
    status = NBHelperUnavailable;
  NBHelperRelease (port);
  return status;
}
