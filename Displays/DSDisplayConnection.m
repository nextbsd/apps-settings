/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "DSDisplayConnection.h"
#import <AppKit/NSApplication.h>
#import <GNUstepBase/GNUstep.h>

#include <errno.h>
#include <stdint.h>
#include <string.h>

#include <WindowServer/WSClient.h>

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
@end

static void
DSHandleEvent (ws_connection_t *conn, const ws_event_t *event, void *ctx)
{
  (void)conn;
  [(DSDisplayConnection *)ctx handleEvent:event];
}

static void
DSCollectSetting (const ws_event_setting_t *setting, void *ctx)
{
  NSMutableDictionary *dict = (NSMutableDictionary *)ctx;

  if (strncmp (setting->key, "Display", 7) != 0)
    return;
  NSString *key = [NSString stringWithUTF8String:setting->key];
  NSString *value = [NSString stringWithUTF8String:setting->value];
  if (key != nil && value != nil)
    [dict setObject:value forKey:key];
}

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
  _delegate = nil;
}

- (BOOL)isConnected
{
  return _conn != NULL;
}

- (NSDictionary *)displaySettings
{
  NSMutableDictionary *dict = [NSMutableDictionary dictionary];

  if (_conn == NULL)
    return dict;
  if (ws_get_settings (CONN, DSCollectSetting, dict) < 0)
    {
      NSLog (@"Displays: can't read WindowServer's settings: %s",
             strerror (errno));
      if (errno == EPIPE || errno == ECONNRESET || errno == ENOTCONN)
        {
          [self disconnect];
          [self startRetrying];
        }
      return [NSMutableDictionary dictionary];
    }
  /* Events read while waiting for the answer are queued in the
     library: handle them from the run loop. */
  if (ws_pending (CONN))
    [self performSelector:@selector (processEvents) withObject:nil afterDelay:0];
  return dict;
}

- (int)setLooksLike:(NSString *)value
{
  ws_setting_t setting;
  char failed[64] = "";

  if (_conn == NULL)
    return ENOTCONN;
  setting.key = "DisplayLooksLike";
  setting.type = WS_SETTING_STRING;
  setting.value = [value UTF8String];
  if (ws_set_settings (CONN, 0, &setting, 1, failed, sizeof (failed)) < 0)
    {
      int e = errno;
      NSLog (@"Displays: WindowServer refused DisplayLooksLike %@: %s",
             value, strerror (e));
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
      _changed = YES;
      break;
    default:
      break;
    }
}

@end
