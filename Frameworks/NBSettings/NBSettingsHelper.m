/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "NBSettingsHelper.h"

#include "NBHelperClient.h"
#include "settingshelper_types.h"

NSString *const NBPowerSourceAC = @"AC Power";
NSString *const NBPowerSourceBattery = @"Battery Power";
NSString *const NBPowerSourceUPS = @"UPS Power";

NSString *const NBPMDisplaySleep = @"displaysleep";
NSString *const NBPMSystemSleep = @"sleep";
NSString *const NBPMDiskSleep = @"disksleep";
NSString *const NBPMWakeOnLAN = @"womp";
NSString *const NBPMReduceBrightness = @"lessbright";
NSString *const NBPMTTYSKeepAwake = @"ttyskeepawake";

@implementation NBSettingsHelper

+ (int)setPMPreferences:(NSDictionary *)values
         forPowerSource:(NSString *)source
          authorization:(NBAuthorization *)auth
{
  NSString *const keys[SH_PM_KEY_LIMIT] = {
    [SH_PM_DISPLAY_SLEEP] = NBPMDisplaySleep,
    [SH_PM_SYSTEM_SLEEP] = NBPMSystemSleep,
    [SH_PM_DISK_SLEEP] = NBPMDiskSleep,
    [SH_PM_WAKE_ON_LAN] = NBPMWakeOnLAN,
    [SH_PM_REDUCE_BRIGHTNESS] = NBPMReduceBrightness,
    [SH_PM_TTYS_PREVENT_SLEEP] = NBPMTTYSKeepAwake,
  };
  int32_t v[SH_PM_VALUES];
  int i, src;
  NSUInteger used = 0;

  if ([source isEqual:NBPowerSourceAC])
    src = SH_PM_SOURCE_AC;
  else if ([source isEqual:NBPowerSourceBattery])
    src = SH_PM_SOURCE_BATTERY;
  else if ([source isEqual:NBPowerSourceUPS])
    src = SH_PM_SOURCE_UPS;
  else
    return NBAuthorizationInvalid;
  for (i = 0; i < SH_PM_VALUES; i++)
    v[i] = SH_PM_UNCHANGED;
  for (i = 0; i < SH_PM_KEY_LIMIT; i++)
    {
      NSNumber *n = [values objectForKey:keys[i]];
      if (n != nil)
        {
          v[i] = [n intValue];
          used++;
        }
    }
  if (used != [values count])
    return NBAuthorizationInvalid;	/* a name this helper doesn't know */
  return NBHelperSetPMPreferences ([[auth externalForm] bytes], src, v);
}

@end
