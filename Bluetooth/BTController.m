/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "BTController.h"
#import "BTDevice.h"
#import <GNUstepBase/GNUstep.h>

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <string.h>
#include <unistd.h>

/* Layout, in points. */
#define BTMargin 20.0
#define BTWindowWidth 600.0
#define BTIconSize 48.0
#define BTButtonHeight 26.0
#define BTButtonGap 8.0
#define BTRowGap 10.0
#define BTTableHeight 118.0
#define BTLabelWidth 80.0

/* Timing, in seconds. */
#define BTScanSeconds 10	/* each search */
#define BTDiscoverableSeconds 60	/* each timed discoverable ... */
#define BTDiscoverableRearm 30.0	/* ... renewed this often */
#define BTHeartbeat 5.0		/* read everything again anyway */
#define BTReloadDelay 0.15	/* gather a burst of notifications */
#define BTNearbyMaxAge 300	/* seen this long ago at most */

/* Written to the wake pipe by SIGTERM; bluetoothd's wakes are 1. */
#define BTQuitByte 'q'
static int BTQuitFD = -1;

static void
BTTerminated (int sig)
{
  char byte = BTQuitByte;

  (void) sig;
  (void) write (BTQuitFD, &byte, 1);
}

/* Tags of the audio route popup's items. */
#define BTRouteItemStereo 0
#define BTRouteItemHeadset 1

/* A view laid out from the top down. */
@interface BTFlippedView : NSView
@end

@implementation BTFlippedView
- (BOOL)isFlipped
{
  return YES;
}
@end

static NSTextField *
BTLabel (NSRect frame, NSString *text, NSFont *font)
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

static NSFont *
BTSmallFont (void)
{
  return [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
}

static NSButton *
BTButton (NSRect frame, NSString *title, id target, SEL action)
{
  NSButton *button = AUTORELEASE ([[NSButton alloc] initWithFrame:frame]);

  [button setTitle:title];
  [button setTarget:target];
  [button setAction:action];
  return button;
}

static NSButton *
BTSwitch (NSRect frame, NSString *title, id target, SEL action)
{
  NSButton *button = BTButton (frame, title, target, action);

  [button setButtonType:NSSwitchButton];
  return button;
}

/* A NeXT-style group: a titled box around inner, at the given width. */
static NSBox *
BTGroup (NSString *title, NSView *inner, CGFloat width)
{
  NSBox *box = AUTORELEASE ([[NSBox alloc]
                              initWithFrame:NSMakeRect (0, 0, width, 100)]);

  [box setTitle:title];
  [box setTitlePosition:NSAtTop];
  [box setBorderType:NSGrooveBorder];
  [box setContentViewMargins:NSMakeSize (12, 10)];
  [box setContentView:inner];
  [box sizeToFit];
  return box;
}

/* The inside width of a group as wide as the window's content. */
static CGFloat
BTGroupInnerWidth (void)
{
  NSBox *box = AUTORELEASE ([[NSBox alloc]
                              initWithFrame:NSMakeRect (0, 0, 400, 100)]);
  [box setTitle:@"X"];
  [box setTitlePosition:NSAtTop];
  [box setBorderType:NSGrooveBorder];
  [box setContentViewMargins:NSMakeSize (12, 10)];
  return BTWindowWidth - 2 * BTMargin
    - (400 - NSWidth ([[box contentView] frame]));
}

/* A list in a scroll view: columns are {identifier, title, width}. */
static NSTableView *
BTTable (NSView *parent, NSRect frame, NSArray *columns, id owner)
{
  NSScrollView *scroll = AUTORELEASE ([[NSScrollView alloc] initWithFrame:frame]);
  NSTableView *table;
  NSUInteger i;

  [scroll setHasVerticalScroller:YES];
  [scroll setHasHorizontalScroller:NO];
  [scroll setBorderType:NSBezelBorder];
  table = AUTORELEASE ([[NSTableView alloc]
                         initWithFrame:NSMakeRect (0, 0, NSWidth (frame),
                                                   NSHeight (frame))]);
  for (i = 0; i + 2 < [columns count]; i += 3)
    {
      NSTableColumn *column = AUTORELEASE ([[NSTableColumn alloc]
          initWithIdentifier:[columns objectAtIndex:i]]);

      [[column headerCell] setStringValue:[columns objectAtIndex:i + 1]];
      [column setWidth:[[columns objectAtIndex:i + 2] floatValue]];
      [column setEditable:NO];
      [table addTableColumn:column];
    }
  [table setAllowsEmptySelection:YES];
  [table setAllowsMultipleSelection:NO];
  [table setAllowsColumnReordering:NO];
  [table setDataSource:owner];
  [table setDelegate:owner];
  [table setTarget:owner];
  [scroll setDocumentView:table];
  [parent addSubview:scroll];
  return table;
}

/* What a bt_status_t means, as bluetooth(8) says it. */
static NSString *
BTStatusText (int st)
{
  switch (st)
    {
    case BTStatusRPCFailed: return @"bluetoothd isn't answering";
    case 1: return @"the request wasn't valid";
    case 2: return @"there's no Bluetooth controller";
    case 5: return @"the device or controller can't do that";
    case BTStatusPoweredOff: return @"Bluetooth is off";
    case 7: return @"Bluetooth is busy; try again";
    case 8: return @"the device isn't paired";
    case BTStatusNotConnected: return @"the device isn't connected";
    case 10: return @"the device isn't there";
    case 11: return @"pairing failed";
    case 12: return @"the device didn't answer in time";
    case 13: return @"the device refused";
    case BTStatusNoPrompt: return @"there was nothing to answer";
    case 15: return @"the pairing store couldn't be updated";
    default: return @"something went wrong in bluetoothd";
    }
}

/* Name order, the unnamed last, so rows don't jump as signals change. */
static NSInteger
BTCompareNearby (id a, id b, void *context)
{
  if ([a hasName] != [b hasName])
    return [a hasName] ? NSOrderedAscending : NSOrderedDescending;
  return [[a displayName] caseInsensitiveCompare:[b displayName]];
}

@interface BTController (Private)
- (void)buildMenu;
- (void)buildWindow;
- (NSView *)powerSection:(CGFloat)width;
- (NSView *)myDevicesSection:(CGFloat)width;
- (NSView *)nearbySection:(CGFloat)width;
- (void)wake:(NSNotification *)note;
- (void)scheduleReload;
- (void)beat:(NSTimer *)timer;
- (void)reload;
- (NSArray *)readPaired;
- (NSArray *)readNearby;
- (void)showPower;
- (void)showDevice;
- (void)showNearby;
- (void)updateDiscoverable;
- (void)endDiscoverable;
- (void)checkPrompts;
- (BTDevice *)selectedPaired;
- (BTDevice *)selectedNearby;
- (void)reloadTable:(NSTableView *)table
          withState:(NSString *)state
              shown:(NSString **)shown
            devices:(NSArray *)devices
           selected:(BTDevice *)selected;
- (BTDevice *)deviceWithAddress:(NSString *)address;
- (BOOL)report:(int)st what:(NSString *)what;
- (void)togglePower:(id)sender;
- (void)connectDevice:(id)sender;
- (void)disconnectDevice:(id)sender;
- (void)removeDevice:(id)sender;
- (void)pairedDoubleClicked:(id)sender;
- (void)toggleAutoconnect:(id)sender;
- (void)toggleAudio:(id)sender;
- (void)chooseRoute:(id)sender;
- (void)search:(id)sender;
- (void)pairDevice:(id)sender;
@end

@implementation BTController

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [NSObject cancelPreviousPerformRequestsWithTarget:self];
  [heartbeat invalidate];
  RELEASE (heartbeat);
  RELEASE (pairingPanel);
  RELEASE (wakeHandle);
  RELEASE (window);
  RELEASE (pairedDevices);
  RELEASE (nearbyDevices);
  RELEASE (shownPaired);
  RELEASE (shownNearby);
  RELEASE (dismissedPrompts);
  [super dealloc];
}

