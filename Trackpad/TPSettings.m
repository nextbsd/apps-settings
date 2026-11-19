/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TPSettings.h"
#import <AppKit/NSApplication.h>
#import <GNUstepBase/GNUstep.h>

#include <errno.h>
#include <stdint.h>
#include <string.h>

#include <WindowServer/WSClient.h>

_Static_assert (TPSettingString == WS_SETTING_STRING
                && TPSettingInteger == WS_SETTING_INTEGER
                && TPSettingBoolean == WS_SETTING_BOOLEAN
                && TPSettingReal == WS_SETTING_REAL
                && TPInputKeyboard == WS_INPUT_KEYBOARD
                && TPInputPointer == WS_INPUT_POINTER
                && TPInputTouchpad == WS_INPUT_TOUCHPAD
                && TPInputMouse == WS_INPUT_MOUSE
                && TPInputTouch == WS_INPUT_TOUCH,
                "TPSetting* and TPInput* are WindowServer's");

#define CONN ((ws_connection_t *)_conn)

/* Seconds between attempts to reach WindowServer, and between looks
   at the input devices. */
#define TPRetryInterval 3.0
#define TPDeviceInterval 3.0

/* The user's WindowServer defaults, and what settings apps post after
   changing a domain (the settings design's org.nextbsd.SettingsChanged). */
static NSString *const TPDomain = @"org.nextbsd.WindowServer";
static NSString *const TPChangedNotification = @"org.nextbsd.SettingsChanged";

static NSArray *
TPWatchedModes (void)
{
  return [NSArray arrayWithObjects:NSDefaultRunLoopMode,
                  NSEventTrackingRunLoopMode, NSModalPanelRunLoopMode, nil];
}

@interface TPSettings (Private)
- (BOOL)connect;
- (void)disconnect;
- (void)retry:(NSTimer *)timer;
- (void)startRetrying;
- (void)checkDevices:(NSTimer *)timer;
- (BOOL)readSettings;
- (BOOL)readDevices;
- (void)processEvents;
- (void)handleEvent:(const ws_event_t *)event;
- (void)checkLost:(int)error;
- (void)notifyDelegate;
- (int)send:(const ws_setting_t *)list count:(unsigned)count;
- (void)save:(NSDictionary *)changes remove:(NSArray *)removed;
@end

static void
TPHandleEvent (ws_connection_t *conn, const ws_event_t *event, void *ctx)
{
  (void)conn;
  [(TPSettings *)ctx handleEvent:event];
}

static NSString *
TPString (const char *chars, size_t size)
{
  NSString *s = AUTORELEASE ([[NSString alloc]
                               initWithBytes:chars
                                      length:strnlen (chars, size)
                                    encoding:NSUTF8StringEncoding]);
  return s != nil ? s : @"";
}

struct TPCollect
{
  NSDictionary *types;
  NSMutableDictionary *values;
  NSMutableSet *session;
};

static void
TPCollectSetting (const ws_event_setting_t *setting, void *ctx)
{
  struct TPCollect *c = ctx;
  NSString *key = TPString (setting->key, sizeof (setting->key));

  if ([c->types objectForKey:key] == nil)
    return;
  [c->values setObject:TPString (setting->value, sizeof (setting->value))
                forKey:key];
  if (setting->source == WS_SETTING_SOURCE_SESSION)
    [c->session addObject:key];
}

static void
TPCollectDevice (const ws_event_input_device_t *device, void *ctx)
{
  NSMutableArray *list = (NSMutableArray *)ctx;

  [list addObject:
     [NSDictionary dictionaryWithObjectsAndKeys:
        TPString (device->name, sizeof (device->name)), @"name",
        TPString (device->sysname, sizeof (device->sysname)), @"sysname",
        [NSNumber numberWithUnsignedInt:device->flags], @"flags", nil]];
}

@implementation TPSettings

- (id)initWithTypes:(NSDictionary *)types
           delegate:(id<TPSettingsDelegate>)delegate
{
  if ((self = [super init]) == nil)
    return nil;
  ASSIGN (_types, types);
  _values = [[NSDictionary alloc] init];
  _sessionKeys = [[NSSet alloc] init];
  _devices = [[NSArray alloc] init];
  /* The delegate hears about this first connection only when it
     comes later, through the retries. */
  if (![self connect])
    [self startRetrying];
  _delegate = delegate;
  ASSIGN (_deviceTimer,
          [NSTimer scheduledTimerWithTimeInterval:TPDeviceInterval
                                           target:self
                                         selector:@selector (checkDevices:)
                                         userInfo:nil
                                          repeats:YES]);
  return self;
}

- (void)dealloc
{
  [self invalidate];
  RELEASE (_types);
  RELEASE (_values);
  RELEASE (_sessionKeys);
  RELEASE (_devices);
  [super dealloc];
}

- (void)invalidate
{
  [_retryTimer invalidate];
  DESTROY (_retryTimer);
  [_deviceTimer invalidate];
  DESTROY (_deviceTimer);
  [self disconnect];
  _delegate = nil;
}

