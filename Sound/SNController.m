/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "SNController.h"
#import <GNUstepBase/GNUstep.h>
#import <GNUstepGUI/GSTheme.h>

#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <unistd.h>

/* Layout, in points. */
#define SNMargin 20.0
#define SNWindowWidth 600.0
#define SNTabHeight 300.0
#define SNRowGap 10.0
#define SNLabelWidth 120.0
#define SNTableHeight 150.0

/* Timing, in seconds. */
#define SNPollSeconds 1.0	/* the volumes, read again */
#define SNDevicesEvery 3	/* the devices too, every this many polls */
#define SNMeterSeconds 0.05	/* the level meter */
#define SNReloadDelay 0.15	/* gather a burst of notifications */

/* The alert sound: NSGlobalDomain keys, as the NB* desktop keys
   (nextbsd-theme NBDesktopSettings.h): the user's value, else the
   theme's Info.plist, else these. */
#define SNAlertSoundKey @"NBAlertSound"
#define SNAlertVolumeKey @"NBAlertVolume"
#define SNDefaultAlertSound @"Tink"
#define SNDefaultAlertVolume 0.75
#define SNSettingsChangedNotification @"org.nextbsd.SettingsChanged"

/* A view laid out from the top down. */
@interface SNFlippedView : NSView
@end

@implementation SNFlippedView
- (BOOL)isFlipped
{
  return YES;
}
@end

static NSTextField *
SNLabel (NSRect frame, NSString *text, NSFont *font)
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
SNSmallFont (void)
{
  return [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
}

static NSButton *
SNSwitch (NSRect frame, NSString *title, id target, SEL action)
{
  NSButton *button = AUTORELEASE ([[NSButton alloc] initWithFrame:frame]);

  [button setTitle:title];
  [button setTarget:target];
  [button setAction:action];
  [button setButtonType:NSSwitchButton];
  return button;
}

static NSSlider *
SNSlider (NSRect frame, id target, SEL action)
{
  NSSlider *slider = AUTORELEASE ([[NSSlider alloc] initWithFrame:frame]);

  [slider setMinValue:0.0];
  [slider setMaxValue:100.0];
  [slider setContinuous:YES];
  [slider setTarget:target];
  [slider setAction:action];
  return slider;
}

/* A list in a scroll view: columns are {identifier, title, width}. */
static NSTableView *
SNTable (NSView *parent, NSRect frame, NSArray *columns, id owner)
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

static NSString *
SNString (const char *s)
{
  NSString *string = [NSString stringWithUTF8String:s];

  return string != nil ? string : @"";
}

static NSString *
SNKindText (const SNAudioDevice *d)
{
  switch (d->kind)
    {
    case SNAudioBluetooth: return @"Bluetooth";
    case SNAudioVirtual: return @"Virtual";
    default: return @"Built-in";
    }
}

@interface SNController (Private)
- (void)buildMenu;
- (void)buildWindow;
- (NSView *)effectsTab:(NSSize)size;
- (NSView *)outputTab:(NSSize)size;
- (NSView *)inputTab:(NSSize)size;
- (void)wake:(NSNotification *)note;
- (void)scheduleReload;
- (void)pollFired:(NSTimer *)timer;
- (void)reloadDevices;
- (void)readVolumes;
- (void)showOutput;
- (void)showInput;
- (void)updateMeter;
- (void)meterFired:(NSTimer *)timer;
- (SNAudioDevice *)deviceInRow:(NSInteger)row of:(NSArray *)list;
- (SNAudioDevice *)defaultOutput;
- (SNAudioDevice *)defaultInput;
- (SNAudioDevice *)headsetOwningOutput;
- (void)findAlertSounds;
- (NSString *)alertSound;
- (float)alertVolume;
- (void)setGlobal:(id)value forKey:(NSString *)key;
- (void)playAlert;
- (void)volumeChanged:(id)sender;
- (void)muteChanged:(id)sender;
- (void)inputVolumeChanged:(id)sender;
- (void)alertVolumeChanged:(id)sender;
- (void)toggleDockExtra:(id)sender;
- (void)dockExtraChanged:(SNDockExtra *)extra;
@end

@implementation SNController

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [NSObject cancelPreviousPerformRequestsWithTarget:self];
  [poll invalidate];
  RELEASE (poll);
  [meterTimer invalidate];
  RELEASE (meterTimer);
  [dockExtra invalidate];
  RELEASE (dockExtra);
  RELEASE (playing);
  RELEASE (wakeHandle);
  RELEASE (window);
  RELEASE (outputs);
  RELEASE (inputs);
  RELEASE (shownDevices);
  RELEASE (meterDevice);
  RELEASE (alertSounds);
  RELEASE (alertPaths);
  [super dealloc];
}

