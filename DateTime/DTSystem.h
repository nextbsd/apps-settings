/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * DTSystem: what Date & Time reads about the system as the user.
 *
 * Whether network time is on is whether root's ntpd is running: the job
 * (org.nextbsd.ntpd, RunAtLoad and KeepAlive) runs exactly while it's
 * enabled, and launchd's overrides database, which says so, is root's
 * alone. The process table is open to everyone.
 */

#ifndef _DT_SYSTEM_H_
#define _DT_SYSTEM_H_

/* 1 if root's ntpd is running, else 0. */
int DTNetworkTimeRunning (void);

#endif
