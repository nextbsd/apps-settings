/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "DSDisplayConnection.h"
#import "DSDisplay.h"
#import "DSFakeDisplays.h"
#import <AppKit/NSApplication.h>
#import <GNUstepBase/GNUstep.h>

#include <errno.h>
#include <math.h>
#include <stdint.h>
#include <string.h>

#include <WindowServer/WSClient.h>

/*
 * WS_SERVER_DISPLAYS came with the several-displays protocol (E40 T6).
 * Built against an older WindowServerClient, Displays keeps to the
 * Display* settings, as it would with an older server.
 */
#ifdef WS_SERVER_DISPLAYS
#define DS_HAVE_DISPLAYS 1
/* DSDisplay.h repeats WindowServer's values. WS_DISPLAY_CONFIRM and
   WS_DISPLAY_REVERT_MS (DSConfirm, DSRevertSeconds) are in WSProtocol.h,
   whose Mach headers clash with GNUstep's, so they aren't checked here;
   the DSOp* values never reach WindowServer. */
_Static_assert (DSDisplayMain == WS_DISPLAY_MAIN
                && DSDisplayBuiltin == WS_DISPLAY_BUILTIN
                && DSDisplayMirror == WS_DISPLAY_MIRROR
                && DSDisplayHiDPI == WS_DISPLAY_HIDPI
                && DSDisplayPending == WS_DISPLAY_PENDING
                && DSModeLooksLike == WS_DISPLAY_MODE_LOOKS_LIKE
                && DSModePanel == WS_DISPLAY_MODE_PANEL
                && DSModeCurrent == WS_DISPLAY_MODE_CURRENT
                && DSModeDefault == WS_DISPLAY_MODE_DEFAULT
                && DSModeInterlaced == WS_DISPLAY_MODE_INTERLACED,
                "DSDisplay* and DSMode* are WS_DISPLAY_*");
#else
#define DS_HAVE_DISPLAYS 0
#endif

#define CONN ((ws_connection_t *)_conn)

/* Seconds between attempts to reach WindowServer. */
#define DSRetryInterval 3.0

static NSArray *
DSWatchedModes (void)
{
  return [NSArray arrayWithObjects:NSDefaultRunLoopMode,
                  NSEventTrackingRunLoopMode, NSModalPanelRunLoopMode, nil];
}

@interface DSDisplayConnection (Private)
- (BOOL)connect;
- (void)disconnect;
- (void)retry:(NSTimer *)timer;
- (void)startRetrying;
- (void)processEvents;
- (void)handleEvent:(const ws_event_t *)event;
- (void)checkLost:(int)error;
- (void)notifyDelegate;
- (NSArray *)displaysFromSettings;
- (int)configure:(unsigned)op
         display:(DSDisplay *)display
               x:(int)x
               y:(int)y
           width:(unsigned)width
          height:(unsigned)height
         refresh:(unsigned)refresh
             arg:(unsigned)arg
           flags:(unsigned)flags;
@end

static void
DSHandleEvent (ws_connection_t *conn, const ws_event_t *event, void *ctx)
{
  (void)conn;
  [(DSDisplayConnection *)ctx handleEvent:event];
}

static BOOL
DSIsShownSetting (const char *key)
{
  return strncmp (key, "Display", 7) == 0
    || strncmp (key, "NightShift", 10) == 0;
}

static void
DSCollectSetting (const ws_event_setting_t *setting, void *ctx)
{
  NSMutableDictionary *dict = (NSMutableDictionary *)ctx;

  if (!DSIsShownSetting (setting->key))
    return;
  NSString *key = [NSString stringWithUTF8String:setting->key];
  NSString *value = [NSString stringWithUTF8String:setting->value];
  if (key != nil && value != nil)
    [dict setObject:value forKey:key];
}

