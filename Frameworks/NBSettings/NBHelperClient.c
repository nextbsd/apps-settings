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

int
NBHelperSetTimeZone (const char *form, const char *zone)
{
  mach_port_t port;
  SHAuthForm f;
  SHZoneName z;
  int status = NBHelperUnavailable;

  if (strlen (zone) > SH_ZONE_MAX)
    return SH_ERR_INVALID;
  port = NBHelperPort ();
  if (port == MACH_PORT_NULL)
    return NBHelperUnavailable;
  memcpy (f, form, sizeof (f));
  memset (z, 0, sizeof (z));
  strlcpy (z, zone, sizeof (z));
  if (sh_set_time_zone (port, f, z, &status) != KERN_SUCCESS)
    status = NBHelperUnavailable;
  NBHelperRelease (port);
  return status;
}

int
NBHelperSetDate (const char *form, int64_t seconds, int microseconds)
{
  mach_port_t port = NBHelperPort ();
  SHAuthForm f;
  int status = NBHelperUnavailable;

  if (port == MACH_PORT_NULL)
    return NBHelperUnavailable;
  memcpy (f, form, sizeof (f));
  if (sh_set_date (port, f, seconds, microseconds, &status) != KERN_SUCCESS)
    status = NBHelperUnavailable;
  NBHelperRelease (port);
  return status;
}

int
NBHelperSetNetworkTime (const char *form, int enabled, const char *server)
{
  mach_port_t port;
  SHAuthForm f;
  SHNTPServer s;
  int status = NBHelperUnavailable;

  if (strlen (server) > SH_NTP_SERVER_MAX)
    return SH_ERR_INVALID;
  port = NBHelperPort ();
  if (port == MACH_PORT_NULL)
    return NBHelperUnavailable;
  memcpy (f, form, sizeof (f));
  memset (s, 0, sizeof (s));
  strlcpy (s, server, sizeof (s));
  if (sh_set_network_time (port, f, enabled ? TRUE : FALSE, s, &status)
      != KERN_SUCCESS)
    status = NBHelperUnavailable;
  NBHelperRelease (port);
  return status;
}

int
NBHelperSetSystemLocale (const char *form, const char *locale)
{
  mach_port_t port;
  SHAuthForm f;
  SHLocaleName l;
  int status = NBHelperUnavailable;

  if (strlen (locale) > SH_LOCALE_MAX)
    return SH_ERR_INVALID;
  port = NBHelperPort ();
  if (port == MACH_PORT_NULL)
    return NBHelperUnavailable;
  memcpy (f, form, sizeof (f));
  memset (l, 0, sizeof (l));
  strlcpy (l, locale, sizeof (l));
  if (sh_set_system_locale (port, f, l, &status) != KERN_SUCCESS)
    status = NBHelperUnavailable;
  NBHelperRelease (port);
  return status;
}