- (void)applicationDidFinishLaunching:(NSNotification *)note
{
  NSImage *icon = [NSImage imageNamed:@"Bluetooth.png"];
  NSArray *modes = [NSArray arrayWithObjects:NSDefaultRunLoopMode,
                            NSEventTrackingRunLoopMode,
                            NSModalPanelRunLoopMode, nil];

  if (icon != nil)
    [NSApp setApplicationIconImage:icon];
  [self buildMenu];
  dismissedPrompts = [[NSMutableSet alloc] init];

  /* bluetoothd's notifications and State:/Bluetooth changes come in on
     dispatch queues, as a byte on this pipe each. */
  wakeFDs[0] = wakeFDs[1] = -1;
  if (pipe (wakeFDs) == 0)
    {
      int i;

      for (i = 0; i < 2; i++)
        {
          (void) fcntl (wakeFDs[i], F_SETFL,
                        fcntl (wakeFDs[i], F_GETFL) | O_NONBLOCK);
          (void) fcntl (wakeFDs[i], F_SETFD, FD_CLOEXEC);
        }
      wakeHandle = [[NSFileHandle alloc] initWithFileDescriptor:wakeFDs[0]
                                                 closeOnDealloc:NO];
      [[NSNotificationCenter defaultCenter]
          addObserver:self
             selector:@selector (wake:)
                 name:NSFileHandleDataAvailableNotification
               object:wakeHandle];
      [wakeHandle waitForDataInBackgroundAndNotifyForModes:modes];
      /* Killed (a logout, kill(1)): quit the ordinary way, so a timed
         discoverable ends and a pairing prompt gets its no. */
      BTQuitFD = wakeFDs[1];
      signal (SIGTERM, BTTerminated);
    }
  else
    NSLog (@"Bluetooth: no pipe for notifications: %s", strerror (errno));
  client = BTClientOpen (wakeFDs[1]);
  pairingPanel = [[BTPairingPanel alloc] initWithClient:client delegate:self];

  [self buildWindow];
  [self reload];
  [window makeKeyAndOrderFront:self];

  /* A search to start with, as macOS does when the window opens. */
  if (powered)
    [self search:nil];

  heartbeat = RETAIN ([NSTimer timerWithTimeInterval:BTHeartbeat
                                              target:self
                                            selector:@selector (beat:)
                                            userInfo:nil
                                             repeats:YES]);
  [[NSRunLoop currentRunLoop] addTimer:heartbeat forMode:NSDefaultRunLoopMode];
  [[NSRunLoop currentRunLoop] addTimer:heartbeat
                               forMode:NSModalPanelRunLoopMode];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app
{
  return YES;
}

- (void)applicationWillTerminate:(NSNotification *)note
{
  /* Quitting with a question up says no to the device. */
  if ([pairingPanel isVisible])
    (void) BTClientPairConfirm (client, [[pairingPanel address] UTF8String],
                                0, 0, NULL);
  [pairingPanel close];
  [self endDiscoverable];
  [heartbeat invalidate];
  BTClientClose (client);
  client = NULL;
}

/* ---- the lists ---- */

- (NSInteger)numberOfRowsInTableView:(NSTableView *)table
{
  return (NSInteger) [(table == pairedTable ? pairedDevices : nearbyDevices)
                       count];
}

- (id)tableView:(NSTableView *)table
    objectValueForTableColumn:(NSTableColumn *)column
                          row:(NSInteger)row
{
  NSArray *devices = table == pairedTable ? pairedDevices : nearbyDevices;
  NSString *which = [column identifier];
  BTDevice *device;

  if (row < 0 || (NSUInteger) row >= [devices count])
    return nil;
  device = [devices objectAtIndex:row];
  if ([which isEqual:@"name"])
    return [device displayName];
  if ([which isEqual:@"kind"])
    return [device kind];
  if ([which isEqual:@"status"])
    return [device statusText];
  if ([which isEqual:@"signal"])
    return [device signalText];
  return nil;
}

- (BOOL)tableView:(NSTableView *)table shouldEditTableColumn:(NSTableColumn *)c
              row:(NSInteger)row
{
  return NO;
}

- (void)tableViewSelectionDidChange:(NSNotification *)note
{
  if ([note object] == pairedTable)
    [self showDevice];
  else
    [self showNearby];
}

/* ---- pairing ---- */

- (void)pairingPanel:(BTPairingPanel *)panel didPairWith:(NSString *)address
{
  [self reload];
  [self showNearby];
}

- (void)pairingPanel:(BTPairingPanel *)panel
     didFailWithName:(NSString *)name
              status:(int)st
{
  [self reload];
  [self showNearby];
  NSRunAlertPanel (@"Bluetooth",
                   [NSString stringWithFormat:@"Couldn't pair with “%@”: %@.",
                             name, BTStatusText (st)],
                   @"OK", nil, nil);
}

- (void)pairingPanelDidCancel:(BTPairingPanel *)panel
{
  [self reload];
  [self showNearby];
}

@end

@implementation BTController (Private)

- (void)buildMenu
{
  NSMenu *menu = AUTORELEASE ([[NSMenu alloc] initWithTitle:@"Bluetooth"]);
  NSMenu *windows = AUTORELEASE ([[NSMenu alloc] initWithTitle:@"Window"]);
  id<NSMenuItem> item;

  [menu addItemWithTitle:@"About Bluetooth"
                  action:@selector (orderFrontStandardAboutPanel:)
           keyEquivalent:@""];
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
}

/* The window is built once; reloads only change what its controls
   show, so a selection or a scrolled list stays put. */
- (void)buildWindow
{
  BTFlippedView *content;
  NSArray *sections;
  CGFloat inner = BTGroupInnerWidth ();
  CGFloat width = BTWindowWidth - 2 * BTMargin;
  CGFloat height, y;
  NSUInteger i;

  sections = [NSArray arrayWithObjects:
                        BTGroup (@"Bluetooth", [self powerSection:inner], width),
                        BTGroup (@"My Devices", [self myDevicesSection:inner],
                                 width),
                        BTGroup (@"Nearby Devices", [self nearbySection:inner],
                                 width),
                        nil];
  height = BTMargin;
  for (i = 0; i < [sections count]; i++)
    height += NSHeight ([[sections objectAtIndex:i] frame]) + BTRowGap;
  height += BTMargin - BTRowGap;

  window = [[NSWindow alloc]
      initWithContentRect:NSMakeRect (200, 200, BTWindowWidth, height)
                styleMask:NSTitledWindowMask | NSClosableWindowMask
                          | NSMiniaturizableWindowMask
                  backing:NSBackingStoreBuffered
                    defer:NO];
  [window setTitle:@"Bluetooth"];
  [window setReleasedWhenClosed:NO];
  [window setFrameAutosaveName:@"Bluetooth"];

  content = AUTORELEASE ([[BTFlippedView alloc]
                           initWithFrame:NSMakeRect (0, 0, BTWindowWidth,
                                                     height)]);
  y = BTMargin;
  for (i = 0; i < [sections count]; i++)
    {
      NSView *section = [sections objectAtIndex:i];
      [section setFrameOrigin:NSMakePoint (BTMargin, y)];
      [content addSubview:section];
      y += NSHeight ([section frame]) + BTRowGap;
    }
  [window setContentView:content];
}

- (NSView *)powerSection:(CGFloat)width
{
  BTFlippedView *view = AUTORELEASE ([[BTFlippedView alloc]
                                       initWithFrame:NSMakeRect (0, 0, width,
                                                                 BTIconSize)]);
  NSImageView *icon;
  CGFloat buttonW = 170, textX = BTIconSize + 12;
  CGFloat textW = width - textX - buttonW - 12;

  icon = AUTORELEASE ([[NSImageView alloc]
                        initWithFrame:NSMakeRect (0, 0, BTIconSize, BTIconSize)]);
  [icon setImage:[NSApp applicationIconImage]];
  [icon setImageScaling:NSScaleProportionally];
  [icon setEditable:NO];
  [view addSubview:icon];

  powerTitle = BTLabel (NSMakeRect (textX, 0, textW, 20), @"Bluetooth",
                        [NSFont boldSystemFontOfSize:14]);
  [view addSubview:powerTitle];
  powerDetail = BTLabel (NSMakeRect (textX, 20, textW, 30), @"",
                         BTSmallFont ());
  [[powerDetail cell] setWraps:YES];
  [view addSubview:powerDetail];

  powerButton = BTButton (NSMakeRect (width - buttonW, 10, buttonW,
                                      BTButtonHeight),
                          @"Turn Bluetooth Off", self,
                          @selector (togglePower:));
  [view addSubview:powerButton];
  return view;
}

- (NSView *)myDevicesSection:(CGFloat)width
{
  BTFlippedView *view = AUTORELEASE ([[BTFlippedView alloc]
                                       initWithFrame:NSMakeRect (0, 0, width, 10)]);
  CGFloat y = 0, x, kindW = 140, statusW = 170;

  pairedTable = BTTable (view, NSMakeRect (0, y, width, BTTableHeight),
                         [NSArray arrayWithObjects:
                                    @"name", @"Device",
                                    [NSNumber numberWithFloat:
                                                width - kindW - statusW - 24],
                                    @"kind", @"Kind",
                                    [NSNumber numberWithFloat:kindW],
                                    @"status", @"Status",
                                    [NSNumber numberWithFloat:statusW], nil],
                         self);
  [pairedTable setDoubleAction:@selector (pairedDoubleClicked:)];
  y += BTTableHeight + 6;

  deviceDetail = BTLabel (NSMakeRect (0, y, width, 16), @"", BTSmallFont ());
  [view addSubview:deviceDetail];
  y += 16 + BTRowGap;

  /* Connect, Disconnect, Remove; Connect automatically on their right. */
  connectButton = BTButton (NSMakeRect (0, y, 100, BTButtonHeight),
                            @"Connect", self, @selector (connectDevice:));
  [view addSubview:connectButton];
  x = 100 + BTButtonGap;
  disconnectButton = BTButton (NSMakeRect (x, y, 100, BTButtonHeight),
                               @"Disconnect", self,
                               @selector (disconnectDevice:));
  [view addSubview:disconnectButton];
  x += 100 + BTButtonGap;
  removeButton = BTButton (NSMakeRect (x, y, 100, BTButtonHeight),
                           @"Remove...", self, @selector (removeDevice:));
  [view addSubview:removeButton];
  autoconnectSwitch = BTSwitch (NSMakeRect (width - 190, y + 2, 190, 22),
                                @"Connect automatically", self,
                                @selector (toggleAutoconnect:));
  [view addSubview:autoconnectSwitch];
  y += BTButtonHeight + BTRowGap;

  /* A headset's audio. */
  audioSwitch = BTSwitch (NSMakeRect (0, y + 1, 210, 22),
                          @"Play sound on this device", self,
                          @selector (toggleAudio:));
  [view addSubview:audioSwitch];
  routeLabel = BTLabel (NSMakeRect (width - 220 - BTLabelWidth - 8, y + 3,
                                    BTLabelWidth, 20),
                        @"Use it as:", nil);
  [routeLabel setAlignment:NSRightTextAlignment];
  [view addSubview:routeLabel];
  routePopup = AUTORELEASE ([[NSPopUpButton alloc]
                              initWithFrame:NSMakeRect (width - 220, y, 220, 24)
                                  pullsDown:NO]);
  [routePopup addItemWithTitle:@"Stereo headphones"];
  [[routePopup lastItem] setTag:BTRouteItemStereo];
  [routePopup addItemWithTitle:@"Headset with microphone"];
  [[routePopup lastItem] setTag:BTRouteItemHeadset];
  [routePopup setTarget:self];
  [routePopup setAction:@selector (chooseRoute:)];
  [view addSubview:routePopup];
  y += 24;

  [view setFrameSize:NSMakeSize (width, y)];
  return view;
}

- (NSView *)nearbySection:(CGFloat)width
{
  BTFlippedView *view = AUTORELEASE ([[BTFlippedView alloc]
                                       initWithFrame:NSMakeRect (0, 0, width, 10)]);
  CGFloat y = 0, kindW = 140, signalW = 90;

  nearbyTable = BTTable (view, NSMakeRect (0, y, width, BTTableHeight),
                         [NSArray arrayWithObjects:
                                    @"name", @"Device",
                                    [NSNumber numberWithFloat:
                                                width - kindW - signalW - 24],
                                    @"kind", @"Kind",
                                    [NSNumber numberWithFloat:kindW],
                                    @"signal", @"Signal",
                                    [NSNumber numberWithFloat:signalW], nil],
                         self);
  [nearbyTable setDoubleAction:@selector (pairDevice:)];
  y += BTTableHeight + BTRowGap;

  searchSpinner = AUTORELEASE ([[NSProgressIndicator alloc]
                                 initWithFrame:NSMakeRect (0, y + 5, 16, 16)]);
  [searchSpinner setStyle:NSProgressIndicatorSpinningStyle];
  [searchSpinner setIndeterminate:YES];
  [searchSpinner setDisplayedWhenStopped:NO];
  [view addSubview:searchSpinner];
  searchStatus = BTLabel (NSMakeRect (24, y + 4, width - 24 - 2 * 110 - 16, 20),
                          @"", BTSmallFont ());
  [view addSubview:searchStatus];
  pairButton = BTButton (NSMakeRect (width - 100, y, 100, BTButtonHeight),
                         @"Pair...", self, @selector (pairDevice:));
  [view addSubview:pairButton];
  searchButton = BTButton (NSMakeRect (width - 100 - BTButtonGap - 120, y, 120,
                                       BTButtonHeight),
                           @"Search Again", self, @selector (search:));
  [view addSubview:searchButton];
  y += BTButtonHeight;

  [view setFrameSize:NSMakeSize (width, y)];
  return view;
}

/* ---- live updates ---- */

- (void)wake:(NSNotification *)note
{
  char buffer[256];
  ssize_t n;
  BOOL quit = NO;

  while ((n = read (wakeFDs[0], buffer, sizeof (buffer))) > 0)
    if (memchr (buffer, BTQuitByte, (size_t) n) != NULL)
      quit = YES;
  if (quit)
    {
      [NSApp terminate:self];
      return;
    }
  [wakeHandle waitForDataInBackgroundAndNotifyForModes:
                [NSArray arrayWithObjects:NSDefaultRunLoopMode,
                         NSEventTrackingRunLoopMode, NSModalPanelRunLoopMode,
                         nil]];
  [pairingPanel update];
  [self scheduleReload];
}

/* A scan posts many notifications: read once they settle. */
- (void)scheduleReload
{
  [NSObject cancelPreviousPerformRequestsWithTarget:self
                                           selector:@selector (reload)
                                             object:nil];
  [self performSelector:@selector (reload)
             withObject:nil
             afterDelay:BTReloadDelay
                inModes:[NSArray arrayWithObjects:NSDefaultRunLoopMode,
                                 NSModalPanelRunLoopMode, nil]];
}

- (void)beat:(NSTimer *)timer
{
  [self reload];
}

/* Read everything bluetoothd says, and show it. */
- (void)reload
{
  BTDevice *selected;

  if (client == NULL)
    return;
  reachable = BTClientGetStatus (client, &status) == BTStatusSuccess;
  haveAdapter = reachable && status.adapters > 0
    && BTClientGetAdapter (client, &adapter) == BTStatusSuccess;
  powered = haveAdapter && adapter.powered;
  scanning = NO;

  selected = RETAIN ([self selectedPaired]);
  ASSIGN (pairedDevices, reachable ? [self readPaired] : [NSArray array]);
  [self reloadTable:pairedTable
          withState:[[pairedDevices valueForKey:@"stateDescription"]
                      componentsJoinedByString:@"\n"]
              shown:&shownPaired
            devices:pairedDevices
           selected:selected];
  RELEASE (selected);

  selected = RETAIN ([self selectedNearby]);
  ASSIGN (nearbyDevices, powered ? [self readNearby] : [NSArray array]);
  [self reloadTable:nearbyTable
          withState:[[nearbyDevices valueForKey:@"stateDescription"]
                      componentsJoinedByString:@"\n"]
              shown:&shownNearby
            devices:nearbyDevices
           selected:selected];
  RELEASE (selected);

  /* Bluetooth just came on: look around. */
  if (powered && !wasPowered && heartbeat != nil)
    [self search:nil];
  wasPowered = powered;

  [self showPower];
  [self showDevice];
  [self showNearby];
  [self updateDiscoverable];
  [self checkPrompts];
}

- (NSArray *)readPaired
{
  NSMutableArray *list = [NSMutableArray array];
  NSMutableDictionary *audio = [NSMutableDictionary dictionary];
  NSEnumerator *e;
  BTDevice *device;
  int count = 0, i;

  if (BTClientPairedCount (client, &count) != BTStatusSuccess)
    return list;
  for (i = 0; i < count; i++)
    {
      BTClientDevice info;

      if (BTClientPairedEntry (client, i, &info) == BTStatusSuccess)
        [list addObject:[BTDevice deviceWithInfo:&info]];
    }

  /* The devices with audio now, and how. */
  if (BTClientAudioCount (client, &count) == BTStatusSuccess)
    for (i = 0; i < count; i++)
      {
        BTClientAudio a;

        if (BTClientAudioEntry (client, i, &a) != BTStatusSuccess)
          break;
        if (a.role == 1)	/* we play to it */
          [audio setObject:[NSNumber numberWithInt:a.route]
                    forKey:[[NSString stringWithUTF8String:a.address]
                             uppercaseString]];
      }
  e = [list objectEnumerator];
  while ((device = [e nextObject]) != nil)
    {
      NSNumber *route = [audio objectForKey:[[device address] uppercaseString]];
      BTClientHandsFree h;

      [device setPlaying:route != nil route:[route intValue]];
      if ([device isConnected] && [device isHeadset]
          && BTClientGetHandsFree (client, [[device address] UTF8String], &h)
             == BTStatusSuccess)
        [device setHandsFree:h.connected != 0 microphone:h.microphone != 0
                     battery:h.battery];
    }
  return list;
}

- (NSArray *)readNearby
{
  NSMutableArray *list = [NSMutableArray array];
  BTDevice *device;
  int count = 0, i, scan = 0;

  if (BTClientScanCount (client, &count, &scan) != BTStatusSuccess)
    return list;
  scanning = scan != 0;
  for (i = 0; i < count; i++)
    {
      BTClientDevice info;

      if (BTClientScanEntry (client, i, &info) != BTStatusSuccess)
        continue;
      if (info.paired || info.age > BTNearbyMaxAge)
        continue;
      device = [BTDevice deviceWithInfo:&info];
      /* As on macOS, not the nameless advertisers around (beacons,
         phones' LE chatter): a device with no name shows only if it
         says what it is. */
      if (![device hasName] && [[device kind] isEqual:@"Device"])
        continue;
      [list addObject:device];
    }
  [list sortUsingFunction:BTCompareNearby context:NULL];
  return list;
}

/* Reload a list if what it shows changed, keeping the selected device
   selected. */
- (void)reloadTable:(NSTableView *)table
          withState:(NSString *)state
              shown:(NSString **)shown
            devices:(NSArray *)devices
           selected:(BTDevice *)selected
{
  NSUInteger i;

  if ([state isEqual:*shown])
    return;
  ASSIGN (*shown, state);
  [table reloadData];
  [table deselectAll:self];
  for (i = 0; selected != nil && i < [devices count]; i++)
    if ([[[devices objectAtIndex:i] address]
          isEqual:[selected address]])
      {
        [table selectRow:(NSInteger) i byExtendingSelection:NO];
        break;
      }
}

- (void)showPower
{
  NSString *title, *detail, *name;
  BOOL canToggle = haveAdapter && (adapter.state == BTAdapterOn
                                   || adapter.state == BTAdapterOff);

  name = adapter.name[0] != '\0'
    ? [NSString stringWithUTF8String:adapter.name] : nil;
  if (!reachable)
    {
      title = @"Bluetooth: Unavailable";
      detail = @"bluetoothd isn't running. Bluetooth will connect when "
               @"it starts.";
    }
  else if (!haveAdapter)
    {
      title = @"Bluetooth: No Controller";
      detail = @"This computer has no Bluetooth controller that NextBSD "
               @"can use.";
    }
  else if (adapter.state == BTAdapterFirmware
           || adapter.state == BTAdapterInitializing
           || adapter.state == BTAdapterArrived)
    {
      title = @"Bluetooth: Starting";
      detail = @"The Bluetooth controller is starting up.";
    }
  else if (adapter.state == BTAdapterError)
    {
      title = @"Bluetooth: Not Working";
      detail = @"The Bluetooth controller failed to start.";
    }
  else if (powered)
    {
      title = @"Bluetooth: On";
      if (adapter.discoverable && name != nil)
        detail = [NSString stringWithFormat:status.discoverable
                           ? @"Discoverable as “%@”."
                           : @"Discoverable as “%@” while this "
                             @"window is open.", name];
      else if (name != nil)
        detail = [NSString stringWithFormat:@"Known as “%@”.", name];
      else
        detail = @"";
      if (adapter.address[0] != '\0')
        detail = [detail stringByAppendingFormat:@"\nAddress: %s",
                         adapter.address];
    }
  else
    {
      title = @"Bluetooth: Off";
      detail = @"Turn Bluetooth on to use your devices and find new ones.";
    }
  [powerTitle setStringValue:title];
  [powerDetail setStringValue:detail];
  [powerButton setTitle:powered ? @"Turn Bluetooth Off" : @"Turn Bluetooth On"];
  [powerButton setEnabled:canToggle];
}

/* The buttons and switches for the selected paired device. */
- (void)showDevice
{
  BTDevice *device = [self selectedPaired];
  BOOL headset = device != nil && [device isHeadset];
  BOOL busy = device != nil && ([device linkState] == BTDeviceConnecting
                                || [device linkState] == BTDevicePairing);

  [connectButton setEnabled:powered && device != nil && ![device isConnected]
                 && !busy];
  [disconnectButton setEnabled:powered && device != nil
                    && ([device isConnected] || busy)];
  [removeButton setEnabled:reachable && device != nil];
  [autoconnectSwitch setEnabled:reachable && device != nil];
  [autoconnectSwitch setState:(device != nil && [device autoconnect])
                     ? NSOnState : NSOffState];
  [audioSwitch setEnabled:reachable && headset];
  [audioSwitch setState:(headset && [device audioEnabled])
               ? NSOnState : NSOffState];
  /* Headset with its microphone needs the hands-free channel up. */
  [routePopup setEnabled:powered && headset && [device isConnected]
              && [device hasHandsFree] && [device audioEnabled]];
  [routePopup selectItemWithTag:(headset && [device route] == BTRouteHFP)
              ? BTRouteItemHeadset : BTRouteItemStereo];
  [routeLabel setTextColor:[routePopup isEnabled]
              ? [NSColor controlTextColor] : [NSColor disabledControlTextColor]];

  if (device != nil)
    [deviceDetail setStringValue:[device detailText]];
  else if ([pairedDevices count] == 0)
    [deviceDetail setStringValue:
        @"No devices are paired. Pair one from Nearby Devices below."];
  else
    [deviceDetail setStringValue:
        @"Choose a device to connect, disconnect or remove it."];
}

- (void)showNearby
{
  NSString *text;
  NSUInteger count = [nearbyDevices count];

  if (!reachable || !haveAdapter)
    text = @"";
  else if (!powered)
    text = @"Turn Bluetooth on to find devices.";
  else if (scanning)
    text = @"Searching...";
  else if (count == 0)
    text = @"No devices found. Make sure yours is in pairing mode.";
  else
    text = @"Put your device in pairing mode, choose it, and click Pair.";
  [searchStatus setStringValue:text];
  if (scanning && powered)
    [searchSpinner startAnimation:self];
  else
    [searchSpinner stopAnimation:self];
  [searchButton setEnabled:powered && !scanning];
  [pairButton setEnabled:powered && [self selectedNearby] != nil
              && ![pairingPanel isVisible]];
}

/* Discoverable while the window is open: a timed discoverable, renewed
   before it ends. bluetoothd ends it by itself if Bluetooth quits
   without saying so, and never persists it. Left alone when it's
   discoverable all the time anyway (DiscoverableState). */
- (void)updateDiscoverable
{
  NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];

  if (!powered || status.discoverable)
    {
      discoverableArmed = 0;
      return;
    }
  if (discoverableArmed != 0 && adapter.discoverable
      && now - discoverableArmed < BTDiscoverableRearm)
    return;
  if (BTClientSetDiscoverable (client, 1, BTDiscoverableSeconds)
      == BTStatusSuccess)
    {
      discoverableArmed = now;
      if (!adapter.discoverable)
        {
          adapter.discoverable = 1;
          [self showPower];
        }
    }
}

