/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "MSController.h"
#import <GNUstepBase/GNUstep.h>

#include <errno.h>
#include <math.h>
#include <string.h>

/* Layout, in points. */
#define MSMargin 20.0
#define MSWindowWidth 560.0
#define MSIconSize 48.0
#define MSButtonWidth 96.0
#define MSButtonHeight 28.0
#define MSRowGap 10.0
#define MSLabelWidth 150.0	/* "Double-click speed:" and the like */
#define MSSliderWidth 260.0
#define MSIndent 20.0		/* a caption or option under a switch */

/* Double-click speed, GSDoubleClickTime in ms. WindowServer counts
   clicks within 500 ms, so that's the default shown. */
#define MSDoubleClickSlowest 1000
#define MSDoubleClickFastest 200
#define MSDoubleClickDefault 500

/* Scroll speed: the slider runs over log2 of ScrollSpeed. */
#define MSScrollSlowest (-2.0)	/* 0.25 */
#define MSScrollFastest 2.0	/* 4 */

/* The WindowServer keys Mouse changes; PointerSpeed is read for the
   tracking speed while MouseSpeed is empty. */
static NSArray *
MSKeys (void)
{
  return [NSArray arrayWithObjects:@"MouseSpeed", @"MouseAccelProfile",
                  @"LeftHanded", @"NaturalScrolling", @"ScrollSpeed", nil];
}

static NSDictionary *
MSTypes (void)
{
  NSNumber *b = [NSNumber numberWithInt:MSSettingBoolean];
  NSNumber *r = [NSNumber numberWithInt:MSSettingReal];
  NSNumber *s = [NSNumber numberWithInt:MSSettingString];

  return [NSDictionary dictionaryWithObjectsAndKeys:
                         r, @"MouseSpeed", r, @"PointerSpeed",
                         s, @"MouseAccelProfile", b, @"LeftHanded",
                         b, @"NaturalScrolling", r, @"ScrollSpeed", nil];
}

static NSString *const MSDoubleClickKey = @"GSDoubleClickTime";

/* GSDoubleClickTime as saved in NSGlobalDomain, or nil. */
static id
MSSavedDoubleClick (void)
{
  NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];

  [defs synchronize];
  return [[defs persistentDomainForName:NSGlobalDomain]
           objectForKey:MSDoubleClickKey];
}

/* Save GSDoubleClickTime (nil removes it) and say so, as settings
   apps do (org.nextbsd.SettingsChanged). */
static void
MSSaveDoubleClick (id value)
{
  NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
  NSMutableDictionary *domain;

  [defs synchronize];
  domain = AUTORELEASE ([[defs persistentDomainForName:NSGlobalDomain]
                          mutableCopy]);
  if (domain == nil)
    domain = [NSMutableDictionary dictionary];
  if (value != nil)
    [domain setObject:value forKey:MSDoubleClickKey];
  else
    [domain removeObjectForKey:MSDoubleClickKey];
  [defs setPersistentDomain:domain forName:NSGlobalDomain];
  [defs synchronize];
  [[NSDistributedNotificationCenter defaultCenter]
      postNotificationName:@"org.nextbsd.SettingsChanged"
                    object:nil
                  userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
                                           NSGlobalDomain, @"domain",
                                           [NSArray arrayWithObject:
                                                      MSDoubleClickKey],
                                           @"keys", nil]
        deliverImmediately:YES];
}

/* The milliseconds in effect: GSDoubleClickTime, else WindowServer's. */
static int
MSDoubleClickTime (void)
{
  id saved = MSSavedDoubleClick ();
  int ms = saved != nil ? [saved intValue] : 0;

  if (ms < MSDoubleClickFastest || ms > MSDoubleClickSlowest)
    ms = MSDoubleClickDefault;
  return ms;
}

/* A view laid out from the top down. */
@interface MSFlippedView : NSView
@end

@implementation MSFlippedView
- (BOOL)isFlipped
{
  return YES;
}
@end

static NSTextField *
MSLabel (NSRect frame, NSString *text, NSFont *font)
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

