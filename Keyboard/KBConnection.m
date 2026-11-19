/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "KBConnection.h"
#import <AppKit/NSApplication.h>
#import <GNUstepBase/GNUstep.h>

#include <errno.h>
#include <stdint.h>
#include <string.h>

#include <WindowServer/WSClient.h>

#define CONN ((ws_connection_t *)_conn)

/* Seconds between attempts to reach WindowServer. */
#define KBRetryInterval 3.0

static NSArray *
KBWatchedModes (void)
{
  return [NSArray arrayWithObjects:NSDefaultRunLoopMode,
                  NSEventTrackingRunLoopMode, NSModalPanelRunLoopMode, nil];
}

static NSString *
KBString (const char *chars, size_t size)
{
  NSString *s = AUTORELEASE ([[NSString alloc]
                               initWithBytes:chars
                                      length:strnlen (chars, size)
                                    encoding:NSUTF8StringEncoding]);
  return s != nil ? s : @"";
}

@interface KBConnection (Private)
- (BOOL)connect;
- (void)disconnect;
- (void)retry:(NSTimer *)timer;
- (void)startRetrying;
- (void)processEvents;
- (void)processEventsLater;
- (void)handleEvent:(const ws_event_t *)event;
- (void)checkLost:(int)error;
- (void)notifyDelegate;
@end

static void
KBHandleEvent (ws_connection_t *conn, const ws_event_t *event, void *ctx)
{
  (void)conn;
  [(KBConnection *)ctx handleEvent:event];
}

struct KBSettingsContext
{
  NSMutableDictionary *values;
  NSMutableDictionary *sources;
};

static void
KBCollectSetting (const ws_event_setting_t *setting, void *ctx)
{
  struct KBSettingsContext *c = ctx;
  NSString *key = KBString (setting->key, sizeof (setting->key));
  NSString *value = KBString (setting->value, sizeof (setting->value));

  if ([key length] == 0)
    return;
  [c->values setObject:value forKey:key];
  [c->sources setObject:[NSNumber numberWithUnsignedInt:setting->source]
                 forKey:key];
}

struct KBLayoutsContext
{
  NSMutableArray *list;
  int active;
};

static void
KBCollectLayout (const ws_event_keyboard_layout_t *layout, void *ctx)
{
  struct KBLayoutsContext *c = ctx;

  [c->list addObject:
     [NSDictionary dictionaryWithObjectsAndKeys:
        KBString (layout->layout, sizeof (layout->layout)), @"Layout",
        KBString (layout->variant, sizeof (layout->variant)), @"Variant",
        KBString (layout->name, sizeof (layout->name)), @"Name",
        nil]];
  if (layout->flags & WS_KEYBOARD_LAYOUT_ACTIVE)
    c->active = (int) layout->index;
}

@implementation KBConnection

- (id)initWithName:(NSString *)name
          delegate:(id<KBConnectionDelegate>)delegate
{
  if ((self = [super init]) == nil)
    return nil;
  ASSIGN (_name, name);
  /* The delegate hears about this first connection only when it
     comes later, through the retries. */
  if (![self connect])
    [self startRetrying];
  _delegate = delegate;
  return self;
}

- (void)dealloc
{
  [self invalidate];
  RELEASE (_name);
  [super dealloc];
}

- (void)invalidate
{
  [NSObject cancelPreviousPerformRequestsWithTarget:self];
  [_retryTimer invalidate];
  DESTROY (_retryTimer);
  [self disconnect];
  _delegate = nil;
}

- (BOOL)isConnected
{
  return _conn != NULL;
}

- (NSDictionary *)settingsWithSources:(NSDictionary **)sources
{
  struct KBSettingsContext c;

  if (sources != NULL)
    *sources = nil;
  if (_conn == NULL)
    return nil;
  c.values = [NSMutableDictionary dictionary];
  c.sources = [NSMutableDictionary dictionary];
  if (ws_get_settings (CONN, KBCollectSetting, &c) < 0)
    {
      int e = errno;
      NSLog (@"%@: can't read WindowServer's settings: %s", _name,
             strerror (e));
      [self checkLost:e];
      return nil;
    }
  [self processEventsLater];
  if (sources != NULL)
    *sources = c.sources;
  return c.values;
}

- (NSArray *)layoutsWithActiveIndex:(int *)activeIndex
{
  struct KBLayoutsContext c;

  c.list = [NSMutableArray array];
  c.active = -1;
  if (_conn != NULL
      && ws_list_keyboard_layouts (CONN, KBCollectLayout, &c) < 0)
    {
      int e = errno;
      NSLog (@"%@: can't list the keyboard layouts: %s", _name, strerror (e));
      [self checkLost:e];
      [c.list removeAllObjects];
      c.active = -1;
    }
  if (_conn != NULL)
    [self processEventsLater];
  if (activeIndex != NULL)
    *activeIndex = c.active;
  return c.list;
}

