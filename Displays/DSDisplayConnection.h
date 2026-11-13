/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * DSDisplayConnection: Displays' own tool connection to WindowServer
 * (WS_CONNECT_CONTROL, as wsctl's), beside the GNUstep backend's. It
 * reads the display entries of WS_MSG_GET_SETTINGS (DisplayName,
 * DisplayPanel, DisplayModes, DisplayDefault, DisplayCurrent,
 * DisplayLooksLike; "HiDPI" in apps-windowserver's WSProtocol.h), sets
 * DisplayLooksLike, and tells its delegate when the screen or the
 * settings change (WS_EVENT_SCREEN_CHANGED, WS_EVENT_SETTINGS_CHANGED).
 * When WindowServer goes away it tries again every few seconds.
 */

#import <Foundation/Foundation.h>

@class DSDisplayConnection;

@protocol DSDisplayConnectionDelegate
/* Connected, disconnected, or the display changed: read it again. */
- (void)displayConnectionDidChange:(DSDisplayConnection *)connection;
@end

@interface DSDisplayConnection : NSObject
{
  void *_conn;			/* ws_connection_t */
  id _delegate;			/* not retained */
  NSTimer *_retryTimer;
  BOOL _changed;
}

- (id)initWithDelegate:(id<DSDisplayConnectionDelegate>)delegate;
- (void)invalidate;

- (BOOL)isConnected;

/* The Display* entries WindowServer lists, key -> value string. Empty
   when not connected; without DisplayModes when the server has no
   display settings. */
- (NSDictionary *)displaySettings;

/* Set DisplayLooksLike to "WxH" or "Default". Returns 0, or the errno
   value WindowServer refused it with. */
- (int)setLooksLike:(NSString *)value;

@end
