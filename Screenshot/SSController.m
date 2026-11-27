/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "SSController.h"
#import "SSThumbnail.h"
#import "SSWindowServer.h"
#import <GNUstepBase/GNUstep.h>

#include <errno.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

/* Defaults (the app's own domain, org.nextbsd.Screenshot). */
#define SSSaveToKey @"ScreenshotSaveTo"		/* Desktop, Documents,
						   Clipboard, Other */
#define SSOtherFolderKey @"ScreenshotOtherFolder"
#define SSTimerKey @"ScreenshotTimer"		/* 0, 5 or 10 */
#define SSMicrophoneKey @"ScreenshotMicrophone"	/* /dev/dspN, or "" */
#define SSShowPointerKey @"ScreenshotShowPointer"
#define SSShowThumbnailKey @"ScreenshotShowThumbnail"
#define SSRememberKey @"ScreenshotRememberSelection"
#define SSLastSelectionKey @"ScreenshotLastSelection"
#define SSLastToolKey @"ScreenshotLastTool"
/* Seconds with nothing to do before quitting (0: never). The Dock
   starts Screenshot again for the next screenshot key. */
#define SSIdleQuitKey @"ScreenshotIdleQuitSeconds"

/* The windows go before the picture is taken: time for WindowServer
   to show the screen without them. */
#define SSSettleSeconds 0.2
#define SSDefaultSelection NSMakeSize (640, 400)
#define SSMaxMicrophones 8

static NSString *
SSUserDefault (NSString *key)
{
  return [[NSUserDefaults standardUserDefaults] stringForKey:key];
}

static BOOL
SSBoolDefault (NSString *key, BOOL fallback)
{
  id value = [[NSUserDefaults standardUserDefaults] objectForKey:key];

  return value != nil ? [value boolValue] : fallback;
}

/* "2026-11-27 at 21.04.07" */
static NSString *
SSStamp (void)
{
  char buf[64];
  time_t now = time (NULL);
  struct tm tm;

  localtime_r (&now, &tm);
  strftime (buf, sizeof (buf), "%Y-%m-%d at %H.%M.%S", &tm);
  return [NSString stringWithUTF8String:buf];
}

/* A name not taken yet in folder: "base.ext", else "base (2).ext". */
static NSString *
SSFreePath (NSString *folder, NSString *base, NSString *ext)
{
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *path = [folder stringByAppendingPathComponent:
                             [base stringByAppendingPathExtension:ext]];
  int n = 2;

  while ([fm fileExistsAtPath:path])
    path = [folder stringByAppendingPathComponent:
                     [[NSString stringWithFormat:@"%@ (%d)", base, n++]
                       stringByAppendingPathExtension:ext]];
  return path;
}

/* XRGB8888 pixels (B, G, R, x) to an RGB image, the part in crop. */
static NSBitmapImageRep *
SSImageRep (const SSImage *img, int cx, int cy, int cw, int ch)
{
  NSBitmapImageRep *rep;
  unsigned char *out;
  int x, y;

  if (cw <= 0 || ch <= 0)
    return nil;
  rep = [[NSBitmapImageRep alloc]
          initWithBitmapDataPlanes:NULL
                        pixelsWide:cw
                        pixelsHigh:ch
                     bitsPerSample:8
                   samplesPerPixel:3
                          hasAlpha:NO
                          isPlanar:NO
                    colorSpaceName:NSDeviceRGBColorSpace
                       bytesPerRow:cw * 3
                      bitsPerPixel:24];
  out = [rep bitmapData];
  if (out == NULL)
    {
      RELEASE (rep);
      return nil;
    }
  for (y = 0; y < ch; y++)
    {
      const unsigned char *s = img->pixels + (size_t) (cy + y) * img->stride
        + (size_t) cx * 4;
      unsigned char *d = out + (size_t) y * cw * 3;

      for (x = 0; x < cw; x++, s += 4, d += 3)
        {
          d[0] = s[2];
          d[1] = s[1];
          d[2] = s[0];
        }
    }
  return AUTORELEASE (rep);
}

/* The big number of the timer's countdown. */
@interface SSCountdownView : NSView
{
  int _value;
}
- (void)setValue:(int)value;
@end

@implementation SSCountdownView
- (BOOL)isOpaque
{
  return NO;
}