/* "3840x2160" -> 3840, 2160; NO if it isn't a size. */
static BOOL
DSParseSize (NSString *text, unsigned *width, unsigned *height)
{
  NSArray *parts = [text componentsSeparatedByString:@"x"];
  int w, h;

  if ([parts count] != 2)
    return NO;
  w = [[parts objectAtIndex:0] intValue];
  h = [[parts objectAtIndex:1] intValue];
  if (w <= 0 || h <= 0)
    return NO;
  *width = (unsigned) w;
  *height = (unsigned) h;
  return YES;
}

#if DS_HAVE_DISPLAYS
static NSString *
DSString (const char *chars, size_t size)
{
  NSString *s = AUTORELEASE ([[NSString alloc]
                               initWithBytes:chars
                                      length:strnlen (chars, size)
                                    encoding:NSUTF8StringEncoding]);
  return s != nil ? s : @"";
}

static void
DSCollectDisplay (const ws_display_info_t *info, void *ctx)
{
  NSMutableArray *list = (NSMutableArray *)ctx;
  DSDisplay *display = [[DSDisplay alloc]
      initWithID:info->display_id
           flags:info->flags
           frame:NSMakeRect (info->frame.x, info->frame.y,
                             info->frame.width, info->frame.height)
           scale:info->scale
      panelWidth:info->panel_width
     panelHeight:info->panel_height
      refreshMHz:info->refresh_mhz
        mirrorOf:info->mirror_of
        revertMS:info->revert_ms
            name:DSString (info->name, sizeof (info->name))
          edidID:DSString (info->edid_id, sizeof (info->edid_id))
       connector:DSString (info->connector, sizeof (info->connector))];
  [list addObject:display];
  RELEASE (display);
}

static void
DSCollectMode (const ws_display_mode_t *mode, void *ctx)
{
  NSMutableArray *list = (NSMutableArray *)ctx;

  [list addObject:[DSDisplayMode modeWithKind:mode->kind
                                        flags:mode->flags
                                        width:mode->width
                                       height:mode->height
                                   refreshMHz:mode->refresh_mhz]];
}
#endif

@implementation DSDisplayConnection

- (id)initWithDelegate:(id<DSDisplayConnectionDelegate>)delegate
{
  if ((self = [super init]) == nil)
    return nil;
  /* The delegate hears about this first connection only when it
     comes later, through the retries. */
  if (![self connect])
    [self startRetrying];
  _delegate = delegate;
  _fake = RETAIN ([DSFakeDisplays fakeDisplaysWithTarget:self
                                                selector:@selector (notifyDelegate)]);
  return self;
}

- (void)dealloc
{
  [self invalidate];
  [super dealloc];
}

- (void)invalidate
{
  [_retryTimer invalidate];
  DESTROY (_retryTimer);
  [self disconnect];
  DESTROY (_fake);
  _delegate = nil;
}

- (BOOL)isConnected
{
  return _conn != NULL || _fake != nil;
}

- (BOOL)hasDisplayList
{
  if (_fake != nil)
    return YES;
#if DS_HAVE_DISPLAYS
  return _conn != NULL && (ws_server_flags (CONN) & WS_SERVER_DISPLAYS) != 0;
#else
  return NO;
#endif
}

- (NSDictionary *)settings
{
  NSMutableDictionary *dict = [NSMutableDictionary dictionary];

  if (_fake != nil)
    return [_fake settings];
  if (_conn == NULL)
    return dict;
  if (ws_get_settings (CONN, DSCollectSetting, dict) < 0)
    {
      int e = errno;
      NSLog (@"Displays: can't read WindowServer's settings: %s",
             strerror (e));
      [self checkLost:e];
      return [NSMutableDictionary dictionary];
    }
  /* Events read while waiting for the answer are queued in the
     library: handle them from the run loop. */
  if (ws_pending (CONN))
    [self performSelector:@selector (processEvents) withObject:nil afterDelay:0];
  return dict;
}