- (void)applicationDidFinishLaunching:(NSNotification *)note
{
  NSImage *icon = [NSImage imageNamed:@"Sound.png"];

  if (icon != nil)
    [NSApp setApplicationIconImage:icon];
  [self buildMenu];
  outputs = [[NSArray alloc] init];
  inputs = [[NSArray alloc] init];

  /* bluetoothd's notifications come in on a dispatch queue, as a byte
     on this pipe each. */
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
      [wakeHandle waitForDataInBackgroundAndNotifyForModes:
                    [NSArray arrayWithObjects:NSDefaultRunLoopMode,
                             NSEventTrackingRunLoopMode, nil]];
    }
  else
    NSLog (@"Sound: no pipe for notifications: %s", strerror (errno));
  audio = SNAudioOpen (wakeFDs[1]);
  dockExtra = [[SNDockExtra alloc] initWithIdentifier:SNDockExtraSound
                                           bundleName:@"Sound"];
  [dockExtra setTarget:self action:@selector (dockExtraChanged:)];
  [self findAlertSounds];

  [self buildWindow];
  [self reloadDevices];
  [window makeKeyAndOrderFront:self];

  /* While a slider is dragged too, so the other controls keep up. */
  poll = RETAIN ([NSTimer timerWithTimeInterval:SNPollSeconds
                                         target:self
                                       selector:@selector (pollFired:)
                                       userInfo:nil
                                        repeats:YES]);
  [[NSRunLoop currentRunLoop] addTimer:poll forMode:NSDefaultRunLoopMode];
  [[NSRunLoop currentRunLoop] addTimer:poll
                               forMode:NSEventTrackingRunLoopMode];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app
{
  return YES;
}

- (void)applicationWillTerminate:(NSNotification *)note
{
  [poll invalidate];
  [meterTimer invalidate];
  SNAudioMeterClose (meter);
  meter = NULL;
  [playing stop];
  SNAudioClose (audio);
  audio = NULL;
}

/* ---- the lists ---- */

- (NSInteger)numberOfRowsInTableView:(NSTableView *)table
{
  if (table == alertTable)
    return (NSInteger) [alertSounds count];
  return (NSInteger) [(table == outputTable ? outputs : inputs) count];
}

- (id)tableView:(NSTableView *)table
    objectValueForTableColumn:(NSTableColumn *)column
                          row:(NSInteger)row
{
  SNAudioDevice *d;

  if (table == alertTable)
    return row >= 0 && (NSUInteger) row < [alertSounds count]
      ? [alertSounds objectAtIndex:row] : nil;
  d = [self deviceInRow:row of:(table == outputTable ? outputs : inputs)];
  if (d == NULL)
    return nil;
  if ([[column identifier] isEqual:@"name"])
    return SNString (d->name);
  return SNKindText (d);
}

- (BOOL)tableView:(NSTableView *)table shouldEditTableColumn:(NSTableColumn *)c
              row:(NSInteger)row
{
  return NO;
}

- (BOOL)tableView:(NSTableView *)table shouldSelectRow:(NSInteger)row
{
  SNAudioDevice *d;
  NSUInteger i;

  if (reloading || table == alertTable)
    return YES;
  if (table == outputTable)
    {
      /* Only the output playing now: choosing needs the helper. */
      d = [self deviceInRow:row of:outputs];
      return d != NULL && d->defaultOut;
    }
  d = [self deviceInRow:row of:inputs];
  if (d == NULL)
    return NO;
  /* A headset's microphone can be opened; any other choice closes one
     that is open. A kernel input can't be chosen yet (the helper). */
  if (d->defaultIn || (d->kind == SNAudioBluetooth && d->handsFree))
    return YES;
  for (i = 0; i < [inputs count]; i++)
    {
      SNAudioDevice *other = [self deviceInRow:(NSInteger) i of:inputs];

      if (other->kind == SNAudioBluetooth && other->microphone)
        return YES;
    }
  return NO;
}