- (void)setValue:(int)value
{
  _value = value;
  [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)rect
{
  NSString *text = [NSString stringWithFormat:@"%d", _value];
  NSDictionary *attrs =
    [NSDictionary dictionaryWithObjectsAndKeys:
                    [NSFont boldSystemFontOfSize:56], NSFontAttributeName,
                  [NSColor whiteColor], NSForegroundColorAttributeName, nil];
  NSSize size = [text sizeWithAttributes:attrs];
  NSRect b = [self bounds];

  [[NSColor clearColor] set];
  NSRectFillUsingOperation (b, NSCompositeCopy);
  [[NSColor colorWithCalibratedWhite:0.1 alpha:0.85] set];
  [[NSBezierPath bezierPathWithRoundedRect:b xRadius:22 yRadius:22] fill];
  [text drawAtPoint:NSMakePoint (floor (NSMidX (b) - size.width / 2),
                                 floor (NSMidY (b) - size.height / 2))
     withAttributes:attrs];
}
@end

@interface SSController (Private)
- (void)handleRequest:(NSDictionary *)request;
- (void)closeUI;
- (void)showOverlayMode:(SSOverlayMode)mode quick:(BOOL)quick
                toolbar:(BOOL)toolbar;
- (void)takeTool:(SSTool)tool rect:(NSRect)rect window:(uint32_t)window;
- (void)startRecordingRect:(NSRect)rect;
- (void)stopRecording;
- (void)postRecordingState;
- (void)noteBusy;
@end

@implementation SSController

+ (id)proxy
{
  id proxy = nil;

  NS_DURING
    {
      proxy = [NSConnection
                rootProxyForConnectionWithRegisteredName:SSConnectionName
                                                    host:@""
                                         usingNameServer:
                  [NSMessagePortNameServer sharedInstance]];
      [proxy setProtocolForProxy:@protocol (SSScreenshotServer)];
    }
  NS_HANDLER
    {
      proxy = nil;
    }
  NS_ENDHANDLER
  return proxy;
}

+ (BOOL)forwardRequest:(NSDictionary *)request
{
  id proxy = [self proxy];

  if (proxy == nil)
    return NO;
  if (request == nil)
    request = [NSDictionary dictionaryWithObject:SSActionToolbar
                                          forKey:SSActionKey];
  NS_DURING
    {
      [proxy performRequest:request];
    }
  NS_HANDLER
    {
      NSLog (@"Screenshot: the copy already running didn't answer: %@",
             localException);
    }
  NS_ENDHANDLER
  return YES;
}

- (id)initWithRequest:(NSDictionary *)request
{
  if ((self = [super init]) == nil)
    return nil;
  ASSIGN (_firstRequest, request);
  _thumbnail = [[SSThumbnail alloc] init];
  [[NSUserDefaults standardUserDefaults] registerDefaults:
    [NSDictionary dictionaryWithObjectsAndKeys:
                    @"Desktop", SSSaveToKey,
                  [NSNumber numberWithInt:0], SSTimerKey,
                  @"", SSMicrophoneKey,
                  [NSNumber numberWithBool:YES], SSShowPointerKey,
                  [NSNumber numberWithBool:YES], SSShowThumbnailKey,
                  [NSNumber numberWithBool:YES], SSRememberKey,
                  [NSNumber numberWithInt:SSToolSelection], SSLastToolKey,
                  [NSNumber numberWithInt:300], SSIdleQuitKey,
                  nil]];
  return self;
}

- (void)dealloc
{
  [[NSDistributedNotificationCenter defaultCenter] removeObserver:self];
  RELEASE (_firstRequest);
  RELEASE (_connection);
  RELEASE (_overlay);
  RELEASE (_toolbar);
  RELEASE (_thumbnail);
  RELEASE (_recordPath);
  RELEASE (_recordStarted);
  [super dealloc];
}

/* ---- the app ---- */

- (void)buildMenu
{
  NSMenu *menu = AUTORELEASE ([[NSMenu alloc] initWithTitle:@"Screenshot"]);
  NSMenu *capture = AUTORELEASE ([[NSMenu alloc] initWithTitle:@"Capture"]);

  [menu addItemWithTitle:@"Info..." action:@selector (orderFrontStandardInfoPanel:)
           keyEquivalent:@""];
  [[menu addItemWithTitle:@"Capture" action:NULL keyEquivalent:@""]
    setSubmenu:capture];
  [capture addItemWithTitle:@"Screen" action:@selector (captureScreen:)
              keyEquivalent:@""];
  [capture addItemWithTitle:@"Selection" action:@selector (captureSelection:)
              keyEquivalent:@""];
  [capture addItemWithTitle:@"Window" action:@selector (captureWindow:)
              keyEquivalent:@""];
  [capture addItemWithTitle:@"Show Toolbar" action:@selector (showToolbar:)
              keyEquivalent:@""];
  [capture addItem:[NSMenuItem separatorItem]];
  [capture addItemWithTitle:@"Stop Recording" action:@selector (stopRecording:)
              keyEquivalent:@""];
  [menu addItemWithTitle:@"Hide" action:@selector (hide:) keyEquivalent:@"h"];
  [menu addItemWithTitle:@"Quit" action:@selector (terminate:)
           keyEquivalent:@"q"];
  [NSApp setMainMenu:menu];
}

- (void)applicationDidFinishLaunching:(NSNotification *)note
{
  NSDistributedNotificationCenter *dnc =
    [NSDistributedNotificationCenter defaultCenter];

  /* One Screenshot a user: the other programs (the Dock, Video) find
     it by this name. */
  _connection = [[NSConnection alloc] initWithReceivePort:[NSMessagePort port]
                                                 sendPort:nil];
  [_connection setRootObject:self];
  if (![_connection registerName:SSConnectionName
                  withNameServer:[NSMessagePortNameServer sharedInstance]])
    {
      /* Another started at the same moment: it takes the request. */
      DESTROY (_connection);
      [SSController forwardRequest:_firstRequest];
      [NSApp terminate:self];
      return;
    }
  [dnc addObserver:self selector:@selector (stopNotified:)
              name:SSStopNotification object:nil];
  [dnc addObserver:self selector:@selector (queryNotified:)
              name:SSRecordingQueryNotification object:nil];
  [self buildMenu];
  [self handleRequest:_firstRequest];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(id)sender
{
  return NO;
}

- (void)applicationWillTerminate:(NSNotification *)note
{
  if (_recorder != NULL || _streaming)
    [self stopRecording];
  [_connection registerName:nil
             withNameServer:[NSMessagePortNameServer sharedInstance]];
  [_connection invalidate];
}

/* ---- requests ---- */

- (oneway void)performRequest:(bycopy NSDictionary *)request
{
  /* Out of the Distributed Objects call first: the caller (the Dock)
     isn't kept waiting for what this shows. */
  [self performSelector:@selector (handleRequest:) withObject:request
             afterDelay:0];
}

- (void)stopNotified:(NSNotification *)note
{
  [self stopRecording];
}

- (void)queryNotified:(NSNotification *)note
{
  [self postRecordingState];
}

- (void)handleRequest:(NSDictionary *)request
{
  NSString *action = [request objectForKey:SSActionKey];
  BOOL clipboard = [[request objectForKey:SSClipboardKey] boolValue];
  BOOL recording = _recorder != NULL || _streaming;

  [self noteBusy];
  if (action == nil)
    action = SSActionToolbar;
  if ([action isEqualToString:SSActionStop])
    {
      [self stopRecording];
      return;
    }
  if (_busy)
    return;
  if (recording)
    {
      /* While recording, any of them brings the Stop toolbar. */
      [self closeUI];
      [self showOverlayMode:SSOverlayScreen quick:NO toolbar:YES];
      return;
    }
  [self closeUI];
  _toClipboard = clipboard;
  if ([action isEqualToString:SSActionScreen])
    [self takeTool:SSToolScreen rect:NSZeroRect window:0];
  else if ([action isEqualToString:SSActionSelection])
    [self showOverlayMode:SSOverlaySelection quick:YES toolbar:NO];
  else if ([action isEqualToString:SSActionWindow])
    [self showOverlayMode:SSOverlayWindow quick:YES toolbar:NO];
  else
    {
      if ([action isEqualToString:SSActionRecordScreen])
        [[NSUserDefaults standardUserDefaults]
          setInteger:SSToolRecordScreen forKey:SSLastToolKey];
      else if ([action isEqualToString:SSActionRecordSelection])
        [[NSUserDefaults standardUserDefaults]
          setInteger:SSToolRecordSelection forKey:SSLastToolKey];
      [self showToolbar:nil];
    }
}

- (void)captureScreen:(id)sender
{
  [self handleRequest:[NSDictionary dictionaryWithObject:SSActionScreen
                                                  forKey:SSActionKey]];
}

- (void)captureSelection:(id)sender
{
  [self handleRequest:[NSDictionary dictionaryWithObject:SSActionSelection
                                                  forKey:SSActionKey]];
}

- (void)captureWindow:(id)sender
{
  [self handleRequest:[NSDictionary dictionaryWithObject:SSActionWindow
                                                  forKey:SSActionKey]];
}

- (void)stopRecording:(id)sender
{
  [self stopRecording];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
  if ([item action] == @selector (stopRecording:))
    return _recorder != NULL || _streaming;
  return YES;
}

/* ---- quitting when idle ---- */

- (void)idleExpired:(NSTimer *)timer
{
  _idleTimer = nil;
  if (_overlay != nil && [_overlay isVisible])
    return;
  if (_toolbar != nil && [_toolbar isVisible])
    return;
  if (_recorder != NULL || _streaming || _busy || _countdownTimer != nil)
    {
      [self noteBusy];
      return;
    }
  [NSApp terminate:self];
}

/* Something happened: quit only after the idle time from now. */
- (void)noteBusy
{
  NSInteger seconds = [[NSUserDefaults standardUserDefaults]
                        integerForKey:SSIdleQuitKey];

  [_idleTimer invalidate];
  _idleTimer = nil;
  if (seconds > 0)
    _idleTimer = [NSTimer scheduledTimerWithTimeInterval:seconds
                                                  target:self
                                                selector:@selector (idleExpired:)
                                                userInfo:nil
                                                 repeats:NO];
}

/* ---- the overlay and the toolbar ---- */

- (NSRect)screenFrame
{
  return [[NSScreen mainScreen] frame];
}

- (NSRect)defaultSelection
{
  NSRect s = [self screenFrame];
  NSString *saved = SSUserDefault (SSLastSelectionKey);
  NSRect r;

  if (saved != nil && SSBoolDefault (SSRememberKey, YES))
    {
      r = NSIntersectionRect (NSRectFromString (saved),
                              NSMakeRect (0, 0, NSWidth (s), NSHeight (s)));
      if (NSWidth (r) >= 8 && NSHeight (r) >= 8)
        return r;
    }
  return NSIntegralRect (NSMakeRect (NSWidth (s) / 2 - SSDefaultSelection.width / 2,
                                     NSHeight (s) / 2
                                     - SSDefaultSelection.height / 2 + 40,
                                     SSDefaultSelection.width,
                                     SSDefaultSelection.height));
}

/* The windows to pick from, in the overlay's coordinates, front
   first: every app's but this one's, above the desktop. */
- (void)loadWindows
{
  NSMutableArray *rects = [NSMutableArray array];
  NSMutableArray *ids = [NSMutableArray array];
  CGFloat height = NSHeight ([self screenFrame]);
  SSWindowInfo *list;
  int n, i;

  if (SSWSListWindows (&list, &n) < 0)
    {
      NSLog (@"Screenshot: can't list the windows: %s", strerror (errno));
      n = 0;
      list = NULL;
    }
  for (i = 0; i < n; i++)
    {
      SSWindowInfo *w = &list[i];

      if (w->pid == getpid () || w->level < 0 || w->width < 8
          || w->height < 8)
        continue;
      [rects addObject:[NSValue valueWithRect:
                                  NSMakeRect (w->x, height - w->y - w->height,
                                              w->width, w->height)]];
      [ids addObject:[NSNumber numberWithUnsignedInt:w->window]];
    }
  free (list);
  [_overlayView setWindows:rects ids:ids];
}

- (void)showOverlayMode:(SSOverlayMode)mode quick:(BOOL)quick
                toolbar:(BOOL)toolbar
{
  BOOL recording = _recorder != NULL || _streaming;

  if (_overlay == nil)
    _overlay = RETAIN (SSOverlayWindowCreate (self, &_overlayView));
  [_overlay setFrame:[self screenFrame] display:NO];
  if (mode == SSOverlayWindow)
    [self loadWindows];
  [_overlayView setSelection:(quick ? NSZeroRect : [self defaultSelection])];
  [_overlayView setMode:mode quick:quick];
  [NSApp activateIgnoringOtherApps:YES];
  [_overlay makeKeyAndOrderFront:nil];
  [_overlay makeFirstResponder:_overlayView];
  if (toolbar)
    {
      [_toolbar orderOut:nil];
      DESTROY (_toolbar);
      _toolbar = RETAIN (SSToolbarWindowCreate (self, &_toolbarView));
      if (recording)
        {
          NSSize size = SSToolbarSize (YES);
          NSRect f = [_toolbar frame];

          [_toolbarView setRecording:YES];
          [_toolbar setFrame:NSMakeRect (floor (NSMidX (f) - size.width / 2),
                                         NSMinY (f), size.width, size.height)
                     display:NO];
          [_toolbarView setFrame:NSMakeRect (0, 0, size.width, size.height)];
        }
      else
        [_toolbarView setTool:[_overlayView mode] == SSOverlayScreen
                      && SSToolRecords ((SSTool) [[NSUserDefaults
                                                   standardUserDefaults]
                                                  integerForKey:SSLastToolKey])
                      ? SSToolRecordScreen
                      : mode == SSOverlayWindow ? SSToolWindow
                      : mode == SSOverlayScreen ? SSToolScreen
                      : SSToolSelection];
      [_toolbar orderFront:nil];
    }
}

- (void)showToolbar:(id)sender
{
  NSInteger last = [[NSUserDefaults standardUserDefaults]
                     integerForKey:SSLastToolKey];
  SSTool tool = last >= SSToolScreen && last <= SSToolRecordSelection
    ? (SSTool) last : SSToolSelection;

  [self showOverlayMode:(SSToolSelects (tool) ? SSOverlaySelection
                         : tool == SSToolWindow ? SSOverlayWindow
                         : SSOverlayScreen)
                  quick:NO toolbar:YES];
  [_toolbarView setTool:tool];
}

- (void)saveSelection
{
  if (_overlayView != nil && !NSIsEmptyRect ([_overlayView selection])
      && ![_overlayView isQuick])
    [[NSUserDefaults standardUserDefaults]
      setObject:NSStringFromRect ([_overlayView selection])
         forKey:SSLastSelectionKey];
}

- (void)closeUI
{
  [self saveSelection];
  [_countdownTimer invalidate];
  _countdownTimer = nil;
  [_countdown orderOut:nil];
  [_toolbar orderOut:nil];
  [_overlay orderOut:nil];
}

/* After a picture or Escape: the app that was in front is again. */
- (void)giveBackFocus
{
  [NSApp deactivate];
}

/* ---- SSOverlayDelegate ---- */

- (void)overlayDidCancel:(SSOverlayView *)overlay
{
  [self closeUI];
  [self giveBackFocus];
}

- (void)overlayDidChoose:(SSOverlayView *)overlay
{
  BOOL recording = _recorder != NULL || _streaming;
  SSTool tool;

  if (recording)
    return;
  if (_toolbar != nil && [_toolbar isVisible])
    tool = [_toolbarView tool];
  else
    tool = [overlay mode] == SSOverlayWindow ? SSToolWindow
      : [overlay mode] == SSOverlayScreen ? SSToolScreen : SSToolSelection;
  /* With the toolbar, a selection is taken by its button; a click
     takes the screen or a window. */
  if (_toolbar != nil && [_toolbar isVisible] && SSToolSelects (tool))
    return;
  [self takeTool:tool rect:[overlay selection]
          window:[overlay chosenWindow]];
}

- (void)overlayDidConfirm:(SSOverlayView *)overlay
{
  if (_toolbar != nil && [_toolbar isVisible])
    [self toolbarCapture:_toolbarView];
  else
    [self overlayDidChoose:overlay];
}

- (void)overlayDidSwapMode:(SSOverlayView *)overlay
{
  if ([overlay mode] == SSOverlaySelection)
    {
      [self loadWindows];
      [overlay setMode:SSOverlayWindow quick:YES];
    }
  else
    [overlay setMode:SSOverlaySelection quick:YES];
}

/* ---- SSToolbarDelegate ---- */

- (void)toolbarClose:(id)toolbar
{
  [self closeUI];
  [self giveBackFocus];
}

- (void)toolbar:(id)toolbar choseTool:(SSTool)tool
{
  [[NSUserDefaults standardUserDefaults] setInteger:tool forKey:SSLastToolKey];
  [_toolbarView setTool:tool];
  if (SSToolSelects (tool))
    {
      if ([_overlayView mode] != SSOverlaySelection
          || NSIsEmptyRect ([_overlayView selection]))
        [_overlayView setSelection:[self defaultSelection]];
      [_overlayView setMode:SSOverlaySelection quick:NO];
    }
  else if (tool == SSToolWindow)
    {
      [self saveSelection];
      [self loadWindows];
      [_overlayView setMode:SSOverlayWindow quick:NO];
    }
  else
    {
      [self saveSelection];
      [_overlayView setMode:SSOverlayScreen quick:NO];
    }
  [_overlay makeKeyWindow];
}

- (void)toolbarCapture:(id)toolbar
{
  SSTool tool = [_toolbarView tool];

  if (_recorder != NULL || _streaming)
    {
      [self closeUI];
      [self stopRecording];
      return;
    }
  if (tool == SSToolWindow && [_overlayView chosenWindow] == 0)
    return;			/* point at one first */
  if (SSToolSelects (tool) && NSIsEmptyRect ([_overlayView selection]))
    return;
  [self takeTool:tool rect:[_overlayView selection]
          window:[_overlayView chosenWindow]];
}

/* The Options menu. */
- (NSMenuItem *)addOption:(NSString *)title to:(NSMenu *)menu
                   action:(SEL)action value:(id)value on:(BOOL)on
{
  NSMenuItem *item = (NSMenuItem *) [menu addItemWithTitle:title action:action
                              keyEquivalent:@""];

  [item setTarget:self];
  [item setRepresentedObject:value];
  [item setState:on ? NSOnState : NSOffState];
  return item;
}

- (void)addHeading:(NSString *)title to:(NSMenu *)menu
{
  NSMenuItem *item = (NSMenuItem *) [menu addItemWithTitle:title action:NULL
                              keyEquivalent:@""];

  [item setEnabled:NO];
}

- (void)toolbar:(id)toolbar showOptions:(NSEvent *)event inRect:(NSRect)rect
{
  NSMenu *menu = AUTORELEASE ([[NSMenu alloc] initWithTitle:@"Options"]);
  NSString *saveTo = SSUserDefault (SSSaveToKey);
  NSString *mic = SSUserDefault (SSMicrophoneKey);
  NSInteger timer = [[NSUserDefaults standardUserDefaults]
                      integerForKey:SSTimerKey];
  NSString *other = SSUserDefault (SSOtherFolderKey);
  char paths[SSMaxMicrophones][32], names[SSMaxMicrophones][96];
  int n = SSRecorderMicrophones (paths, names, SSMaxMicrophones), i;

  [menu setAutoenablesItems:NO];
  [self addHeading:@"Save to" to:menu];
  [self addOption:@"Desktop" to:menu action:@selector (setSaveTo:)
            value:@"Desktop" on:[saveTo isEqualToString:@"Desktop"]];
  [self addOption:@"Documents" to:menu action:@selector (setSaveTo:)
            value:@"Documents" on:[saveTo isEqualToString:@"Documents"]];
  [self addOption:@"Clipboard" to:menu action:@selector (setSaveTo:)
            value:@"Clipboard" on:[saveTo isEqualToString:@"Clipboard"]];
  if (other != nil && [other length] > 0)
    [self addOption:[other lastPathComponent] to:menu
             action:@selector (setSaveTo:) value:@"Other"
                 on:[saveTo isEqualToString:@"Other"]];
  [self addOption:@"Other Folder..." to:menu
           action:@selector (chooseOtherFolder:) value:nil on:NO];
  [menu addItem:[NSMenuItem separatorItem]];
  [self addHeading:@"Timer" to:menu];
  [self addOption:@"None" to:menu action:@selector (setTimer:)
            value:[NSNumber numberWithInt:0] on:timer == 0];
  [self addOption:@"5 Seconds" to:menu action:@selector (setTimer:)
            value:[NSNumber numberWithInt:5] on:timer == 5];
  [self addOption:@"10 Seconds" to:menu action:@selector (setTimer:)
            value:[NSNumber numberWithInt:10] on:timer == 10];
  [menu addItem:[NSMenuItem separatorItem]];
  [self addHeading:@"Recording" to:menu];
  [self addOption:@"Microphone: None" to:menu
           action:@selector (setMicrophone:) value:@""
               on:mic == nil || [mic length] == 0];
  for (i = 0; i < n; i++)
    {
      NSString *path = [NSString stringWithUTF8String:paths[i]];

      [self addOption:[NSString stringWithFormat:@"Microphone: %s", names[i]]
                   to:menu action:@selector (setMicrophone:) value:path
                   on:[mic isEqualToString:path]];
    }
  [menu addItem:[NSMenuItem separatorItem]];
  [self addHeading:@"Options" to:menu];
  [self addOption:@"Show the Pointer" to:menu
           action:@selector (toggleOption:) value:SSShowPointerKey
               on:SSBoolDefault (SSShowPointerKey, YES)];
  [self addOption:@"Show the Thumbnail" to:menu
           action:@selector (toggleOption:) value:SSShowThumbnailKey
               on:SSBoolDefault (SSShowThumbnailKey, YES)];
  [self addOption:@"Remember the Last Selection" to:menu
           action:@selector (toggleOption:) value:SSRememberKey
               on:SSBoolDefault (SSRememberKey, YES)];
  [NSMenu popUpContextMenu:menu withEvent:event forView:toolbar];
}

- (void)setSaveTo:(id)sender
{
  [[NSUserDefaults standardUserDefaults] setObject:[sender representedObject]
                                            forKey:SSSaveToKey];
}

- (void)chooseOtherFolder:(id)sender
{
  NSOpenPanel *panel = [NSOpenPanel openPanel];

  [panel setCanChooseDirectories:YES];
  [panel setCanChooseFiles:NO];
  [panel setAllowsMultipleSelection:NO];
  [panel setTitle:@"Save Screenshots To"];
  [panel setLevel:SSToolbarLevel + 1];
  if ([panel runModalForDirectory:NSHomeDirectory () file:nil types:nil]
      == NSOKButton)
    {
      NSUserDefaults *d = [NSUserDefaults standardUserDefaults];

      [d setObject:[panel filename] forKey:SSOtherFolderKey];
      [d setObject:@"Other" forKey:SSSaveToKey];
    }
  [_overlay makeKeyWindow];
}

- (void)setTimer:(id)sender
{
  [[NSUserDefaults standardUserDefaults]
    setInteger:[[sender representedObject] intValue] forKey:SSTimerKey];
}

- (void)setMicrophone:(id)sender
{
  [[NSUserDefaults standardUserDefaults] setObject:[sender representedObject]
                                            forKey:SSMicrophoneKey];
}

- (void)toggleOption:(id)sender
{
  NSString *key = [sender representedObject];

  [[NSUserDefaults standardUserDefaults]
    setBool:!SSBoolDefault (key, YES) forKey:key];
}

/* ---- taking it ---- */

/* Where pictures go: a folder, or nil for the clipboard. */
- (NSString *)destinationFolder
{
  NSString *saveTo = SSUserDefault (SSSaveToKey);
  NSString *folder;

  if (_toClipboard || [saveTo isEqualToString:@"Clipboard"])
    return nil;
  if ([saveTo isEqualToString:@"Other"]
      && [SSUserDefault (SSOtherFolderKey) length] > 0)
    folder = SSUserDefault (SSOtherFolderKey);
  else if ([saveTo isEqualToString:@"Documents"])
    folder = [NSHomeDirectory () stringByAppendingPathComponent:@"Documents"];
  else
    folder = [NSHomeDirectory () stringByAppendingPathComponent:@"Desktop"];
  [[NSFileManager defaultManager] createDirectoryAtPath:folder
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:NULL];
  return folder;
}

/* "Desktop", or the folder's name */
- (NSString *)nameOfFolder:(NSString *)folder
{
  return [[NSFileManager defaultManager] displayNameAtPath:folder];
}

- (void)countdownTick:(NSTimer *)timer
{
  _countdownLeft--;
  if (_countdownLeft > 0)
    {
      [(SSCountdownView *) [_countdown contentView] setValue:_countdownLeft];
      return;
    }
  [_countdownTimer invalidate];
  _countdownTimer = nil;
  [_countdown orderOut:nil];
  [self performSelector:@selector (takeNow:) withObject:nil
             afterDelay:SSSettleSeconds];
}

- (void)takeTool:(SSTool)tool rect:(NSRect)rect window:(uint32_t)window
{
  NSInteger timer = [[NSUserDefaults standardUserDefaults]
                      integerForKey:SSTimerKey];
  BOOL fromToolbar = _toolbar != nil && [_toolbar isVisible];

  [self noteBusy];
  _busy = YES;
  [self closeUI];
  _countdownTool = tool;
  _countdownRect = rect;
  _countdownWindow = window;
  /* The timer is the toolbar's (and recordings start without it). */
  if (fromToolbar && timer > 0 && !SSToolRecords (tool))
    {
      NSRect s = [self screenFrame];

      if (_countdown == nil)
        {
          SSCountdownView *v =
            AUTORELEASE ([[SSCountdownView alloc]
                           initWithFrame:NSMakeRect (0, 0, 120, 120)]);

          _countdown = [[NSWindow alloc]
                         initWithContentRect:NSMakeRect (0, 0, 120, 120)
                                   styleMask:NSBorderlessWindowMask
                                     backing:NSBackingStoreBuffered
                                       defer:NO];
          [_countdown setOpaque:NO];
          [_countdown setBackgroundColor:[NSColor clearColor]];
          [_countdown setLevel:SSToolbarLevel];
          [_countdown setContentView:v];
        }
      [_countdown setFrameOrigin:NSMakePoint (floor (NSMidX (s) - 60),
                                              floor (NSMidY (s) - 60))];
      _countdownLeft = (int) timer;
      [(SSCountdownView *) [_countdown contentView] setValue:_countdownLeft];
      [_countdown orderFrontRegardless];
      _countdownTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                         target:self
                                                       selector:@selector (countdownTick:)
                                                       userInfo:nil
                                                        repeats:YES];
      return;
    }
  [self performSelector:@selector (takeNow:) withObject:nil
             afterDelay:(fromToolbar || _overlay != nil ? SSSettleSeconds
                         : 0.0)];
}

- (void)failed:(NSString *)what error:(int)error
{
  NSString *why = error == EPERM
    ? @"Screen recording isn't allowed for Screenshot."
    : [NSString stringWithUTF8String:strerror (error)];

  NSLog (@"Screenshot: %@: %@", what, why);
  [NSApp activateIgnoringOtherApps:YES];
  NSRunAlertPanel (what, @"%@", @"OK", nil, nil, why);
}

- (void)takeNow:(id)unused
{
  SSTool tool = _countdownTool;
  NSRect rect = _countdownRect, s = [self screenFrame];
  BOOL pointer = SSBoolDefault (SSShowPointerKey, YES);
  NSBitmapImageRep *rep;
  NSString *folder, *path = nil, *detail;
  SSImage img;
  int cx = 0, cy = 0, cw, ch;
  CGFloat k;

  if (SSToolRecords (tool))
    {
      _busy = NO;
      [self startRecordingRect:(tool == SSToolRecordSelection ? rect
                                : NSZeroRect)];
      return;
    }
  if (SSWSCaptureImage (tool == SSToolWindow ? _countdownWindow : 0,
                        pointer && tool != SSToolWindow, &img) < 0)
    {
      int e = errno;

      _busy = NO;
      [self failed:@"The screenshot couldn't be taken" error:e];
      return;
    }
  cw = img.width;
  ch = img.height;
  if (tool == SSToolSelection && !NSIsEmptyRect (rect))
    {
      /* Points to the picture's pixels, from its top left. */
      k = img.width / NSWidth (s);
      cx = (int) floor (NSMinX (rect) * k);
      cy = (int) floor ((NSHeight (s) - NSMaxY (rect)) * k);
      cw = (int) ceil (NSWidth (rect) * k);
      ch = (int) ceil (NSHeight (rect) * k);
      cx = MAX (0, MIN (cx, img.width - 1));
      cy = MAX (0, MIN (cy, img.height - 1));
      cw = MIN (cw, img.width - cx);
      ch = MIN (ch, img.height - cy);
    }
  rep = SSImageRep (&img, cx, cy, cw, ch);
  SSImageFree (&img);
  _busy = NO;
  if (rep == nil)
    {
      [self failed:@"The screenshot couldn't be taken" error:ENOMEM];
      return;
    }
  folder = [self destinationFolder];
  if (folder == nil)
    {
      NSPasteboard *pb = [NSPasteboard generalPasteboard];

      [pb declareTypes:[NSArray arrayWithObject:NSTIFFPboardType] owner:nil];
      [pb setData:[rep TIFFRepresentation] forType:NSTIFFPboardType];
      detail = @"Copied to the clipboard";
    }
  else
    {
      NSData *png = [rep representationUsingType:NSPNGFileType properties:nil];

      path = SSFreePath (folder, [@"Screenshot " stringByAppendingString:SSStamp ()],
                         @"png");
      if (png == nil || ![png writeToFile:path atomically:YES])
        {
          [self failed:@"The screenshot couldn't be saved" error:errno];
          return;
        }
      detail = [NSString stringWithFormat:@"Saved to %@ · drag it into "
                         @"a document, or click to open",
                         [self nameOfFolder:folder]];
    }
  if (SSBoolDefault (SSShowThumbnailKey, YES))
    {
      NSImage *image = AUTORELEASE ([[NSImage alloc]
                                      initWithSize:NSMakeSize (cw, ch)]);

      [image addRepresentation:rep];
      [_thumbnail showImage:image path:path
                      title:(path != nil ? [path lastPathComponent]
                             : @"Screenshot")
                     detail:detail];
    }
  [self giveBackFocus];
  [self noteBusy];
}

/* ---- recording ---- */

- (void)receivedEvent:(void *)data
                 type:(RunLoopEventType)type
                extra:(void *)extra
              forMode:(NSString *)mode
{
  SSWSDispatch ();
}

- (NSArray *)watchedModes
{
  return [NSArray arrayWithObjects:NSDefaultRunLoopMode,
                  NSEventTrackingRunLoopMode, NSModalPanelRunLoopMode, nil];
}

- (void)watch:(BOOL)on
{
  NSRunLoop *loop = [NSRunLoop currentRunLoop];
  NSArray *modes = [self watchedModes];
  int fd = SSWSFileDescriptor ();
  NSUInteger i;

  if (on == _watching || (on && fd < 0))
    return;
  for (i = 0; i < [modes count]; i++)
    {
      if (on)
        [loop addEvent:(void *) (intptr_t) fd type:ET_RDESC
               watcher:(id<RunLoopEvents>) self
               forMode:[modes objectAtIndex:i]];
      else
        [loop removeEvent:(void *) (intptr_t) fd type:ET_RDESC
                  forMode:[modes objectAtIndex:i] all:YES];
    }
  _watching = on;
}

static void
SSGotFrame (const unsigned char *pixels, int stride, int width, int height,
            void *context)
{
  [(SSController *) context gotFrame:pixels stride:stride width:width
                              height:height];
}

static void
SSStreamEnded (int error, void *context)
{
  [(SSController *) context streamEnded:error];
}

- (void)postRecordingState
{
  NSMutableDictionary *info = [NSMutableDictionary dictionary];
  BOOL recording = _recorder != NULL;

  [info setObject:[NSNumber numberWithBool:recording] forKey:@"Recording"];
  if (recording && _recordStarted != nil)
    [info setObject:[NSNumber numberWithDouble:
                                [_recordStarted timeIntervalSince1970]]
             forKey:@"Started"];
  if (_recordPath != nil)
    [info setObject:_recordPath forKey:@"Path"];
  [[NSDistributedNotificationCenter defaultCenter]
    postNotificationName:SSRecordingNotification object:nil userInfo:info
      deliverImmediately:YES];
}

- (void)startRecordingRect:(NSRect)rect
{
  _recordRect = rect;
  if (SSWSStreamStart (SSBoolDefault (SSShowPointerKey, YES), SSRecorderFPS,
                       SSGotFrame, SSStreamEnded, self) < 0)
    {
      [self failed:@"The recording couldn't start" error:errno];
      return;
    }
  _streaming = YES;
  [self watch:YES];
  [self giveBackFocus];
}

/* The first frame says how big the screen's pixels are: then the
   movie can start. */
- (BOOL)startRecorderWidth:(int)width height:(int)height
{
  NSRect s = [self screenFrame];
  CGFloat k = width / NSWidth (s);
  NSString *folder, *mic, *log;
  char error[256];

  if (NSIsEmptyRect (_recordRect))
    {
      _cropX = _cropY = 0;
      _cropWidth = width;
      _cropHeight = height;
    }
  else
    {
      _cropX = (int) floor (NSMinX (_recordRect) * k);
      _cropY = (int) floor ((NSHeight (s) - NSMaxY (_recordRect)) * k);
      _cropWidth = (int) floor (NSWidth (_recordRect) * k);
      _cropHeight = (int) floor (NSHeight (_recordRect) * k);
      _cropX = MAX (0, MIN (_cropX, width - 2));
      _cropY = MAX (0, MIN (_cropY, height - 2));
      _cropWidth = MIN (_cropWidth, width - _cropX);
      _cropHeight = MIN (_cropHeight, height - _cropY);
    }
  /* yuv420p wants both even. */
  _cropWidth &= ~1;
  _cropHeight &= ~1;
  folder = [self destinationFolder];
  if (folder == nil)		/* a movie doesn't go to the clipboard */
    {
      _toClipboard = NO;
      folder = [NSHomeDirectory () stringByAppendingPathComponent:@"Desktop"];
    }
  ASSIGN (_recordPath, SSFreePath (folder,
                                   [@"Screen Recording "
                                     stringByAppendingString:SSStamp ()],
                                   @"mov"));
  mic = SSUserDefault (SSMicrophoneKey);
  if ([mic length] == 0
      || ![[NSFileManager defaultManager] fileExistsAtPath:mic])
    mic = nil;
  log = [NSHomeDirectory () stringByAppendingPathComponent:
                              @"Library/Logs/Screenshot.log"];
  [[NSFileManager defaultManager]
    createDirectoryAtPath:[log stringByDeletingLastPathComponent]
    withIntermediateDirectories:YES attributes:nil error:NULL];
  _recorder = SSRecorderStart ([_recordPath fileSystemRepresentation],
                               _cropWidth, _cropHeight,
                               mic != nil ? [mic fileSystemRepresentation]
                               : NULL,
                               [log fileSystemRepresentation],
                               error, sizeof (error));
  if (_recorder == NULL)
    {
      NSString *why = [NSString stringWithUTF8String:error];

      DESTROY (_recordPath);
      NSRunAlertPanel (@"The recording couldn't start", @"%@", @"OK", nil,
                       nil, why);
      return NO;
    }
  ASSIGN (_recordStarted, [NSDate date]);
  [self postRecordingState];
  return YES;
}

- (void)gotFrame:(const unsigned char *)pixels stride:(int)stride
           width:(int)width height:(int)height
{
  if (_recorder == NULL)
    {
      if (![self startRecorderWidth:width height:height])
        {
          [self watch:NO];
          SSWSStreamStop ();
          _streaming = NO;
          return;
        }
    }
  if (_cropX + _cropWidth > width || _cropY + _cropHeight > height)
    return;			/* the screen changed size: skip */
  SSRecorderFrame (_recorder, pixels, stride, _cropX, _cropY);
}

- (void)streamEnded:(int)error
{
  /* Stopped from elsewhere (wsctl capture stop, WindowServer went):
     keep what was recorded. */
  _streaming = NO;
  [self performSelector:@selector (stopRecording) withObject:nil
             afterDelay:0];
}

- (void)finishRecording:(NSDictionary *)job
{
  CREATE_AUTORELEASE_POOL (pool);
  SSRecorder *recorder = [[job objectForKey:@"Recorder"] pointerValue];
  char error[256] = "";
  int r = SSRecorderFinish (recorder, error, sizeof (error));
  NSMutableDictionary *result =
    [NSMutableDictionary dictionaryWithDictionary:job];

  [result removeObjectForKey:@"Recorder"];
  if (r < 0)
    [result setObject:[NSString stringWithUTF8String:error] forKey:@"Error"];
  [self performSelectorOnMainThread:@selector (recordingFinished:)
                         withObject:result waitUntilDone:NO];
  RELEASE (pool);
}

- (void)recordingFinished:(NSDictionary *)result
{
  NSString *path = [result objectForKey:@"Path"];
  NSString *error = [result objectForKey:@"Error"];

  _busy = NO;
  [self noteBusy];
  if (error != nil)
    {
      [NSApp activateIgnoringOtherApps:YES];
      NSRunAlertPanel (@"The recording couldn't be saved", @"%@", @"OK", nil,
                       nil, error);
      return;
    }
  /* Opened where .mov files open: Video, once it's there. */
  if (path != nil && ![[NSWorkspace sharedWorkspace] openFile:path])
    NSLog (@"Screenshot: saved %@ (nothing opens .mov files yet)", path);
}

- (void)stopRecording
{
  SSRecorder *recorder = _recorder;

  [self watch:NO];
  if (_streaming)
    SSWSStreamStop ();
  _streaming = NO;
  _recorder = NULL;
  if (recorder == NULL)
    return;
  _busy = YES;
  [self postRecordingState];
  [NSThread detachNewThreadSelector:@selector (finishRecording:)
                           toTarget:self
                         withObject:[NSDictionary dictionaryWithObjectsAndKeys:
                                                    [NSValue valueWithPointer:recorder],
                                                  @"Recorder",
                                                  _recordPath, @"Path", nil]];
  DESTROY (_recordPath);
  DESTROY (_recordStarted);
}

@end
