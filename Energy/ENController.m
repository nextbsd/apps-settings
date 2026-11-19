/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "ENController.h"
#import "NBSettingsHelper.h"
#import <GNUstepBase/GNUstep.h>

/* Layout, in points, as Displays'. */
#define ENMargin 20.0
#define ENWindowWidth 560.0
#define ENRowGap 10.0
#define ENLabelWidth 230.0	/* "Put the computer to sleep after:" */
#define ENPopupWidth 150.0
#define ENButtonWidth 100.0
#define ENButtonHeight 26.0
/* The lock and its sentence, beside Defaults and Revert. */
#define ENLockWidth (ENWindowWidth - 2 * ENMargin - 2 * ENButtonWidth - 16)

/* The popups' tags: which power source. */
#define ENSourceAC 0
#define ENSourceBattery 1

static NSString *const ENRight = @"org.nextbsd.settings.energy";
static NSString *const ENReason = @"change the Energy settings";

/* The Dock's battery extra and its settings (apps-dock). */
static NSString *const ENDockDomain = @"Dock";
static NSString *const ENDockHiddenKey = @"DockExtrasHidden";
static NSString *const ENBatteryExtra = @"org.nextbsd.dockextra.battery";
static NSString *const ENDockSetHidden = @"org.nextbsd.Dock.SetExtraHidden";
static NSString *const ENDockChanged = @"org.nextbsd.Dock.ExtrasChanged";
#define ENDockAnswerSeconds 2.0

/* The timers' choices, in minutes; 0 is Never. */
static const int ENMinutes[] = { 1, 2, 3, 5, 10, 15, 20, 30, 45, 60, 120,
                                 180, 0 };
#define ENMinutesCount (sizeof (ENMinutes) / sizeof (ENMinutes[0]))

/* A view laid out from the top down. */
@interface ENFlippedView : NSView
@end

@implementation ENFlippedView
- (BOOL)isFlipped
{
  return YES;
}
@end

static NSTextField *
ENLabel (NSRect frame, NSString *text, NSFont *font)
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
ENRowLabel (CGFloat y, NSString *text)
{
  NSTextField *label = ENLabel (NSMakeRect (0, y + 3, ENLabelWidth, 20), text,
                                nil);
  [label setAlignment:NSRightTextAlignment];
  return label;
}

