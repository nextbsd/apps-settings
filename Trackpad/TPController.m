/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TPController.h"
#import <GNUstepBase/GNUstep.h>

#include <errno.h>
#include <math.h>
#include <string.h>

/* Layout, in points. */
#define TPMargin 20.0
#define TPWindowWidth 560.0
#define TPIconSize 48.0
#define TPButtonWidth 96.0
#define TPButtonHeight 28.0
#define TPRowGap 10.0
#define TPLabelWidth 130.0	/* "Tracking speed:" and the like */
#define TPSliderWidth 260.0
#define TPIndent 20.0		/* a caption or option under a switch */

/* Scroll speed: the slider runs over log2 of ScrollSpeed. */
#define TPScrollSlowest (-2.0)	/* 0.25 */
#define TPScrollFastest 2.0	/* 4 */

/* The keys Trackpad changes; PointerSpeed is read for the tracking
   speed while TrackpadSpeed is empty. */
static NSArray *
TPKeys (void)
{
  return [NSArray arrayWithObjects:@"TapToClick", @"TapToDrag",
                  @"ThreeFingerDrag", @"SecondaryClick", @"TrackpadSpeed",
                  @"NaturalScrolling", @"MomentumScrolling", @"ScrollSpeed",
                  nil];
}

static NSDictionary *
TPTypes (void)
{
  NSNumber *b = [NSNumber numberWithInt:TPSettingBoolean];
  NSNumber *r = [NSNumber numberWithInt:TPSettingReal];
  NSNumber *s = [NSNumber numberWithInt:TPSettingString];

  return [NSDictionary dictionaryWithObjectsAndKeys:
                         b, @"TapToClick", b, @"TapToDrag",
                         b, @"ThreeFingerDrag", s, @"SecondaryClick",
                         r, @"TrackpadSpeed", r, @"PointerSpeed",
                         b, @"NaturalScrolling", b, @"MomentumScrolling",
                         r, @"ScrollSpeed", nil];
}

/* A view laid out from the top down. */
@interface TPFlippedView : NSView
@end

@implementation TPFlippedView
- (BOOL)isFlipped
{
  return YES;
}
@end

static NSTextField *
TPLabel (NSRect frame, NSString *text, NSFont *font)
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
TPRowLabel (CGFloat y, NSString *text)
{
  NSTextField *label = TPLabel (NSMakeRect (0, y + 3, TPLabelWidth, 20), text,
                                nil);
  [label setAlignment:NSRightTextAlignment];
  return label;
}

