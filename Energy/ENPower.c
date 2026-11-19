/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Built without GNUstep's headers: see the GNUmakefile.
 */

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/pwr_mgt/IOPMLib.h>
#include <IOKit/pwr_mgt/IOPMLibPrivate.h>
#include <IOKit/ps/IOPowerSources.h>
#include <IOKit/ps/IOPSKeys.h>

#include <stdint.h>
#include <string.h>

#include "ENPower.h"

/*
 * NextBSD's <notify.h> needs <os/base.h>, which isn't installed, so the
 * two calls used are declared here, as Bluetooth.app and the Dock extras
 * do.
 */
extern uint32_t notify_register_check (const char *name, int *out_token);
extern uint32_t notify_check (int token, int *check);

static int
ENNumber (CFTypeRef v, int fallback)
{
  int result = fallback;

  if (v != NULL && CFGetTypeID (v) == CFNumberGetTypeID ())
    CFNumberGetValue ((CFNumberRef) v, kCFNumberIntType, &result);
  else if (v != NULL && CFGetTypeID (v) == CFBooleanGetTypeID ())
    result = CFBooleanGetValue ((CFBooleanRef) v) ? 1 : 0;
  return result;
}

static int
ENDictInt (CFDictionaryRef d, const char *key, int fallback)
{
  CFStringRef k = CFStringCreateWithCString (NULL, key, kCFStringEncodingUTF8);
  int result = ENNumber (k != NULL ? CFDictionaryGetValue (d, k) : NULL,
                         fallback);

  if (k != NULL)
    CFRelease (k);
  return result;
}

static int
ENDictString (CFDictionaryRef d, const char *key, char *out, size_t size)
{
  CFStringRef k = CFStringCreateWithCString (NULL, key, kCFStringEncodingUTF8);
  CFTypeRef v = k != NULL ? CFDictionaryGetValue (d, k) : NULL;
  int ok = 0;

  out[0] = '\0';
  if (v != NULL && CFGetTypeID (v) == CFStringGetTypeID ())
    ok = CFStringGetCString ((CFStringRef) v, out, (CFIndex) size,
                             kCFStringEncodingUTF8);
  if (k != NULL)
    CFRelease (k);
  return ok;
}

/* A registry entry's integer property, by class; fallback if absent. */
static int
ENRegistryInt (const char *class, const char *key, int fallback)
{
  io_service_t entry;
  CFStringRef k;
  CFTypeRef v;
  int result = fallback;

  entry = IOServiceGetMatchingService (kIOMasterPortDefault,
                                       IOServiceMatching (class));
  if (entry == 0)
    return fallback;
  k = CFStringCreateWithCString (NULL, key, kCFStringEncodingUTF8);
  v = IORegistryEntryCreateCFProperty (entry, k, NULL, 0);
  if (v != NULL)
    {
      result = ENNumber (v, fallback);
      CFRelease (v);
    }
  CFRelease (k);
  IOObjectRelease (entry);
  return result;
}

static void
ENReadSource (CFDictionaryRef prefs, const char *name, ENSourceSettings *out)
{
  CFStringRef source = CFStringCreateWithCString (NULL, name,
                                                  kCFStringEncodingUTF8);
  CFTypeRef d = CFDictionaryGetValue (prefs, source);
  CFStringRef wol = CFSTR (kIOPMWakeOnLANKey);

  memset (out, 0, sizeof (*out));
  out->wakeOnLAN = -1;
  if (d != NULL && CFGetTypeID (d) == CFDictionaryGetTypeID ())
    {
      out->present = 1;
      out->displaySleep = ENDictInt (d, kIOPMDisplaySleepKey, 0);
      out->systemSleep = ENDictInt (d, kIOPMSystemSleepKey, 0);
      if (IOPMFeatureIsAvailable (wol, source))
        out->wakeOnLAN = ENDictInt (d, kIOPMWakeOnLANKey, 0) ? 1 : 0;
    }
  CFRelease (source);
}