- (void)endDiscoverable
{
  BTClientStatus now;

  if (discoverableArmed == 0 || client == NULL)
    return;
  /* Off, and timed so it isn't persisted; unless it was made
     discoverable for good meanwhile. */
  if (BTClientGetStatus (client, &now) == BTStatusSuccess && !now.discoverable)
    (void) BTClientSetDiscoverable (client, 0, 1);
  discoverableArmed = 0;
}

/* A device asking to pair by itself (State:/Bluetooth/Pairing). */
- (void)checkPrompts
{
  char addresses[8][32];
  NSMutableSet *waiting = [NSMutableSet set];
  int n = BTClientWaitingPrompts (client, addresses, 8), i;

  for (i = 0; i < n; i++)
    [waiting addObject:[NSString stringWithUTF8String:addresses[i]]];
  /* A prompt answered elsewhere, or gone: ask again next time. */
  [dismissedPrompts intersectSet:waiting];
  if ([pairingPanel isVisible])
    return;
  for (i = 0; i < n; i++)
    {
      NSString *address = [NSString stringWithUTF8String:addresses[i]];
      BTDevice *device;

      if ([dismissedPrompts containsObject:address])
        continue;
      [dismissedPrompts addObject:address];	/* once per prompt */
      device = [self deviceWithAddress:address];
      [pairingPanel answerPromptFrom:address
                                name:(device != nil ? [device displayName]
                                                    : address)
                          overWindow:window];
      break;
    }
}

