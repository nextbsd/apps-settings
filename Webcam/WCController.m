/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "WCController.h"
#import "WCImage.h"
#import <GNUstepBase/GNUstep.h>

#include <string.h>

/* Layout, in points. */
#define WCMargin 12.0
#define WCPreviewWidth 640.0
#define WCPreviewHeight 480.0
#define WCBarHeight 56.0
#define WCStripHeight 96.0
#define WCShutterSize 44.0
#define WCModeWidth 130.0
#define WCSwitchWidth 110.0
#define WCCameraWidth 240.0

/* Timing, in seconds. */
#define WCFrameSeconds (1.0 / 60.0)	/* ask for a frame; most cameras
					   make 30 */
#define WCListSeconds 2.0		/* cameras plugged in or out */
#define WCCountdownFrom 3

#define WCStripMost 30			/* captures in the strip */
#define WCThumbWidth 160
#define WCThumbHeight 120
#define WCJPEGQuality 92

#define WCCameraKey @"WebcamCamera"
#define WCPhotosFolderKey @"WebcamPhotosFolder"
#define WCVideosFolderKey @"WebcamVideosFolder"
#define WCPhotoFormatKey @"WebcamPhotoFormat"
#define WCCountdownKey @"WebcamCountdown"
#define WCMirrorKey @"WebcamMirror"
#define WCModeKey @"WebcamMode"

static NSString *
WCString (const char *s)
{
  NSString *string = [NSString stringWithUTF8String:s];

  return string != nil ? string : @"";
}

static NSTextField *
WCLabel (NSRect frame, NSString *text, NSFont *font)
{
  NSTextField *label = AUTORELEASE ([[NSTextField alloc] initWithFrame:frame]);
  [label setStringValue:(text != nil ? text : @"")];
  [label setEditable:NO];
  [label setSelectable:NO];
  [label setBordered:NO];
  [label setBezeled:NO];
  [label setDrawsBackground:NO];
  if (font != nil)
    [label setFont:font];
  return label;
}

/* A copy of a frame as an image to draw. */
static NSBitmapImageRep *
WCImageRep (const WCFrame *f)
{
  NSBitmapImageRep *rep;
  unsigned char *data;
  int y;

  rep = [[NSBitmapImageRep alloc]
          initWithBitmapDataPlanes:NULL
                        pixelsWide:f->width
                        pixelsHigh:f->height
                     bitsPerSample:8
                   samplesPerPixel:3
                          hasAlpha:NO
                          isPlanar:NO
                    colorSpaceName:NSDeviceRGBColorSpace
                       bytesPerRow:f->width * 3
                      bitsPerPixel:24];
  data = [rep bitmapData];
  if (data == NULL)
    {
      RELEASE (rep);
      return nil;
    }
  for (y = 0; y < f->height; y++)
    memcpy (data + (size_t) y * f->width * 3, f->rgb + (size_t) y * f->stride,
            (size_t) f->width * 3);
  return AUTORELEASE (rep);
}

static NSImage *
WCImageFromFrame (const WCFrame *f)
{
  NSBitmapImageRep *rep = WCImageRep (f);
  NSImage *image;

  if (rep == nil)
    return nil;
  image = [[NSImage alloc] initWithSize:NSMakeSize (f->width, f->height)];
  [image addRepresentation:rep];
  return AUTORELEASE (image);
}

/* "1:05" */
static NSString *
WCDuration (double seconds)
{
  long s = (long) seconds;

  return [NSString stringWithFormat:@"%ld:%02ld", s / 60, s % 60];
}

/* For the strip: [date, path, video] entries, newest first. */
static NSComparisonResult
WCNewestFirst (id a, id b, void *context)
{
  return [[b objectAtIndex:0] compare:[a objectAtIndex:0]];
}

@interface WCController (Private)
- (void)buildMenu;
- (void)buildWindow;
- (void)addTimer:(NSTimer *)timer;
- (void)relist:(NSTimer *)timer;
- (void)showCameras;
- (void)openCamera:(int)index;
- (void)closeCamera;
- (BOOL)mirrors;
- (void)frameFired:(NSTimer *)timer;
- (BOOL)videoMode;
- (void)showMode;
- (void)cancelCountdown;
- (void)countdownFired:(NSTimer *)timer;
- (void)captureNow;
- (NSString *)folderForKey:(NSString *)key;
- (NSString *)newPathIn:(NSString *)folder kind:(NSString *)kind
              extension:(NSString *)extension;