- (int)setActiveLayout:(unsigned)index
{
  if (_conn == NULL)
    return ENOTCONN;
  if (ws_set_keyboard_layout (CONN, index) < 0)
    {
      int e = errno;
      NSLog (@"%@: WindowServer refused layout %u: %s", _name, index,
             strerror (e));
      [self checkLost:e];
      return e;
    }
  [self processEventsLater];
  return 0;
}

- (int)setSettings:(NSDictionary *)values failedKey:(NSString **)failedKey
{
  NSUInteger count = [values count], n = 0;
  ws_setting_t *list;
  NSEnumerator *e;
  NSString *key;
  char failed[WS_MAX_SETTING_KEY + 1] = "";
  int r = 0;

  if (failedKey != NULL)
    *failedKey = nil;
  if (_conn == NULL)
    return ENOTCONN;
  if (count == 0)
    return 0;
  list = calloc (count, sizeof (*list));
  if (list == NULL)
    return ENOMEM;
  e = [values keyEnumerator];
  while ((key = [e nextObject]) != nil)
    {
      id value = [values objectForKey:key];

      list[n].key = [key UTF8String];
      if (value == [NSNull null])
        {
          list[n].type = WS_SETTING_DEFAULT;
          list[n].value = "";
        }
      else
        {
          list[n].type = WS_SETTING_STRING;
          list[n].value = [[value description] UTF8String];
        }
      n++;
    }
  if (ws_set_settings (CONN, 0, list, (unsigned) n, failed,
                       sizeof (failed)) < 0)
    {
      r = errno;
      NSLog (@"%@: WindowServer refused %@: %s (%s)", _name, values,
             strerror (r), failed);
      if (failedKey != NULL && failed[0] != '\0')
        *failedKey = [NSString stringWithUTF8String:failed];
      [self checkLost:r];
    }
  else
    [self processEventsLater];
  free (list);
  return r;
}

@end

@implementation KBConnection (Private)

- (BOOL)connect
{
  ws_connection_t *conn = ws_connect ([_name UTF8String], WS_CONNECT_CONTROL);
  NSRunLoop *loop = [NSRunLoop currentRunLoop];
  NSArray *modes = KBWatchedModes ();
  NSUInteger i;

  if (conn == NULL)
    return NO;
  _conn = conn;
  for (i = 0; i < [modes count]; i++)
    [loop addEvent:(void *)(intptr_t)ws_connection_fd (conn)
              type:ET_RDESC
           watcher:(id<RunLoopEvents>)self
           forMode:[modes objectAtIndex:i]];
  [_delegate connectionDidChange:self];
  return YES;
}

- (void)disconnect
{
  NSRunLoop *loop = [NSRunLoop currentRunLoop];
  NSArray *modes = KBWatchedModes ();
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
  ASSIGN (_retryTimer, [NSTimer scheduledTimerWithTimeInterval:KBRetryInterval
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

- (void)notifyDelegate
{
  [_delegate connectionDidChange:self];
}

- (void)receivedEvent:(void *)data
                 type:(RunLoopEventType)type
                extra:(void *)extra
              forMode:(NSString *)mode
{
  [self processEvents];
}

/* Events read while waiting for an answer are queued in the library:
   handle them from the run loop. */
- (void)processEventsLater
{
  if (_conn != NULL && ws_pending (CONN))
    [self performSelector:@selector (processEvents) withObject:nil
               afterDelay:0];
}

- (void)processEvents
{
  if (_conn == NULL)
    return;
  _changed = NO;
  _layoutChanged = NO;
  if (ws_dispatch (CONN, KBHandleEvent, self) < 0)
    {
      NSLog (@"%@: lost the WindowServer connection (%s)", _name,
             strerror (errno));
      [self disconnect];
      [self startRetrying];
      [_delegate connectionDidChange:self];
      return;
    }
  if (_changed)
    {
      _changed = NO;
      _layoutChanged = NO;
      [_delegate connectionDidChange:self];
    }
  else if (_layoutChanged)
    {
      _layoutChanged = NO;
      [_delegate connectionLayoutDidChange:self];
    }
}

- (void)handleEvent:(const ws_event_t *)event
{
  switch (event->hdr.type)
    {
    case WS_EVENT_SETTINGS_CHANGED:
      _changed = YES;
      break;
    case WS_EVENT_KEYBOARD_LAYOUT:
      if (event->u.keyboard_layout.flags & WS_KEYBOARD_LAYOUT_CHANGED)
        _layoutChanged = YES;
      break;
    default:
      break;
    }
}

@end