/* A label right-aligned in the label column, for a control beside it. */
static NSTextField *
MSRowLabel (CGFloat y, NSString *text)
{
  NSTextField *label = MSLabel (NSMakeRect (0, y + 3, MSLabelWidth, 20), text,
                                nil);
  [label setAlignment:NSRightTextAlignment];
  return label;
}

static NSFont *
MSSmallFont (void)
{
  return [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
}

/* A small wrapped note; returns its height. */
static CGFloat
MSAddNote (NSView *view, CGFloat x, CGFloat y, CGFloat width, NSString *text,
           CGFloat height)
{
  NSTextField *note = MSLabel (NSMakeRect (x, y, width, height), text,
                               MSSmallFont ());
  [[note cell] setWraps:YES];
  [view addSubview:note];
  return height;
}

/* A NeXT-style group: a titled box around inner, at the given width. */
static NSBox *
MSGroup (NSString *title, NSView *inner, CGFloat width)
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
MSGroupInnerWidth (void)
{
  NSBox *box = AUTORELEASE ([[NSBox alloc]
                              initWithFrame:NSMakeRect (0, 0, 400, 100)]);
  [box setTitle:@"X"];
  [box setTitlePosition:NSAtTop];
  [box setBorderType:NSGrooveBorder];
  [box setContentViewMargins:NSMakeSize (12, 10)];
  return MSWindowWidth - 2 * MSMargin
    - (400 - NSWidth ([[box contentView] frame]));
}

static NSButton *
MSSwitch (NSRect frame, NSString *title, BOOL on, id target, SEL action)
{
  NSButton *button = AUTORELEASE ([[NSButton alloc] initWithFrame:frame]);

  [button setButtonType:NSSwitchButton];
  [button setTitle:title];
  [button setState:on ? NSOnState : NSOffState];
  [button setTarget:target];
  [button setAction:action];
  return button;
}

/* A slider in the control column with its two end labels under it;
   returns the height used. */
static CGFloat
MSAddSlider (NSView *view, CGFloat y, NSString *title, double min, double max,
             double value, NSString *low, NSString *high, id target,
             SEL action)
{
  CGFloat x = MSLabelWidth + 8;
  NSSlider *slider = AUTORELEASE ([[NSSlider alloc]
                                    initWithFrame:NSMakeRect (x, y + 2,
                                                              MSSliderWidth,
                                                              20)]);
  NSTextField *right;

  [view addSubview:MSRowLabel (y, title)];
  [slider setMinValue:min];
  [slider setMaxValue:max];
  [slider setDoubleValue:MIN (MAX (value, min), max)];
  [slider setContinuous:NO];
  [slider setTarget:target];
  [slider setAction:action];
  [view addSubview:slider];
  [view addSubview:MSLabel (NSMakeRect (x, y + 24, 100, 16), low,
                            MSSmallFont ())];
  right = MSLabel (NSMakeRect (x + MSSliderWidth - 100, y + 24, 100, 16), high,
                   MSSmallFont ());
  [right setAlignment:NSRightTextAlignment];
  [view addSubview:right];
  return 40;
}

@interface MSController (Private)
- (void)buildMenu;
- (void)reload;
- (void)rebuildContent;
- (NSArray *)mice;
- (NSView *)headerSection:(CGFloat)width;
- (NSView *)mouseSection:(CGFloat)width;
- (NSView *)scrollSection:(CGFloat)width;
- (NSView *)buttonRow:(CGFloat)width;
- (BOOL)report:(int)error what:(NSString *)what;
- (void)setTrackingSpeed:(id)sender;
- (void)toggleAcceleration:(id)sender;
- (void)choosePrimaryButton:(id)sender;
- (void)setDoubleClickSpeed:(id)sender;
- (void)toggleNaturalScrolling:(id)sender;
- (void)setScrollSpeed:(id)sender;
- (void)useDefaults:(id)sender;
- (void)revert:(id)sender;
@end

@implementation MSController

- (void)dealloc
{
  [settings invalidate];
  RELEASE (settings);
  RELEASE (window);
  RELEASE (openedWith);
  RELEASE (openedDoubleClick);
  RELEASE (shownState);
  [super dealloc];
}

- (void)applicationDidFinishLaunching:(NSNotification *)note
{
  NSImage *icon = [NSImage imageNamed:@"Mouse.png"];
  id saved = MSSavedDoubleClick ();

  if (icon != nil)
    [NSApp setApplicationIconImage:icon];
  [self buildMenu];
  window = [[NSWindow alloc]
      initWithContentRect:NSMakeRect (200, 200, MSWindowWidth, 300)
                styleMask:NSTitledWindowMask | NSClosableWindowMask
                          | NSMiniaturizableWindowMask
                  backing:NSBackingStoreBuffered
                    defer:NO];
  [window setTitle:@"Mouse"];
  [window setReleasedWhenClosed:NO];
  [window setFrameAutosaveName:@"Mouse"];

  ASSIGN (openedDoubleClick, saved != nil ? saved : (id)[NSNull null]);
  settings = [[MSSettings alloc] initWithTypes:MSTypes () delegate:self];
  [self reload];
  [window makeKeyAndOrderFront:self];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app
{
  return YES;
}

- (void)applicationWillTerminate:(NSNotification *)note
{
  [settings invalidate];
}

- (void)settingsDidChange:(MSSettings *)s
{
  [self reload];
}

@end

@implementation MSController (Private)

- (void)buildMenu
{
  NSMenu *menu = AUTORELEASE ([[NSMenu alloc] initWithTitle:@"Mouse"]);
  NSMenu *windows = AUTORELEASE ([[NSMenu alloc] initWithTitle:@"Window"]);
  id<NSMenuItem> item;

  [menu addItemWithTitle:@"About Mouse"
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

/* Rebuild the window if anything shown changed. */
- (void)reload
{
  NSString *state;

  /* Revert goes back to the values from the first time they could be
     read. */
  if (openedWith == nil && [settings canChangeSettings]
      && [[settings values] count] > 0)
    ASSIGN (openedWith, [settings snapshotOfKeys:MSKeys ()]);

  state = [NSString stringWithFormat:@"%d %d %d\n%@\n%@",
                    (int) [settings isConnected],
                    (int) [settings canChangeSettings],
                    MSDoubleClickTime (), [self mice], [settings values]];
  if ([state isEqual:shownState])
    return;
  ASSIGN (shownState, state);
  [self rebuildContent];
}

/*
 * The mice WindowServer has: pointers that aren't touchpads, leaving
 * out two that aren't a mouse someone holds: FreeBSD's "System mouse"
 * (sysmouse, every moused mouse together, each also listed on its
 * own) and the mouse half of a touchpad ("VEN_04F3:00 04F3:31D1
 * Mouse" beside "... TouchPad"), which reports its buttons.
 */
- (NSArray *)mice
{
  NSMutableArray *names = [NSMutableArray array];
  NSMutableSet *touchpads = [NSMutableSet set];
  NSArray *devices = [settings devices];
  NSEnumerator *e;
  NSDictionary *device;

  e = [devices objectEnumerator];
  while ((device = [e nextObject]) != nil)
    if ([[device objectForKey:@"flags"] unsignedIntValue] & MSInputTouchpad)
      {
        NSString *name = [device objectForKey:@"name"];
        NSRange r = [name rangeOfString:@" " options:NSBackwardsSearch];
        if (r.location != NSNotFound)
          [touchpads addObject:[name substringToIndex:r.location]];
      }

  e = [devices objectEnumerator];
  while ((device = [e nextObject]) != nil)
    {
      NSString *name = [device objectForKey:@"name"];
      NSRange r = [name rangeOfString:@" " options:NSBackwardsSearch];

      if (!([[device objectForKey:@"flags"] unsignedIntValue] & MSInputMouse))
        continue;
      if ([name isEqual:@"System mouse"])
        continue;
      if (r.location != NSNotFound
          && [touchpads containsObject:[name substringToIndex:r.location]])
        continue;
      [names addObject:name];
    }
  return names;
}

- (void)rebuildContent
{
  MSFlippedView *content;
  NSMutableArray *sections = [NSMutableArray array];
  CGFloat inner = MSGroupInnerWidth ();
  CGFloat groupWidth = MSWindowWidth - 2 * MSMargin;
  CGFloat height, y;
  NSString *note = nil;
  NSRect frame, newFrame;
  NSUInteger i;

  if (![settings isConnected])
    note = @"WindowServer isn't running. Mouse will connect when it starts.";
  else if (![settings canChangeSettings])
    note = @"This WindowServer can't change mouse settings.";

  if (note == nil)
    {
      [sections addObject:[self headerSection:groupWidth]];
      if ([[self mice] count] > 0)
        {
          [sections addObject:MSGroup (@"Mouse", [self mouseSection:inner],
                                       groupWidth)];
          [sections addObject:MSGroup (@"Scrolling",
                                       [self scrollSection:inner], groupWidth)];
          [sections addObject:[self buttonRow:groupWidth]];
        }
    }

  height = MSMargin;
  for (i = 0; i < [sections count]; i++)
    height += NSHeight ([[sections objectAtIndex:i] frame]) + MSRowGap;
  if (note != nil)
    height += 30;
  height += MSMargin - MSRowGap;
  height = MAX (height, 120);

  content = AUTORELEASE ([[MSFlippedView alloc]
                           initWithFrame:NSMakeRect (0, 0, MSWindowWidth,
                                                     height)]);
  y = MSMargin;
  for (i = 0; i < [sections count]; i++)
    {
      NSView *section = [sections objectAtIndex:i];
      [section setFrameOrigin:NSMakePoint (MSMargin, y)];
      [content addSubview:section];
      y += NSHeight ([section frame]) + MSRowGap;
    }
  if (note != nil)
    [content addSubview:MSLabel (NSMakeRect (MSMargin, y,
                                             MSWindowWidth - 2 * MSMargin, 20),
                                 note, nil)];

  /* Keep the window's top left where it is. */
  frame = [window frame];
  newFrame = [window frameRectForContentRect:
                       NSMakeRect (0, 0, MSWindowWidth, height)];
  newFrame.origin.x = frame.origin.x;
  newFrame.origin.y = NSMaxY (frame) - newFrame.size.height;
  [window setContentView:content];
  [window setFrame:newFrame display:YES];
}

/* ---- the sections ---- */

/* The icon and the mice's names, or that there's none. */
- (NSView *)headerSection:(CGFloat)width
{
  MSFlippedView *view = AUTORELEASE ([[MSFlippedView alloc]
                                       initWithFrame:NSMakeRect (0, 0, width,
                                                                 MSIconSize)]);
  NSArray *mice = [self mice];
  NSImageView *icon;
  CGFloat x = MSIconSize + 12;
  NSString *title, *detail;

  icon = AUTORELEASE ([[NSImageView alloc]
                        initWithFrame:NSMakeRect (0, 0, MSIconSize, MSIconSize)]);
  [icon setImage:[NSApp applicationIconImage]];
  [icon setImageScaling:NSScaleProportionally];
  [icon setEditable:NO];
  [view addSubview:icon];

  if ([mice count] == 0)
    {
      title = @"No mouse found";
      detail = @"Connect a mouse, or pair one in Bluetooth, and its settings "
               @"appear here.";
    }
  else
    {
      title = [mice count] > 1 ? @"Mice" : @"Mouse";
      detail = [mice componentsJoinedByString:@", "];
    }
  [view addSubview:MSLabel (NSMakeRect (x, 4, width - x, 20), title,
                            [NSFont boldSystemFontOfSize:14])];
  [view addSubview:MSLabel (NSMakeRect (x, 26, width - x, 16), detail,
                            MSSmallFont ())];
  return view;
}

- (NSView *)mouseSection:(CGFloat)width
{
  MSFlippedView *view = AUTORELEASE ([[MSFlippedView alloc]
                                       initWithFrame:NSMakeRect (0, 0, width, 10)]);
  NSString *speed = [settings valueForKey:@"MouseSpeed"];
  NSString *profile = [settings valueForKey:@"MouseAccelProfile"];
  NSButtonCell *cell;
  NSMatrix *primary;
  CGFloat x = MSLabelWidth + 8, y = 0;

  /* An empty MouseSpeed follows PointerSpeed. */
  y += MSAddSlider (view, y, @"Tracking speed:", -1, 1,
                    [speed length] > 0 ? [speed doubleValue]
                                       : [settings doubleForKey:@"PointerSpeed"],
                    @"Slow", @"Fast", self, @selector (setTrackingSpeed:));
  y += MSRowGap;

  [view addSubview:MSSwitch (NSMakeRect (x, y, 300, 22), @"Pointer acceleration",
                             [profile caseInsensitiveCompare:@"flat"]
                               != NSOrderedSame,
                             self, @selector (toggleAcceleration:))];
  y += 22;
  y += MSAddNote (view, x + MSIndent, y, width - x - MSIndent,
                  @"The pointer goes further when the mouse moves faster. "
                  @"Off, it goes the same distance however fast.", 30);
  y += MSRowGap;

  [view addSubview:MSRowLabel (y, @"Primary button:")];
  cell = AUTORELEASE ([[NSButtonCell alloc] init]);
  [cell setButtonType:NSRadioButton];
  primary = AUTORELEASE ([[NSMatrix alloc]
                           initWithFrame:NSMakeRect (x, y + 1, 160, 22)
                                    mode:NSRadioModeMatrix
                               prototype:cell
                            numberOfRows:1
                         numberOfColumns:2]);
  [primary setCellSize:NSMakeSize (80, 22)];
  [[primary cellAtRow:0 column:0] setTitle:@"Left"];
  [[primary cellAtRow:0 column:1] setTitle:@"Right"];
  [primary selectCellAtRow:0
                    column:[settings boolForKey:@"LeftHanded"] ? 1 : 0];
  [primary setTarget:self];
  [primary setAction:@selector (choosePrimaryButton:)];
  [view addSubview:primary];
  y += 24;
  y += MSAddNote (view, x, y, width - x,
                  @"Right swaps the buttons of the trackpad too.", 16);
  y += MSRowGap;

  /* Fast at the right: the slider runs the other way from the time. */
  y += MSAddSlider (view, y, @"Double-click speed:",
                    -MSDoubleClickSlowest, -MSDoubleClickFastest,
                    -MSDoubleClickTime (), @"Slow", @"Fast", self,
                    @selector (setDoubleClickSpeed:));
  y += 4;
  y += MSAddNote (view, x, y, width - x,
                  @"Saved for GNUstep (GSDoubleClickTime). WindowServer "
                  @"doesn't read it yet and counts clicks within half a "
                  @"second.", 30);

  [view setFrameSize:NSMakeSize (width, y)];
  return view;
}

- (NSView *)scrollSection:(CGFloat)width
{
  MSFlippedView *view = AUTORELEASE ([[MSFlippedView alloc]
                                       initWithFrame:NSMakeRect (0, 0, width, 10)]);
  double speed = [settings doubleForKey:@"ScrollSpeed"];
  CGFloat x = MSLabelWidth + 8, y = 0;

  [view addSubview:MSSwitch (NSMakeRect (x, y, 300, 22), @"Natural scrolling",
                             [settings boolForKey:@"NaturalScrolling"], self,
                             @selector (toggleNaturalScrolling:))];
  y += 22;
  y += MSAddNote (view, x + MSIndent, y, width - x - MSIndent,
                  @"Content follows the wheel, as it follows your fingers on "
                  @"a trackpad.", 30);
  y += MSRowGap;

  y += MSAddSlider (view, y, @"Scroll speed:", MSScrollSlowest, MSScrollFastest,
                    speed > 0 ? log2 (speed) : 0, @"Slow", @"Fast", self,
                    @selector (setScrollSpeed:));
  y += 4;
  y += MSAddNote (view, 0, y, width,
                  @"The scroll direction and speed are the trackpad's too.",
                  16);

  [view setFrameSize:NSMakeSize (width, y)];
  return view;
}

/* Defaults and Revert, at the right. */
- (NSView *)buttonRow:(CGFloat)width
{
  MSFlippedView *view = AUTORELEASE ([[MSFlippedView alloc]
                                       initWithFrame:NSMakeRect (0, 0, width,
                                                                 MSButtonHeight)]);
  NSButton *button;

  button = AUTORELEASE ([[NSButton alloc]
      initWithFrame:NSMakeRect (width - 2 * MSButtonWidth - 8, 0, MSButtonWidth,
                                MSButtonHeight)]);
  [button setTitle:@"Defaults"];
  [button setTarget:self];
  [button setAction:@selector (useDefaults:)];
  [view addSubview:button];

  button = AUTORELEASE ([[NSButton alloc]
      initWithFrame:NSMakeRect (width - MSButtonWidth, 0, MSButtonWidth,
                                MSButtonHeight)]);
  [button setTitle:@"Revert"];
  [button setTarget:self];
  [button setAction:@selector (revert:)];
  [button setEnabled:openedWith != nil];
  [view addSubview:button];
  return view;
}

/* An alert for a change WindowServer refused. YES if error is 0. */
- (BOOL)report:(int)error what:(NSString *)what
{
  NSString *why;

  if (error == 0)
    return YES;
  if (error == EPERM)
    why = @"Only the user logged in at the display can change it.";
  else if (error == EINVAL)
    why = [NSString stringWithFormat:@"WindowServer doesn't accept that, so "
                    @"Mouse couldn't %@.", what];
  else
    why = [NSString stringWithFormat:@"WindowServer couldn't %@ (%s).", what,
                    strerror (error)];
  NSRunAlertPanel (@"Mouse", @"%@", @"OK", nil, nil, why);
  return NO;
}

/* ---- actions ---- */

/* After each, the window shows what WindowServer has, even when the
   change was refused. */
#define MSChanged()		\
  do {				\
    DESTROY (shownState);	\
    [self reload];		\
  } while (0)

- (void)setTrackingSpeed:(id)sender
{
  /* Steps of 0.05 */
  double speed = round ([sender doubleValue] * 20.0) / 20.0;

  [self report:[settings setDouble:speed forKey:@"MouseSpeed"]
          what:@"change the tracking speed"];
  MSChanged ();
}

- (void)toggleAcceleration:(id)sender
{
  [self report:[settings setValue:([sender state] == NSOnState
                                   ? @"adaptive" : @"flat")
                           forKey:@"MouseAccelProfile"]
          what:@"change pointer acceleration"];
  MSChanged ();
}

- (void)choosePrimaryButton:(id)sender
{
  [self report:[settings setBool:[sender selectedColumn] == 1
                          forKey:@"LeftHanded"]
          what:@"change the primary button"];
  MSChanged ();
}

- (void)setDoubleClickSpeed:(id)sender
{
  /* Steps of 50 ms */
  int ms = (int) lrint (-[sender doubleValue] / 50.0) * 50;

  MSSaveDoubleClick ([NSNumber numberWithInt:ms]);
  MSChanged ();
}

- (void)toggleNaturalScrolling:(id)sender
{
  [self report:[settings setBool:[sender state] == NSOnState
                          forKey:@"NaturalScrolling"]
          what:@"change the scroll direction"];
  MSChanged ();
}

- (void)setScrollSpeed:(id)sender
{
  double speed = exp2 ([sender doubleValue]);

  /* Close to normal is normal. */
  if (fabs (speed - 1.0) < 0.06)
    speed = 1.0;
  [self report:[settings setDouble:speed forKey:@"ScrollSpeed"]
          what:@"change the scroll speed"];
  MSChanged ();
}

- (void)useDefaults:(id)sender
{
  MSSaveDoubleClick (nil);
  [self report:[settings resetKeys:MSKeys ()]
          what:@"go back to the defaults"];
  MSChanged ();
}

- (void)revert:(id)sender
{
  MSSaveDoubleClick (openedDoubleClick != [NSNull null]
                     ? openedDoubleClick : nil);
  if (openedWith != nil)
    [self report:[settings restore:openedWith]
            what:@"go back to the earlier settings"];
  MSChanged ();
}

@end
