/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * DSDisplayConnection: Displays' own tool connection to WindowServer
 * (WS_CONNECT_CONTROL, as wsctl's), beside the GNUstep backend's.
 *
 * On servers with WS_SERVER_DISPLAYS ("Displays" in apps-windowserver's
 * WSProtocol.h) it lists every display and its modes and changes them
 * with WS_MSG_DISPLAY_CONFIGURE. On older servers it reads the one
 * display from the Display* entries of WS_MSG_GET_SETTINGS ("HiDPI")
 * and sets DisplayLooksLike. Either way it reads and sets the Night
 * Shift settings, and tells its delegate when the displays, the screen
 * or the settings change (WS_EVENT_DISPLAYS_CHANGED,
 * WS_EVENT_SCREEN_CHANGED, WS_EVENT_SETTINGS_CHANGED). When WindowServer
 * goes away it tries again every few seconds.
 *
 * The setters return 0 or the errno value WindowServer refused the
 * change with.
 */

#import <Foundation/Foundation.h>

@class DSDisplay, DSDisplayMode, DSDisplayConnection;

@protocol DSDisplayConnectionDelegate
/* Connected, disconnected, or the displays changed: read them again. */
- (void)displayConnectionDidChange:(DSDisplayConnection *)connection;
@end

@interface DSDisplayConnection : NSObject
{
  void *_conn;			/* ws_connection_t */
  id _delegate;			/* not retained */
  NSTimer *_retryTimer;
  BOOL _changed;
  id _fake;			/* DSFakeDisplays, test builds only */
}

- (id)initWithDelegate:(id<DSDisplayConnectionDelegate>)delegate;
- (void)invalidate;

- (BOOL)isConnected;

/* Whether WindowServer lists displays (WS_SERVER_DISPLAYS): several
   displays, modes, refresh rates, arrangement, mirroring, and changes
   that go back unless kept. Without it there is one display and only
   its "looks like" size can change. */
- (BOOL)hasDisplayList;

/* The settings Displays shows, key -> value string: the Display*
   entries and Night Shift's. Empty when not connected. */
- (NSDictionary *)settings;

/* Every display, the main one first, each with its modes. Without a
   display list, the one display the Display* settings describe, or
   none if the server has no display settings. */
- (NSArray *)displays;

/* A "looks like" size; nil goes back to the display's default. With a
   display list and confirm, the change is pending (DSDisplayPending)
   until -keepChanges. */
- (int)setLooksLike:(DSDisplayMode *)mode
         forDisplay:(DSDisplay *)display
            confirm:(BOOL)confirm;

/* A panel mode (pixels); refresh 0 is the highest the size has.
   Pending until -keepChanges. */
- (int)setModeWidth:(unsigned)width
             height:(unsigned)height
         refreshMHz:(unsigned)refresh
         forDisplay:(DSDisplay *)display;

/* Where the display's top-left corner goes, in desktop points.
   WindowServer moves it to touch the others. Applies at once. */
- (int)setOrigin:(NSPoint)origin forDisplay:(DSDisplay *)display;

/* The menu bar and the Dock go to the display. Applies at once. */
- (int)setMainDisplay:(DSDisplay *)display;

/* The display shows display `of`'s part of the desktop; 0 gives it
   its own part back. Pending until -keepChanges. */
- (int)setMirrorOf:(unsigned)of forDisplay:(DSDisplay *)display;

/* Keep or undo the pending change. */
- (int)keepChanges;
- (int)revertChanges;

/* One WindowServer setting (Night Shift's). */
- (int)setSetting:(NSString *)key value:(NSString *)value;

@end