static NSFont *
TPSmallFont (void)
{
  return [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
}

/* A small wrapped note; returns its height. */
static CGFloat
TPAddNote (NSView *view, CGFloat x, CGFloat y, CGFloat width, NSString *text,
           CGFloat height)
{
  NSTextField *note = TPLabel (NSMakeRect (x, y, width, height), text,
                               TPSmallFont ());
  [[note cell] setWraps:YES];
  [view addSubview:note];
  return height;
}

/* A NeXT-style group: a titled box around inner, at the given width. */
static NSBox *
TPGroup (NSString *title, NSView *inner, CGFloat width)
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
TPGroupInnerWidth (void)
{
  NSBox *box = AUTORELEASE ([[NSBox alloc]
                              initWithFrame:NSMakeRect (0, 0, 400, 100)]);
  [box setTitle:@"X"];
  [box setTitlePosition:NSAtTop];
  [box setBorderType:NSGrooveBorder];
  [box setContentViewMargins:NSMakeSize (12, 10)];
  return TPWindowWidth - 2 * TPMargin
    - (400 - NSWidth ([[box contentView] frame]));
}

static NSButton *
TPSwitch (NSRect frame, NSString *title, BOOL on, id target, SEL action)
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
TPAddSlider (NSView *view, CGFloat y, NSString *title, double min, double max,
             double value, NSString *low, NSString *high, id target,
             SEL action)
{
  CGFloat x = TPLabelWidth + 8;
  NSSlider *slider = AUTORELEASE ([[NSSlider alloc]
                                    initWithFrame:NSMakeRect (x, y + 2,
                                                              TPSliderWidth,
                                                              20)]);
  NSTextField *right;

  [view addSubview:TPRowLabel (y, title)];
  [slider setMinValue:min];
  [slider setMaxValue:max];
  [slider setDoubleValue:MIN (MAX (value, min), max)];
  [slider setContinuous:NO];
  [slider setTarget:target];
  [slider setAction:action];
  [view addSubview:slider];
  [view addSubview:TPLabel (NSMakeRect (x, y + 24, 100, 16), low,
                            TPSmallFont ())];
  right = TPLabel (NSMakeRect (x + TPSliderWidth - 100, y + 24, 100, 16), high,
                   TPSmallFont ());
  [right setAlignment:NSRightTextAlignment];
  [view addSubview:right];
  return 40;
}

@interface TPController (Private)
- (void)buildMenu;
- (void)reload;
- (void)rebuildContent;
- (NSArray *)touchpads;
- (NSView *)headerSection:(CGFloat)width;
- (NSView *)pointSection:(CGFloat)width;
- (NSView *)scrollSection:(CGFloat)width;
- (NSView *)gesturesSection:(CGFloat)width;
- (NSView *)buttonRow:(CGFloat)width;
- (BOOL)report:(int)error what:(NSString *)what;
- (void)toggleTapToClick:(id)sender;
- (void)toggleTapToDrag:(id)sender;
- (void)toggleThreeFingerDrag:(id)sender;
- (void)chooseSecondaryClick:(id)sender;
- (void)setTrackingSpeed:(id)sender;
- (void)toggleNaturalScrolling:(id)sender;
- (void)toggleMomentum:(id)sender;
- (void)setScrollSpeed:(id)sender;
- (void)useDefaults:(id)sender;
- (void)revert:(id)sender;
@end

@implementation TPController

- (void)dealloc
{
  [settings invalidate];
  RELEASE (settings);
  RELEASE (window);
  RELEASE (openedWith);
  RELEASE (shownState);
  [super dealloc];
}

- (void)applicationDidFinishLaunching:(NSNotification *)note
{
  NSImage *icon = [NSImage imageNamed:@"Trackpad.png"];

  if (icon != nil)
    [NSApp setApplicationIconImage:icon];
  [self buildMenu];
  window = [[NSWindow alloc]
      initWithContentRect:NSMakeRect (200, 200, TPWindowWidth, 300)
                styleMask:NSTitledWindowMask | NSClosableWindowMask
                          | NSMiniaturizableWindowMask
                  backing:NSBackingStoreBuffered
                    defer:NO];
  [window setTitle:@"Trackpad"];
  [window setReleasedWhenClosed:NO];
  [window setFrameAutosaveName:@"Trackpad"];

  settings = [[TPSettings alloc] initWithTypes:TPTypes () delegate:self];
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

- (void)settingsDidChange:(TPSettings *)s
{
  [self reload];
}

@end

@implementation TPController (Private)

- (void)buildMenu
{
  NSMenu *menu = AUTORELEASE ([[NSMenu alloc] initWithTitle:@"Trackpad"]);
  NSMenu *windows = AUTORELEASE ([[NSMenu alloc] initWithTitle:@"Window"]);
  id<NSMenuItem> item;

  [menu addItemWithTitle:@"About Trackpad"
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
    ASSIGN (openedWith, [settings snapshotOfKeys:TPKeys ()]);

  state = [NSString stringWithFormat:@"%d %d\n%@\n%@",
                    (int) [settings isConnected],
                    (int) [settings canChangeSettings],
                    [self touchpads], [settings values]];
  if ([state isEqual:shownState])
    return;
  ASSIGN (shownState, state);
  [self rebuildContent];
}

/* The touchpads WindowServer has. */
- (NSArray *)touchpads
{
  NSMutableArray *names = [NSMutableArray array];
  NSEnumerator *e = [[settings devices] objectEnumerator];
  NSDictionary *device;

  while ((device = [e nextObject]) != nil)
    if ([[device objectForKey:@"flags"] unsignedIntValue] & TPInputTouchpad)
      [names addObject:[device objectForKey:@"name"]];
  return names;
}

- (void)rebuildContent
{
  TPFlippedView *content;
  NSMutableArray *sections = [NSMutableArray array];
  CGFloat inner = TPGroupInnerWidth ();
  CGFloat groupWidth = TPWindowWidth - 2 * TPMargin;
  CGFloat height, y;
  NSString *note = nil;
  NSRect frame, newFrame;
  NSUInteger i;

  if (![settings isConnected])
    note = @"WindowServer isn't running. Trackpad will connect when it starts.";
  else if (![settings canChangeSettings])
    note = @"This WindowServer can't change trackpad settings.";

  if (note == nil)
    {
      [sections addObject:[self headerSection:groupWidth]];
      if ([[self touchpads] count] > 0)
        {
          [sections addObject:TPGroup (@"Point & Click",
                                       [self pointSection:inner], groupWidth)];
          [sections addObject:TPGroup (@"Scroll & Zoom",
                                       [self scrollSection:inner], groupWidth)];
          [sections addObject:TPGroup (@"More Gestures",
                                       [self gesturesSection:inner],
                                       groupWidth)];
          [sections addObject:[self buttonRow:groupWidth]];
        }
    }

  height = TPMargin;
  for (i = 0; i < [sections count]; i++)
    height += NSHeight ([[sections objectAtIndex:i] frame]) + TPRowGap;
  if (note != nil)
    height += 30;
  height += TPMargin - TPRowGap;
  height = MAX (height, 120);

  content = AUTORELEASE ([[TPFlippedView alloc]
                           initWithFrame:NSMakeRect (0, 0, TPWindowWidth,
                                                     height)]);
  y = TPMargin;
  for (i = 0; i < [sections count]; i++)
    {
      NSView *section = [sections objectAtIndex:i];
      [section setFrameOrigin:NSMakePoint (TPMargin, y)];
      [content addSubview:section];
      y += NSHeight ([section frame]) + TPRowGap;
    }
  if (note != nil)
    [content addSubview:TPLabel (NSMakeRect (TPMargin, y,
                                             TPWindowWidth - 2 * TPMargin, 20),
                                 note, nil)];

  /* Keep the window's top left where it is. */
  frame = [window frame];
  newFrame = [window frameRectForContentRect:
                       NSMakeRect (0, 0, TPWindowWidth, height)];
  newFrame.origin.x = frame.origin.x;
  newFrame.origin.y = NSMaxY (frame) - newFrame.size.height;
  [window setContentView:content];
  [window setFrame:newFrame display:YES];
}

/* ---- the sections ---- */

/* The icon and the trackpad's name, or that there's none. */
- (NSView *)headerSection:(CGFloat)width
{
  TPFlippedView *view = AUTORELEASE ([[TPFlippedView alloc]
                                       initWithFrame:NSMakeRect (0, 0, width,
                                                                 TPIconSize)]);
  NSArray *pads = [self touchpads];
  NSImageView *icon;
  CGFloat x = TPIconSize + 12;
  NSString *title, *detail;

  icon = AUTORELEASE ([[NSImageView alloc]
                        initWithFrame:NSMakeRect (0, 0, TPIconSize, TPIconSize)]);
  [icon setImage:[NSApp applicationIconImage]];
  [icon setImageScaling:NSScaleProportionally];
  [icon setEditable:NO];
  [view addSubview:icon];

  if ([pads count] == 0)
    {
      title = @"No trackpad found";
      detail = @"Its settings appear here when a trackpad is connected.";
    }
  else
    {
      title = @"Trackpad";
      detail = [pads componentsJoinedByString:@", "];
    }
  [view addSubview:TPLabel (NSMakeRect (x, 4, width - x, 20), title,
                            [NSFont boldSystemFontOfSize:14])];
  [view addSubview:TPLabel (NSMakeRect (x, 26, width - x, 16), detail,
                            TPSmallFont ())];
  return view;
}

- (NSView *)pointSection:(CGFloat)width
{
  TPFlippedView *view = AUTORELEASE ([[TPFlippedView alloc]
                                       initWithFrame:NSMakeRect (0, 0, width, 10)]);
  BOOL tap = [settings boolForKey:@"TapToClick"];
  BOOL threeFinger = [settings boolForKey:@"ThreeFingerDrag"];
  NSString *secondary = [settings valueForKey:@"SecondaryClick"];
  NSString *speed = [settings valueForKey:@"TrackpadSpeed"];
  NSButton *drag;
  NSPopUpButton *popup;
  CGFloat y = 0;

  [view addSubview:TPSwitch (NSMakeRect (0, y, 300, 22), @"Tap to click", tap,
                             self, @selector (toggleTapToClick:))];
  y += 22;
  y += TPAddNote (view, TPIndent, y, width - TPIndent,
                  @"Tap with one finger to click, two to secondary click.", 16);
  y += 4;

  drag = TPSwitch (NSMakeRect (TPIndent, y, 300, 22), @"Tap and drag",
                   [settings boolForKey:@"TapToDrag"], self,
                   @selector (toggleTapToDrag:));
  [drag setEnabled:tap];
  [view addSubview:drag];
  y += 22;
  y += TPAddNote (view, 2 * TPIndent, y, width - 2 * TPIndent,
                  @"Tap, then keep the finger down to drag.", 16);
  y += TPRowGap;

  [view addSubview:TPSwitch (NSMakeRect (0, y, 300, 22), @"Three-finger drag",
                             threeFinger, self,
                             @selector (toggleThreeFingerDrag:))];
  y += 22;
  y += TPAddNote (view, TPIndent, y, width - TPIndent,
                  @"Drag windows and select text with three fingers, without "
                  @"clicking. The three-finger swipes then take four fingers.",
                  30);
  y += TPRowGap;

  [view addSubview:TPRowLabel (y, @"Secondary click:")];
  popup = AUTORELEASE ([[NSPopUpButton alloc]
      initWithFrame:NSMakeRect (TPLabelWidth + 8, y, TPSliderWidth, 24)
          pullsDown:NO]);
  [popup addItemWithTitle:@"Click with two fingers"];
  [[popup lastItem] setRepresentedObject:@"TwoFingers"];
  [popup addItemWithTitle:@"Click in bottom-right corner"];
  [[popup lastItem] setRepresentedObject:@"BottomRightCorner"];
  [popup addItemWithTitle:@"Off"];
  [[popup lastItem] setRepresentedObject:@"Off"];
  if ([secondary caseInsensitiveCompare:@"BottomRightCorner"] == NSOrderedSame)
    [popup selectItemAtIndex:1];
  else if ([secondary caseInsensitiveCompare:@"Off"] == NSOrderedSame)
    [popup selectItemAtIndex:2];
  else
    [popup selectItemAtIndex:0];
  [popup setTarget:self];
  [popup setAction:@selector (chooseSecondaryClick:)];
  [view addSubview:popup];
  y += 24 + TPRowGap;

  /* An empty TrackpadSpeed follows PointerSpeed. */
  y += TPAddSlider (view, y, @"Tracking speed:", -1, 1,
                    [speed length] > 0 ? [speed doubleValue]
                                       : [settings doubleForKey:@"PointerSpeed"],
                    @"Slow", @"Fast", self, @selector (setTrackingSpeed:));

  [view setFrameSize:NSMakeSize (width, y)];
  return view;
}

- (NSView *)scrollSection:(CGFloat)width
{
  TPFlippedView *view = AUTORELEASE ([[TPFlippedView alloc]
                                       initWithFrame:NSMakeRect (0, 0, width, 10)]);
  double speed = [settings doubleForKey:@"ScrollSpeed"];
  CGFloat y = 0;

  [view addSubview:TPSwitch (NSMakeRect (0, y, 300, 22), @"Natural scrolling",
                             [settings boolForKey:@"NaturalScrolling"], self,
                             @selector (toggleNaturalScrolling:))];
  y += 22;
  y += TPAddNote (view, TPIndent, y, width - TPIndent,
                  @"Content follows your fingers. This is also the mouse's "
                  @"scroll direction.", 16);
  y += TPRowGap;

  [view addSubview:TPSwitch (NSMakeRect (0, y, 300, 22), @"Momentum scrolling",
                             [settings boolForKey:@"MomentumScrolling"], self,
                             @selector (toggleMomentum:))];
  y += 22;
  y += TPAddNote (view, TPIndent, y, width - TPIndent,
                  @"Scrolling carries on for a moment after your fingers lift.",
                  16);
  y += TPRowGap;

  y += TPAddSlider (view, y, @"Scroll speed:", TPScrollSlowest, TPScrollFastest,
                    speed > 0 ? log2 (speed) : 0, @"Slow", @"Fast", self,
                    @selector (setScrollSpeed:));
  y += 4;
  y += TPAddNote (view, 0, y, width,
                  @"The scroll speed is the mouse's too. Pinch to zoom and "
                  @"smart zoom aren't available yet.", 30);

  [view setFrameSize:NSMakeSize (width, y)];
  return view;
}

/* WindowServer's swipes are always on; there's no setting to show yet. */
- (NSView *)gesturesSection:(CGFloat)width
{
  TPFlippedView *view = AUTORELEASE ([[TPFlippedView alloc]
                                       initWithFrame:NSMakeRect (0, 0, width, 10)]);
  NSString *fingers = [settings boolForKey:@"ThreeFingerDrag"]
    ? @"four" : @"three";
  CGFloat x = TPLabelWidth + 8, y = 0;

  [view addSubview:TPRowLabel (y - 3, @"All windows:")];
  [view addSubview:TPLabel (NSMakeRect (x, y, width - x, 20),
                            [NSString stringWithFormat:
                                        @"Swipe up with %@ fingers", fingers],
                            nil)];
  y += 22;
  [view addSubview:TPRowLabel (y - 3, @"App windows:")];
  [view addSubview:TPLabel (NSMakeRect (x, y, width - x, 20),
                            [NSString stringWithFormat:
                                        @"Swipe down with %@ fingers", fingers],
                            nil)];
  y += 22 + 4;
  y += TPAddNote (view, 0, y, width,
                  @"These are always on. Swiping between workspaces, and "
                  @"gestures for the desktop and Applications, aren't "
                  @"available yet.", 30);

  [view setFrameSize:NSMakeSize (width, y)];
  return view;
}

/* Defaults and Revert, at the right. */
- (NSView *)buttonRow:(CGFloat)width
{
  TPFlippedView *view = AUTORELEASE ([[TPFlippedView alloc]
                                       initWithFrame:NSMakeRect (0, 0, width,
                                                                 TPButtonHeight)]);
  NSButton *button;

  button = AUTORELEASE ([[NSButton alloc]
      initWithFrame:NSMakeRect (width - 2 * TPButtonWidth - 8, 0, TPButtonWidth,
                                TPButtonHeight)]);
  [button setTitle:@"Defaults"];
  [button setTarget:self];
  [button setAction:@selector (useDefaults:)];
  [view addSubview:button];

  button = AUTORELEASE ([[NSButton alloc]
      initWithFrame:NSMakeRect (width - TPButtonWidth, 0, TPButtonWidth,
                                TPButtonHeight)]);
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
                    @"Trackpad couldn't %@.", what];
  else
    why = [NSString stringWithFormat:@"WindowServer couldn't %@ (%s).", what,
                    strerror (error)];
  NSRunAlertPanel (@"Trackpad", @"%@", @"OK", nil, nil, why);
  return NO;
}

/* ---- actions ---- */

/* After each, the window shows what WindowServer has, even when the
   change was refused. */
#define TPChanged()		\
  do {				\
    DESTROY (shownState);	\
    [self reload];		\
  } while (0)

- (void)toggleTapToClick:(id)sender
{
  [self report:[settings setBool:[sender state] == NSOnState
                          forKey:@"TapToClick"]
          what:@"change tap to click"];
  TPChanged ();
}

- (void)toggleTapToDrag:(id)sender
{
  [self report:[settings setBool:[sender state] == NSOnState
                          forKey:@"TapToDrag"]
          what:@"change tap and drag"];
  TPChanged ();
}

- (void)toggleThreeFingerDrag:(id)sender
{
  [self report:[settings setBool:[sender state] == NSOnState
                          forKey:@"ThreeFingerDrag"]
          what:@"change three-finger drag"];
  TPChanged ();
}

- (void)chooseSecondaryClick:(id)sender
{
  [self report:[settings setValue:[[sender selectedItem] representedObject]
                           forKey:@"SecondaryClick"]
          what:@"change the secondary click"];
  TPChanged ();
}

- (void)setTrackingSpeed:(id)sender
{
  /* Steps of 0.05 */
  double speed = round ([sender doubleValue] * 20.0) / 20.0;

  [self report:[settings setDouble:speed forKey:@"TrackpadSpeed"]
          what:@"change the tracking speed"];
  TPChanged ();
}

- (void)toggleNaturalScrolling:(id)sender
{
  [self report:[settings setBool:[sender state] == NSOnState
                          forKey:@"NaturalScrolling"]
          what:@"change the scroll direction"];
  TPChanged ();
}

- (void)toggleMomentum:(id)sender
{
  [self report:[settings setBool:[sender state] == NSOnState
                          forKey:@"MomentumScrolling"]
          what:@"change momentum scrolling"];
  TPChanged ();
}

- (void)setScrollSpeed:(id)sender
{
  double speed = exp2 ([sender doubleValue]);

  /* Close to normal is normal. */
  if (fabs (speed - 1.0) < 0.06)
    speed = 1.0;
  [self report:[settings setDouble:speed forKey:@"ScrollSpeed"]
          what:@"change the scroll speed"];
  TPChanged ();
}

- (void)useDefaults:(id)sender
{
  [self report:[settings resetKeys:TPKeys ()]
          what:@"go back to the defaults"];
  TPChanged ();
}

- (void)revert:(id)sender
{
  if (openedWith != nil)
    [self report:[settings restore:openedWith]
            what:@"go back to the earlier settings"];
  TPChanged ();
}

@end