- (BOOL)isConnected
{
  return _conn != NULL;
}

- (BOOL)canChangeSettings
{
  return _conn != NULL && (ws_server_flags (CONN) & WS_SERVER_SETTINGS) != 0;
}

- (NSDictionary *)values
{
  return _values;
}

- (NSString *)valueForKey:(NSString *)key
{
  return [_values objectForKey:key];
}

- (BOOL)boolForKey:(NSString *)key
{
  NSString *v = [_values objectForKey:key];

  return [v caseInsensitiveCompare:@"true"] == NSOrderedSame
    || [v caseInsensitiveCompare:@"yes"] == NSOrderedSame
    || [v isEqual:@"1"];
}

- (double)doubleForKey:(NSString *)key
{
  return [[_values objectForKey:key] doubleValue];
}

- (NSArray *)devices
{
  return _devices;
}

- (int)setValue:(NSString *)value forKey:(NSString *)key
{
  int type = [[_types objectForKey:key] intValue];
  ws_setting_t setting;
  id saved;
  int e;

  if (type == 0)
    type = TPSettingString;
  setting.key = [key UTF8String];
  setting.type = type;
  setting.value = [value UTF8String];
  if ((e = [self send:&setting count:1]) != 0)
    return e;

  /* Saved with its own type, as `defaults write` would. */
  if (type == TPSettingBoolean)
    saved = [NSNumber numberWithBool:([value caseInsensitiveCompare:@"true"]
                                      == NSOrderedSame)];
  else if (type == TPSettingReal)
    saved = [NSNumber numberWithDouble:[value doubleValue]];
  else if (type == TPSettingInteger)
    saved = [NSNumber numberWithInt:[value intValue]];
  else
    saved = value;
  [self save:[NSDictionary dictionaryWithObject:saved forKey:key] remove:nil];
  [self readSettings];
  return 0;
}

- (int)setBool:(BOOL)value forKey:(NSString *)key
{
  return [self setValue:(value ? @"true" : @"false") forKey:key];
}

- (int)setDouble:(double)value forKey:(NSString *)key
{
  return [self setValue:[NSString stringWithFormat:@"%.2f", value] forKey:key];
}

- (int)resetKeys:(NSArray *)keys
{
  ws_setting_t list[[keys count] + 1];
  NSUInteger i;
  int e;

  for (i = 0; i < [keys count]; i++)
    {
      list[i].key = [[keys objectAtIndex:i] UTF8String];
      list[i].type = WS_SETTING_DEFAULT;
      list[i].value = "";
    }
  e = [self send:list count:(unsigned) [keys count]];
  /* Saved values go even if WindowServer isn't there to hear it. */
  [self save:nil remove:keys];
  [self readSettings];
  return e;
}

- (id)snapshotOfKeys:(NSArray *)keys
{
  NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
  NSDictionary *domain;
  NSMutableDictionary *saved = [NSMutableDictionary dictionary];
  NSMutableDictionary *session = [NSMutableDictionary dictionary];
  NSEnumerator *e = [keys objectEnumerator];
  NSString *key;

  [defs synchronize];
  domain = [defs persistentDomainForName:TPDomain];
  while ((key = [e nextObject]) != nil)
    {
      id v = [domain objectForKey:key];

      if (v != nil)
        [saved setObject:v forKey:key];
      if ([_sessionKeys containsObject:key]
          && [_values objectForKey:key] != nil)
        [session setObject:[_values objectForKey:key] forKey:key];
    }
  return [NSDictionary dictionaryWithObjectsAndKeys:keys, @"keys",
                       saved, @"saved", session, @"session", nil];
}

- (int)restore:(id)snapshot
{
  NSDictionary *saved = [snapshot objectForKey:@"saved"];
  NSDictionary *session = [snapshot objectForKey:@"session"];
  NSArray *keys = [snapshot objectForKey:@"keys"];
  NSMutableArray *removed = [NSMutableArray array];
  ws_setting_t list[[keys count] + 1];
  NSUInteger i;
  int e;

  for (i = 0; i < [keys count]; i++)
    {
      NSString *key = [keys objectAtIndex:i];
      NSString *v = [session objectForKey:key];

      list[i].key = [key UTF8String];
      if (v != nil)
        {
          list[i].type = WS_SETTING_STRING;	/* parsed for any key */
          list[i].value = [v UTF8String];
        }
      else
        {
          list[i].type = WS_SETTING_DEFAULT;
          list[i].value = "";
        }
      if ([saved objectForKey:key] == nil)
        [removed addObject:key];
    }
  e = [self send:list count:(unsigned) [keys count]];
  [self save:saved remove:removed];
  [self readSettings];
  return e;
}

@end

@implementation TPSettings (Private)