- (NSArray *)displays
{
  if (_fake != nil)
    return [_fake displays];
  if (![self hasDisplayList])
    return [self displaysFromSettings];
#if DS_HAVE_DISPLAYS
  NSMutableArray *list = [NSMutableArray array];
  NSEnumerator *e;
  DSDisplay *display;

  if (ws_list_displays (CONN, DSCollectDisplay, list) < 0)
    {
      int e = errno;
      NSLog (@"Displays: can't list the displays: %s", strerror (e));
      [self checkLost:e];
      return [NSArray array];
    }
  e = [list objectEnumerator];
  while ((display = [e nextObject]) != nil)
    {
      NSMutableArray *modes = [NSMutableArray array];

      if (ws_list_display_modes (CONN, [display displayID], DSCollectMode,
                                 modes) < 0)
        {
          int e = errno;

          /* It may have just gone; the event that says so follows. */
          NSLog (@"Displays: can't list %@'s modes: %s", [display name],
                 strerror (e));
          if (e != ENOENT)
            {
              [self checkLost:e];
              if (_conn == NULL)
                return [NSArray array];
            }
          continue;
        }
      [display setModes:modes];
      [display setFollowsDefault:[[display currentLooksLike] isDefault]];
    }
  if (ws_pending (CONN))
    [self performSelector:@selector (processEvents) withObject:nil afterDelay:0];
  return list;
#else
  return [NSArray array];
#endif
}

- (int)setLooksLike:(DSDisplayMode *)mode
         forDisplay:(DSDisplay *)display
            confirm:(BOOL)confirm
{
  if ([self hasDisplayList])
    return [self configure:DSOpSetLooksLike
                   display:display
                         x:0
                         y:0
                     width:(mode != nil ? [mode width] : 0)
                    height:(mode != nil ? [mode height] : 0)
                   refresh:0
                       arg:0
                     flags:(confirm ? DSConfirm : 0)];

  /* The settings way, for the one display. */
  NSString *value = mode != nil
    ? [NSString stringWithFormat:@"%ux%u", [mode width], [mode height]]
    : @"Default";
  return [self setSetting:@"DisplayLooksLike" value:value];
}

- (int)setModeWidth:(unsigned)width
             height:(unsigned)height
         refreshMHz:(unsigned)refresh
         forDisplay:(DSDisplay *)display
{
  return [self configure:DSOpSetMode
                 display:display
                       x:0
                       y:0
                   width:width
                  height:height
                 refresh:refresh
                     arg:0
                   flags:DSConfirm];
}

- (int)setOrigin:(NSPoint)origin forDisplay:(DSDisplay *)display
{
  return [self configure:DSOpSetOrigin
                 display:display
                       x:(int) lrint (origin.x)
                       y:(int) lrint (origin.y)
                   width:0
                  height:0
                 refresh:0
                     arg:0
                   flags:0];
}

- (int)setMainDisplay:(DSDisplay *)display
{
  return [self configure:DSOpSetMain
                 display:display
                       x:0
                       y:0
                   width:0
                  height:0
                 refresh:0
                     arg:0
                   flags:0];
}

- (int)setMirrorOf:(unsigned)of forDisplay:(DSDisplay *)display
{
  return [self configure:DSOpSetMirror
                 display:display
                       x:0
                       y:0
                   width:0
                  height:0
                 refresh:0
                     arg:of
                   flags:DSConfirm];
}

- (int)keepChanges
{
  return [self configure:DSOpKeep display:nil x:0 y:0 width:0 height:0
                 refresh:0 arg:0 flags:0];
}

- (int)revertChanges
{
  return [self configure:DSOpRevert display:nil x:0 y:0 width:0 height:0
                 refresh:0 arg:0 flags:0];
}

- (int)setSetting:(NSString *)key value:(NSString *)value
{
  ws_setting_t setting;
  char failed[64] = "";

  if (_fake != nil)
    return [_fake setSetting:key value:value];
  if (_conn == NULL)
    return ENOTCONN;
  setting.key = [key UTF8String];
  setting.type = WS_SETTING_STRING;
  setting.value = [value UTF8String];
  if (ws_set_settings (CONN, 0, &setting, 1, failed, sizeof (failed)) < 0)
    {
      int e = errno;
      NSLog (@"Displays: WindowServer refused %@ %@: %s", key, value,
             strerror (e));
      [self checkLost:e];
      return e;
    }
  return 0;
}