- (void)tableViewSelectionDidChange:(NSNotification *)note
{
  NSTableView *table = [note object];
  SNAudioDevice *d;
  NSUInteger i;

  if (reloading)
    return;
  if (table == alertTable)
    {
      NSInteger row = [alertTable selectedRow];

      if (row >= 0 && (NSUInteger) row < [alertSounds count])
        {
          [self setGlobal:[alertSounds objectAtIndex:row]
                   forKey:SNAlertSoundKey];
          [self playAlert];
        }
      return;
    }
  if (table != inputTable)
    return;
  d = [self deviceInRow:[inputTable selectedRow] of:inputs];
  if (d == NULL)
    return;
  for (i = 0; i < [inputs count]; i++)
    {
      SNAudioDevice *other = [self deviceInRow:(NSInteger) i of:inputs];

      if (other != d && other->kind == SNAudioBluetooth && other->microphone
          && SNAudioSetMicrophone (audio, other, 0) != 0)
        NSLog (@"Sound: can't close %s's microphone: %s", other->name,
               strerror (errno));
    }
  if (d->kind == SNAudioBluetooth && !d->microphone
      && SNAudioSetMicrophone (audio, d, 1) != 0)
    NSRunAlertPanel (@"Sound",
                     [NSString stringWithFormat:
                                 @"Couldn't open the microphone of “%@”: "
                               @"bluetoothd isn't answering, or its "
                               @"hands-free link is down.",
                               SNString (d->name)],
                     @"OK", nil, nil);
  /* bluetoothd's notification brings the new state; until then show
     what's still true. */
  [self reloadDevices];
}

- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)item
{
  [self updateMeter];
}

@end

@implementation SNController (Private)

