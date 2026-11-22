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

/* Copy a string into a fixed-size wire field; false if it doesn't fit. */
static int
NBHelperCopy (char *field, size_t size, const char *s)
{
  memset (field, 0, size);
  return strlcpy (field, s, size) < size;
}

int
NBHelperCreateUser (const char *form, const char *user, const char *fullName,
                    const char *password, int admin)
{
  mach_port_t port;
  SHAuthForm f;
  SHUserName u;
  SHFullName n;
  SHPassword p;
  int status = NBHelperUnavailable;

  if (!NBHelperCopy (u, sizeof (u), user)
      || !NBHelperCopy (n, sizeof (n), fullName)
      || !NBHelperCopy (p, sizeof (p), password))
    {
      explicit_bzero (p, sizeof (p));
      return SH_ERR_INVALID;
    }
  port = NBHelperPort ();
  if (port != MACH_PORT_NULL)
    {
      memcpy (f, form, sizeof (f));
      if (sh_create_user (port, f, u, n, p, admin ? TRUE : FALSE, &status)
          != KERN_SUCCESS)
        status = NBHelperUnavailable;
      NBHelperRelease (port);
    }
  explicit_bzero (p, sizeof (p));
  return status;
}

int
NBHelperDeleteUser (const char *form, const char *user, int keepHome)
{
  mach_port_t port;
  SHAuthForm f;
  SHUserName u;
  int status = NBHelperUnavailable;

  if (!NBHelperCopy (u, sizeof (u), user))
    return SH_ERR_INVALID;
  port = NBHelperPort ();
  if (port == MACH_PORT_NULL)
    return NBHelperUnavailable;
  memcpy (f, form, sizeof (f));
  if (sh_delete_user (port, f, u, keepHome ? TRUE : FALSE, &status)
      != KERN_SUCCESS)
    status = NBHelperUnavailable;
  NBHelperRelease (port);
  return status;
}

int
NBHelperSetPassword (const char *form, const char *user, const char *password)
{
  mach_port_t port;
  SHAuthForm f;
  SHUserName u;
  SHPassword p;
  int status = NBHelperUnavailable;

  if (!NBHelperCopy (u, sizeof (u), user)
      || !NBHelperCopy (p, sizeof (p), password))
    {
      explicit_bzero (p, sizeof (p));
      return SH_ERR_INVALID;
    }
  port = NBHelperPort ();
  if (port != MACH_PORT_NULL)
    {
      memcpy (f, form, sizeof (f));
      if (sh_set_password (port, f, u, p, &status) != KERN_SUCCESS)
        status = NBHelperUnavailable;
      NBHelperRelease (port);
    }
  explicit_bzero (p, sizeof (p));
  return status;
}

int
NBHelperSetAdmin (const char *form, const char *user, int admin)
{
  mach_port_t port;
  SHAuthForm f;
  SHUserName u;
  int status = NBHelperUnavailable;

  if (!NBHelperCopy (u, sizeof (u), user))
    return SH_ERR_INVALID;
  port = NBHelperPort ();
  if (port == MACH_PORT_NULL)
    return NBHelperUnavailable;
  memcpy (f, form, sizeof (f));
  if (sh_set_admin (port, f, u, admin ? TRUE : FALSE, &status)
      != KERN_SUCCESS)
    status = NBHelperUnavailable;
  NBHelperRelease (port);
  return status;
}

int
NBHelperSetAutoLogin (const char *form, const char *user)
{
  mach_port_t port;
  SHAuthForm f;
  SHUserName u;
  int status = NBHelperUnavailable;

  if (!NBHelperCopy (u, sizeof (u), user))
    return SH_ERR_INVALID;
  port = NBHelperPort ();
  if (port == MACH_PORT_NULL)
    return NBHelperUnavailable;
  memcpy (f, form, sizeof (f));
  if (sh_set_auto_login (port, f, u, &status) != KERN_SUCCESS)
    status = NBHelperUnavailable;
  NBHelperRelease (port);
  return status;
}