static NSFont *
ENSmallFont (void)
{
  return [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
}

/* A NeXT-style group: a titled box around inner. */
static NSBox *
ENGroup (NSString *title, NSView *inner, CGFloat width)
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

static CGFloat
ENGroupInnerWidth (void)
{
  NSBox *box = AUTORELEASE ([[NSBox alloc]
                              initWithFrame:NSMakeRect (0, 0, 400, 100)]);
  [box setTitle:@"X"];
  [box setTitlePosition:NSAtTop];
  [box setBorderType:NSGrooveBorder];
  [box setContentViewMargins:NSMakeSize (12, 10)];
  return ENWindowWidth - 2 * ENMargin
    - (400 - NSWidth ([[box contentView] frame]));
}

static NSString *
ENMinutesTitle (int minutes)
{
  if (minutes == 0)
    return @"Never";
  if (minutes % 60 == 0)
    return minutes == 60 ? @"1 hour"
      : [NSString stringWithFormat:@"%d hours", minutes / 60];
  return minutes == 1 ? @"1 minute"
    : [NSString stringWithFormat:@"%d minutes", minutes];
}

static NSString *
ENDuration (int minutes)
{
  return [NSString stringWithFormat:@"%d:%02d", minutes / 60, minutes % 60];
}

@interface ENController (Private)
- (void)buildMenu;
- (void)tick:(NSTimer *)t;
- (void)reload;
- (void)refresh;
- (void)rebuildContent;
- (NSView *)batterySection:(CGFloat)width;
- (NSView *)sourceSection:(int)source width:(CGFloat)width;
- (NSPopUpButton *)timerPopup:(int)minutes y:(CGFloat)y source:(int)source
                       action:(SEL)action;
- (NSView *)bottomRow;
- (NSDictionary *)dockDomain;
- (BOOL)readDockHidden;
- (void)setDockHidden:(BOOL)hidden;
- (void)dockChanged:(NSNotification *)note;
- (BOOL)set:(NSDictionary *)values source:(int)source;
- (void)chooseDisplaySleep:(id)sender;
- (void)chooseSystemSleep:(id)sender;
- (void)toggleWake:(id)sender;
- (void)toggleDock:(id)sender;
- (void)useDefaults:(id)sender;
- (void)revert:(id)sender;
@end

@implementation ENController

- (void)dealloc
{
  [[NSDistributedNotificationCenter defaultCenter] removeObserver:self];
  [timer invalidate];
  RELEASE (timer);
  RELEASE (window);
  RELEASE (auth);
  RELEASE (lockView);
  RELEASE (shownState);
  [super dealloc];
}

- (void)applicationDidFinishLaunching:(NSNotification *)note
{
  NSImage *icon = [NSImage imageNamed:@"Energy.png"];
  NSEnumerator *e;
  NSString *dir;

  if (icon != nil)
    [NSApp setApplicationIconImage:icon];
  [self buildMenu];
  window = [[NSWindow alloc]
      initWithContentRect:NSMakeRect (200, 200, ENWindowWidth, 300)
                styleMask:NSTitledWindowMask | NSClosableWindowMask
                          | NSMiniaturizableWindowMask
                  backing:NSBackingStoreBuffered
                    defer:NO];
  [window setTitle:@"Energy"];
  [window setReleasedWhenClosed:NO];
  [window setFrameAutosaveName:@"Energy"];

  /* The Dock's battery extra, wherever the Dock looks for extras. */
  e = [NSSearchPathForDirectoriesInDomains (NSLibraryDirectory,
                                            NSAllDomainsMask, YES)
          objectEnumerator];
  while ((dir = [e nextObject]) != nil && !dockExtraInstalled)
    dockExtraInstalled = [[NSFileManager defaultManager]
        fileExistsAtPath:[dir stringByAppendingPathComponent:
                                @"DockExtras/Battery.dockextra"]];
  [[NSDistributedNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector (dockChanged:)
             name:ENDockChanged
           object:nil];

  auth = RETAIN ([NBAuthorization authorizationWithRight:ENRight]);
  lockView = [[NBLockView alloc]
                initWithFrame:NSMakeRect (0, 0, ENLockWidth, 30)
                authorization:auth
                       reason:ENReason];
  [lockView setDelegate:self];

  ENWatchStart ();
  ENReadSettings (&original);
  originalDockHidden = [self readDockHidden];
  [self reload];
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

/* Energy has no documents; a file it's asked to open (Workspace's Open
   With) just brings the window forward. */
- (BOOL)application:(NSApplication *)app openFile:(NSString *)filename
{
  [window makeKeyAndOrderFront:self];
  return YES;
}

- (void)lockViewDidChange:(NBLockView *)view
{
  [self refresh];
}

@end

@implementation ENController (Private)

- (void)buildMenu
{
  NSMenu *menu = AUTORELEASE ([[NSMenu alloc] initWithTitle:@"Energy"]);
  NSMenu *windows = AUTORELEASE ([[NSMenu alloc] initWithTitle:@"Window"]);
  id<NSMenuItem> item;

  [menu addItemWithTitle:@"About Energy"
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

/* Every second: the lock's time, powerd's notifications, and a Dock
   that never answered. */
- (void)tick:(NSTimer *)t
{
  [lockView update];
  if (dockAskedAt != 0
      && [NSDate timeIntervalSinceReferenceDate] - dockAskedAt
         > ENDockAnswerSeconds)
    {
      /* No Dock running: its defaults are ours to write. */
      NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
      NSMutableDictionary *domain = [NSMutableDictionary dictionaryWithDictionary:
          [self dockDomain]];
      NSMutableArray *hidden = [NSMutableArray arrayWithArray:
          [domain objectForKey:ENDockHiddenKey]];

      dockAskedAt = 0;
      [hidden removeObject:ENBatteryExtra];
      if (dockAskedHidden)
        [hidden addObject:ENBatteryExtra];
      [domain setObject:hidden forKey:ENDockHiddenKey];
      [defaults setPersistentDomain:domain forName:ENDockDomain];
      [defaults synchronize];
      [self refresh];
    }
  if (ENWatchChanged ())
    [self reload];
}

/* Read everything again, and rebuild the window if anything shown
   changed. */
- (void)reload
{
  NSString *state;

  ENReadSettings (&settings);
  ENReadBattery (&battery);
  if (dockAskedAt == 0)
    dockHidden = [self readDockHidden];
  state = [NSString stringWithFormat:
      @"%d %d/%d/%d/%d %d/%d/%d/%d | %d %d %d %d %d %d %d %s %d %d %d | %d %d %d",
      settings.sleepSupported,
      settings.ac.present, settings.ac.displaySleep, settings.ac.systemSleep,
      settings.ac.wakeOnLAN,
      settings.battery.present, settings.battery.displaySleep,
      settings.battery.systemSleep, settings.battery.wakeOnLAN,
      battery.present, battery.percent, battery.charging, battery.charged,
      battery.onAC, battery.minutesToEmpty, battery.minutesToFull,
      battery.health, battery.maxCapacity, battery.designCapacity,
      battery.cycleCount,
      (int) dockHidden, (int) [lockView isUnlocked], [auth status]];
  if ([state isEqual:shownState])
    return;
  ASSIGN (shownState, state);
  [self rebuildContent];
}

- (void)refresh
{
  DESTROY (shownState);
  [self reload];
}

- (void)rebuildContent
{
  ENFlippedView *content;
  NSMutableArray *sections = [NSMutableArray array];
  CGFloat inner = ENGroupInnerWidth (), width = ENWindowWidth - 2 * ENMargin;
  CGFloat height, y;
  NSView *bottom;
  NSRect frame, newFrame;
  NSUInteger i;

  if (battery.present)
    [sections addObject:ENGroup (@"Battery", [self batterySection:inner],
                                 width)];
  if (settings.battery.present)
    [sections addObject:ENGroup (@"On Battery",
                                 [self sourceSection:ENSourceBattery
                                               width:inner], width)];
  if (settings.ac.present)
    [sections addObject:ENGroup (settings.battery.present
                                   ? @"On Power Adapter" : @"Sleep",
                                 [self sourceSection:ENSourceAC width:inner],
                                 width)];
  bottom = [self bottomRow];

  height = ENMargin;
  for (i = 0; i < [sections count]; i++)
    height += NSHeight ([[sections objectAtIndex:i] frame]) + ENRowGap;
  height += 6 + NSHeight ([bottom frame]) + ENMargin;

  content = AUTORELEASE ([[ENFlippedView alloc]
                           initWithFrame:NSMakeRect (0, 0, ENWindowWidth,
                                                     height)]);
  y = ENMargin;
  for (i = 0; i < [sections count]; i++)
    {
      NSView *section = [sections objectAtIndex:i];
      [section setFrameOrigin:NSMakePoint (ENMargin, y)];
      [content addSubview:section];
      y += NSHeight ([section frame]) + ENRowGap;
    }
  [bottom setFrameOrigin:NSMakePoint (ENMargin, y + 6)];
  [content addSubview:bottom];

  /* Keep the window's top left where it is. */
  frame = [window frame];
  newFrame = [window frameRectForContentRect:
                       NSMakeRect (0, 0, ENWindowWidth, height)];
  newFrame.origin.x = frame.origin.x;
  newFrame.origin.y = NSMaxY (frame) - newFrame.size.height;
  [window setContentView:content];
  [window setFrame:newFrame display:YES];
}

/* ---- the sections ---- */

- (NSView *)batterySection:(CGFloat)width
{
  ENFlippedView *view = AUTORELEASE ([[ENFlippedView alloc]
                                       initWithFrame:NSMakeRect (0, 0, width, 10)]);
  NSMutableString *charge, *condition;
  NSImageView *icon;
  CGFloat y = 0, textX = 48 + 12, textW = width - textX;
  int health = 0;

  icon = AUTORELEASE ([[NSImageView alloc]
                        initWithFrame:NSMakeRect (0, 0, 48, 48)]);
  [icon setImage:[NSApp applicationIconImage]];
  [icon setImageScaling:NSScaleProportionally];
  [icon setEditable:NO];
  [view addSubview:icon];

  charge = [NSMutableString stringWithFormat:@"%d%%", battery.percent];
  if (battery.charging)
    {
      [charge appendString:@", charging"];
      if (battery.minutesToFull > 0)
        [charge appendFormat:@", %@ until full",
                ENDuration (battery.minutesToFull)];
    }
  else if (battery.charged && battery.onAC)
    [charge appendString:@", charged"];
  else if (!battery.onAC && battery.minutesToEmpty > 0)
    [charge appendFormat:@", %@ left", ENDuration (battery.minutesToEmpty)];
  [view addSubview:ENLabel (NSMakeRect (textX, y, textW, 20), charge,
                            [NSFont boldSystemFontOfSize:14])];
  [view addSubview:ENLabel (NSMakeRect (textX, y + 20, textW, 16),
                            battery.onAC ? @"Running on the power adapter."
                                         : @"Running on the battery.",
                            ENSmallFont ())];

  /* Condition: powerd's word for it if it has one, else from the
     capacity left against the design. */
  if (battery.designCapacity > 0 && battery.maxCapacity > 0)
    health = (int) ((battery.maxCapacity * 100.0) / battery.designCapacity
                    + 0.5);
  if (battery.health[0] != '\0')
    condition = [NSMutableString stringWithFormat:@"Condition: %s.",
                                 battery.health];
  else if (health > 0)
    condition = [NSMutableString stringWithString:
                   health >= 80 ? @"Condition: Normal."
                                : @"Condition: Service recommended."];
  else
    condition = [NSMutableString stringWithString:@"Condition: unknown."];
  if (health > 0)
    [condition appendFormat:@" Maximum capacity %d%% of new (%d of %d mAh).",
               health, battery.maxCapacity, battery.designCapacity];
  if (battery.cycleCount >= 0)
    [condition appendFormat:@" Cycle count %d.", battery.cycleCount];
  [view addSubview:ENLabel (NSMakeRect (textX, y + 36, textW, 16), condition,
                            ENSmallFont ())];
  y += 48 + ENRowGap;

  if (dockExtraInstalled)
    {
      NSButton *dock = AUTORELEASE ([[NSButton alloc]
                                      initWithFrame:NSMakeRect (textX, y, 260,
                                                                22)]);
      [dock setButtonType:NSSwitchButton];
      [dock setTitle:@"Show battery in Dock"];
      [dock setState:dockHidden ? NSOffState : NSOnState];
      [dock setTarget:self];
      [dock setAction:@selector (toggleDock:)];
      [view addSubview:dock];
      y += 22;
    }

  [view setFrameSize:NSMakeSize (width, y)];
  return view;
}

- (NSPopUpButton *)timerPopup:(int)minutes y:(CGFloat)y source:(int)source
                       action:(SEL)action
{
  NSPopUpButton *popup = AUTORELEASE ([[NSPopUpButton alloc]
      initWithFrame:NSMakeRect (ENLabelWidth + 8, y, ENPopupWidth, 24)
          pullsDown:NO]);
  NSMutableArray *choices = [NSMutableArray array];
  NSUInteger i;

  /* The usual choices, and a value set elsewhere (pmset) in its place;
     Never last. */
  for (i = 0; i < ENMinutesCount; i++)
    if (ENMinutes[i] != 0)
      [choices addObject:[NSNumber numberWithInt:ENMinutes[i]]];
  if (minutes > 0
      && ![choices containsObject:[NSNumber numberWithInt:minutes]])
    {
      [choices addObject:[NSNumber numberWithInt:minutes]];
      [choices sortUsingSelector:@selector (compare:)];
    }
  [choices addObject:[NSNumber numberWithInt:0]];
  for (i = 0; i < [choices count]; i++)
    {
      int m = [[choices objectAtIndex:i] intValue];
      [popup addItemWithTitle:ENMinutesTitle (m)];
      [[popup lastItem] setTag:m];
    }
  [popup selectItemWithTag:minutes];
  [popup setTag:source];
  [popup setTarget:self];
  [popup setAction:action];
  [popup setEnabled:[lockView isUnlocked]];
  return popup;
}

- (NSView *)sourceSection:(int)source width:(CGFloat)width
{
  ENFlippedView *view = AUTORELEASE ([[ENFlippedView alloc]
                                       initWithFrame:NSMakeRect (0, 0, width, 10)]);
  ENSourceSettings *s = source == ENSourceAC ? &settings.ac : &settings.battery;
  NSPopUpButton *popup;
  CGFloat y = 0;

  [view addSubview:ENRowLabel (y, @"Turn the display off after:")];
  [view addSubview:[self timerPopup:s->displaySleep y:y source:source
                             action:@selector (chooseDisplaySleep:)]];
  y += 24 + ENRowGap;

  [view addSubview:ENRowLabel (y, @"Put the computer to sleep after:")];
  popup = [self timerPopup:s->systemSleep y:y source:source
                    action:@selector (chooseSystemSleep:)];
  /* Shown with what's saved, but not offered: it would do nothing. */
  if (!settings.sleepSupported)
    [popup setEnabled:NO];
  [view addSubview:popup];
  y += 24;
  if (!settings.sleepSupported)
    {
      [view addSubview:ENLabel (NSMakeRect (ENLabelWidth + 8, y + 2,
                                            width - ENLabelWidth - 8, 16),
                                @"This computer can't sleep yet.",
                                ENSmallFont ())];
      y += 18;
    }
  y += ENRowGap;

  if (s->wakeOnLAN >= 0)
    {
      NSButton *wake = AUTORELEASE ([[NSButton alloc]
          initWithFrame:NSMakeRect (ENLabelWidth + 8, y,
                                    width - ENLabelWidth - 8, 22)]);
      [wake setButtonType:NSSwitchButton];
      [wake setTitle:@"Wake for network access"];
      [wake setState:s->wakeOnLAN ? NSOnState : NSOffState];
      [wake setTag:source];
      [wake setTarget:self];
      [wake setAction:@selector (toggleWake:)];
      [wake setEnabled:[lockView isUnlocked] && settings.sleepSupported];
      [view addSubview:wake];
      y += 22 + ENRowGap;
    }

  [view setFrameSize:NSMakeSize (width, y - ENRowGap)];
  return view;
}

/* The lock at the left, Defaults and Revert at the right. */
- (NSView *)bottomRow
{
  CGFloat width = ENWindowWidth - 2 * ENMargin;
  ENFlippedView *row = AUTORELEASE ([[ENFlippedView alloc]
                                      initWithFrame:NSMakeRect (0, 0, width,
                                                                30)]);
  NSButton *defaults, *revert;

  [lockView removeFromSuperview];
  [lockView setFrameOrigin:NSMakePoint (0, 0)];
  [row addSubview:lockView];

  revert = AUTORELEASE ([[NSButton alloc]
                          initWithFrame:NSMakeRect (width - ENButtonWidth, 2,
                                                    ENButtonWidth,
                                                    ENButtonHeight)]);
  [revert setTitle:@"Revert"];
  [revert setTarget:self];
  [revert setAction:@selector (revert:)];
  [row addSubview:revert];

  defaults = AUTORELEASE ([[NSButton alloc]
                            initWithFrame:NSMakeRect (width - 2 * ENButtonWidth
                                                      - 8, 2, ENButtonWidth,
                                                      ENButtonHeight)]);
  [defaults setTitle:@"Defaults"];
  [defaults setTarget:self];
  [defaults setAction:@selector (useDefaults:)];
  [row addSubview:defaults];
  return row;
}

/* ---- the Dock ---- */

/* The Dock's list, read from its defaults file: NSUserDefaults in a
   running app doesn't see another process's change to a domain outside
   its own search list. */
- (NSDictionary *)dockDomain
{
  NSString *path = [[GSDefaultsRootForUser (NSUserName ())
                      stringByAppendingPathComponent:ENDockDomain]
                     stringByAppendingPathExtension:@"plist"];

  return [NSDictionary dictionaryWithContentsOfFile:path];
}

- (BOOL)readDockHidden
{
  id hidden = [[self dockDomain] objectForKey:ENDockHiddenKey];

  return [hidden isKindOfClass:[NSArray class]]
    && [hidden containsObject:ENBatteryExtra];
}

- (void)setDockHidden:(BOOL)hidden
{
  if (hidden == [self readDockHidden] && dockAskedAt == 0)
    return;
  dockHidden = hidden;
  dockAskedHidden = hidden;
  dockAskedAt = [NSDate timeIntervalSinceReferenceDate];
  [[NSDistributedNotificationCenter defaultCenter]
      postNotificationName:ENDockSetHidden
                    object:nil
                  userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
                                           ENBatteryExtra, @"identifier",
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
    dockHidden = [hidden containsObject:ENBatteryExtra];
  else
    dockHidden = [self readDockHidden];
  [self refresh];
}

/* ---- changes ---- */

/* Through the helper, unlocking first if the lock was open but the
   right ran out. */
- (BOOL)set:(NSDictionary *)values source:(int)source
{
  NSString *name = source == ENSourceAC ? NBPowerSourceAC
                                        : NBPowerSourceBattery;
  int status;

  status = [NBSettingsHelper setPMPreferences:values
                               forPowerSource:name
                                authorization:auth];
  if (status == NBAuthorizationNeeded)
    {
      /* The helper no longer holds the right (it ran out, or the helper
         was restarted): close the lock, then ask. */
      [auth refresh];
      [lockView update];
      if ([lockView unlock])
        status = [NBSettingsHelper setPMPreferences:values
                                     forPowerSource:name
                                      authorization:auth];
      else
        status = NBAuthorizationOK;	/* cancelled: nothing to say */
    }
  if (status != NBAuthorizationOK)
    NSRunAlertPanel (@"Energy", @"%@", @"OK", nil, nil,
                     [NBAuthorization messageForStatus:status]);
  return status == NBAuthorizationOK;
}

- (void)chooseDisplaySleep:(id)sender
{
  [self set:[NSDictionary dictionaryWithObject:
                 [NSNumber numberWithInt:(int) [[sender selectedItem] tag]]
                                         forKey:NBPMDisplaySleep]
     source:(int) [sender tag]];
  [self refresh];
}

- (void)chooseSystemSleep:(id)sender
{
  [self set:[NSDictionary dictionaryWithObject:
                 [NSNumber numberWithInt:(int) [[sender selectedItem] tag]]
                                         forKey:NBPMSystemSleep]
     source:(int) [sender tag]];
  [self refresh];
}

- (void)toggleWake:(id)sender
{
  [self set:[NSDictionary dictionaryWithObject:
                 [NSNumber numberWithInt:[sender state] == NSOnState ? 1 : 0]
                                         forKey:NBPMWakeOnLAN]
     source:(int) [sender tag]];
  [self refresh];
}

- (void)toggleDock:(id)sender
{
  [self setDockHidden:[sender state] != NSOnState];
}

/* The system's defaults for everything shown. */
- (void)useDefaults:(id)sender
{
  NSNumber *def = [NSNumber numberWithInt:NBPMDefault];
  int source;

  if (![lockView unlock])
    return;
  for (source = ENSourceAC; source <= ENSourceBattery; source++)
    {
      ENSourceSettings *s = source == ENSourceAC ? &settings.ac
                                                 : &settings.battery;
      NSMutableDictionary *values;

      if (!s->present)
        continue;
      values = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                      def, NBPMDisplaySleep,
                                      def, NBPMSystemSleep, nil];
      if (s->wakeOnLAN >= 0)
        [values setObject:def forKey:NBPMWakeOnLAN];
      if (![self set:values source:source])
        break;
    }
  if (dockExtraInstalled)
    [self setDockHidden:NO];
  [self refresh];
}

/* Back to the values from when the window opened. */
- (void)revert:(id)sender
{
  int source;

  if (![lockView unlock])
    return;
  for (source = ENSourceAC; source <= ENSourceBattery; source++)
    {
      ENSourceSettings *s = source == ENSourceAC ? &original.ac
                                                 : &original.battery;
      NSMutableDictionary *values;

      if (!s->present)
        continue;
      values = [NSMutableDictionary dictionaryWithObjectsAndKeys:
          [NSNumber numberWithInt:s->displaySleep], NBPMDisplaySleep,
          [NSNumber numberWithInt:s->systemSleep], NBPMSystemSleep, nil];
      if (s->wakeOnLAN >= 0)
        [values setObject:[NSNumber numberWithInt:s->wakeOnLAN]
                   forKey:NBPMWakeOnLAN];
      if (![self set:values source:source])
        break;
    }
  if (dockExtraInstalled)
    [self setDockHidden:originalDockHidden];
  [self refresh];
}

@end
