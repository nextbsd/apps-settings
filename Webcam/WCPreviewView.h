/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * WCPreviewView: the live view. The camera's picture, fitted to the view
 * on black and shown as a mirror if asked, and over it: a badge (the
 * test pattern says it's one), the recording's time, the countdown's
 * number, the flash of a photo, and a message when there's no picture.
 */

#import <AppKit/AppKit.h>

@interface WCPreviewView : NSView
{
  NSBitmapImageRep *image;
  BOOL mirror;
  NSString *message;		/* instead of a picture */
  NSString *badge;		/* top left */
  NSString *recording;		/* top right, by a red dot: "0:12" */
  NSInteger countdown;		/* 3, 2, 1; 0 none */
  float flash;			/* 1.0 white, fading to 0.0 */
  NSTimer *flashTimer;
}
- (void)setImage:(NSBitmapImageRep *)newImage;
- (void)setMirror:(BOOL)flag;
- (void)setMessage:(NSString *)text;
- (void)setBadge:(NSString *)text;
- (void)setRecording:(NSString *)text;
- (void)setCountdown:(NSInteger)number;
- (void)flash;
@end
