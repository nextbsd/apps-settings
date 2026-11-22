/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "NBSettingsHelper.h"

#include "NBHelperClient.h"
#include "settingshelper_types.h"

#include <math.h>

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

+ (int)setTimeZone:(NSString *)zone
     authorization:(NBAuthorization *)auth
{
  if ([zone length] == 0)
    return NBAuthorizationInvalid;
  return NBHelperSetTimeZone ([[auth externalForm] bytes], [zone UTF8String]);
}

+ (int)setDate:(NSDate *)date
 authorization:(NBAuthorization *)auth
{
  double t = [date timeIntervalSince1970];
  int64_t seconds = (int64_t) floor (t);
  int micro = (int) ((t - (double) seconds) * 1e6);

  return NBHelperSetDate ([[auth externalForm] bytes], seconds,
                          micro > 999999 ? 999999 : micro);
}

+ (int)setNetworkTime:(BOOL)enabled
               server:(NSString *)server
        authorization:(NBAuthorization *)auth
{
  return NBHelperSetNetworkTime ([[auth externalForm] bytes], enabled ? 1 : 0,
                                 server != nil ? [server UTF8String] : "");
}

+ (int)createUser:(NSString *)user
         fullName:(NSString *)fullName
         password:(NSString *)password
            admin:(BOOL)admin
    authorization:(NBAuthorization *)auth
{
  if ([user length] == 0)
    return NBAuthorizationInvalid;
  return NBHelperCreateUser ([[auth externalForm] bytes], [user UTF8String],
                             fullName != nil ? [fullName UTF8String] : "",
                             password != nil ? [password UTF8String] : "",
                             admin ? 1 : 0);
}

+ (int)deleteUser:(NSString *)user
         keepHome:(BOOL)keepHome
    authorization:(NBAuthorization *)auth
{
  if ([user length] == 0)
    return NBAuthorizationInvalid;
  return NBHelperDeleteUser ([[auth externalForm] bytes], [user UTF8String],
                             keepHome ? 1 : 0);
}

+ (int)setPassword:(NSString *)password
           forUser:(NSString *)user
     authorization:(NBAuthorization *)auth
{
  if ([user length] == 0)
    return NBAuthorizationInvalid;
  return NBHelperSetPassword ([[auth externalForm] bytes], [user UTF8String],
                              password != nil ? [password UTF8String] : "");
}

+ (int)setAdmin:(BOOL)admin
        forUser:(NSString *)user
  authorization:(NBAuthorization *)auth
{
  if ([user length] == 0)
    return NBAuthorizationInvalid;
  return NBHelperSetAdmin ([[auth externalForm] bytes], [user UTF8String],
                           admin ? 1 : 0);
}

+ (int)setAutoLoginUser:(NSString *)user
          authorization:(NBAuthorization *)auth
{
  return NBHelperSetAutoLogin ([[auth externalForm] bytes],
                               user != nil ? [user UTF8String] : "");
}

+ (int)setLoginWindowShowsNameFields:(BOOL)nameFields
                        powerButtons:(BOOL)powerButtons
                       authorization:(NBAuthorization *)auth
{
  return NBHelperSetLoginWindowOptions ([[auth externalForm] bytes],
                                        nameFields ? 1 : 0,
                                        powerButtons ? 1 : 0);
}

@end
