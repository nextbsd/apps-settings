/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * BTDevice: one paired or nearby device as the window shows it: its
 * name, what it is (from its Class of Device, or for LE its GAP
 * appearance, as bluetooth(8) tells them apart), its link, and for a
 * headset its audio.
 */

#import <Foundation/Foundation.h>
#import "BTClient.h"

@interface BTDevice : NSObject
{
  NSString *_address;
  NSString *_name;
  NSArray *_profiles;		/* "HID", "A2DPSink", ... */
  int _classOfDevice;
  int _appearance;
  int _state;			/* BTDevice* */
  int _rssi;
  BOOL _paired;
  BOOL _autoconnect;
  BOOL _audio;			/* the Audio switch */
  /* While it has audio (bt_audio_entry, bt_hfp_status). */
  BOOL _playing;
  int _route;			/* BTRoute*, 0 none */
  BOOL _handsFree;
  BOOL _microphone;
  int _battery;
}

+ (BTDevice *)deviceWithInfo:(const BTClientDevice *)info;

- (NSString *)address;
/* Its name, or its address while it has none. */
- (NSString *)displayName;
- (BOOL)hasName;
/* "Mouse", "Keyboard", "Headphones", ...; "Device" if it doesn't say. */
- (NSString *)kind;
- (NSArray *)profiles;
- (BOOL)isPaired;
- (int)linkState;
- (BOOL)isConnected;
- (BOOL)autoconnect;
- (int)rssi;
/* A device we can play to: an A2DP sink or a hands-free headset. */
- (BOOL)isHeadset;
- (BOOL)audioEnabled;

- (void)setPlaying:(BOOL)playing route:(int)route;
- (void)setHandsFree:(BOOL)handsFree microphone:(BOOL)mic battery:(int)battery;
- (BOOL)isPlaying;
- (int)route;
- (BOOL)hasHandsFree;
- (int)battery;

/* "Connected", "Not Connected", ... for the list. */
- (NSString *)statusText;
/* "Strong", "Weak", ... for the nearby list. */
- (NSString *)signalText;
/* The line under the list: address, profiles, audio, battery. */
- (NSString *)detailText;
/* Everything shown, to tell whether the list changed. */
- (NSString *)stateDescription;

@end