- (BTDevice *)selectedPaired
{
  NSInteger row = [pairedTable selectedRow];

  if (row < 0 || (NSUInteger) row >= [pairedDevices count])
    return nil;
  return [pairedDevices objectAtIndex:row];
}

- (BTDevice *)selectedNearby
{
  NSInteger row = [nearbyTable selectedRow];

  if (row < 0 || (NSUInteger) row >= [nearbyDevices count])
    return nil;
  return [nearbyDevices objectAtIndex:row];
}

- (BTDevice *)deviceWithAddress:(NSString *)address
{
  NSEnumerator *e;
  BTDevice *device;

  e = [[pairedDevices arrayByAddingObjectsFromArray:nearbyDevices]
        objectEnumerator];
  while ((device = [e nextObject]) != nil)
    if ([[device address] caseInsensitiveCompare:address] == NSOrderedSame)
      return device;
  return nil;
}

/* YES if it worked; otherwise say what bluetoothd said. */
- (BOOL)report:(int)st what:(NSString *)what
{
  if (st == BTStatusSuccess)
    return YES;
  NSRunAlertPanel (@"Bluetooth",
                   [NSString stringWithFormat:@"Couldn't %@: %@.", what,
                             BTStatusText (st)],
                   @"OK", nil, nil);
  return NO;
}

