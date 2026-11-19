/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * KBConnection: a tool connection to WindowServer (WS_CONNECT_CONTROL,
 * as wsctl's) for Keyboard and its Input menu, beside the GNUstep
 * backend's own.
 *
 * It reads WindowServer's keyboard settings ("Settings" in
 * apps-windowserver's WSProtocol.h) and the layout list, changes them
 * for the session with WS_MSG_SET_SETTINGS and WS_MSG_SET_KEYBOARD_LAYOUT,
 * and tells its delegate when they change (WS_EVENT_SETTINGS_CHANGED,
 * WS_EVENT_KEYBOARD_LAYOUT). When WindowServer goes away it tries again
 * every few seconds.
 *
 * Built into Keyboard.app and into Input.dockextra, which runs in the
 * Dock's process.
 *
 * Copied from Displays' DSDisplayConnection (connecting, retrying,
 * watching the socket on the run loop); a settings framework (#627)
 * can share it later.
 */

#import <Foundation/Foundation.h>

@class KBConnection;

/* Where a setting's value in effect comes from (WS_SETTING_SOURCE_*). */
enum {
  KBSourceBuiltin = 0,
  KBSourceSystem = 1,
  KBSourceSession = 2
};

@protocol KBConnectionDelegate
/* Connected, disconnected, or the settings changed: read them again. */
- (void)connectionDidChange:(KBConnection *)connection;
/* The active layout changed (the shortcut, the Input menu, a request). */
- (void)connectionLayoutDidChange:(KBConnection *)connection;
@end

@interface KBConnection : NSObject
{
  void *_conn;			/* ws_connection_t */
  NSString *_name;
  id _delegate;			/* not retained */
  NSTimer *_retryTimer;
  BOOL _changed;
  BOOL _layoutChanged;
}

- (id)initWithName:(NSString *)name
          delegate:(id<KBConnectionDelegate>)delegate;
- (void)invalidate;

- (BOOL)isConnected;

/* Every setting WindowServer has, key -> value as text; nil when not
   connected. sources, if not NULL, gets key -> NSNumber KBSource*. */
- (NSDictionary *)settingsWithSources:(NSDictionary **)sources;

/* The layout list, each a dictionary of Layout, Variant and Name
   (XKB's description), in order; activeIndex gets the active one's
   index (-1 if none). Empty when not connected. */
- (NSArray *)layoutsWithActiveIndex:(int *)activeIndex;

/* Make layout index of the list active. 0 or an errno value. */
- (int)setActiveLayout:(unsigned)index;

/* Change the session's values in one request: key -> NSString, or
   NSNull to drop the session's value (back to the system's). 0 or the
   errno value WindowServer refused it with; failedKey, if not NULL,
   gets the key it named. */
- (int)setSettings:(NSDictionary *)values failedKey:(NSString **)failedKey;

@end