int
NBHelperSetLoginWindowOptions (const char *form, int showNameFields,
                               int showPowerButtons)
{
  mach_port_t port = NBHelperPort ();
  SHAuthForm f;
  int status = NBHelperUnavailable;

  if (port == MACH_PORT_NULL)
    return NBHelperUnavailable;
  memcpy (f, form, sizeof (f));
  if (sh_set_login_window_options (port, f, showNameFields ? TRUE : FALSE,
                                   showPowerButtons ? TRUE : FALSE, &status)
      != KERN_SUCCESS)
    status = NBHelperUnavailable;
  NBHelperRelease (port);
  return status;
}

int
NBHelperCUPSAdmin (const char *form, int op, const char *printer,
                   const char *uri, const char *info, const char *location)
{
  mach_port_t port;
  SHAuthForm f;
  SHPrinterName p;
  SHDeviceURI u;
  SHPrinterText i, l;
  int status = NBHelperUnavailable;

  if (strlen (printer) > SH_PRINTER_MAX || strlen (uri) > SH_DEVICE_URI_MAX
      || strlen (info) > SH_PRINTER_TEXT_MAX
      || strlen (location) > SH_PRINTER_TEXT_MAX)
    return SH_ERR_INVALID;
  port = NBHelperPort ();
  if (port == MACH_PORT_NULL)
    return NBHelperUnavailable;
  memcpy (f, form, sizeof (f));
  memset (p, 0, sizeof (p));
  memset (u, 0, sizeof (u));
  memset (i, 0, sizeof (i));
  memset (l, 0, sizeof (l));
  strlcpy (p, printer, sizeof (p));
  strlcpy (u, uri, sizeof (u));
  strlcpy (i, info, sizeof (i));
  strlcpy (l, location, sizeof (l));
  if (sh_cups_admin (port, f, op, p, u, i, l, &status) != KERN_SUCCESS)
    status = NBHelperUnavailable;
  NBHelperRelease (port);
  return status;
}

/* Copy a string into a fixed wire field; false if it doesn't fit. */
static int
NBHelperField (char *field, size_t size, const char *s)
{
  memset (field, 0, size);
  if (s == NULL)
    return 1;
  return strlcpy (field, s, size) < size;
}

int
NBHelperCommitNetworkPreferences (const char *form,
                                  const NBHelperNetworkService *s)
{
  mach_port_t port;
  SHAuthForm f;
  SHNetServiceID id;
  SHNetAddress a4, m4, r4, a6, r6;
  SHNetList dns, search;
  int status = NBHelperUnavailable;

  if (!NBHelperField (id, sizeof (id), s->serviceID)
      || !NBHelperField (a4, sizeof (a4), s->ipv4Address)
      || !NBHelperField (m4, sizeof (m4), s->ipv4Mask)
      || !NBHelperField (r4, sizeof (r4), s->ipv4Router)
      || !NBHelperField (a6, sizeof (a6), s->ipv6Address)
      || !NBHelperField (r6, sizeof (r6), s->ipv6Router)
      || !NBHelperField (dns, sizeof (dns), s->dnsServers)
      || !NBHelperField (search, sizeof (search), s->searchDomains))
    return SH_ERR_INVALID;
  port = NBHelperPort ();
  if (port == MACH_PORT_NULL)
    return NBHelperUnavailable;
  memcpy (f, form, sizeof (f));
  if (sh_commit_network_preferences (port, f, id, s->ipv4Method, a4, m4, r4,
                                     s->ipv6Method, a6, s->ipv6Prefix, r6,
                                     dns, search, &status)
      != KERN_SUCCESS)
    status = NBHelperUnavailable;
  NBHelperRelease (port);
  return status;
}

int
NBHelperSetComputerName (const char *form, const char *computerName,
                         const char *localHostName)
{
  mach_port_t port;
  SHAuthForm f;
  SHComputerName c;
  SHLocalHostName l;
  int status = NBHelperUnavailable;

  if (!NBHelperField (c, sizeof (c), computerName)
      || !NBHelperField (l, sizeof (l), localHostName))
    return SH_ERR_INVALID;
  port = NBHelperPort ();
  if (port == MACH_PORT_NULL)
    return NBHelperUnavailable;
  memcpy (f, form, sizeof (f));
  if (sh_set_computer_name (port, f, c, l, &status) != KERN_SUCCESS)
    status = NBHelperUnavailable;
  NBHelperRelease (port);
  return status;
}