/* ---- actions ---- */

- (void)togglePower:(id)sender
{
  if (powered)
    {
      [self endDiscoverable];
      [self report:BTClientSetPower (client, 0) what:@"turn Bluetooth off"];
    }
  else
    [self report:BTClientSetPower (client, 1) what:@"turn Bluetooth on"];
  [self reload];
}

- (void)connectDevice:(id)sender
{
  BTDevice *device = [self selectedPaired];

  if (device == nil)
    return;
  [self report:BTClientConnect (client, [[device address] UTF8String])
          what:[NSString stringWithFormat:@"connect to “%@”",
                         [device displayName]]];
  [self reload];
}

- (void)disconnectDevice:(id)sender
{
  BTDevice *device = [self selectedPaired];

  if (device == nil)
    return;
  [self report:BTClientDisconnect (client, [[device address] UTF8String])
          what:[NSString stringWithFormat:@"disconnect “%@”",
                         [device displayName]]];
  [self reload];
}

- (void)removeDevice:(id)sender
{
  BTDevice *device = [self selectedPaired];

  if (device == nil)
    return;
  if (NSRunAlertPanel ([NSString stringWithFormat:@"Remove “%@”?",
                                 [device displayName]],
                       @"You'll have to pair it again to use it with this "
                       @"computer.",
                       @"Remove", @"Cancel", nil) != NSAlertDefaultReturn)
    return;
  [self report:BTClientUnpair (client, [[device address] UTF8String])
          what:[NSString stringWithFormat:@"remove “%@”",
                         [device displayName]]];
  [self reload];
}