@end

@implementation DSDisplayConnection (Private)

- (BOOL)connect
{
  ws_connection_t *conn = ws_connect ("Displays", WS_CONNECT_CONTROL);
  NSRunLoop *loop = [NSRunLoop currentRunLoop];
  NSArray *modes = DSWatchedModes ();
  NSUInteger i;

  if (conn == NULL)
    return NO;
  _conn = conn;
  for (i = 0; i < [modes count]; i++)
    [loop addEvent:(void *)(intptr_t)ws_connection_fd (conn)
              type:ET_RDESC
           watcher:(id<RunLoopEvents>)self
           forMode:[modes objectAtIndex:i]];
  [_delegate displayConnectionDidChange:self];
  return YES;
}

- (void)disconnect
{
  NSRunLoop *loop = [NSRunLoop currentRunLoop];
  NSArray *modes = DSWatchedModes ();
  NSUInteger i;

  if (_conn == NULL)
    return;
  for (i = 0; i < [modes count]; i++)
    [loop removeEvent:(void *)(intptr_t)ws_connection_fd (CONN)
                 type:ET_RDESC
              forMode:[modes objectAtIndex:i]
                  all:YES];
  ws_disconnect (CONN);
  _conn = NULL;
}

- (void)startRetrying
{
  if (_retryTimer != nil)
    return;
  ASSIGN (_retryTimer, [NSTimer scheduledTimerWithTimeInterval:DSRetryInterval
                                                        target:self
                                                      selector:@selector (retry:)
                                                      userInfo:nil
                                                       repeats:YES]);
}

- (void)retry:(NSTimer *)timer
{
  if ([self connect])
    {
      [_retryTimer invalidate];
      DESTROY (_retryTimer);
    }
}

/* After a failed request: if it was the connection that failed, start
   over, and tell the delegate from the run loop. */
- (void)checkLost:(int)error
{
  if (error == EPIPE || error == ECONNRESET || error == ENOTCONN)
    {
      [self disconnect];
      [self startRetrying];
      [self performSelector:@selector (notifyDelegate) withObject:nil
                 afterDelay:0];
    }
}

/* Also how the test build's made-up displays say they changed. */
- (void)notifyDelegate
{
  [_delegate displayConnectionDidChange:self];
}

- (void)receivedEvent:(void *)data
                 type:(RunLoopEventType)type
                extra:(void *)extra
              forMode:(NSString *)mode
{
  [self processEvents];
}

- (void)processEvents
{
  if (_conn == NULL)
    return;
  _changed = NO;
  if (ws_dispatch (CONN, DSHandleEvent, self) < 0)
    {
      NSLog (@"Displays: lost the WindowServer connection (%s)",
             strerror (errno));
      [self disconnect];
      [self startRetrying];
      [_delegate displayConnectionDidChange:self];
      return;
    }
  if (_changed)
    {
      _changed = NO;
      [_delegate displayConnectionDidChange:self];
    }
}

- (void)handleEvent:(const ws_event_t *)event
{
  switch (event->hdr.type)
    {
    case WS_EVENT_SCREEN_CHANGED:
    case WS_EVENT_SETTINGS_CHANGED:
#if DS_HAVE_DISPLAYS
    case WS_EVENT_DISPLAYS_CHANGED:
#endif
      _changed = YES;
      break;
    default:
      break;
    }
}

/* The one display the Display* settings describe, for servers
   without a display list. */