- (void)takePhoto;
- (void)startRecording;
- (void)stopRecording;
- (void)setThumbnailOf:(NSString *)path from:(const WCFrame *)picture;
- (NSImage *)thumbnailOf:(NSString *)path video:(BOOL)video;
- (void)reloadStrip;
- (void)showPhotoFormat;
@end

@implementation WCController

- (void)dealloc
{
  [frameTimer invalidate];
  RELEASE (frameTimer);
  [listTimer invalidate];
  RELEASE (listTimer);
  [countdownTimer invalidate];
  RELEASE (countdownTimer);
  WCCaptureClose (capture);
  WCFrameFree (&frame);
  WCFrameFree (&scratch);
  RELEASE (recordingPath);
  RELEASE (thumbnails);
  RELEASE (stripMenu);
  RELEASE (window);
  [super dealloc];
}

- (void)applicationDidFinishLaunching:(NSNotification *)note
{
  NSImage *icon = [NSImage imageNamed:@"Webcam.png"];

  if (icon != nil)
    [NSApp setApplicationIconImage:icon];
  [[NSUserDefaults standardUserDefaults] registerDefaults:
    [NSDictionary dictionaryWithObjectsAndKeys:
      @"png", WCPhotoFormatKey,
      @"YES", WCCountdownKey,
      @"YES", WCMirrorKey,
      @"photo", WCModeKey,
      nil]];
  current = -1;
  thumbnails = [[NSMutableDictionary alloc] init];
  [self buildMenu];
  [self buildWindow];
  [self relist:nil];
  [self reloadStrip];
  [window center];
  [window makeKeyAndOrderFront:self];

  frameTimer = RETAIN ([NSTimer timerWithTimeInterval:WCFrameSeconds
                                               target:self
                                             selector:@selector (frameFired:)
                                             userInfo:nil
                                              repeats:YES]);
  [self addTimer:frameTimer];
  listTimer = RETAIN ([NSTimer timerWithTimeInterval:WCListSeconds
                                              target:self
                                            selector:@selector (relist:)
                                            userInfo:nil
                                             repeats:YES]);
  [self addTimer:listTimer];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app
{
  return YES;
}

- (void)applicationWillTerminate:(NSNotification *)note
{
  [frameTimer invalidate];
  [listTimer invalidate];
  [self cancelCountdown];
  /* A recording is finished, so what's recorded so far plays. */
  [self stopRecording];
  [self closeCamera];
}

/* ---- actions ---- */

- (void)shutterPressed:(id)sender
{
  if (recorder != NULL)
    {
      [self stopRecording];
      return;
    }
  if (countdownTimer != nil)
    {
      [self cancelCountdown];
      return;
    }
  if (!haveFrame)
    {
      NSBeep ();
      return;
    }
  if ([countdownSwitch state] == NSOnState)
    {
      countdown = WCCountdownFrom;
      [preview setCountdown:countdown];
      countdownTimer = RETAIN ([NSTimer timerWithTimeInterval:1.0
                                                       target:self
                                                     selector:@selector
                                                     (countdownFired:)
                                                     userInfo:nil
                                                      repeats:YES]);
      [self addTimer:countdownTimer];
      [self showMode];
      return;
    }
  [self captureNow];
}

- (void)cameraChosen:(id)sender
{
  NSInteger index = [cameraPopUp indexOfSelectedItem];

  if (index < 0 || index >= cameraCount || index == current)
    return;
  [[NSUserDefaults standardUserDefaults]
    setObject:WCString (cameras[index].ident) forKey:WCCameraKey];
  [self openCamera:(int) index];
}

- (void)modeChosen:(id)sender
{
  /* Not while recording or counting down. The control stays enabled
     then, since the theme draws a disabled selected segment unreadably. */
  if (recorder != NULL || countdownTimer != nil)
    {
      [modeControl setSelectedSegment:
                     ([[[NSUserDefaults standardUserDefaults]
                         stringForKey:WCModeKey] isEqual:@"video"] ? 1 : 0)];
      return;
    }
  [[NSUserDefaults standardUserDefaults]
    setObject:([modeControl selectedSegment] == 1 ? @"video" : @"photo")
       forKey:WCModeKey];
  [self showMode];
}

- (void)countdownChanged:(id)sender
{
  [[NSUserDefaults standardUserDefaults]
    setBool:([countdownSwitch state] == NSOnState) forKey:WCCountdownKey];
}

- (void)toggleMirror:(id)sender
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

  [defaults setBool:![defaults boolForKey:WCMirrorKey] forKey:WCMirrorKey];
  [mirrorItem setState:([defaults boolForKey:WCMirrorKey]
                        ? NSOnState : NSOffState)];
  [preview setMirror:[self mirrors]];
}