- (void)buildMenu
{
  NSMenu *menu = AUTORELEASE ([[NSMenu alloc] initWithTitle:@"Sound"]);
  NSMenu *windows = AUTORELEASE ([[NSMenu alloc] initWithTitle:@"Window"]);
  id<NSMenuItem> item;

  [menu addItemWithTitle:@"About Sound"
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

/* The tabs, then the output volume under them, as macOS's Sound
   settings. Built once; reloads only change what the controls show. */
- (void)buildWindow
{
  SNFlippedView *content;
  NSTabViewItem *item;
  NSSize inner;
  CGFloat width = SNWindowWidth - 2 * SNMargin;
  CGFloat height, y;
  NSArray *titles = [NSArray arrayWithObjects:@"Sound Effects", @"Output",
                             @"Input", nil];
  NSUInteger i;

  height = SNMargin + SNTabHeight + SNRowGap + 24 + 6 + 22 + SNMargin;
  window = [[NSWindow alloc]
      initWithContentRect:NSMakeRect (200, 200, SNWindowWidth, height)
                styleMask:NSTitledWindowMask | NSClosableWindowMask
                          | NSMiniaturizableWindowMask
                  backing:NSBackingStoreBuffered
                    defer:NO];
  [window setTitle:@"Sound"];
  [window setReleasedWhenClosed:NO];
  [window setFrameAutosaveName:@"Sound"];
  content = AUTORELEASE ([[SNFlippedView alloc]
                           initWithFrame:NSMakeRect (0, 0, SNWindowWidth,
                                                     height)]);

  tabs = AUTORELEASE ([[NSTabView alloc]
                        initWithFrame:NSMakeRect (SNMargin, SNMargin, width,
                                                  SNTabHeight)]);
  [tabs setDelegate:self];
  inner = [tabs contentRect].size;
  for (i = 0; i < [titles count]; i++)
    {
      NSView *view = i == 0 ? [self effectsTab:inner]
        : (i == 1 ? [self outputTab:inner] : [self inputTab:inner]);

      item = AUTORELEASE ([[NSTabViewItem alloc]
                            initWithIdentifier:[titles objectAtIndex:i]]);
      [item setLabel:[titles objectAtIndex:i]];
      [item setView:view];
      [tabs addTabViewItem:item];
    }
  /* macOS opens on Output. */
  [tabs selectTabViewItemAtIndex:1];
  [content addSubview:tabs];
  y = SNMargin + SNTabHeight + SNRowGap;

  [content addSubview:SNLabel (NSMakeRect (SNMargin, y + 3, SNLabelWidth, 20),
                               @"Output volume:", nil)];
  volumeSlider = SNSlider (NSMakeRect (SNMargin + SNLabelWidth, y + 1,
                                       width - SNLabelWidth - 90, 22),
                           self, @selector (volumeChanged:));
  [content addSubview:volumeSlider];
  muteSwitch = SNSwitch (NSMakeRect (SNWindowWidth - SNMargin - 76, y + 1,
                                     76, 22),
                         @"Mute", self, @selector (muteChanged:));
  [content addSubview:muteSwitch];
  y += 24 + 6;

  /* As macOS's "Show volume in menu bar". */
  dockSwitch = SNSwitch (NSMakeRect (SNMargin + SNLabelWidth, y,
                                     width - SNLabelWidth, 22),
                         @"Show volume in Dock", self,
                         @selector (toggleDockExtra:));
  [content addSubview:dockSwitch];
  [self dockExtraChanged:dockExtra];

  [window setContentView:content];
}

- (NSView *)effectsTab:(NSSize)size
{
  SNFlippedView *view = AUTORELEASE ([[SNFlippedView alloc]
                                       initWithFrame:NSMakeRect (0, 0,
                                                                 size.width,
                                                                 size.height)]);
  CGFloat width = size.width - 2 * 12, y = 12;
  NSString *sound = [self alertSound];
  NSUInteger row;

  [view addSubview:SNLabel (NSMakeRect (12, y, width, 18),
                            @"Select an alert sound:", nil)];
  y += 22;
  alertTable = SNTable (view, NSMakeRect (12, y, width, SNTableHeight + 20),
                        [NSArray arrayWithObjects:
                                   @"name", @"Name",
                                   [NSNumber numberWithFloat:width - 24], nil],
                        self);
  [alertTable setHeaderView:nil];
  y += SNTableHeight + 20 + SNRowGap + 4;

  [view addSubview:SNLabel (NSMakeRect (12, y + 3, SNLabelWidth, 20),
                            @"Alert volume:", nil)];
  alertSlider = SNSlider (NSMakeRect (12 + SNLabelWidth, y + 1,
                                      width - SNLabelWidth, 22),
                          self, @selector (alertVolumeChanged:));
  /* Play it when the slider is let go, not all the way. */
  [alertSlider setContinuous:NO];
  [alertSlider setFloatValue:[self alertVolume] * 100.0];
  [view addSubview:alertSlider];
  y += 24 + 8;
  effectsNote = SNLabel (NSMakeRect (12, y, width, 34), @"", SNSmallFont ());
  [[effectsNote cell] setWraps:YES];
  [view addSubview:effectsNote];

  reloading = YES;
  [alertTable reloadData];
  row = [alertSounds indexOfObject:sound];
  if (row != NSNotFound)
    {
      [alertTable selectRow:(NSInteger) row byExtendingSelection:NO];
      [alertTable scrollRowToVisible:(NSInteger) row];
    }
  reloading = NO;
  return view;
}

- (NSView *)outputTab:(NSSize)size
{
  SNFlippedView *view = AUTORELEASE ([[SNFlippedView alloc]
                                       initWithFrame:NSMakeRect (0, 0,
                                                                 size.width,
                                                                 size.height)]);
  CGFloat width = size.width - 2 * 12, y = 12, kindW = 120;

  [view addSubview:SNLabel (NSMakeRect (12, y, width, 18),
                            @"Select a device for sound output:", nil)];
  y += 22;
  outputTable = SNTable (view, NSMakeRect (12, y, width, SNTableHeight),
                         [NSArray arrayWithObjects:
                                    @"name", @"Name",
                                    [NSNumber numberWithFloat:
                                                width - kindW - 24],
                                    @"kind", @"Type",
                                    [NSNumber numberWithFloat:kindW], nil],
                         self);
  y += SNTableHeight + 8;
  outputDetail = SNLabel (NSMakeRect (12, y, width, 34), @"", SNSmallFont ());
  [[outputDetail cell] setWraps:YES];
  [view addSubview:outputDetail];
  y += 34 + 4;
  outputNote = SNLabel (NSMakeRect (12, y, width, 34), @"", SNSmallFont ());
  [[outputNote cell] setWraps:YES];
  [view addSubview:outputNote];
  return view;
}

- (NSView *)inputTab:(NSSize)size
{
  SNFlippedView *view = AUTORELEASE ([[SNFlippedView alloc]
                                       initWithFrame:NSMakeRect (0, 0,
                                                                 size.width,
                                                                 size.height)]);
  CGFloat width = size.width - 2 * 12, y = 12, kindW = 120;
  CGFloat tableH = SNTableHeight - 48;

  [view addSubview:SNLabel (NSMakeRect (12, y, width, 18),
                            @"Select a device for sound input:", nil)];
  y += 22;
  inputTable = SNTable (view, NSMakeRect (12, y, width, tableH),
                        [NSArray arrayWithObjects:
                                   @"name", @"Name",
                                   [NSNumber numberWithFloat:
                                               width - kindW - 24],
                                   @"kind", @"Type",
                                   [NSNumber numberWithFloat:kindW], nil],
                        self);
  y += tableH + 6;
  inputDetail = SNLabel (NSMakeRect (12, y, width, 18), @"", SNSmallFont ());
  [view addSubview:inputDetail];
  y += 18 + SNRowGap;

  inputVolumeLabel = SNLabel (NSMakeRect (12, y + 3, SNLabelWidth, 20),
                              @"Input volume:", nil);
  [view addSubview:inputVolumeLabel];
  inputSlider = SNSlider (NSMakeRect (12 + SNLabelWidth, y + 1,
                                      width - SNLabelWidth, 22),
                          self, @selector (inputVolumeChanged:));
  [view addSubview:inputSlider];
  y += 24 + 6;

  [view addSubview:SNLabel (NSMakeRect (12, y + 1, SNLabelWidth, 20),
                            @"Input level:", nil)];
  levelView = AUTORELEASE ([[SNLevelView alloc]
                             initWithFrame:NSMakeRect (12 + SNLabelWidth + 2,
                                                       y + 5,
                                                       width - SNLabelWidth - 4,
                                                       12)]);
  [view addSubview:levelView];
  y += 22 + 8;

  inputNote = SNLabel (NSMakeRect (12, y, width, 46), @"", SNSmallFont ());
  [[inputNote cell] setWraps:YES];
  [view addSubview:inputNote];
  return view;
}

/* ---- live updates ---- */

- (void)wake:(NSNotification *)note
{
  char buffer[256];

  while (read (wakeFDs[0], buffer, sizeof (buffer)) > 0)
    ;
  [wakeHandle waitForDataInBackgroundAndNotifyForModes:
                [NSArray arrayWithObjects:NSDefaultRunLoopMode,
                         NSEventTrackingRunLoopMode, nil]];
  [self scheduleReload];
}

- (void)scheduleReload
{
  [NSObject cancelPreviousPerformRequestsWithTarget:self
                                           selector:@selector (reloadDevices)
                                             object:nil];
  [self performSelector:@selector (reloadDevices)
             withObject:nil
             afterDelay:SNReloadDelay];
}

- (void)pollFired:(NSTimer *)timer
{
  static unsigned beats;

  if (++beats % SNDevicesEvery == 0)
    [self reloadDevices];
  else
    [self readVolumes];
}

/* Read the devices again, and show them if anything changed. */
- (void)reloadDevices
{
  NSMutableArray *outs = [NSMutableArray array];
  NSMutableArray *ins = [NSMutableArray array];
  NSMutableString *state = [NSMutableString string];
  int i;

  if (audio == NULL)
    return;
  deviceCount = SNAudioCopyDevices (audio, devices, SNAudioMaxDevices);
  for (i = 0; i < deviceCount; i++)
    {
      SNAudioDevice *d = &devices[i];

      if (d->play)
        [outs addObject:[NSNumber numberWithInt:i]];
      if (d->record)
        [ins addObject:[NSNumber numberWithInt:i]];
      [state appendFormat:@"%s|%s|%d%d%d%d%d%d|%d\n", d->ident, d->name,
             d->play, d->record, d->defaultOut, d->defaultIn, d->handsFree,
             d->microphone, d->battery];
    }
  ASSIGN (outputs, outs);
  ASSIGN (inputs, ins);
  if (![state isEqual:shownDevices])
    {
      ASSIGN (shownDevices, state);
      [self showOutput];
      [self showInput];
      [self updateMeter];
    }
  [self readVolumes];
}

/* The output's volume and mute, and the input's volume. */
- (void)readVolumes
{
  SNAudioDevice *out = [self defaultOutput];
  SNAudioDevice *in = [self defaultInput];
  int volume = 0, muted = 0, got = -1;
  BOOL tracking = [[NSRunLoop currentRunLoop] currentMode]
    == NSEventTrackingRunLoopMode;
  BOOL stalled;

  if (out != NULL)
    got = SNAudioGetOutputVolume (audio, out, &volume, &muted);
  stalled = got != 0 && out != NULL && (errno == ETIMEDOUT || errno == EBUSY);
  if (stalled != outputStalled)
    {
      outputStalled = stalled;
      [self showOutput];
    }
  if (got == 0)
    {
      outputVolume = volume;
      outputMuted = muted != 0;
      /* Not under the user's hand while a slider is dragged. */
      if (!tracking)
        [volumeSlider setIntValue:volume];
      [muteSwitch setState:muted ? NSOnState : NSOffState];
      [volumeSlider setEnabled:SNAudioOutputHasVolume (out)];
      [muteSwitch setEnabled:YES];
    }
  else
    {
      [volumeSlider setIntValue:0];
      [volumeSlider setEnabled:NO];
      [muteSwitch setState:NSOffState];
      [muteSwitch setEnabled:NO];
    }

  if (in != NULL && SNAudioGetInputVolume (audio, in, &volume) == 0)
    {
      if (!tracking)
        [inputSlider setIntValue:volume];
      [inputSlider setEnabled:YES];
      [inputSlider setToolTip:nil];
    }
  else
    {
      [inputSlider setIntValue:0];
      [inputSlider setEnabled:NO];
      [inputSlider setToolTip:in != NULL && in->kind == SNAudioBluetooth
                   ? @"A headset's microphone level is set on the headset."
                   : nil];
    }
}

- (void)showOutput
{
  SNAudioDevice *out = [self defaultOutput];
  NSMutableString *detail = [NSMutableString string];
  NSUInteger i;
  BOOL kernel = NO;

  reloading = YES;
  [outputTable reloadData];
  [outputTable deselectAll:self];
  for (i = 0; i < [outputs count]; i++)
    if ([self deviceInRow:(NSInteger) i of:outputs] == out)
      [outputTable selectRow:(NSInteger) i byExtendingSelection:NO];
  reloading = NO;

  /* With nothing to play to, what needs a device waits for one; the
     alert sound can still be chosen, and plays once one is there. */
  [alertSlider setEnabled:out != NULL && !outputStalled];
  [effectsNote setStringValue:out != NULL && !outputStalled ? @""
               : @"No sound output device. The alert sound you choose "
               @"is kept, and plays once one is connected."];
  if (out == NULL)
    [detail setString:[outputs count]
            ? @"No device is the output now."
            : @"No sound output device. Headphones or a headset show "
            @"here when they connect."];
  else if (out->kind == SNAudioBluetooth)
    {
      [detail appendFormat:@"“%@” plays the sound (%s)",
              SNString (out->name), out->dsp];
      if (out->battery >= 0)
        [detail appendFormat:@"; battery %d%%", out->battery];
      [detail appendString:out->absoluteVolume >= 0
              ? @". Its volume is the headset's own."
              : @". It has no volume of its own, so the volume moves in "
              @"6 dB steps."];
    }
  else
    {
      [detail appendFormat:@"“%@” plays the sound (%s).",
              SNString (out->name), out->dsp];
      if (SNAudioOutputVolumeIsCoarse (out))
        [detail appendString:@" Its volume moves in 6 dB steps."];
    }
  if (out != NULL && outputStalled)
    [detail setString:[NSString stringWithFormat:
                                  @"“%@” isn't answering (its mixer is "
                                @"waiting for the device), so its volume "
                                @"can't be changed now.",
                                SNString (out->name)]];
  [outputDetail setStringValue:detail];

  for (i = 0; i < [outputs count]; i++)
    if ([self deviceInRow:(NSInteger) i of:outputs]->kind == SNAudioKernel)
      kernel = YES;
  [outputNote setStringValue:
                [outputs count] > 1 && kernel
              ? @"A Bluetooth headset takes the output when it connects. "
              @"Choosing another built-in output needs the settings apps' "
              @"administrator helper, which isn't there yet."
              : @""];
}

- (void)showInput
{
  SNAudioDevice *in = [self defaultInput];
  SNAudioDevice *headset = [self headsetOwningOutput];
  NSMutableString *note = [NSMutableString string];
  NSUInteger i;
  BOOL kernel = NO;

  reloading = YES;
  [inputTable reloadData];
  [inputTable deselectAll:self];
  for (i = 0; i < [inputs count]; i++)
    if ([self deviceInRow:(NSInteger) i of:inputs] == in)
      [inputTable selectRow:(NSInteger) i byExtendingSelection:NO];
  reloading = NO;

  if (in != NULL)
    [inputDetail setStringValue:
                   [NSString stringWithFormat:@"“%@” records (%s).",
                             SNString (in->name), in->dsp]];
  else
    [inputDetail setStringValue:[inputs count] ? @"No device records now."
                                               : @"No sound input device. A "
                                               @"headset's microphone shows "
                                               @"here while its hands-free "
                                               @"link is up."];

  if (headset != NULL && headset->microphone)
    [note appendFormat:@"The microphone of “%@” is open, so it plays in "
          @"headset quality. Choose another input to hear it in stereo "
          @"again.", SNString (headset->name)];
  else if (headset != NULL)
    [note appendFormat:@"While “%@” plays in stereo, recording gets "
          @"silence. Choose it here to use its microphone; it then plays "
          @"in headset quality, as on macOS.", SNString (headset->name)];
  for (i = 0; i < [inputs count]; i++)
    if ([self deviceInRow:(NSInteger) i of:inputs]->kind == SNAudioKernel)
      kernel = YES;
  if (kernel && [inputs count] > 1)
    [note appendFormat:@"%@Choosing another built-in input needs the "
          @"administrator helper, which isn't there yet.",
          [note length] ? @" " : @""];
  [inputNote setStringValue:note];
}

/* The meter runs while the Input tab is shown, on the input that
   records now. */
- (void)updateMeter
{
  SNAudioDevice *in = [self defaultInput];
  BOOL shown = [[[tabs selectedTabViewItem] identifier] isEqual:@"Input"]
    && [window isVisible];
  NSString *ident = shown && in != NULL ? SNString (in->ident) : nil;

  if (ident == meterDevice || [ident isEqual:meterDevice])
    return;
  SNAudioMeterClose (meter);
  meter = NULL;
  [meterTimer invalidate];
  DESTROY (meterTimer);
  ASSIGN (meterDevice, ident);
  if (ident != nil)
    meter = SNAudioMeterOpen (in);
  [levelView setActive:meter != NULL];
  if (meter == NULL)
    return;
  meterTimer = RETAIN ([NSTimer timerWithTimeInterval:SNMeterSeconds
                                               target:self
                                             selector:@selector (meterFired:)
                                             userInfo:nil
                                              repeats:YES]);
  [[NSRunLoop currentRunLoop] addTimer:meterTimer
                               forMode:NSDefaultRunLoopMode];
  [[NSRunLoop currentRunLoop] addTimer:meterTimer
                               forMode:NSEventTrackingRunLoopMode];
}

- (void)meterFired:(NSTimer *)timer
{
  [levelView setLevel:SNAudioMeterLevel (meter)];
}

- (SNAudioDevice *)deviceInRow:(NSInteger)row of:(NSArray *)list
{
  int index;

  if (row < 0 || (NSUInteger) row >= [list count])
    return NULL;
  index = [[list objectAtIndex:row] intValue];
  return index >= 0 && index < deviceCount ? &devices[index] : NULL;
}

- (SNAudioDevice *)defaultOutput
{
  int i = SNAudioDefaultOutput (devices, deviceCount);

  return i >= 0 ? &devices[i] : NULL;
}

- (SNAudioDevice *)defaultInput
{
  int i = SNAudioDefaultInput (devices, deviceCount);

  return i >= 0 ? &devices[i] : NULL;
}

/* A headset that has /dev/dsp. */
- (SNAudioDevice *)headsetOwningOutput
{
  int i;

  for (i = 0; i < deviceCount; i++)
    if (devices[i].kind == SNAudioBluetooth && devices[i].defaultOut)
      return &devices[i];
  return NULL;
}

/* ---- the alert sound ---- */

/* Every sound in the Library/Sounds folders, by name, the user's first
   where two share one. */
- (void)findAlertSounds
{
  NSFileManager *fm = [NSFileManager defaultManager];
  NSMutableDictionary *paths = [NSMutableDictionary dictionary];
  NSMutableArray *dirs = [NSMutableArray arrayWithObjects:
      [NSHomeDirectory () stringByAppendingPathComponent:@"Library"],
      @"/Local/Library", @"/Network/Library", @"/System/Library", nil];
  NSArray *types = [NSArray arrayWithObjects:@"wav", @"aiff", @"aif", @"au",
                            @"snd", nil];
  NSUInteger i, j;

  [dirs addObjectsFromArray:
          NSSearchPathForDirectoriesInDomains (NSLibraryDirectory,
                                               NSAllDomainsMask, YES)];
  for (i = 0; i < [dirs count]; i++)
    {
      NSString *dir = [[dirs objectAtIndex:i]
                        stringByAppendingPathComponent:@"Sounds"];
      NSArray *files = [fm directoryContentsAtPath:dir];

      for (j = 0; j < [files count]; j++)
        {
          NSString *file = [files objectAtIndex:j];
          NSString *name = [file stringByDeletingPathExtension];

          if ([types containsObject:[[file pathExtension] lowercaseString]]
              && [paths objectForKey:name] == nil)
            [paths setObject:[dir stringByAppendingPathComponent:file]
                      forKey:name];
        }
    }
  ASSIGN (alertPaths, paths);
  ASSIGN (alertSounds, [[paths allKeys]
                         sortedArrayUsingSelector:
                           @selector (caseInsensitiveCompare:)]);
}

/* key's value: the user's, else the theme's, else nil. */
static id
SNGlobalSetting (NSString *key)
{
  id value = [[[NSUserDefaults standardUserDefaults]
                persistentDomainForName:NSGlobalDomain] objectForKey:key];

  if (value == nil)
    value = [[[GSTheme theme] infoDictionary] objectForKey:key];
  return value;
}

- (NSString *)alertSound
{
  id value = SNGlobalSetting (SNAlertSoundKey);

  /* One that isn't installed falls through to the built-in default. */
  if ([value isKindOfClass:[NSString class]]
      && [alertPaths objectForKey:value] != nil)
    return value;
  return SNDefaultAlertSound;
}

- (float)alertVolume
{
  id value = SNGlobalSetting (SNAlertVolumeKey);

  if ([value respondsToSelector:@selector (floatValue)]
      && [value floatValue] >= 0.0 && [value floatValue] <= 1.0)
    return [value floatValue];
  return SNDefaultAlertVolume;
}

/* Write an NSGlobalDomain key and say so, the way the settings apps'
   shared NBSettings is to (org.nextbsd.SettingsChanged {domain, keys}). */
- (void)setGlobal:(id)value forKey:(NSString *)key
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSMutableDictionary *domain;

  [defaults synchronize];
  domain = [NSMutableDictionary dictionaryWithDictionary:
             [defaults persistentDomainForName:NSGlobalDomain]];
  [domain setObject:value forKey:key];
  [defaults setPersistentDomain:domain forName:NSGlobalDomain];
  [defaults synchronize];
  NS_DURING
    [[NSDistributedNotificationCenter defaultCenter]
        postNotificationName:SNSettingsChangedNotification
                      object:nil
                    userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
                                NSGlobalDomain, @"domain",
                                [NSArray arrayWithObject:key], @"keys", nil]
          deliverImmediately:YES];
  NS_HANDLER
    NSLog (@"Sound: can't announce %@: %@", key, [localException reason]);
  NS_ENDHANDLER
}

