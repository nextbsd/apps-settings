/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "DTController.h"
#import "DTZones.h"
#import "NBSettingsHelper.h"
#import <GNUstepBase/GNUstep.h>

#include <stdlib.h>
#include <time.h>

#include "DTSystem.h"

/* Layout, in points, as Energy's. */
#define DTMargin 20.0
#define DTWindowWidth 560.0
#define DTTabHeight 340.0
#define DTLabelWidth 130.0
#define DTFieldX (DTLabelWidth + 8)
#define DTRowGap 10.0
#define DTButtonWidth 100.0
#define DTButtonHeight 26.0
/* The lock and its sentence, beside Defaults and Revert. */
#define DTLockWidth (DTWindowWidth - 2 * DTMargin - 2 * DTButtonWidth - 16)

/* ntpd comes back this long after a change (launchd's throttle is 10 s). */
#define DTNetworkTimeSettle 15.0

static NSString *const DTRight = @"org.nextbsd.settings.datetime";
static NSString *const DTReason = @"change the date and time settings";

static NSString *const DTNTPConf = @"/etc/ntp.conf";
/* Offered in the server box; any other name or address can be typed. */
static NSString *const DTServers[] = { @"pool.ntp.org", @"0.pool.ntp.org",
                                       @"time.cloudflare.com",
                                       @"time.google.com", nil };

/* The Dock's clock extra and its settings (apps-dock Extras/Clock). */
static NSString *const DTDockDomain = @"DockWM";
static NSString *const DTAnalogKey = @"DockExtraClockAnalog";
static NSString *const DT24HourKey = @"DockExtraClock24Hour";
static NSString *const DTSecondsKey = @"DockExtraClockShowsSeconds";
static NSString *const DTShowDateKey = @"DockExtraClockShowsDate";
static NSString *const DTDockHiddenKey = @"DockExtrasHidden";
static NSString *const DTClockExtra = @"org.nextbsd.dockextra.clock";
static NSString *const DTDockSetHidden = @"org.nextbsd.Dock.SetExtraHidden";
static NSString *const DTDockChanged = @"org.nextbsd.Dock.ExtrasChanged";
#define DTDockAnswerSeconds 2.0
/* The settings apps' change notification (the design's NBSettings). */
static NSString *const DTSettingsChanged = @"org.nextbsd.SettingsChanged";

/* The clock's own defaults, as it registers them. */
static NSDictionary *
DTClockDefaults (void)
{
  return [NSDictionary dictionaryWithObjectsAndKeys:
                         [NSNumber numberWithBool:NO], DTAnalogKey,
                         [NSNumber numberWithBool:YES], DT24HourKey,
                         [NSNumber numberWithBool:NO], DTSecondsKey,
                         [NSNumber numberWithBool:YES], DTShowDateKey, nil];
}

static NSArray *
DTClockKeys (void)
{
  return [NSArray arrayWithObjects:DTAnalogKey, DT24HourKey, DTSecondsKey,
                  DTShowDateKey, nil];
}

/* A view laid out from the top down. */
@interface DTFlippedView : NSView
@end

@implementation DTFlippedView
- (BOOL)isFlipped
{
  return YES;
}
@end

static NSTextField *
DTLabel (NSRect frame, NSString *text, NSFont *font)
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

static NSTextField *
DTRowLabel (CGFloat y, NSString *text)
{
  NSTextField *label = DTLabel (NSMakeRect (0, y + 3, DTLabelWidth, 20), text,
                                nil);
  [label setAlignment:NSRightTextAlignment];
  return label;
}

