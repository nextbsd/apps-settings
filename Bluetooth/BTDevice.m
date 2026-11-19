/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "BTDevice.h"
#import <GNUstepBase/GNUstep.h>

/* The Class of Device's major class, and the minor where it matters
   (bluetooth(8)'s class_str). */
static NSString *
BTClassKind (int cod)
{
  int major = (cod >> 8) & 0x1f, minor = (cod >> 2) & 0x3f;

  switch (major)
    {
    case 0x01: return @"Computer";
    case 0x02: return @"Phone";
    case 0x03: return @"Network";
    case 0x04:
      switch (minor)
        {
        case 0x01: return @"Headset";
        case 0x02: return @"Hands-free";
        case 0x05: return @"Speaker";
        case 0x06: return @"Headphones";
        case 0x0a: return @"Hi-Fi Audio";
        default: return @"Audio";
        }
    case 0x05:
      switch (minor & 0x30)
        {
        case 0x10: return @"Keyboard";
        case 0x20: return @"Mouse";
        case 0x30: return @"Keyboard and Mouse";
        default: return @"Input Device";
        }
    case 0x06: return @"Printer or Camera";
    case 0x07: return @"Wearable";
    case 0x08: return @"Toy";
    case 0x09: return @"Health";
    default: return nil;
    }
}

/* An LE device's GAP appearance: category in the top ten bits
   (bluetooth(8)'s appearance_str). */
static NSString *
BTAppearanceKind (int appearance)
{
  int cat = (appearance >> 6) & 0x3ff, sub = appearance & 0x3f;

  switch (cat)
    {
    case 0x001: return @"Phone";
    case 0x002: return @"Computer";
    case 0x003: return @"Watch";
    case 0x00f:
      switch (sub)
        {
        case 0x01: return @"Keyboard";
        case 0x02: return @"Mouse";
        case 0x03: return @"Joystick";
        case 0x04: return @"Gamepad";
        case 0x05: return @"Tablet";
        default: return @"Input Device";
        }
    case 0x021: return @"Speaker";
    case 0x025: return @"Headphones";
    default: return nil;
    }
}

@implementation BTDevice

+ (BTDevice *)deviceWithInfo:(const BTClientDevice *)info
{
  BTDevice *d = AUTORELEASE ([[self alloc] init]);
  NSString *profiles;

  d->_address = RETAIN ([NSString stringWithUTF8String:info->address]);
  d->_name = [[NSString alloc] initWithUTF8String:info->name];
  if (d->_name == nil)		/* not UTF-8 */
    d->_name = [[NSString alloc] initWithCString:info->name
                                        encoding:NSISOLatin1StringEncoding];
  profiles = [NSString stringWithUTF8String:info->profiles];
  d->_profiles = RETAIN ([profiles length] > 0
                         ? [profiles componentsSeparatedByString:@","]
                         : [NSArray array]);
  d->_classOfDevice = info->classOfDevice & 0xffffff;
  d->_appearance = info->appearance;
  d->_state = info->state;
  d->_rssi = info->rssi;
  d->_paired = info->paired != 0;
  d->_autoconnect = info->autoconnect != 0;
  d->_audio = info->audio != 0;
  d->_battery = -1;
  return d;
}

- (void)dealloc
{
  RELEASE (_address);
  RELEASE (_name);
  RELEASE (_profiles);
  [super dealloc];
}

- (NSString *)address
{
  return _address;
}

- (BOOL)hasName
{
  return [_name length] > 0;
}

- (NSString *)displayName
{
  return [self hasName] ? _name : _address;
}

- (NSString *)kind
{
  NSString *kind = nil;

  if (_classOfDevice == 0 && _appearance != 0)
    kind = BTAppearanceKind (_appearance);
  else if (_classOfDevice != 0)
    kind = BTClassKind (_classOfDevice);
  /* A paired LE device keeps no class: say what it does. */
  if (kind == nil)
    {
      if ([_profiles containsObject:@"HFP"])
        kind = @"Headset";
      else if ([_profiles containsObject:@"A2DPSink"])
        kind = @"Headphones";
      else if ([_profiles containsObject:@"HID"]
               || [_profiles containsObject:@"HOGP"])
        kind = @"Input Device";
      else if ([_profiles containsObject:@"A2DPSource"])
        kind = @"Audio Source";
      else
        kind = @"Device";
    }
  return kind;
}

- (NSArray *)profiles
{
  return _profiles;
}

- (BOOL)isPaired
{
  return _paired;
}

- (int)linkState
{
  return _state;
}

- (BOOL)isConnected
{
  return _state == BTDeviceConnected;
}

- (BOOL)autoconnect
{
  return _autoconnect;
}

- (int)rssi
{
  return _rssi;
}

- (BOOL)isHeadset
{
  int major = (_classOfDevice >> 8) & 0x1f;

  if ([_profiles containsObject:@"A2DPSink"]
      || [_profiles containsObject:@"HFP"])
    return YES;
  /* Its services not read yet: go by its class. */
  return [_profiles count] == 0 && major == 0x04;
}

- (BOOL)audioEnabled
{
  return _audio;
}

- (void)setPlaying:(BOOL)playing route:(int)route
{
  _playing = playing;
  _route = route;
}

- (void)setHandsFree:(BOOL)handsFree microphone:(BOOL)mic battery:(int)battery
{
  _handsFree = handsFree;
  _microphone = mic;
  _battery = battery;
}

- (BOOL)isPlaying
{
  return _playing;
}

- (int)route
{
  return _route;
}

- (BOOL)hasHandsFree
{
  return _handsFree;
}

- (int)battery
{
  return _battery;
}

- (NSString *)statusText
{
  switch (_state)
    {
    case BTDeviceConnected:
      if (_microphone)
        return @"Connected, microphone on";
      if (_playing)
        return @"Connected, audio";
      return @"Connected";
    case BTDeviceConnecting:
      return @"Connecting...";
    case BTDevicePairing:
      return @"Pairing...";
    default:
      return _paired ? @"Not Connected" : @"";
    }
}

- (NSString *)signalText
{
  if (_rssi == 127)
    return @"";
  if (_rssi >= -55)
    return @"Strong";
  if (_rssi >= -70)
    return @"Good";
  if (_rssi >= -80)
    return @"Fair";
  return @"Weak";
}

- (NSString *)detailText
{
  NSMutableString *s = [NSMutableString stringWithString:_address];

  if ([_profiles count] > 0)
    [s appendFormat:@"   Services: %@",
       [_profiles componentsJoinedByString:@", "]];
  if (_battery >= 0)
    [s appendFormat:@"   Battery: %d%%", _battery];
  return s;
}

- (NSString *)stateDescription
{
  return [NSString stringWithFormat:@"%@|%@|%@|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%@",
                   _address, _name, _profiles, _classOfDevice, _appearance,
                   _state, _paired, _autoconnect, _audio, _playing, _route,
                   _handsFree, _microphone, _battery, [self signalText]];
}

@end
