/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * WCShutterButton: the round red button under the live view, as Photo
 * Booth's: a camera on it to take a photo, a film camera to record, a
 * square to stop.
 */

#import <AppKit/AppKit.h>

typedef enum
{
  WCShutterPhoto,
  WCShutterVideo,
  WCShutterStop,
} WCShutterKind;

@interface WCShutterButton : NSButton
{
  WCShutterKind kind;
}
- (void)setKind:(WCShutterKind)newKind;
@end