- (void)choosePNG:(id)sender
{
  [[NSUserDefaults standardUserDefaults] setObject:@"png"
                                            forKey:WCPhotoFormatKey];
  [self showPhotoFormat];
}

- (void)chooseJPEG:(id)sender
{
  [[NSUserDefaults standardUserDefaults] setObject:@"jpeg"
                                            forKey:WCPhotoFormatKey];
  [self showPhotoFormat];
}

- (void)openCapture:(id)sender
{
  NSString *path = [strip selectedPath];

  if (path == nil)
    return;
  if (![[NSWorkspace sharedWorkspace] openFile:path])
    NSRunAlertPanel (@"Webcam",
                     [NSString stringWithFormat:
                                 @"No app is set to open “%@”.",
                               [path lastPathComponent]],
                     @"OK", nil, nil);
}

- (void)showInWorkspace:(id)sender
{
  NSString *path = [strip selectedPath];

  if (path != nil)
    [[NSWorkspace sharedWorkspace] selectFile:path
                     inFileViewerRootedAtPath:@""];
}

- (BOOL)validateMenuItem:(id<NSMenuItem>)item
{
  SEL action = [item action];

  if (action == @selector (openCapture:)
      || action == @selector (showInWorkspace:))
    return [strip selectedPath] != nil;
  if (action == @selector (shutterPressed:))
    return haveFrame || recorder != NULL;
  if (action == @selector (choosePNG:) || action == @selector (chooseJPEG:))
    return recorder == NULL;
  return YES;
}

@end

@implementation WCController (Private)

- (void)buildMenu
{
  NSMenu *menu = AUTORELEASE ([[NSMenu alloc] initWithTitle:@"Webcam"]);
  NSMenu *captureMenu = AUTORELEASE ([[NSMenu alloc] initWithTitle:@"Capture"]);
  NSMenu *options = AUTORELEASE ([[NSMenu alloc] initWithTitle:@"Options"]);
  NSMenu *windows = AUTORELEASE ([[NSMenu alloc] initWithTitle:@"Window"]);
  id<NSMenuItem> item;

  [menu addItemWithTitle:@"About Webcam"
                  action:@selector (orderFrontStandardAboutPanel:)
           keyEquivalent:@""];

  item = [menu addItemWithTitle:@"Capture" action:NULL keyEquivalent:@""];
  shutterItem = (NSMenuItem *) [captureMenu addItemWithTitle:@"Take Photo"
                                                      action:@selector
                                                      (shutterPressed:)
                                               keyEquivalent:@"t"];
  [captureMenu addItemWithTitle:@"Open"
                         action:@selector (openCapture:)
                  keyEquivalent:@"o"];
  [captureMenu addItemWithTitle:@"Show in Workspace"
                         action:@selector (showInWorkspace:)
                  keyEquivalent:@""];
  [menu setSubmenu:captureMenu forItem:item];

  item = [menu addItemWithTitle:@"Options" action:NULL keyEquivalent:@""];
  mirrorItem = (NSMenuItem *) [options addItemWithTitle:@"Mirror Image"
                                                 action:@selector
                                                 (toggleMirror:)
                                          keyEquivalent:@""];
  [mirrorItem setState:([[NSUserDefaults standardUserDefaults]
                          boolForKey:WCMirrorKey] ? NSOnState : NSOffState)];
  pngItem = (NSMenuItem *) [options addItemWithTitle:@"Save Photos as PNG"
                                              action:@selector (choosePNG:)
                                       keyEquivalent:@""];
  jpegItem = (NSMenuItem *) [options addItemWithTitle:@"Save Photos as JPEG"
                                               action:@selector (chooseJPEG:)
                                        keyEquivalent:@""];
  [menu setSubmenu:options forItem:item];
  [self showPhotoFormat];

  item = [menu addItemWithTitle:@"Window" action:NULL keyEquivalent:@""];
  [windows addItemWithTitle:@"Minimize"
                     action:@selector (performMiniaturize:)
              keyEquivalent:@"m"];
  [windows addItemWithTitle:@"Close"
                     action:@selector (performClose:)
              keyEquivalent:@"w"];
  [menu setSubmenu:windows forItem:item];
  [NSApp setWindowsMenu:windows];
  [menu addItemWithTitle:@"Hide" action:@selector (hide:) keyEquivalent:@"h"];
  [menu addItemWithTitle:@"Quit" action:@selector (terminate:) keyEquivalent:@"q"];
  [NSApp setMainMenu:menu];

  /* The strip's own. */
  stripMenu = [[NSMenu alloc] initWithTitle:@"Capture"];
  [stripMenu addItemWithTitle:@"Open"
                       action:@selector (openCapture:)
                keyEquivalent:@""];
  [stripMenu addItemWithTitle:@"Show in Workspace"
                       action:@selector (showInWorkspace:)
                keyEquivalent:@""];
}

