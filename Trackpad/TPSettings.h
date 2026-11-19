/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * TPSettings: a settings app's view onto some of WindowServer's
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

@class TPSettings;

/* The type of a setting's value, WindowServer's WS_SETTING_*. */
typedef enum
{
  TPSettingString = 's',
  TPSettingInteger = 'i',
  TPSettingBoolean = 'b',
  TPSettingReal = 'r'
} TPSettingType;

/* An input device's kind, WindowServer's WS_INPUT_*. */
enum
{
  TPInputKeyboard = 0x0001,
  TPInputPointer = 0x0002,
  TPInputTouchpad = 0x0004,
  TPInputMouse = 0x0008,
  TPInputTouch = 0x0010
};

@protocol TPSettingsDelegate
/* Connected, disconnected, or the settings or devices changed. */
- (void)settingsDidChange:(TPSettings *)settings;
@end

@interface TPSettings : NSObject
{
  void *_conn;			/* ws_connection_t */
  id _delegate;			/* not retained */
  NSDictionary *_types;		/* key -> NSNumber TPSettingType */
  NSDictionary *_values;	/* key -> value in effect, as text */
  NSSet *_sessionKeys;		/* keys the user's session has set */
  NSArray *_devices;		/* NSDictionary: name, sysname, flags */
  NSTimer *_retryTimer;
  NSTimer *_deviceTimer;
  BOOL _changed;
}

/* types: key -> NSNumber TPSettingType, the keys the app shows. */
- (id)initWithTypes:(NSDictionary *)types
           delegate:(id<TPSettingsDelegate>)delegate;
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
   "flags" (NSNumber, TPInput*). */
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
