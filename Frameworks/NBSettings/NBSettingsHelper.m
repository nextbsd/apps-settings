/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "NBSettingsHelper.h"

#include "NBHelperClient.h"
#include "settingshelper_types.h"

#include <math.h>
#include <string.h>

NSString *const NBPowerSourceAC = @"AC Power";
NSString *const NBPowerSourceBattery = @"Battery Power";
NSString *const NBPowerSourceUPS = @"UPS Power";

NSString *const NBPMDisplaySleep = @"displaysleep";
NSString *const NBPMSystemSleep = @"sleep";
NSString *const NBPMDiskSleep = @"disksleep";
NSString *const NBPMWakeOnLAN = @"womp";
NSString *const NBPMReduceBrightness = @"lessbright";
NSString *const NBPMTTYSKeepAwake = @"ttyskeepawake";

NSString *const NBNetIPv4Method = @"IPv4Method";
NSString *const NBNetIPv4Address = @"IPv4Address";
NSString *const NBNetIPv4SubnetMask = @"IPv4SubnetMask";
NSString *const NBNetIPv4Router = @"IPv4Router";
NSString *const NBNetIPv6Method = @"IPv6Method";
NSString *const NBNetIPv6Address = @"IPv6Address";
NSString *const NBNetIPv6PrefixLength = @"IPv6PrefixLength";
NSString *const NBNetIPv6Router = @"IPv6Router";
NSString *const NBNetDNSServers = @"DNSServers";
NSString *const NBNetSearchDomains = @"SearchDomains";

/* A string setting as UTF-8, "" when it's absent. */
static const char *
NBNetString (NSDictionary *settings, NSString *key)
{
  id value = [settings objectForKey:key];

  return [value isKindOfClass:[NSString class]] ? [value UTF8String] : "";
}

/* A list setting, one entry a line. */
static const char *
NBNetList (NSDictionary *settings, NSString *key)
{
  id value = [settings objectForKey:key];

  if (![value isKindOfClass:[NSArray class]])
    return "";
  return [[value componentsJoinedByString:@"\n"] UTF8String];
}

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

+ (int)addPrinter:(NSString *)name
              uri:(NSString *)uri
             info:(NSString *)info
         location:(NSString *)location
    authorization:(NBAuthorization *)auth
{
  if ([name length] == 0 || [uri length] == 0)
    return NBAuthorizationInvalid;
  return NBHelperCUPSAdmin ([[auth externalForm] bytes], SH_CUPS_ADD,
                            [name UTF8String], [uri UTF8String],
                            info != nil ? [info UTF8String] : "",
                            location != nil ? [location UTF8String] : "");
}

+ (int)removePrinter:(NSString *)name
       authorization:(NBAuthorization *)auth
{
  if ([name length] == 0)
    return NBAuthorizationInvalid;
  return NBHelperCUPSAdmin ([[auth externalForm] bytes], SH_CUPS_DELETE,
                            [name UTF8String], "", "", "");
}


+ (int)commitNetworkService:(NSString *)serviceID
                   settings:(NSDictionary *)settings
              authorization:(NBAuthorization *)auth
{
  NBHelperNetworkService s;

  if ([serviceID length] == 0)
    return NBAuthorizationInvalid;
  memset (&s, 0, sizeof (s));
  s.serviceID = [serviceID UTF8String];
  s.ipv4Method = [[settings objectForKey:NBNetIPv4Method] intValue];
  s.ipv4Address = NBNetString (settings, NBNetIPv4Address);
  s.ipv4Mask = NBNetString (settings, NBNetIPv4SubnetMask);
  s.ipv4Router = NBNetString (settings, NBNetIPv4Router);
  s.ipv6Method = [[settings objectForKey:NBNetIPv6Method] intValue];
  s.ipv6Address = NBNetString (settings, NBNetIPv6Address);
  s.ipv6Prefix = [[settings objectForKey:NBNetIPv6PrefixLength] intValue];
  s.ipv6Router = NBNetString (settings, NBNetIPv6Router);
  s.dnsServers = NBNetList (settings, NBNetDNSServers);
  s.searchDomains = NBNetList (settings, NBNetSearchDomains);
  return NBHelperCommitNetworkPreferences ([[auth externalForm] bytes], &s);
}

+ (int)setComputerName:(NSString *)name
         localHostName:(NSString *)localName
         authorization:(NBAuthorization *)auth
{
  if ([name length] == 0 || [localName length] == 0)
    return NBAuthorizationInvalid;
  return NBHelperSetComputerName ([[auth externalForm] bytes],
                                  [name UTF8String], [localName UTF8String]);
}

+ (int)setSystemLocale:(NSString *)locale
         authorization:(NBAuthorization *)auth
{
  if ([locale length] == 0)
    return NBAuthorizationInvalid;
  return NBHelperSetSystemLocale ([[auth externalForm] bytes],
                                  [locale UTF8String]);
}

@end