/* The alert sound at the alert volume, as macOS plays it on a choice. */
- (void)playAlert
{
  NSString *path = [alertPaths objectForKey:[self alertSound]];
  NSSound *sound;

  [playing stop];
  DESTROY (playing);
  /* Not into a device that isn't answering: NSSound's thread would
     wait on it. */
  if (path == nil || [self defaultOutput] == NULL || outputStalled)
    return;
  sound = [[NSSound alloc] initWithContentsOfFile:path byReference:YES];
  if (sound == nil)
    return;
  [sound setVolume:[self alertVolume]];
  [sound play];
  playing = sound;
}

/* ---- actions ---- */

- (void)volumeChanged:(id)sender
{
  SNAudioDevice *out = [self defaultOutput];
  int volume = [volumeSlider intValue];

  if (out == NULL)
    return;
  if (SNAudioSetOutputVolume (audio, out, volume) != 0)
    {
      NSLog (@"Sound: can't set the volume of %s: %s", out->name,
             strerror (errno));
      return;
    }
  outputVolume = volume;
  /* Changing the volume unmutes, as on macOS. */
  if (outputMuted && SNAudioSetOutputMuted (audio, out, 0) == 0)
    {
      outputMuted = NO;
      [muteSwitch setState:NSOffState];
    }
}

