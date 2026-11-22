/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * WCController: Webcam's app delegate and its one window, as macOS's
 * Photo Booth:
 *   - the live view of the camera (WCPreviewView), shown as a mirror;
 *   - under it, the camera (a menu when there are several), the shutter,
 *     a three-second countdown, and Photo or Video;
 *   - a photo is the picture as shown, with a flash, saved to ~/Images
 *     as PNG or JPEG; a video is recorded to ~/Videos (WCRecorder);
 *   - the recent captures in a strip at the bottom (WCStripView).
 * Pictures come through WCCapture, which doesn't tie the app to one
 * capture API. With no camera, it's the test pattern, and the window
 * says so.
 *
 * Defaults (the app's domain; a command line -Key value overrides):
 *   WebcamCamera		the camera chosen last, by ident
 *   WebcamPhotosFolder		~/Images
 *   WebcamVideosFolder		~/Videos
 *   WebcamPhotoFormat		png or jpeg
 *   WebcamCountdown		YES: count down from 3
 *   WebcamMirror		NO: show cameras as they see, not as a mirror
 *   WebcamMode			photo or video
 */

#import <AppKit/AppKit.h>
#import "WCCapture.h"
#import "WCPreviewView.h"
#import "WCRecorder.h"
#import "WCShutterButton.h"
#import "WCStripView.h"

@interface WCController : NSObject
{
  NSWindow *window;
  NSTimer *frameTimer;
  NSTimer *listTimer;
  NSTimer *countdownTimer;

  /* The cameras, as WCCaptureListCameras said last. */
  WCCameraInfo cameras[WCCaptureMaxCameras];
  int cameraCount;
  int current;			/* index into cameras; -1 none */
  WCCapture *capture;
  BOOL captureFailed;		/* opening it again waits for a relisting */
  WCFrame frame;		/* the last picture, our copy */
  BOOL haveFrame;
  WCFrame scratch;		/* mirrored and shrunk copies */

  WCRecorder *recorder;
  NSString *recordingPath;
  NSInteger countdown;

  NSMutableDictionary *thumbnails;	/* path -> NSImage */

  /* The window's controls; the window retains them. */
  WCPreviewView *preview;
  NSPopUpButton *cameraPopUp;
  NSTextField *cameraLabel;
  WCShutterButton *shutter;
  NSButton *countdownSwitch;
  NSSegmentedControl *modeControl;
  WCStripView *strip;
  NSMenu *stripMenu;
  NSMenuItem *shutterItem;
  NSMenuItem *mirrorItem;
  NSMenuItem *pngItem;
  NSMenuItem *jpegItem;
}
@end