int
ENReadSettings (ENSettings *out)
{
  CFDictionaryRef prefs = IOPMCopyPMPreferences ();

  memset (out, 0, sizeof (*out));
  out->ac.wakeOnLAN = out->battery.wakeOnLAN = -1;
  /* A root domain without the property (an older kernel) is taken to
     sleep, as before. */
  out->sleepSupported = ENRegistryInt ("IOPMrootDomain", "IOSleepSupported",
                                       1);
  if (prefs == NULL)
    return 0;
  ENReadSource (prefs, kIOPMACPowerKey, &out->ac);
  ENReadSource (prefs, kIOPMBatteryPowerKey, &out->battery);
  CFRelease (prefs);
  return 1;
}

int
ENReadBattery (ENBattery *out)
{
  CFTypeRef snapshot = IOPSCopyPowerSourcesInfo ();
  CFArrayRef list = snapshot != NULL ? IOPSCopyPowerSourcesList (snapshot)
                                     : NULL;
  CFIndex i;

  memset (out, 0, sizeof (*out));
  out->minutesToEmpty = out->minutesToFull = out->cycleCount = -1;
  for (i = 0; list != NULL && i < CFArrayGetCount (list) && !out->present;
       i++)
    {
      CFDictionaryRef d = IOPSGetPowerSourceDescription (snapshot,
                            CFArrayGetValueAtIndex (list, i));
      char type[64], state[64];
      int max;

      if (d == NULL || !ENDictString (d, kIOPSTypeKey, type, sizeof (type))
          || strcmp (type, kIOPSInternalBatteryType) != 0
          || !ENDictInt (d, kIOPSIsPresentKey, 1))
        continue;
      out->present = 1;
      max = ENDictInt (d, kIOPSMaxCapacityKey, 100);
      out->percent = ENDictInt (d, kIOPSCurrentCapacityKey, 0);
      if (max > 0 && max != 100)
        out->percent = out->percent * 100 / max;
      if (out->percent < 0)
        out->percent = 0;
      if (out->percent > 100)
        out->percent = 100;
      out->charging = ENDictInt (d, kIOPSIsChargingKey, 0);
      out->charged = ENDictInt (d, kIOPSIsChargedKey, 0);
      ENDictString (d, kIOPSPowerSourceStateKey, state, sizeof (state));
      out->onAC = strcmp (state, kIOPSACPowerValue) == 0;
      out->minutesToEmpty = ENDictInt (d, kIOPSTimeToEmptyKey, -1);
      out->minutesToFull = ENDictInt (d, kIOPSTimeToFullChargeKey, -1);
      ENDictString (d, kIOPSBatteryHealthKey, out->health,
                    sizeof (out->health));
    }
  if (list != NULL)
    CFRelease (list);
  if (snapshot != NULL)
    CFRelease (snapshot);
  if (out->present)
    {
      /* The battery driver's own numbers, in mAh. */
      out->maxCapacity = ENRegistryInt ("IOPMPowerSource", "MaxCapacity", 0);
      out->designCapacity = ENRegistryInt ("IOPMPowerSource",
                                           "DesignCapacity", 0);
      out->cycleCount = ENRegistryInt ("IOPMPowerSource", "CycleCount", -1);
    }
  return out->present;
}

/* ---- notifications ---- */

static const char *const ENNotifyNames[] = {
  kIOPMPrefsChangeNotify,
  kIOPSNotifyTimeRemaining,
  kIOPSNotifyPowerSource,
  kIOPSNotifyAttach,
  kIOPSNotifyAnyPowerSource,
};
#define ENNotifyCount (sizeof (ENNotifyNames) / sizeof (ENNotifyNames[0]))

static int ENTokens[ENNotifyCount];
static int ENWatching;

void
ENWatchStart (void)
{
  size_t i;

  if (ENWatching)
    return;
  for (i = 0; i < ENNotifyCount; i++)
    if (notify_register_check (ENNotifyNames[i], &ENTokens[i]) != 0)
      ENTokens[i] = -1;
  ENWatching = 1;
  (void) ENWatchChanged ();	/* the first check always says yes */
}

int
ENWatchChanged (void)
{
  size_t i;
  int any = 0, check;

  for (i = 0; ENWatching && i < ENNotifyCount; i++)
    if (ENTokens[i] >= 0 && notify_check (ENTokens[i], &check) == 0 && check)
      any = 1;
  return any;
}
