/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * ENPower: what Energy shows, read as the user from libIOKit, which
 * powerd (Apple's pmconfigd, nextbsd-userland src/PowerManagement)
 * serves:
 *   - the Energy Saver settings, IOPMCopyPMPreferences, with what this
 *     machine supports (IOPMFeatureIsAvailable);
 *   - whether it can sleep at all: the root domain's IOSleepSupported
 *     (false on a machine whose ACPI has no S3, such as the XPS 9320,
 *     which offers only S4 and S5 and needs s2idle);
 *   - the internal battery: IOPowerSources, and the IOPMPowerSource
 *     registry entry's capacities and cycle count for its health.
 * Plain C, compiled without GNUstep's headers (see the GNUmakefile):
 * GNUstep has a CoreFoundation of its own.
 */

#ifndef _EN_POWER_H_
#define _EN_POWER_H_

/* One power source's settings. -1: not offered on this machine. */
typedef struct
{
  int present;			/* the source exists here */
  int displaySleep;		/* minutes, 0 for never */
  int systemSleep;		/* minutes, 0 for never */
  int wakeOnLAN;		/* 0 or 1, or -1 when unsupported */
} ENSourceSettings;

typedef struct
{
  ENSourceSettings ac;
  ENSourceSettings battery;
  int sleepSupported;		/* the root domain's IOSleepSupported */
} ENSettings;

/* Fill *out. Returns 0 if the settings couldn't be read. */
int ENReadSettings (ENSettings *out);

typedef struct
{
  int present;
  int percent;			/* 0-100 */
  int charging;
  int charged;
  int onAC;			/* drawing from the power adapter */
  int minutesToEmpty;		/* -1: unknown */
  int minutesToFull;		/* -1: unknown */
  char health[32];		/* IOPS BatteryHealth: Good, Fair, Poor; "" */
  int maxCapacity;		/* mAh now, from the registry; 0 unknown */
  int designCapacity;		/* mAh new; 0 unknown */
  int cycleCount;		/* -1: unknown */
} ENBattery;

/* The internal battery: 1 and *out filled, or 0 when there is none. */
int ENReadBattery (ENBattery *out);

/* Watch powerd's notify(3) names: the settings (kIOPMPrefsChangeNotify)
 * and the power sources. ENWatchChanged() says whether any was posted
 * since the last call. */
void ENWatchStart (void);
int ENWatchChanged (void);

#endif