static NSFont *
DTSmallFont (void)
{
  return [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
}

static NSButton *
DTCheckbox (NSRect frame, NSString *title, id target, SEL action)
{
  NSButton *box = AUTORELEASE ([[NSButton alloc] initWithFrame:frame]);
  [box setButtonType:NSSwitchButton];
  [box setTitle:title];
  [box setTarget:target];
  [box setAction:action];
  return box;
}

/* "CST, UTC-06:00" for a zone now. */
static NSString *
DTZoneOffset (NSTimeZone *zone)
{
  NSInteger s = [zone secondsFromGMT];
  char sign = s < 0 ? '-' : '+';

  if (s < 0)
    s = -s;
  return [NSString stringWithFormat:@"%@, UTC%c%02ld:%02ld",
                   [zone abbreviation], sign, (long) (s / 3600),
                   (long) ((s / 60) % 60)];
}

/* Read a whole number from the scanner, then skip one separator. */
static BOOL
DTScanPart (NSScanner *scanner, int *value, NSString *separator)
{
  if (![scanner scanInt:value])
    return NO;
  if (separator != nil && ![scanner isAtEnd])
    return [scanner scanString:separator intoString:NULL];
  return YES;
}

/* The privileged operations, for -apply:value:. */
enum
{
  DTOpTimeZone,
  DTOpDate,
  DTOpNetworkTime
};

@interface DTController (Private)
- (void)buildMenu;
- (NSView *)dateTimeTab:(NSRect)frame;
- (NSView *)timeZoneTab:(NSRect)frame;
- (NSView *)clockTab:(NSRect)frame;
- (NSView *)bottomRow;
- (void)tick:(NSTimer *)t;
- (void)reload;
- (void)updateControls;
- (void)updateClockFields;
- (BOOL)isEditing:(NSTextField *)field;
- (NSTimeZone *)zone;
- (NSString *)readServer;
- (NSDictionary *)dockDomain;
- (NSDictionary *)readClock;
- (void)writeClock:(NSDictionary *)values;
- (void)writeDockValues:(NSDictionary *)values notify:(BOOL)notify;
- (void)settingsChanged:(NSNotification *)note;
- (BOOL)readDockHidden;
- (void)setDockHidden:(BOOL)hidden;
- (void)dockChanged:(NSNotification *)note;
- (void)toggleShowInDock:(id)sender;
- (void)filterZones;
- (void)selectCurrentZone;
- (int)perform:(int)op value:(id)value;
- (BOOL)apply:(int)op value:(id)value;
- (void)toggleAutomatic:(id)sender;
- (void)chooseServer:(id)sender;
- (void)setDateAndTime:(id)sender;
- (void)chooseZone:(id)sender;
- (void)chooseStyle:(id)sender;
- (void)toggleClock:(id)sender;
- (void)useDefaults:(id)sender;
- (void)revert:(id)sender;
@end

@implementation DTController

- (void)dealloc
{
  [[NSDistributedNotificationCenter defaultCenter] removeObserver:self];
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [timer invalidate];
  RELEASE (timer);
  RELEASE (window);
  RELEASE (auth);
  RELEASE (lockView);
  RELEASE (allZones);
  RELEASE (shownZones);
  RELEASE (zoneName);
  RELEASE (server);
  RELEASE (clock);
  RELEASE (shownState);
  RELEASE (originalZone);
  RELEASE (originalServer);
  RELEASE (originalClock);
  [super dealloc];
}

- (void)applicationDidFinishLaunching:(NSNotification *)note
{
  NSImage *icon = [NSImage imageNamed:@"DateTime.png"];
  DTFlippedView *content;
  NSTabViewItem *item;
  NSView *bottom;
  NSRect inner;
  CGFloat height;

  if (icon != nil)
    [NSApp setApplicationIconImage:icon];
  [self buildMenu];

  auth = RETAIN ([NBAuthorization authorizationWithRight:DTRight]);
  lockView = [[NBLockView alloc]
                initWithFrame:NSMakeRect (0, 0, DTLockWidth, 30)
                authorization:auth
                       reason:DTReason];
  [lockView setDelegate:self];

  allZones = RETAIN (DTZonesLoad ());
  shownZones = [NSMutableArray new];
  ASSIGN (zoneName, DTCurrentZoneName ());
  networkTime = DTNetworkTimeRunning () != 0;
  ASSIGN (server, [self readServer]);
  ASSIGN (clock, [self readClock]);
  dockHidden = [self readDockHidden];
  originalDockHidden = dockHidden;
  ASSIGN (originalZone, zoneName);
  originalNetworkTime = networkTime;
  ASSIGN (originalServer, server);
  {
    /* Only what the user has set; the rest stays unset on Revert. */
    NSDictionary *dock = [self dockDomain];
    NSMutableDictionary *own = [NSMutableDictionary dictionary];
    NSEnumerator *e = [DTClockKeys () objectEnumerator];
    NSString *key;

    while ((key = [e nextObject]) != nil)
      if ([dock objectForKey:key] != nil)
        [own setObject:[clock objectForKey:key] forKey:key];
    ASSIGN (originalClock, own);
  }

  height = DTMargin + DTTabHeight + DTRowGap + 30 + DTMargin;
  window = [[NSWindow alloc]
      initWithContentRect:NSMakeRect (200, 200, DTWindowWidth, height)
                styleMask:NSTitledWindowMask | NSClosableWindowMask
                          | NSMiniaturizableWindowMask
                  backing:NSBackingStoreBuffered
                    defer:NO];
  [window setTitle:@"Date & Time"];
  [window setReleasedWhenClosed:NO];
  [window setFrameAutosaveName:@"DateTime"];

  content = AUTORELEASE ([[DTFlippedView alloc]
                           initWithFrame:NSMakeRect (0, 0, DTWindowWidth,
                                                     height)]);
  tabView = AUTORELEASE ([[NSTabView alloc]
                           initWithFrame:NSMakeRect (DTMargin, DTMargin,
                                                     DTWindowWidth
                                                     - 2 * DTMargin,
                                                     DTTabHeight)]);
  [content addSubview:tabView];
  inner = [tabView contentRect];
  inner.origin = NSZeroPoint;

  item = AUTORELEASE ([[NSTabViewItem alloc] initWithIdentifier:@"datetime"]);
  [item setLabel:@"Date & Time"];
  [item setView:[self dateTimeTab:inner]];
  [tabView addTabViewItem:item];
  item = AUTORELEASE ([[NSTabViewItem alloc] initWithIdentifier:@"timezone"]);
  [item setLabel:@"Time Zone"];
  [item setView:[self timeZoneTab:inner]];
  [tabView addTabViewItem:item];
  item = AUTORELEASE ([[NSTabViewItem alloc] initWithIdentifier:@"clock"]);
  [item setLabel:@"Clock"];
  [item setView:[self clockTab:inner]];
  [tabView addTabViewItem:item];

  bottom = [self bottomRow];
  [bottom setFrameOrigin:NSMakePoint (DTMargin,
                                      DTMargin + DTTabHeight + DTRowGap)];
  [content addSubview:bottom];
  [window setContentView:content];

  [[NSDistributedNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector (settingsChanged:)
             name:DTSettingsChanged
           object:nil];
  [[NSDistributedNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector (dockChanged:)
             name:DTDockChanged
           object:nil];

  [self filterZones];
  [self reload];
  [self updateClockFields];
  [window makeKeyAndOrderFront:self];

  ASSIGN (timer, [NSTimer scheduledTimerWithTimeInterval:1.0
                                                  target:self
                                                selector:@selector (tick:)
                                                userInfo:nil
                                                 repeats:YES]);
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app
{
  return YES;
}

/* Date & Time has no documents; a file it's asked to open just brings
   the window forward. */
- (BOOL)application:(NSApplication *)app openFile:(NSString *)filename
{
  [window makeKeyAndOrderFront:self];
  return YES;
}

- (void)lockViewDidChange:(NBLockView *)view
{
  DESTROY (shownState);
  [self reload];
}

/* ---- the zone table ---- */

- (NSInteger)numberOfRowsInTableView:(NSTableView *)table
{
  return [shownZones count];
}

- (id)tableView:(NSTableView *)table
    objectValueForTableColumn:(NSTableColumn *)column
                          row:(NSInteger)row
{
  DTZone *zone = [shownZones objectAtIndex:row];
  NSString *which = [column identifier];

  if ([which isEqual:@"city"])
    return [zone city];
  if ([which isEqual:@"country"])
    return [zone country];
  if ([which isEqual:@"comment"])
    return [zone comment];
  return [zone name];
}

/* Locked, the list can be looked through but not chosen from. */
- (BOOL)tableView:(NSTableView *)table shouldSelectRow:(NSInteger)row
{
  return selectingZone || [lockView isUnlocked];
}

- (void)controlTextDidChange:(NSNotification *)note
{
  if ([note object] == searchField)
    [self filterZones];
}

/* A server picked from the box's list. */
- (void)comboBoxSelectionDidChange:(NSNotification *)note
{
  /* The box's text changes after this notification. */
  [self performSelector:@selector (chooseServer:) withObject:serverBox
             afterDelay:0.0];
}

@end

@implementation DTController (Private)

- (void)buildMenu
{
  NSMenu *menu = AUTORELEASE ([[NSMenu alloc] initWithTitle:@"Date & Time"]);
  NSMenu *edit = AUTORELEASE ([[NSMenu alloc] initWithTitle:@"Edit"]);
  NSMenu *windows = AUTORELEASE ([[NSMenu alloc] initWithTitle:@"Window"]);
  id<NSMenuItem> item;

  [menu addItemWithTitle:@"About Date & Time"
                  action:@selector (orderFrontStandardAboutPanel:)
           keyEquivalent:@""];
  /* The fields take typing, so cut, copy and paste. */
  item = [menu addItemWithTitle:@"Edit" action:NULL keyEquivalent:@""];
  [edit addItemWithTitle:@"Cut" action:@selector (cut:) keyEquivalent:@"x"];
  [edit addItemWithTitle:@"Copy" action:@selector (copy:) keyEquivalent:@"c"];
  [edit addItemWithTitle:@"Paste" action:@selector (paste:)
           keyEquivalent:@"v"];
  [edit addItemWithTitle:@"Select All" action:@selector (selectAll:)
           keyEquivalent:@"a"];
  [menu setSubmenu:edit forItem:item];
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

/* ---- the tabs ---- */

- (NSView *)dateTimeTab:(NSRect)frame
{
  DTFlippedView *view = AUTORELEASE ([[DTFlippedView alloc]
                                       initWithFrame:frame]);
  CGFloat width = NSWidth (frame) - 2 * DTMargin, y = DTMargin;
  NSUInteger i;

  automaticButton = DTCheckbox (NSMakeRect (DTMargin, y, width, 22),
                                @"Set date and time automatically",
                                self, @selector (toggleAutomatic:));
  [view addSubview:automaticButton];
  y += 22 + DTRowGap;

  [view addSubview:DTRowLabel (y, @"Time server:")];
  serverBox = AUTORELEASE ([[NSComboBox alloc]
                             initWithFrame:NSMakeRect (DTFieldX, y, 240, 24)]);
  for (i = 0; DTServers[i] != nil; i++)
    [serverBox addItemWithObjectValue:DTServers[i]];
  [serverBox setCompletes:YES];
  [serverBox setTarget:self];
  [serverBox setAction:@selector (chooseServer:)];
  [serverBox setDelegate:self];
  [view addSubview:serverBox];
  y += 24 + 2 * DTRowGap;

  [view addSubview:DTRowLabel (y, @"Date:")];
  dateField = AUTORELEASE ([[NSTextField alloc]
                             initWithFrame:NSMakeRect (DTFieldX, y, 110, 24)]);
  [dateField setTarget:self];
  [dateField setAction:@selector (setDateAndTime:)];
  [view addSubview:dateField];
  [view addSubview:DTLabel (NSMakeRect (DTFieldX + 118, y + 5, 140, 16),
                            @"year-month-day", DTSmallFont ())];
  y += 24 + DTRowGap;

  [view addSubview:DTRowLabel (y, @"Time:")];
  timeField = AUTORELEASE ([[NSTextField alloc]
                             initWithFrame:NSMakeRect (DTFieldX, y, 110, 24)]);
  [timeField setTarget:self];
  [timeField setAction:@selector (setDateAndTime:)];
  [view addSubview:timeField];
  [view addSubview:DTLabel (NSMakeRect (DTFieldX + 118, y + 5, 140, 16),
                            @"24-hour, hh:mm:ss", DTSmallFont ())];
  y += 24 + DTRowGap;

  dateNote = DTLabel (NSMakeRect (DTFieldX, y, width - DTFieldX, 32), nil,
                      DTSmallFont ());
  [view addSubview:dateNote];
  y += 32 + DTRowGap;

  zoneNote = DTLabel (NSMakeRect (DTMargin, y, width, 16), nil,
                      DTSmallFont ());
  [view addSubview:zoneNote];
  return view;
}

- (NSView *)timeZoneTab:(NSRect)frame
{
  DTFlippedView *view = AUTORELEASE ([[DTFlippedView alloc]
                                       initWithFrame:frame]);
  CGFloat width = NSWidth (frame) - 2 * DTMargin, y = DTMargin - 6;
  NSScrollView *scroll;
  NSTableColumn *column;
  NSString *const ids[] = { @"city", @"country", @"comment" };
  NSString *const titles[] = { @"Time Zone", @"Country", @"Region" };
  const CGFloat widths[] = { 130, 130, 180 };
  int i;

  zoneLabel = DTLabel (NSMakeRect (DTMargin, y, width, 20), nil,
                       [NSFont boldSystemFontOfSize:13]);
  [view addSubview:zoneLabel];
  y += 20 + DTRowGap;

  searchField = AUTORELEASE ([[NSSearchField alloc]
                               initWithFrame:NSMakeRect (DTMargin, y, width,
                                                         24)]);
  [searchField setDelegate:self];
  [view addSubview:searchField];
  y += 24 + DTRowGap;

  scroll = AUTORELEASE ([[NSScrollView alloc]
                          initWithFrame:NSMakeRect (DTMargin, y, width,
                                                    NSHeight (frame) - y
                                                    - DTMargin + 6)]);
  [scroll setHasVerticalScroller:YES];
  [scroll setBorderType:NSBezelBorder];
  zoneTable = AUTORELEASE ([[NSTableView alloc]
                             initWithFrame:[[scroll contentView] bounds]]);
  for (i = 0; i < 3; i++)
    {
      column = AUTORELEASE ([[NSTableColumn alloc]
                              initWithIdentifier:ids[i]]);
      [[column headerCell] setStringValue:titles[i]];
      [column setWidth:widths[i]];
      [column setEditable:NO];
      [zoneTable addTableColumn:column];
    }
  [zoneTable setAllowsMultipleSelection:NO];
  [zoneTable setAllowsEmptySelection:YES];
  [zoneTable setDataSource:self];
  [zoneTable setDelegate:self];
  [zoneTable setTarget:self];
  [zoneTable setAction:@selector (chooseZone:)];
  [scroll setDocumentView:zoneTable];
  [view addSubview:scroll];
  return view;
}

- (NSView *)clockTab:(NSRect)frame
{
  DTFlippedView *view = AUTORELEASE ([[DTFlippedView alloc]
                                       initWithFrame:frame]);
  CGFloat width = NSWidth (frame) - 2 * DTMargin, y = DTMargin;
  NSEnumerator *e;
  NSString *dir;

  /* The Dock's clock extra, wherever the Dock looks for extras. */
  e = [NSSearchPathForDirectoriesInDomains (NSLibraryDirectory,
                                            NSAllDomainsMask, YES)
          objectEnumerator];
  while ((dir = [e nextObject]) != nil && !clockInstalled)
    clockInstalled = [[NSFileManager defaultManager]
        fileExistsAtPath:[dir stringByAppendingPathComponent:
                                @"DockExtras/Clock.dockextra"]];

  showInDockButton = DTCheckbox (NSMakeRect (DTMargin, y, width, 22),
                                 @"Show date and time in Dock", self,
                                 @selector (toggleShowInDock:));
  [showInDockButton setEnabled:clockInstalled];
  [view addSubview:showInDockButton];
  y += 22 + DTRowGap;

  [view addSubview:DTRowLabel (y, @"Style:")];
  stylePopup = AUTORELEASE ([[NSPopUpButton alloc]
                              initWithFrame:NSMakeRect (DTFieldX, y, 140, 24)
                                  pullsDown:NO]);
  [stylePopup addItemWithTitle:@"Digital"];
  [stylePopup addItemWithTitle:@"Analog"];
  [stylePopup setTarget:self];
  [stylePopup setAction:@selector (chooseStyle:)];
  [view addSubview:stylePopup];
  y += 24 + DTRowGap;

  hour24Button = DTCheckbox (NSMakeRect (DTFieldX, y, 260, 22),
                             @"Use a 24-hour clock", self,
                             @selector (toggleClock:));
  [view addSubview:hour24Button];
  y += 22 + 4;
  secondsButton = DTCheckbox (NSMakeRect (DTFieldX, y, 260, 22),
                              @"Show the seconds", self,
                              @selector (toggleClock:));
  [view addSubview:secondsButton];
  y += 22 + 4;
  showDateButton = DTCheckbox (NSMakeRect (DTFieldX, y, 260, 22),
                               @"Show the date", self,
                               @selector (toggleClock:));
  [view addSubview:showDateButton];
  y += 22 + 2 * DTRowGap;

  [view addSubview:DTLabel (NSMakeRect (DTMargin, y, width, 32),
                            clockInstalled
                              ? @"The Dock's clock changes at once. These "
                                @"settings need no password."
                              : @"The Dock's clock isn't installed; these "
                                @"settings are kept for when it is.",
                            DTSmallFont ())];
  return view;
}

/* The lock at the left, Defaults and Revert at the right. */
- (NSView *)bottomRow
{
  CGFloat width = DTWindowWidth - 2 * DTMargin;
  DTFlippedView *row = AUTORELEASE ([[DTFlippedView alloc]
                                      initWithFrame:NSMakeRect (0, 0, width,
                                                                30)]);
  NSButton *defaults, *revert;

  [lockView setFrameOrigin:NSMakePoint (0, 0)];
  [row addSubview:lockView];

  revert = AUTORELEASE ([[NSButton alloc]
                          initWithFrame:NSMakeRect (width - DTButtonWidth, 2,
                                                    DTButtonWidth,
                                                    DTButtonHeight)]);
  [revert setTitle:@"Revert"];
  [revert setTarget:self];
  [revert setAction:@selector (revert:)];
  [row addSubview:revert];

  defaults = AUTORELEASE ([[NSButton alloc]
                            initWithFrame:NSMakeRect (width - 2 * DTButtonWidth
                                                      - 8, 2, DTButtonWidth,
                                                      DTButtonHeight)]);
  [defaults setTitle:@"Defaults"];
  [defaults setTarget:self];
  [defaults setAction:@selector (useDefaults:)];
  [row addSubview:defaults];
  return row;
}

/* ---- following the system ---- */

/* Every second: the lock's time, the clock, and anything changed
   elsewhere. */
- (void)tick:(NSTimer *)t
{
  [lockView update];
  if (dockAskedAt != 0
      && [NSDate timeIntervalSinceReferenceDate] - dockAskedAt
         > DTDockAnswerSeconds)
    {
      /* No Dock running: its list is ours to write. */
      NSMutableArray *hidden = [NSMutableArray arrayWithArray:
          [[self dockDomain] objectForKey:DTDockHiddenKey]];

      dockAskedAt = 0;
      [hidden removeObject:DTClockExtra];
      if (dockAskedHidden)
        [hidden addObject:DTClockExtra];
      [self writeDockValues:[NSDictionary dictionaryWithObject:hidden
                                                        forKey:DTDockHiddenKey]
                     notify:NO];
    }
  [self reload];
  [self updateClockFields];
}

/* Read everything again, and set the controls if anything shown
   changed. */
- (void)reload
{
  NSString *zone = DTCurrentZoneName (), *state;

  if (!(zone == zoneName || [zone isEqual:zoneName]))
    {
      /* Set by tzsetup or another app: this process follows too.
         FreeBSD's tzset() reads /etc/localtime again only about once a
         minute; setting TZ and taking it away makes it read it now. */
      ASSIGN (zoneName, zone);
      if (getenv ("TZ") == NULL)
        {
          setenv ("TZ", "UTC0", 1);
          tzset ();
          unsetenv ("TZ");
        }
      tzset ();
      [NSTimeZone resetSystemTimeZone];
    }
  if ([NSDate timeIntervalSinceReferenceDate] < expectedUntil)
    networkTime = expectedNetworkTime;
  else
    networkTime = DTNetworkTimeRunning () != 0;
  ASSIGN (server, [self readServer]);
  ASSIGN (clock, [self readClock]);
  if (dockAskedAt == 0)
    dockHidden = [self readDockHidden];
  state = [NSString stringWithFormat:@"%@ %d %@ %@ %d %d %d", zoneName,
                    (int) networkTime, server, clock, (int) dockHidden,
                    (int) [lockView isUnlocked], [auth status]];
  if ([state isEqual:shownState])
    return;
  ASSIGN (shownState, state);
  [self updateControls];
}

- (void)updateControls
{
  BOOL unlocked = [lockView isUnlocked];
  NSTimeZone *zone = [self zone];

  [automaticButton setState:networkTime ? NSOnState : NSOffState];
  [automaticButton setEnabled:unlocked];
  if (![self isEditing:serverBox])
    [serverBox setStringValue:server != nil ? server : @""];
  [serverBox setEnabled:unlocked];
  [dateField setEnabled:unlocked && !networkTime];
  [timeField setEnabled:unlocked && !networkTime];
  if (networkTime)
    [dateNote setStringValue:@"The date and time are kept right by the "
                             @"time server. Turn that off to set them "
                             @"by hand."];
  else
    [dateNote setStringValue:@"Type the date or time and press Return to "
                             @"set the clock."];
  [zoneNote setStringValue:
      [NSString stringWithFormat:@"Time zone: %@ (%@).",
                zoneName != nil ? zoneName : @"not set",
                DTZoneOffset (zone)]];

  [zoneLabel setStringValue:
      zoneName != nil
        ? [NSString stringWithFormat:@"%@ — %@", zoneName,
                    DTZoneOffset (zone)]
        : @"No time zone has been chosen."];
  [self selectCurrentZone];

  [showInDockButton setState:dockHidden ? NSOffState : NSOnState];
  [stylePopup selectItemAtIndex:
                [[clock objectForKey:DTAnalogKey] boolValue] ? 1 : 0];
  [hour24Button setState:[[clock objectForKey:DT24HourKey] boolValue]
                ? NSOnState : NSOffState];
  [secondsButton setState:[[clock objectForKey:DTSecondsKey] boolValue]
                 ? NSOnState : NSOffState];
  [showDateButton setState:[[clock objectForKey:DTShowDateKey] boolValue]
                  ? NSOnState : NSOffState];
}

/* The date and time fields tick, except while one is being typed in. */
- (void)updateClockFields
{
  NSCalendarDate *now = [NSCalendarDate calendarDate];

  [now setTimeZone:[self zone]];
  if (![self isEditing:dateField])
    [dateField setStringValue:[now descriptionWithCalendarFormat:@"%Y-%m-%d"]];
  if (![self isEditing:timeField])
    [timeField setStringValue:[now descriptionWithCalendarFormat:@"%H:%M:%S"]];
}

- (BOOL)isEditing:(NSTextField *)field
{
  id responder = [window firstResponder];

  return [responder isKindOfClass:[NSText class]]
    && [(NSText *) responder delegate] == (id) field;
}

/* The zone recorded, which is the one /etc/localtime holds; GNUstep's
   own guess from the file's contents may pick another name for it. */
- (NSTimeZone *)zone
{
  NSTimeZone *zone = nil;

  if (zoneName != nil)
    zone = [NSTimeZone timeZoneWithName:zoneName];
  return zone != nil ? zone : [NSTimeZone systemTimeZone];
}

/* ntp.conf's first server or pool: the one the window shows. */
- (NSString *)readServer
{
  NSString *text = [NSString stringWithContentsOfFile:DTNTPConf];
  NSEnumerator *e = [[text componentsSeparatedByString:@"\n"]
                       objectEnumerator];
  NSString *line;

  while ((line = [e nextObject]) != nil)
    {
      NSMutableArray *words = [NSMutableArray array];
      NSEnumerator *w = [[line componentsSeparatedByCharactersInSet:
                            [NSCharacterSet whitespaceCharacterSet]]
                           objectEnumerator];
      NSString *word;

      while ((word = [w nextObject]) != nil)
        if ([word length] > 0)
          [words addObject:word];
      if ([words count] >= 2
          && ([[words objectAtIndex:0] isEqual:@"server"]
              || [[words objectAtIndex:0] isEqual:@"pool"]))
        return [words objectAtIndex:1];
    }
  return nil;
}

/* ---- the Dock's clock ---- */

/* The Dock's defaults, read from its file: NSUserDefaults in a running
   app doesn't see another process's change to a domain outside its own
   search list. */
- (NSDictionary *)dockDomain
{
  NSString *path = [[GSDefaultsRootForUser (NSUserName ())
                      stringByAppendingPathComponent:DTDockDomain]
                     stringByAppendingPathExtension:@"plist"];
  NSDictionary *domain = [NSDictionary dictionaryWithContentsOfFile:path];

  return domain != nil ? domain : [NSDictionary dictionary];
}

/* The four settings as the clock sees them: the Dock's value, else the
   clock's default. */
- (NSDictionary *)readClock
{
  NSDictionary *dock = [self dockDomain];
  NSMutableDictionary *values = [NSMutableDictionary
                                  dictionaryWithDictionary:DTClockDefaults ()];
  NSEnumerator *e = [DTClockKeys () objectEnumerator];
  NSString *key;

  while ((key = [e nextObject]) != nil)
    {
      id value = [dock objectForKey:key];

      if ([value respondsToSelector:@selector (boolValue)])
        [values setObject:[NSNumber numberWithBool:[value boolValue]]
                   forKey:key];
    }
  return values;
}

/* Set the clock's settings: a value per key, NSNull to unset it (the
   clock's default). Only these keys are written: GNUstep merges a
   domain into its file key by key, so the Dock's other settings, which
   the Dock writes itself, are left alone. */
- (void)writeClock:(NSDictionary *)values
{
  [self writeDockValues:values notify:YES];
}

/* Write these keys of the Dock's domain (NSNull: unset), and say so to
   the clock unless asked not to. */
- (void)writeDockValues:(NSDictionary *)values notify:(BOOL)notify
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSDictionary *disk = [self dockDomain];
  NSMutableDictionary *domain = [NSMutableDictionary dictionaryWithDictionary:
                                                       disk];
  NSEnumerator *e = [values keyEnumerator];
  NSString *key;

  /* First what's on disk, so that only the keys below differ from it. */
  [defaults setPersistentDomain:disk forName:DTDockDomain];
  while ((key = [e nextObject]) != nil)
    {
      id value = [values objectForKey:key];

      if (value == [NSNull null])
        [domain removeObjectForKey:key];
      else
        [domain setObject:value forKey:key];
    }
  [defaults setPersistentDomain:domain forName:DTDockDomain];
  [defaults synchronize];
  if (notify)
    [[NSDistributedNotificationCenter defaultCenter]
      postNotificationName:DTSettingsChanged
                    object:nil
                  userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
                                           DTDockDomain, @"domain",
                                           [values allKeys], @"keys", nil]
        deliverImmediately:YES];
  [self reload];
}

/* The clock's own menu changed its settings. */
- (void)settingsChanged:(NSNotification *)note
{
  if ([[[note userInfo] objectForKey:@"domain"] isEqual:DTDockDomain])
    [self reload];
}

- (BOOL)readDockHidden
{
  id hidden = [[self dockDomain] objectForKey:DTDockHiddenKey];

  return [hidden isKindOfClass:[NSArray class]]
    && [hidden containsObject:DTClockExtra];
}

/* Ask the Dock, which owns the list (apps-dock DockExtrasSettings.h). */
- (void)setDockHidden:(BOOL)hidden
{
  if (hidden == [self readDockHidden] && dockAskedAt == 0)
    return;
  dockHidden = hidden;
  dockAskedHidden = hidden;
  dockAskedAt = [NSDate timeIntervalSinceReferenceDate];
  [[NSDistributedNotificationCenter defaultCenter]
      postNotificationName:DTDockSetHidden
                    object:nil
                  userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
                                           DTClockExtra, @"identifier",
                                           [NSNumber numberWithBool:hidden],
                                           @"hidden", nil]
        deliverImmediately:YES];
}

/* The Dock's answer, and its own Settings -> Extras: userInfo "hidden"
   is the new DockExtrasHidden. */
- (void)dockChanged:(NSNotification *)note
{
  id hidden = [[note userInfo] objectForKey:@"hidden"];

  dockAskedAt = 0;
  if ([hidden isKindOfClass:[NSArray class]])
    dockHidden = [hidden containsObject:DTClockExtra];
  else
    dockHidden = [self readDockHidden];
  DESTROY (shownState);
  [self reload];
}

- (void)toggleShowInDock:(id)sender
{
  [self setDockHidden:[sender state] != NSOnState];
}

/* ---- the zone list ---- */

- (void)filterZones
{
  NSMutableArray *words = [NSMutableArray array];
  NSEnumerator *e;
  NSString *word;
  DTZone *zone;

  e = [[[[searchField stringValue] lowercaseString]
         componentsSeparatedByString:@" "] objectEnumerator];
  while ((word = [e nextObject]) != nil)
    if ([word length] > 0)
      [words addObject:word];
  [shownZones removeAllObjects];
  e = [allZones objectEnumerator];
  while ((zone = [e nextObject]) != nil)
    if ([zone matches:words])
      [shownZones addObject:zone];
  /* A zone that zone.tab doesn't list (Etc/GMT+5), when it's the one
     set. */
  if (zoneName != nil && [words count] == 0)
    {
      BOOL listed = NO;
      NSUInteger i;

      for (i = 0; i < [allZones count] && !listed; i++)
        listed = [[[allZones objectAtIndex:i] name] isEqual:zoneName];
      if (!listed)
        [shownZones insertObject:DTZoneNamed (zoneName) atIndex:0];
    }
  [zoneTable reloadData];
  [self selectCurrentZone];
}

- (void)selectCurrentZone
{
  NSUInteger i;

  selectingZone = YES;
  [zoneTable deselectAll:self];
  for (i = 0; i < [shownZones count]; i++)
    if ([[[shownZones objectAtIndex:i] name] isEqual:zoneName])
      {
        [zoneTable selectRow:i byExtendingSelection:NO];
        break;
      }
  selectingZone = NO;
}

/* ---- changes ---- */

- (int)perform:(int)op value:(id)value
{
  switch (op)
    {
    case DTOpTimeZone:
      return [NBSettingsHelper setTimeZone:value authorization:auth];
    case DTOpDate:
      return [NBSettingsHelper setDate:value authorization:auth];
    case DTOpNetworkTime:
      return [NBSettingsHelper
                setNetworkTime:[[value objectForKey:@"enabled"] boolValue]
                        server:[value objectForKey:@"server"]
                 authorization:auth];
    }
  return NBAuthorizationInvalid;
}

/* Through the helper, unlocking first if the lock was open but the
   right ran out. */
- (BOOL)apply:(int)op value:(id)value
{
  int status = [self perform:op value:value];

  if (status == NBAuthorizationNeeded)
    {
      /* The helper no longer holds the right (it ran out, or the helper
         was restarted): close the lock, then ask. */
      [auth refresh];
      [lockView update];
      if ([lockView unlock])
        status = [self perform:op value:value];
      else
        return NO;		/* cancelled: nothing to say */
    }
  if (status == NBAuthorizationInvalid && op == DTOpNetworkTime)
    NSRunAlertPanel (@"Date & Time", @"\"%@\" isn't a time server's name "
                     @"or address.", @"OK", nil, nil,
                     [value objectForKey:@"server"]);
  else if (status != NBAuthorizationOK)
    NSRunAlertPanel (@"Date & Time", @"%@", @"OK", nil, nil,
                     [NBAuthorization messageForStatus:status]);
  if (status == NBAuthorizationOK && op == DTOpNetworkTime)
    {
      expectedNetworkTime = [[value objectForKey:@"enabled"] boolValue];
      expectedUntil = [NSDate timeIntervalSinceReferenceDate]
        + DTNetworkTimeSettle;
    }
  return status == NBAuthorizationOK;
}

- (void)toggleAutomatic:(id)sender
{
  [self apply:DTOpNetworkTime
        value:[NSDictionary dictionaryWithObject:
                 [NSNumber numberWithBool:[sender state] == NSOnState]
                                          forKey:@"enabled"]];
  DESTROY (shownState);
  [self reload];
}

- (void)chooseServer:(id)sender
{
  NSString *name = [[serverBox stringValue]
                     stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceCharacterSet]];

  if ([name length] == 0 || [name isEqual:server])
    {
      DESTROY (shownState);	/* put the box back */
      [self reload];
      return;
    }
  /* Choosing a server turns network time on, as on macOS. */
  [self apply:DTOpNetworkTime
        value:[NSDictionary dictionaryWithObjectsAndKeys:
                              [NSNumber numberWithBool:YES], @"enabled",
                              name, @"server", nil]];
  [window makeFirstResponder:nil];
  DESTROY (shownState);
  [self reload];
}

- (void)setDateAndTime:(id)sender
{
  NSScanner *date = [NSScanner scannerWithString:[dateField stringValue]];
  NSScanner *time = [NSScanner scannerWithString:[timeField stringValue]];
  NSCalendarDate *when;
  int year, month, day, hour, minute, second = 0;

  if (!DTScanPart (date, &year, @"-") || !DTScanPart (date, &month, @"-")
      || !DTScanPart (date, &day, nil) || ![date isAtEnd]
      || !DTScanPart (time, &hour, @":") || !DTScanPart (time, &minute, @":")
      || (![time isAtEnd] && !DTScanPart (time, &second, nil))
      || ![time isAtEnd]
      || year < 2001 || year > 2099 || month < 1 || month > 12
      || day < 1 || day > 31 || hour < 0 || hour > 23 || minute < 0
      || minute > 59 || second < 0 || second > 59)
    {
      NSRunAlertPanel (@"Date & Time", @"Type the date as year-month-day "
                       @"(2026-11-18) and the time as hours:minutes:seconds "
                       @"(14:05:00).", @"OK", nil, nil);
      return;
    }
  when = [NSCalendarDate dateWithYear:year month:month day:day hour:hour
                               minute:minute second:second
                             timeZone:[self zone]];
  if ([when dayOfMonth] != day)
    {
      NSRunAlertPanel (@"Date & Time", @"There's no %d-%02d-%02d.", @"OK",
                       nil, nil, year, month, day);
      return;
    }
  [self apply:DTOpDate value:when];
  [window makeFirstResponder:nil];
  [self updateClockFields];
}

- (void)chooseZone:(id)sender
{
  NSInteger row = [zoneTable selectedRow];
  NSString *name;

  if (row < 0 || row >= (NSInteger) [shownZones count]
      || ![lockView isUnlocked])
    return;
  name = [[shownZones objectAtIndex:row] name];
  if (![name isEqual:zoneName])
    [self apply:DTOpTimeZone value:name];
  DESTROY (shownState);
  [self reload];
  [self updateClockFields];
}

- (void)chooseStyle:(id)sender
{
  [self writeClock:[NSDictionary dictionaryWithObject:
                      [NSNumber numberWithBool:[sender indexOfSelectedItem]
                                                 == 1]
                                               forKey:DTAnalogKey]];
}

- (void)toggleClock:(id)sender
{
  NSString *key = sender == hour24Button ? DT24HourKey
    : sender == secondsButton ? DTSecondsKey : DTShowDateKey;

  [self writeClock:[NSDictionary dictionaryWithObject:
                      [NSNumber numberWithBool:[sender state] == NSOnState]
                                               forKey:key]];
}

/* The clock's own defaults and shown in the Dock, and network time on. The time zone has no
   default: it stays. */
- (void)useDefaults:(id)sender
{
  NSMutableDictionary *unset = [NSMutableDictionary dictionary];
  NSEnumerator *e = [DTClockKeys () objectEnumerator];
  NSString *key;

  while ((key = [e nextObject]) != nil)
    [unset setObject:[NSNull null] forKey:key];
  [self writeClock:unset];
  if (clockInstalled)
    [self setDockHidden:NO];
  if (!networkTime && [lockView unlock])
    [self apply:DTOpNetworkTime
          value:[NSDictionary dictionaryWithObject:
                   [NSNumber numberWithBool:YES] forKey:@"enabled"]];
  DESTROY (shownState);
  [self reload];
}

/* Back to the settings from when the window opened. */
- (void)revert:(id)sender
{
  NSMutableDictionary *values = [NSMutableDictionary dictionary];
  NSEnumerator *e = [DTClockKeys () objectEnumerator];
  NSString *key;
  BOOL serverChanged = originalServer != nil
    && ![originalServer isEqual:server];

  while ((key = [e nextObject]) != nil)
    {
      id value = [originalClock objectForKey:key];
      [values setObject:value != nil ? value : (id) [NSNull null] forKey:key];
    }
  [self writeClock:values];
  if (clockInstalled)
    [self setDockHidden:originalDockHidden];

  if ((originalZone != nil && ![originalZone isEqual:zoneName])
      || originalNetworkTime != networkTime || serverChanged)
    {
      if (![lockView unlock])
        return;
      if (originalZone != nil && ![originalZone isEqual:zoneName]
          && ![self apply:DTOpTimeZone value:originalZone])
        return;
      if (originalNetworkTime != networkTime || serverChanged)
        {
          NSMutableDictionary *ntp = [NSMutableDictionary dictionaryWithObject:
              [NSNumber numberWithBool:originalNetworkTime] forKey:@"enabled"];
          if (serverChanged)
            [ntp setObject:originalServer forKey:@"server"];
          [self apply:DTOpNetworkTime value:ntp];
        }
    }
  DESTROY (shownState);
  [self reload];
  [self updateClockFields];
}

@end