- (void)pairedDoubleClicked:(id)sender
{
  BTDevice *device = [self selectedPaired];

  if (device == nil || [pairedTable clickedRow] < 0 || !powered)
    return;
  if ([device isConnected])
    [self disconnectDevice:sender];
  else if ([device linkState] == BTDeviceDisconnected)
    [self connectDevice:sender];
}

- (void)toggleAutoconnect:(id)sender
{
  BTDevice *device = [self selectedPaired];

  if (device != nil)
    [self report:BTClientSetAutoconnect (client, [[device address] UTF8String],
                                         [sender state] == NSOnState)
            what:@"change Connect automatically"];
  [self reload];
  [self showDevice];
}

- (void)toggleAudio:(id)sender
{
  BTDevice *device = [self selectedPaired];

  if (device != nil)
    [self report:BTClientSetAudio (client, [[device address] UTF8String],
                                   [sender state] == NSOnState)
            what:@"change where sound plays"];
  [self reload];
  [self showDevice];
}

- (void)chooseRoute:(id)sender
{
  BTDevice *device = [self selectedPaired];
  int route = [[sender selectedItem] tag] == BTRouteItemHeadset
    ? BTRouteHFP : BTRouteA2DP;

  if (device == nil || route == [device route])
    return;
  [self report:BTClientSetAudioRoute (client, [[device address] UTF8String],
                                      route)
          what:(route == BTRouteHFP ? @"turn on the headset's microphone"
                                    : @"switch to stereo")];
  [self reload];
  [self showDevice];
}

- (void)search:(id)sender
{
  int st = BTClientScan (client, BTScanSeconds);

  /* The searches the window starts by itself fail quietly. */
  if (sender != nil)
    [self report:st what:@"search for devices"];
  if (st == BTStatusSuccess)
    {
      scanning = YES;
      [self showNearby];
    }
}

- (void)pairDevice:(id)sender
{
  BTDevice *device = [self selectedNearby];
  int st;

  if (device == nil || !powered || [pairingPanel isVisible])
    return;
  if (sender == nearbyTable && [nearbyTable clickedRow] < 0)
    return;
  st = [pairingPanel pairWithAddress:[device address]
                                name:[device displayName]
                          overWindow:window];
  [self report:st
          what:[NSString stringWithFormat:@"pair with “%@”",
                         [device displayName]]];
  [self showNearby];
}

@end