- (BOOL)connect
{
  NSString *name = [[NSProcessInfo processInfo] processName];
  ws_connection_t *conn = ws_connect ([name UTF8String], WS_CONNECT_CONTROL);
  NSRunLoop *loop = [NSRunLoop currentRunLoop];
  NSArray *modes = TPWatchedModes ();
  NSUInteger i;

  if (conn == NULL)
    return NO;
  _conn = conn;
  for (i = 0; i < [modes count]; i++)
    [loop addEvent:(void *)(intptr_t)ws_connection_fd (conn)
              type:ET_RDESC
           watcher:(id<RunLoopEvents>)self
           forMode:[modes objectAtIndex:i]];
  [self readSettings];
  [self readDevices];
  [_delegate settingsDidChange:self];
  return YES;
}

- (void)disconnect
{
  NSRunLoop *loop = [NSRunLoop currentRunLoop];
  NSArray *modes = TPWatchedModes ();
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
  ASSIGN (_values, [NSDictionary dictionary]);
  ASSIGN (_sessionKeys, [NSSet set]);
  ASSIGN (_devices, [NSArray array]);
}

- (void)startRetrying
{
  if (_retryTimer != nil)
    return;
  ASSIGN (_retryTimer, [NSTimer scheduledTimerWithTimeInterval:TPRetryInterval
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

/* A mouse paired or unplugged: WindowServer has no event for it. */
- (void)checkDevices:(NSTimer *)timer
{
  NSArray *before = RETAIN (_devices);

  if (_conn != NULL && [self readDevices] && ![_devices isEqual:before])
    [_delegate settingsDidChange:self];
  RELEASE (before);
}

- (BOOL)readSettings
{
  struct TPCollect c;

  if (_conn == NULL)
    return NO;
  c.types = _types;
  c.values = [NSMutableDictionary dictionary];
  c.session = [NSMutableSet set];
  if (ws_get_settings (CONN, TPCollectSetting, &c) < 0)
    {
      int e = errno;
      NSLog (@"Can't read WindowServer's settings: %s", strerror (e));
      [self checkLost:e];
      return NO;
    }
  ASSIGN (_values, c.values);
  ASSIGN (_sessionKeys, c.session);
  /* Events read while waiting for the answer are queued in the
     library: handle them from the run loop. */
  if (ws_pending (CONN))
    [self performSelector:@selector (processEvents) withObject:nil afterDelay:0];
  return YES;
}

- (BOOL)readDevices
{
  NSMutableArray *list = [NSMutableArray array];

  if (_conn == NULL)
    return NO;
  if (ws_list_input_devices (CONN, TPCollectDevice, list) < 0)
    {
      int e = errno;
      /* ENOTSUP: an older server, which can't say; assume none. */
      if (e != ENOTSUP)
        {
          NSLog (@"Can't list the input devices: %s", strerror (e));
          [self checkLost:e];
        }
      return NO;
    }
  ASSIGN (_devices, list);
  if (ws_pending (CONN))
    [self performSelector:@selector (processEvents) withObject:nil afterDelay:0];
  return YES;
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
  [_delegate settingsDidChange:self];
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
  if (ws_dispatch (CONN, TPHandleEvent, self) < 0)
    {
      NSLog (@"Lost the WindowServer connection (%s)", strerror (errno));
      [self disconnect];
      [self startRetrying];
      [_delegate settingsDidChange:self];
      return;
    }
  if (_changed)
    {
      _changed = NO;
      if ([self readSettings])
        [_delegate settingsDidChange:self];
    }
}

- (void)handleEvent:(const ws_event_t *)event
{
  if (event->hdr.type == WS_EVENT_SETTINGS_CHANGED)
    _changed = YES;
}

- (int)send:(const ws_setting_t *)list count:(unsigned)count
{
  char failed[WS_MAX_SETTING_KEY] = "";

  if (_conn == NULL)
    return ENOTCONN;
  if (ws_set_settings (CONN, 0, list, count, failed, sizeof (failed)) < 0)
    {
      int e = errno;
      NSLog (@"WindowServer refused the setting %s: %s",
             failed[0] != '\0' ? failed : list[0].key, strerror (e));
      [self checkLost:e];
      return e;
    }
  return 0;
}

/* The user's org.nextbsd.WindowServer defaults: read again first, so
   a change another settings app made meanwhile stays. */
- (void)save:(NSDictionary *)changes remove:(NSArray *)removed
{
  NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
  NSMutableDictionary *domain;
  NSMutableArray *keys = [NSMutableArray array];

  [defs synchronize];
  domain = AUTORELEASE ([[defs persistentDomainForName:TPDomain] mutableCopy]);
  if (domain == nil)
    domain = [NSMutableDictionary dictionary];
  if (changes != nil)
    {
      [domain addEntriesFromDictionary:changes];
      [keys addObjectsFromArray:[changes allKeys]];
    }
  if (removed != nil)
    {
      [domain removeObjectsForKeys:removed];
      [keys addObjectsFromArray:removed];
    }
  [defs setPersistentDomain:domain forName:TPDomain];
  [defs synchronize];
  [[NSDistributedNotificationCenter defaultCenter]
      postNotificationName:TPChangedNotification
                    object:nil
                  userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
                                           TPDomain, @"domain",
                                           keys, @"keys", nil]
        deliverImmediately:YES];
}

@end