- (void)muteChanged:(id)sender
{
  SNAudioDevice *out = [self defaultOutput];
  BOOL muted = [muteSwitch state] == NSOnState;

  if (out == NULL || SNAudioSetOutputMuted (audio, out, muted) != 0)
    {
      NSBeep ();
      [muteSwitch setState:outputMuted ? NSOnState : NSOffState];
      return;
    }
  outputMuted = muted;
}

- (void)inputVolumeChanged:(id)sender
{
  SNAudioDevice *in = [self defaultInput];

  if (in != NULL
      && SNAudioSetInputVolume (audio, in, [inputSlider intValue]) != 0)
    NSLog (@"Sound: can't set the input volume of %s: %s", in->name,
           strerror (errno));
}

- (void)alertVolumeChanged:(id)sender
{
  [self setGlobal:[NSNumber numberWithFloat:[alertSlider floatValue] / 100.0]
           forKey:SNAlertVolumeKey];
  [self playAlert];
}

- (void)toggleDockExtra:(id)sender
{
  [dockExtra setShown:[dockSwitch state] == NSOnState];
}

/* The Dock answered, or its extras changed some other way. */
- (void)dockExtraChanged:(SNDockExtra *)extra
{
  BOOL installed = [dockExtra isInstalled];

  [dockSwitch setState:installed && [dockExtra isShown]
              ? NSOnState : NSOffState];
  [dockSwitch setEnabled:installed];
  [dockSwitch setToolTip:installed ? nil
              : @"The Dock's sound extra isn't installed."];
}

@end