/* From the bottom up: the strip, the controls, the live view. */
- (void)buildWindow
{
  NSRect contentRect = NSMakeRect (0, 0, WCPreviewWidth,
                                   WCPreviewHeight + WCBarHeight
                                   + WCStripHeight);
  NSView *content;
  NSScrollView *scroll;
  CGFloat barMid = WCStripHeight + WCBarHeight / 2;
  CGFloat right = WCPreviewWidth - WCMargin;
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

  window = [[NSWindow alloc]
             initWithContentRect:contentRect
                       styleMask:(NSTitledWindowMask | NSClosableWindowMask
                                  | NSMiniaturizableWindowMask
                                  | NSResizableWindowMask)
                         backing:NSBackingStoreBuffered
                           defer:NO];
  [window setTitle:@"Webcam"];
  [window setReleasedWhenClosed:NO];
  [window setContentMinSize:NSMakeSize (WCPreviewWidth,
                                        240 + WCBarHeight + WCStripHeight)];
  content = [window contentView];

  scroll = AUTORELEASE ([[NSScrollView alloc]
                          initWithFrame:NSMakeRect (0, 0, WCPreviewWidth,
                                                    WCStripHeight)]);
  [scroll setHasHorizontalScroller:YES];
  [scroll setHasVerticalScroller:NO];
  [scroll setBorderType:NSNoBorder];
  [scroll setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
  strip = AUTORELEASE ([[WCStripView alloc]
                         initWithFrame:NSMakeRect (0, 0, WCPreviewWidth,
                                                   [scroll contentSize].height)]);
  [strip setTarget:self openAction:@selector (openCapture:)];
  [strip setMenu:stripMenu];
  [scroll setDocumentView:strip];
  [content addSubview:scroll];

  /* The camera: a menu of them when there are several, else its name. */
  cameraPopUp = AUTORELEASE ([[NSPopUpButton alloc]
                               initWithFrame:NSMakeRect (WCMargin, barMid - 13,
                                                         WCCameraWidth, 26)
                                   pullsDown:NO]);
  [cameraPopUp setTarget:self];
  [cameraPopUp setAction:@selector (cameraChosen:)];
  [cameraPopUp setAutoresizingMask:NSViewMaxXMargin | NSViewMaxYMargin];
  [content addSubview:cameraPopUp];
  cameraLabel = WCLabel (NSMakeRect (WCMargin, barMid - 9, WCCameraWidth, 18),
                         nil, [NSFont systemFontOfSize:
                                        [NSFont smallSystemFontSize]]);
  [cameraLabel setAutoresizingMask:NSViewMaxXMargin | NSViewMaxYMargin];
  [content addSubview:cameraLabel];

  shutter = AUTORELEASE ([[WCShutterButton alloc]
                           initWithFrame:NSMakeRect (floor ((WCPreviewWidth
                                                             - WCShutterSize)
                                                            / 2),
                                                     barMid - WCShutterSize / 2,
                                                     WCShutterSize,
                                                     WCShutterSize)]);
  [shutter setTarget:self];
  [shutter setAction:@selector (shutterPressed:)];
  [shutter setKeyEquivalent:@"\r"];
  [shutter setAutoresizingMask:NSViewMinXMargin | NSViewMaxXMargin
           | NSViewMaxYMargin];
  [content addSubview:shutter];

  modeControl = AUTORELEASE ([[NSSegmentedControl alloc]
                               initWithFrame:NSMakeRect (right - WCModeWidth,
                                                         barMid - 12,
                                                         WCModeWidth, 24)]);
  [modeControl setSegmentCount:2];
  [modeControl setLabel:@"Photo" forSegment:0];
  [modeControl setLabel:@"Video" forSegment:1];
  [modeControl setWidth:WCModeWidth / 2 - 2 forSegment:0];
  [modeControl setWidth:WCModeWidth / 2 - 2 forSegment:1];
  [modeControl setSelectedSegment:
                 ([[defaults stringForKey:WCModeKey] isEqual:@"video"]
                  ? 1 : 0)];
  [modeControl setTarget:self];
  [modeControl setAction:@selector (modeChosen:)];
  [modeControl setAutoresizingMask:NSViewMinXMargin | NSViewMaxYMargin];
  [content addSubview:modeControl];

  countdownSwitch = AUTORELEASE ([[NSButton alloc]
                                   initWithFrame:NSMakeRect (right - WCModeWidth
                                                             - 10
                                                             - WCSwitchWidth,
                                                             barMid - 10,
                                                             WCSwitchWidth,
                                                             20)]);
  [countdownSwitch setButtonType:NSSwitchButton];
  [countdownSwitch setTitle:@"Countdown"];
  [countdownSwitch setState:([defaults boolForKey:WCCountdownKey]
                             ? NSOnState : NSOffState)];
  [countdownSwitch setTarget:self];
  [countdownSwitch setAction:@selector (countdownChanged:)];
  [countdownSwitch setAutoresizingMask:NSViewMinXMargin | NSViewMaxYMargin];
  [content addSubview:countdownSwitch];

  preview = AUTORELEASE ([[WCPreviewView alloc]
                           initWithFrame:NSMakeRect (0, WCStripHeight
                                                     + WCBarHeight,
                                                     WCPreviewWidth,
                                                     WCPreviewHeight)]);
  [preview setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [preview setMessage:@"Looking for cameras…"];
  [content addSubview:preview];

  [self showMode];
}

/* While a menu or a panel is up too, so the picture keeps moving. */
- (void)addTimer:(NSTimer *)timer
{
  NSRunLoop *loop = [NSRunLoop currentRunLoop];

  [loop addTimer:timer forMode:NSDefaultRunLoopMode];
  [loop addTimer:timer forMode:NSEventTrackingRunLoopMode];
  [loop addTimer:timer forMode:NSModalPanelRunLoopMode];
}

/* The cameras again: one plugged in or out changes the menu, and the
   one shown goes on if it's still there. */
- (void)relist:(NSTimer *)timer
{
  WCCameraInfo found[WCCaptureMaxCameras];
  int count = WCCaptureListCameras (found, WCCaptureMaxCameras);
  char shown[sizeof (found[0].ident)] = "";
  NSString *chosen;
  int i, pick = -1;

  if (current >= 0)
    memcpy (shown, cameras[current].ident, sizeof (shown));
  if (count == cameraCount
      && memcmp (found, cameras, sizeof (found[0]) * (size_t) count) == 0)
    {
      /* The same cameras. One that failed is tried again. */
      if (captureFailed && current >= 0)
        [self openCamera:current];
      return;
    }
  memcpy (cameras, found, sizeof (found));
  cameraCount = count;
  current = -1;

  /* The one shown, else the one chosen last, else the first. */
  chosen = [[NSUserDefaults standardUserDefaults] stringForKey:WCCameraKey];
  for (i = 0; i < count && pick < 0; i++)
    if (shown[0] != '\0' && strcmp (cameras[i].ident, shown) == 0)
      pick = i;
  for (i = 0; i < count && pick < 0; i++)
    if (chosen != nil && [chosen isEqualToString:WCString (cameras[i].ident)])
      pick = i;
  if (pick < 0 && count > 0)
    pick = 0;

  if (pick >= 0 && shown[0] != '\0'
      && strcmp (cameras[pick].ident, shown) == 0 && capture != NULL)
    current = pick;		/* still open */
  else if (pick >= 0)
    [self openCamera:pick];
  else
    {
      [self closeCamera];
      [preview setMessage:@"No camera"];
    }
  [self showCameras];
}

- (void)showCameras
{
  int i;

  [cameraPopUp removeAllItems];
  for (i = 0; i < cameraCount; i++)
    {
      /* Two cameras of one model have one name; the device tells them
         apart. */
      NSString *title = WCString (cameras[i].name);

      if ([cameraPopUp itemWithTitle:title] != nil)
        title = [NSString stringWithFormat:@"%@ (%@)", title,
                          WCString (cameras[i].ident)];
      [cameraPopUp addItemWithTitle:title];
    }
  if (current >= 0)
    [cameraPopUp selectItemAtIndex:current];
  [cameraPopUp setHidden:(cameraCount < 2)];
  [cameraLabel setHidden:(cameraCount >= 2)];
  [cameraPopUp setEnabled:(recorder == NULL)];

  if (current >= 0)
    {
      NSString *name = WCString (cameras[current].name);
      BOOL pattern = cameras[current].backend == WCCameraTestPattern;

      [cameraLabel setStringValue:(capture != NULL
                                   ? [NSString stringWithFormat:@"%@ · %@",
                                               name,
                                               WCString (WCCaptureDescription
                                                         (capture))]
                                   : name)];
      [window setTitle:(pattern ? @"Webcam — Test Pattern" : @"Webcam")];
      [preview setBadge:(pattern ? @"Test Pattern — no camera found" : nil)];
    }
  else
    {
      [cameraLabel setStringValue:@"No camera"];
      [window setTitle:@"Webcam"];
      [preview setBadge:nil];
    }
}

- (void)openCamera:(int)index
{
  char error[256];

  [self cancelCountdown];
  [self stopRecording];
  [self closeCamera];
  current = index;
  capture = WCCaptureOpen (&cameras[index], error, sizeof (error));
  captureFailed = capture == NULL;
  [preview setMirror:[self mirrors]];
  if (capture == NULL)
    {
      NSLog (@"Webcam: can't open %s: %s", cameras[index].ident, error);
      [preview setMessage:[NSString stringWithFormat:
                                      @"Can't use “%@”: %@",
                                    WCString (cameras[index].name),
                                    WCString (error)]];
    }
  else
    [preview setMessage:@"Starting the camera…"];
  [self showCameras];
}

- (void)closeCamera
{
  WCCaptureClose (capture);
  capture = NULL;
  haveFrame = NO;
  [preview setImage:nil];
}

/* Cameras are shown as a mirror, as people expect to see themselves;
   the test pattern isn't. */
- (BOOL)mirrors
{
  return current >= 0 && cameras[current].mirror
    && [[NSUserDefaults standardUserDefaults] boolForKey:WCMirrorKey];
}

- (void)frameFired:(NSTimer *)timer
{
  WCFrame got;
  char error[256];
  int y, r;

  if (capture == NULL)
    return;
  r = WCCaptureRead (capture, &got, error, sizeof (error));
  if (r < 0)
    {
      NSLog (@"Webcam: %s: %s", cameras[current].ident, error);
      [self cancelCountdown];
      [self stopRecording];
      [self closeCamera];
      captureFailed = YES;
      [preview setMessage:WCString (error)];
      return;
    }
  if (r == 0)
    return;

  if (WCFrameAlloc (&frame, got.width, got.height) != 0)
    return;
  for (y = 0; y < got.height; y++)
    memcpy (frame.rgb + (size_t) y * frame.stride,
            got.rgb + (size_t) y * got.stride, (size_t) got.width * 3);
  if (!haveFrame)
    {
      haveFrame = YES;
      [self showCameras];	/* its size is known now */
    }
  [preview setImage:WCImageRep (&frame)];

  if (recorder != NULL)
    {
      const WCFrame *shown = &frame;

      if ([self mirrors] && WCFrameMirror (&frame, &scratch) == 0)
        shown = &scratch;
      if (WCRecorderAdd (recorder, shown, error, sizeof (error)) != 0)
        {
          NSString *why = WCString (error);

          [self stopRecording];
          NSRunAlertPanel (@"Webcam",
                           [NSString stringWithFormat:
                                       @"The recording stopped: %@", why],
                           @"OK", nil, nil);
          return;
        }
      [preview setRecording:WCDuration (WCRecorderSeconds (recorder))];
    }
}

- (BOOL)videoMode
{
  return [modeControl selectedSegment] == 1;
}

- (void)showMode
{
  if (recorder != NULL || countdownTimer != nil)
    [shutter setKind:WCShutterStop];
  else
    [shutter setKind:([self videoMode] ? WCShutterVideo : WCShutterPhoto)];
  if (recorder != NULL)
    [shutterItem setTitle:@"Stop Recording"];
  else
    [shutterItem setTitle:([self videoMode] ? @"Record Video"
                           : @"Take Photo")];
  [cameraPopUp setEnabled:(recorder == NULL)];
}

- (void)cancelCountdown
{
  [countdownTimer invalidate];
  DESTROY (countdownTimer);
  countdown = 0;
  [preview setCountdown:0];
  [self showMode];
}

- (void)countdownFired:(NSTimer *)timer
{
  countdown--;
  if (countdown > 0)
    {
      [preview setCountdown:countdown];
      return;
    }
  [self cancelCountdown];
  if (haveFrame)
    [self captureNow];
}

- (void)captureNow
{
  if ([self videoMode])
    [self startRecording];
  else
    [self takePhoto];
}

/* The folder, made if it isn't there; nil if it can't be. */
- (NSString *)folderForKey:(NSString *)key
{
  NSString *folder = [[NSUserDefaults standardUserDefaults] stringForKey:key];
  NSFileManager *files = [NSFileManager defaultManager];
  BOOL isDirectory = NO;

  if ([folder length] == 0)
    folder = [NSHomeDirectory () stringByAppendingPathComponent:
                                   ([key isEqual:WCVideosFolderKey]
                                    ? @"Videos" : @"Images")];
  folder = [folder stringByExpandingTildeInPath];
  if ([files fileExistsAtPath:folder isDirectory:&isDirectory])
    return isDirectory ? folder : nil;
  if (![files createDirectoryAtPath:folder
        withIntermediateDirectories:YES
                         attributes:nil
                              error:NULL])
    return nil;
  return folder;
}

/* "Photo 2026-11-22 at 14.05.09.png", or "... 2.png" if that's taken. */
- (NSString *)newPathIn:(NSString *)folder kind:(NSString *)kind
              extension:(NSString *)extension
{
  NSString *stamp = [[NSDate date]
                      descriptionWithCalendarFormat:@"%Y-%m-%d at %H.%M.%S"
                                           timeZone:nil
                                             locale:nil];
  NSString *base = [NSString stringWithFormat:@"%@ %@", kind, stamp];
  NSString *path = [folder stringByAppendingPathComponent:
                             [base stringByAppendingPathExtension:extension]];
  int n;

  for (n = 2; [[NSFileManager defaultManager] fileExistsAtPath:path]; n++)
    path = [folder stringByAppendingPathComponent:
                     [[NSString stringWithFormat:@"%@ %d", base, n]
                       stringByAppendingPathExtension:extension]];
  return path;
}

- (void)takePhoto
{
  NSString *folder = [self folderForKey:WCPhotosFolderKey];
  BOOL jpeg = [[[NSUserDefaults standardUserDefaults]
                 stringForKey:WCPhotoFormatKey] isEqual:@"jpeg"];
  const WCFrame *shown = &frame;
  NSString *path;
  char error[256];
  int r;

  if (folder == nil)
    {
      NSRunAlertPanel (@"Webcam",
                       @"The photo couldn't be saved: there's no folder "
                       @"for photos, and one can't be made.",
                       @"OK", nil, nil);
      return;
    }
  /* The photo is the picture as shown. */
  if ([self mirrors] && WCFrameMirror (&frame, &scratch) == 0)
    shown = &scratch;
  path = [self newPathIn:folder kind:@"Photo"
               extension:(jpeg ? @"jpg" : @"png")];
  r = jpeg ? WCImageWriteJPEG (shown, WCJPEGQuality,
                               [path fileSystemRepresentation], error,
                               sizeof (error))
    : WCImageWritePNG (shown, [path fileSystemRepresentation], error,
                       sizeof (error));
  [preview flash];
  if (r != 0)
    {
      NSRunAlertPanel (@"Webcam",
                       [NSString stringWithFormat:
                                   @"The photo couldn't be saved to “%@”: %@",
                                 folder, WCString (error)],
                       @"OK", nil, nil);
      return;
    }
  [self setThumbnailOf:path from:shown];
  [self reloadStrip];
  [strip selectPath:path];
}

- (void)startRecording
{
  NSString *folder = [self folderForKey:WCVideosFolderKey];
  NSString *path;
  char error[256];

  if (folder == nil)
    {
      NSRunAlertPanel (@"Webcam",
                       @"Recording couldn't start: there's no folder for "
                       @"videos, and one can't be made.",
                       @"OK", nil, nil);
      return;
    }
  path = [self newPathIn:folder kind:@"Video"
               extension:WCString (WCRecorderExtension)];
  recorder = WCRecorderStart ([path fileSystemRepresentation], frame.width,
                              frame.height, error, sizeof (error));
  if (recorder == NULL)
    {
      NSRunAlertPanel (@"Webcam",
                       [NSString stringWithFormat:
                                   @"Recording couldn't start in “%@”: %@",
                                 folder, WCString (error)],
                       @"OK", nil, nil);
      return;
    }
  ASSIGN (recordingPath, path);
  [self setThumbnailOf:path from:&frame];
  [preview setRecording:WCDuration (0)];
  [self showMode];
}

- (void)stopRecording
{
  NSString *path;
  char error[256];

  if (recorder == NULL)
    return;
  if (WCRecorderFinish (recorder, error, sizeof (error)) != 0)
    NSRunAlertPanel (@"Webcam",
                     [NSString stringWithFormat:
                                 @"The recording “%@” couldn't be finished: %@",
                               [recordingPath lastPathComponent],
                               WCString (error)],
                     @"OK", nil, nil);
  recorder = NULL;
  path = AUTORELEASE (recordingPath);
  recordingPath = nil;
  [preview setRecording:nil];
  [self showMode];
  [self reloadStrip];
  [strip selectPath:path];
}

- (void)setThumbnailOf:(NSString *)path from:(const WCFrame *)picture
{
  WCFrame small;
  NSImage *image;

  memset (&small, 0, sizeof (small));
  if (WCFrameShrink (picture, WCThumbWidth, WCThumbHeight, &small) != 0)
    return;
  image = WCImageFromFrame (&small);
  WCFrameFree (&small);
  if (image != nil)
    [thumbnails setObject:image forKey:path];
}

/* A small copy, made once; NSNull for a file it can't read. */
- (NSImage *)thumbnailOf:(NSString *)path video:(BOOL)video
{
  id image = [thumbnails objectForKey:path];
  WCFrame big, small;
  int r;

  if (image != nil)
    return image == [NSNull null] ? nil : image;
  memset (&big, 0, sizeof (big));
  memset (&small, 0, sizeof (small));
  r = video
    ? WCRecorderReadFirstFrame ([path fileSystemRepresentation], 4, &big)
    : WCImageRead ([path fileSystemRepresentation], WCThumbWidth, &big);
  if (r == 0 && WCFrameShrink (&big, WCThumbWidth, WCThumbHeight, &small) == 0)
    image = WCImageFromFrame (&small);
  WCFrameFree (&big);
  WCFrameFree (&small);
  [thumbnails setObject:(image != nil ? image : [NSNull null]) forKey:path];
  return image;
}

/* This app's photos and videos, newest first. */
- (void)reloadStrip
{
  NSMutableArray *found = [NSMutableArray array];
  NSMutableArray *items = [NSMutableArray array];
  NSFileManager *files = [NSFileManager defaultManager];
  NSString *folders[2];
  NSUInteger f, i;

  folders[0] = [self folderForKey:WCPhotosFolderKey];
  folders[1] = [self folderForKey:WCVideosFolderKey];
  for (f = 0; f < 2; f++)
    {
      NSString *folder = folders[f];
      NSArray *names;

      /* None, or both in one folder. */
      if (folder == nil || (f == 1 && [folder isEqual:folders[0]]))
        continue;
      names = [files contentsOfDirectoryAtPath:folder error:NULL];
      for (i = 0; i < [names count]; i++)
        {
          NSString *name = [names objectAtIndex:i];
          NSString *ext = [[name pathExtension] lowercaseString];
          NSString *path = [folder stringByAppendingPathComponent:name];
          BOOL video = [name hasPrefix:@"Video "]
            && [ext isEqual:WCString (WCRecorderExtension)];
          BOOL photo = [name hasPrefix:@"Photo "]
            && ([ext isEqual:@"png"] || [ext isEqual:@"jpg"]
                || [ext isEqual:@"jpeg"]);
          NSDate *date;

          if (!video && !photo)
            continue;
          /* One still being recorded shows once it's done. */
          if (recordingPath != nil && [path isEqual:recordingPath])
            continue;
          date = [[files attributesOfItemAtPath:path error:NULL]
                   fileModificationDate];
          if (date == nil)
            continue;
          [found addObject:[NSArray arrayWithObjects:date, path,
                                    [NSNumber numberWithBool:video], nil]];
        }
    }
  [found sortUsingFunction:WCNewestFirst context:NULL];
  for (i = 0; i < [found count] && i < WCStripMost; i++)
    {
      NSArray *entry = [found objectAtIndex:i];
      NSString *path = [entry objectAtIndex:1];
      NSNumber *video = [entry objectAtIndex:2];
      NSImage *image = [self thumbnailOf:path video:[video boolValue]];
      NSMutableDictionary *item = [NSMutableDictionary dictionary];

      [item setObject:path forKey:WCStripPath];
      [item setObject:video forKey:WCStripVideo];
      if (image != nil)
        [item setObject:image forKey:WCStripImage];
      [items addObject:item];
    }
  [strip setItems:items];
}

- (void)showPhotoFormat
{
  BOOL jpeg = [[[NSUserDefaults standardUserDefaults]
                 stringForKey:WCPhotoFormatKey] isEqual:@"jpeg"];

  [pngItem setState:(jpeg ? NSOffState : NSOnState)];
  [jpegItem setState:(jpeg ? NSOnState : NSOffState)];
}

@end
