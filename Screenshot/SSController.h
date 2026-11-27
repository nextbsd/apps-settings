/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * SSController: what Screenshot does for a request (SSRequest.h): a
 * picture at once (Command+Shift+3), a selection or a window to pick
 * (Command+Shift+4), or the toolbar (Command+Shift+5, or the app
 * opened), and recordings. Pictures are PNG files named "Screenshot
 * 2026-11-27 at 21.04.07.png" where the Options say (the Desktop by
 * default), or the clipboard; recordings "Screen Recording ... .mov",
 * opened when they stop.
 */

#import <AppKit/AppKit.h>
#import "SSOverlay.h"
#import "SSRequest.h"
#import "SSToolbar.h"
#import "SSRecorder.h"

@class SSThumbnail;

@interface SSController : NSObject <SSScreenshotServer, SSOverlayDelegate,
                                    SSToolbarDelegate>
{
  NSDictionary *_firstRequest;
  NSConnection *_connection;
  SSPanel *_overlay;
  SSOverlayView *_overlayView;
  NSWindow *_toolbar;
  SSToolbarView *_toolbarView;
  SSThumbnail *_thumbnail;
  BOOL _toClipboard;		/* this time, Control held */
  BOOL _busy;			/* taking a picture or starting to record */
  /* the timer's countdown */
  NSWindow *_countdown;
  NSTimer *_countdownTimer;
  int _countdownLeft;
  SSTool _countdownTool;
  NSRect _countdownRect;
  uint32_t _countdownWindow;
  /* recording */
  SSRecorder *_recorder;
  BOOL _streaming;
  BOOL _watching;
  NSRect _recordRect;		/* points, the overlay's; zero: the screen */
  int _cropX, _cropY, _cropWidth, _cropHeight;
  NSString *_recordPath;
  NSDate *_recordStarted;
  /* quitting when idle */
  NSTimer *_idleTimer;
}

/* Hands request (nil: the toolbar) to a Screenshot already running.
   NO when none is. */
+ (BOOL)forwardRequest:(NSDictionary *)request;

- (id)initWithRequest:(NSDictionary *)request;

@end
