/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * NBSettingsHelper: the settings apps' calls to SettingsHelper's
 * operations (nextbsd-userland src/SettingsHelper/settingshelper.defs),
 * one class method per operation. Each takes the NBAuthorization for its
 * right and returns an NBAuthorization status (NBAuthorizationOK, or why
 * not). Each app ticket that adds a helper operation adds its method
 * here.
 */

#import <Foundation/Foundation.h>
#import "NBAuthorization.h"

/* SetPMPreferences' power sources. */
extern NSString *const NBPowerSourceAC;		/* "AC Power" */
extern NSString *const NBPowerSourceBattery;	/* "Battery Power" */
extern NSString *const NBPowerSourceUPS;	/* "UPS Power" */

/* SetPMPreferences' settings, pmset's names. Values are NSNumbers:
 * minutes (0 for never) for the timers, 0 or 1 for the others, or
 * NBPMDefault for the system's default. */
extern NSString *const NBPMDisplaySleep;	/* displaysleep */
extern NSString *const NBPMSystemSleep;		/* sleep */
extern NSString *const NBPMDiskSleep;		/* disksleep */
extern NSString *const NBPMWakeOnLAN;		/* womp */
extern NSString *const NBPMReduceBrightness;	/* lessbright */
extern NSString *const NBPMTTYSKeepAwake;	/* ttyskeepawake */
#define NBPMDefault (-2)

@interface NBSettingsHelper : NSObject

/* Right: org.nextbsd.settings.energy. Settings not in `values` stay as
 * they are. */
+ (int)setPMPreferences:(NSDictionary *)values
         forPowerSource:(NSString *)source
          authorization:(NBAuthorization *)auth;

/* Right: org.nextbsd.settings.datetime. A zone name from
 * /usr/share/zoneinfo ("America/Chicago"); processes hear
 * com.apple.system.timezone. */
+ (int)setTimeZone:(NSString *)zone
     authorization:(NBAuthorization *)auth;

/* Right: org.nextbsd.settings.datetime. Sets the clock; processes hear
 * com.apple.system.clock_set. */
+ (int)setDate:(NSDate *)date
 authorization:(NBAuthorization *)auth;

/* Right: org.nextbsd.settings.datetime. Network time (ntpd) on or off;
 * a server (host name or address) replaces ntp.conf's, nil leaves them
 * as they are. */
+ (int)setNetworkTime:(BOOL)enabled
               server:(NSString *)server
        authorization:(NBAuthorization *)auth;

/* Right: org.nextbsd.settings.printers. CUPSAdmin: a driverless (IPP
 * Everywhere) printer added to the local cupsd as the queue `name`, for
 * `uri` (ipp://, ipps:// or dnssd://), not shared. info and location
 * may be nil. It asks the printer for its capabilities, so it can take
 * a while: don't call it on the main thread. */
+ (int)addPrinter:(NSString *)name
              uri:(NSString *)uri
             info:(NSString *)info
         location:(NSString *)location
    authorization:(NBAuthorization *)auth;

/* Right: org.nextbsd.settings.printers. CUPSAdmin: the queue `name`
 * removed, with its jobs. */
+ (int)removePrinter:(NSString *)name
       authorization:(NBAuthorization *)auth;

@end
