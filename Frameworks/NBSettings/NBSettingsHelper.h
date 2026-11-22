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

/* CommitNetworkPreferences' settings, for one service. Strings are
 * addresses as text; the lists are NSArrays of NSStrings, empty for
 * what DHCP gives. Keys left out are empty. */
extern NSString *const NBNetIPv4Method;		/* NSNumber, NBNetIPv4* */
extern NSString *const NBNetIPv4Address;
extern NSString *const NBNetIPv4SubnetMask;
extern NSString *const NBNetIPv4Router;
extern NSString *const NBNetIPv6Method;		/* NSNumber, NBNetIPv6* */
extern NSString *const NBNetIPv6Address;
extern NSString *const NBNetIPv6PrefixLength;	/* NSNumber */
extern NSString *const NBNetIPv6Router;
extern NSString *const NBNetDNSServers;
extern NSString *const NBNetSearchDomains;

/* The methods, settingshelper_types.h's SH_NET_V4_* and SH_NET_V6_*. */
enum
{
  NBNetIPv4DHCP = 0,
  NBNetIPv4DHCPManualAddress = 1,
  NBNetIPv4Manual = 2,
  NBNetIPv4Off = 3
};
enum
{
  NBNetIPv6Automatic = 0,
  NBNetIPv6Manual = 1,
  NBNetIPv6LinkLocal = 2,
  NBNetIPv6Off = 3
};

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

/* Right: org.nextbsd.settings.users. A new local account: short name,
 * full name, a password ("" or nil for none), an administrator or not. */
+ (int)createUser:(NSString *)user
         fullName:(NSString *)fullName
         password:(NSString *)password
            admin:(BOOL)admin
    authorization:(NBAuthorization *)auth;

/* Right: org.nextbsd.settings.users. Removes the account, and its home
 * in /Local/Users unless keepHome. */
+ (int)deleteUser:(NSString *)user
         keepHome:(BOOL)keepHome
    authorization:(NBAuthorization *)auth;

/* Right: org.nextbsd.settings.users, or for the console user's own
 * account org.nextbsd.settings.users.own-password, proved first with
 * -authorizeUser:password: and the old password. "" or nil: no
 * password. */
+ (int)setPassword:(NSString *)password
           forUser:(NSString *)user
     authorization:(NBAuthorization *)auth;

/* Right: org.nextbsd.settings.users. In group admin or not. */
+ (int)setAdmin:(BOOL)admin
        forUser:(NSString *)user
  authorization:(NBAuthorization *)auth;

/* Right: org.nextbsd.settings.users. The account (one without a
 * password) logged in at startup; nil turns automatic login off. */
+ (int)setAutoLoginUser:(NSString *)user
          authorization:(NBAuthorization *)auth;

/* Right: org.nextbsd.settings.users. The login window asks for a name
 * and password, or lists the users; it shows Restart and Shut Down, or
 * not. */
+ (int)setLoginWindowShowsNameFields:(BOOL)nameFields
                        powerButtons:(BOOL)powerButtons
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

/* Right: org.nextbsd.settings.network. One network service's TCP/IP and
 * DNS settings (the NBNet* keys above), committed and applied; the
 * service is configured again at once. */
+ (int)commitNetworkService:(NSString *)serviceID
                   settings:(NSDictionary *)settings
              authorization:(NBAuthorization *)auth;

/* Right: org.nextbsd.settings.network. The ComputerName and the
 * LocalHostName (a DNS label, without ".local"). */
+ (int)setComputerName:(NSString *)name
         localHostName:(NSString *)localName
         authorization:(NBAuthorization *)auth;

/* Right: org.nextbsd.settings.locale. The system's language, the
 * default login class's: a locale from /usr/share/locale
 * ("de_DE.UTF-8"), which accounts without their own get at their next
 * login. */
+ (int)setSystemLocale:(NSString *)locale
         authorization:(NBAuthorization *)auth;

@end
