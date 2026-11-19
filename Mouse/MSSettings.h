/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * MSSettings: a settings app's view onto some of WindowServer's
 * settings ("Settings" in apps-windowserver's WSProtocol.h), through
 * its own tool connection (WS_CONNECT_CONTROL, as wsctl's).
 *
 *   - It reads the values in effect (WS_MSG_GET_SETTINGS) of the keys
 *     it was given, and the input devices (WS_MSG_LIST_INPUT_DEVICES).
 *   - A change goes to WindowServer at once (WS_MSG_SET_SETTINGS) and
 *     is saved in the user's org.nextbsd.WindowServer defaults
 *     (~/Library/Preferences/org.nextbsd.WindowServer.plist), which the
 *     session sends again at the next login (wsctl settings reload).
 *     Going back to the default drops both.
 *   - Its delegate hears when the settings change (from this app or
 *     any other: WS_EVENT_SETTINGS_CHANGED), when the input devices
 *     change (checked every few seconds; there's no event for it), and
 *     when WindowServer comes and goes (it tries again every few
 *     seconds).
 *
 * Trackpad.app and Mouse.app each have a copy (TPSettings,
 * MSSettings), to become part of the settings framework
 * (nextbsd/nextbsd#627).
 */

#import <Foundation/Foundation.h>

@class MSSettings;

/* The type of a setting's value, WindowServer's WS_SETTING_*. */
typedef enum
{
  MSSettingString = 's',
  MSSettingInteger = 'i',
  MSSettingBoolean = 'b',
  MSSettingReal = 'r'
} MSSettingType;

/* An input device's kind, WindowServer's WS_INPUT_*. */
enum
{
  MSInputKeyboard = 0x0001,
  MSInputPointer = 0x0002,
  MSInputTouchpad = 0x0004,
  MSInputMouse = 0x0008,
  MSInputTouch = 0x0010
};

@protocol MSSettingsDelegate
/* Connected, disconnected, or the settings or devices changed. */
- (void)settingsDidChange:(MSSettings *)settings;
@end

@interface MSSettings : NSObject
{
  void *_conn;			/* ws_connection_t */
  id _delegate;			/* not retained */
  NSDictionary *_types;		/* key -> NSNumber MSSettingType */
  NSDictionary *_values;	/* key -> value in effect, as text */
  NSSet *_sessionKeys;		/* keys the user's session has set */
  NSArray *_devices;		/* NSDictionary: name, sysname, flags */
  NSTimer *_retryTimer;
  NSTimer *_deviceTimer;
  BOOL _changed;
}

/* types: key -> NSNumber MSSettingType, the keys the app shows. */
- (id)initWithTypes:(NSDictionary *)types
           delegate:(id<MSSettingsDelegate>)delegate;
- (void)invalidate;

- (BOOL)isConnected;

/* Whether this WindowServer's settings change while it runs
   (WS_SERVER_SETTINGS). */
- (BOOL)canChangeSettings;

/* The keys' values in effect, as text. Keys the server doesn't have
   are missing. */
- (NSDictionary *)values;
- (NSString *)valueForKey:(NSString *)key;
- (BOOL)boolForKey:(NSString *)key;
- (double)doubleForKey:(NSString *)key;

/* The input devices, each an NSDictionary with "name", "sysname" and
   "flags" (NSNumber, MSInput*). */
- (NSArray *)devices;

/* Change a key now and save it as the user's. Returns 0 or the errno
   value WindowServer refused it with. */
- (int)setValue:(NSString *)value forKey:(NSString *)key;
- (int)setBool:(BOOL)value forKey:(NSString *)key;
- (int)setDouble:(double)value forKey:(NSString *)key;

/* Back to the system's value: drop the user's, here and saved. */
- (int)resetKeys:(NSArray *)keys;

/* What the keys are now, saved and in the session, for -restore:
   (the Revert button). */
- (id)snapshotOfKeys:(NSArray *)keys;
- (int)restore:(id)snapshot;

@end