- (NSArray *)displaysFromSettings
{
  NSDictionary *settings = [self settings];
  NSString *panel = [settings objectForKey:@"DisplayPanel"];
  NSString *current = [settings objectForKey:@"DisplayCurrent"];
  NSString *defaultSize = [settings objectForKey:@"DisplayDefault"];
  NSString *looksLike = [settings objectForKey:@"DisplayLooksLike"];
  NSMutableArray *modes = [NSMutableArray array];
  NSEnumerator *e;
  NSString *size;
  unsigned panelW = 0, panelH = 0, curW = 0, curH = 0, defW = 0, defH = 0;
  unsigned scale = 1;
  NSRange at;
  DSDisplay *display;

  if (panel == nil || !DSParseSize (panel, &panelW, &panelH))
    return [NSArray array];

  /* DisplayCurrent "1920x1080@2" */
  at = [current rangeOfString:@"@"];
  if (current != nil && at.location != NSNotFound)
    {
      scale = (unsigned) MAX (1, [[current substringFromIndex:NSMaxRange (at)]
                                   intValue]);
      current = [current substringToIndex:at.location];
    }
  if (current == nil || !DSParseSize (current, &curW, &curH))
    {
      curW = panelW / scale;
      curH = panelH / scale;
    }
  if (defaultSize != nil)
    DSParseSize (defaultSize, &defW, &defH);

  e = [[[settings objectForKey:@"DisplayModes"]
         componentsSeparatedByString:@","] objectEnumerator];
  while ((size = [e nextObject]) != nil)
    {
      unsigned w, h, flags = 0;

      size = [size stringByTrimmingCharactersInSet:
                     [NSCharacterSet whitespaceCharacterSet]];
      if (!DSParseSize (size, &w, &h))
        continue;
      if (w == curW && h == curH)
        flags |= DSModeCurrent;
      if (w == defW && h == defH)
        flags |= DSModeDefault;
      [modes addObject:[DSDisplayMode modeWithKind:DSModeLooksLike
                                             flags:flags
                                             width:w
                                            height:h
                                        refreshMHz:0]];
    }

  display = [[DSDisplay alloc]
      initWithID:(unsigned) [[settings objectForKey:@"DisplayID"] intValue]
           flags:DSDisplayMain | (scale > 1 ? DSDisplayHiDPI : 0)
           frame:NSMakeRect (0, 0, curW, curH)
           scale:scale
      panelWidth:panelW
     panelHeight:panelH
      refreshMHz:0
        mirrorOf:0
        revertMS:0
            name:[settings objectForKey:@"DisplayName"]
          edidID:nil
       connector:nil];
  [display setModes:modes];
  [display setFollowsDefault:(looksLike == nil
                              || [looksLike isEqual:@"Default"])];
  return [NSArray arrayWithObject:AUTORELEASE (display)];
}

- (int)configure:(unsigned)op
         display:(DSDisplay *)display
               x:(int)x
               y:(int)y
           width:(unsigned)width
          height:(unsigned)height
         refresh:(unsigned)refresh
             arg:(unsigned)arg
           flags:(unsigned)flags
{
  unsigned did = [display displayID];
  int r = -1;

  if (_fake != nil)
    return [(DSFakeDisplays *)_fake configure:op display:did x:x y:y width:width height:height
                    refresh:refresh arg:arg flags:flags];
  if (![self hasDisplayList])
    return _conn == NULL ? ENOTCONN : ENOTSUP;
#if DS_HAVE_DISPLAYS
  switch (op)
    {
    case DSOpSetLooksLike:
      r = ws_display_set_looks_like (CONN, did, width, height, flags);
      break;
    case DSOpSetMode:
      r = ws_display_set_mode (CONN, did, width, height, refresh, flags);
      break;
    case DSOpSetOrigin:
      r = ws_display_set_origin (CONN, did, x, y, flags);
      break;
    case DSOpSetMain:
      r = ws_display_set_main (CONN, did, flags);
      break;
    case DSOpSetMirror:
      r = ws_display_set_mirror (CONN, did, arg, flags);
      break;
    case DSOpKeep:
      r = ws_display_keep (CONN);
      break;
    case DSOpRevert:
      r = ws_display_revert (CONN);
      break;
    default:
      errno = EINVAL;
      break;
    }
#endif
  if (r < 0)
    {
      int e = errno;
      NSLog (@"Displays: WindowServer refused change %u to display %u: %s",
             op, did, strerror (e));
      [self checkLost:e];
      return e;
    }
  return 0;
}

@end
