/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "DSController.h"
#import "DSDisplay.h"
#import <GNUstepBase/GNUstep.h>

#include <errno.h>
#include <math.h>
#include <string.h>

/* Layout, in points. */
#define DSMargin 20.0
#define DSWindowWidth 680.0
#define DSIconSize 48.0
#define DSButtonWidth 112.0
#define DSButtonHeight 28.0
#define DSButtonGap 8.0
#define DSRowGap 10.0
#define DSArrangementHeight 160.0
#define DSResolutionRows 6
#define DSLabelWidth 130.0	/* "Refresh rate:" and the like */

/* Night Shift: NightShiftTemperature, kelvin. */
#define DSWarmest 1900
#define DSCoolest 6500
#define DSDefaultWarmth 3400
static NSString *const DSDefaultSchedule = @"22:00-07:00";

/* Tags of the "Use as" popup's items other than "Mirror for <id>". */
#define DSUseAsMain (-1)
#define DSUseAsExtended 0

/* A view laid out from the top down. */
@interface DSFlippedView : NSView
@end

@implementation DSFlippedView
- (BOOL)isFlipped
{
  return YES;
}
@end

static NSTextField *
DSLabel (NSRect frame, NSString *text, NSFont *font)
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
DSRowLabel (CGFloat y, NSString *text)
{
  NSTextField *label = DSLabel (NSMakeRect (0, y + 3, DSLabelWidth, 20), text,
                                nil);
  [label setAlignment:NSRightTextAlignment];
  return label;
}

static NSFont *
DSSmallFont (void)
{
  return [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
}

/* A NeXT-style group: a titled box around inner, at the given width. */
static NSBox *
DSGroup (NSString *title, NSView *inner, CGFloat width)
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
DSGroupInnerWidth (void)
{
  NSBox *box = AUTORELEASE ([[NSBox alloc]
                              initWithFrame:NSMakeRect (0, 0, 400, 100)]);
  [box setTitle:@"X"];
  [box setTitlePosition:NSAtTop];
  [box setBorderType:NSGrooveBorder];
  [box setContentViewMargins:NSMakeSize (12, 10)];
  return DSWindowWidth - 2 * DSMargin
    - (400 - NSWidth ([[box contentView] frame]));
}

/* "HH:MM" from what was typed ("7", "7:30", "0730"), or nil. */
static NSString *
DSParseTime (NSString *text)
{
  NSString *digits;
  NSArray *parts;
  int h, m = 0;

  text = [text stringByTrimmingCharactersInSet:
                 [NSCharacterSet whitespaceCharacterSet]];
  parts = [text componentsSeparatedByString:@":"];
  if ([parts count] == 2)
    {
      if ([[parts objectAtIndex:0] length] == 0
          || [[parts objectAtIndex:1] length] != 2)
        return nil;
      h = [[parts objectAtIndex:0] intValue];
      m = [[parts objectAtIndex:1] intValue];
      digits = [[parts objectAtIndex:0] stringByAppendingString:
                                         [parts objectAtIndex:1]];
    }
  else if ([parts count] == 1 && [text length] > 0 && [text length] <= 4)
    {
      digits = text;
      if ([text length] <= 2)
        h = [text intValue];
      else
        {
          h = [[text substringToIndex:[text length] - 2] intValue];
          m = [[text substringFromIndex:[text length] - 2] intValue];
        }
    }
  else
    return nil;
  if ([digits rangeOfCharacterFromSet:
                [[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location
      != NSNotFound)
    return nil;
  if (h < 0 || h > 23 || m < 0 || m > 59)
    return nil;
  return [NSString stringWithFormat:@"%02d:%02d", h, m];
}

@interface DSController (Private)
- (void)buildMenu;
- (void)reload;
- (void)refresh;
- (void)rebuildContent;
- (DSDisplay *)displayWithID:(unsigned)displayID;
- (DSDisplay *)selectedDisplay;
- (DSDisplay *)mainDisplay;
- (BOOL)isMirroring;
- (NSView *)arrangementSection:(CGFloat)width;
- (NSView *)displaySection:(DSDisplay *)display width:(CGFloat)width;
- (NSView *)nightShiftSection:(CGFloat)width;
- (void)updateConfirmPanel;
- (void)startConfirming;
- (BOOL)report:(int)error what:(NSString *)what;
- (void)chooseDisplay:(id)sender;
- (void)chooseSize:(id)sender;
- (void)chooseDefault:(id)sender;
- (void)toggleShowAll:(id)sender;
- (void)chooseResolution:(id)sender;
- (void)chooseRefresh:(id)sender;
- (void)chooseUseAs:(id)sender;
- (void)toggleMirror:(id)sender;
- (void)chooseOptimizeFor:(id)sender;
- (void)chooseNightShift:(id)sender;
- (void)setSchedule:(NSString *)typed end:(int)end field:(id)sender;
- (void)setScheduleFrom:(id)sender;
- (void)setScheduleTo:(id)sender;
- (void)setWarmth:(id)sender;
- (void)settle;
- (void)screenParametersChanged:(NSNotification *)note;
@end

@implementation DSController

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [NSObject cancelPreviousPerformRequestsWithTarget:self];
  [connection invalidate];
  RELEASE (connection);
  RELEASE (confirmPanel);
  RELEASE (window);
  RELEASE (displays);
  RELEASE (settings);
  RELEASE (shownState);
  RELEASE (showAllFor);
  RELEASE (resolutions);
  RELEASE (refreshRates);
  [super dealloc];
}

- (void)applicationDidFinishLaunching:(NSNotification *)note
{
  NSImage *icon = [NSImage imageNamed:@"Displays.png"];

  if (icon != nil)
    [NSApp setApplicationIconImage:icon];
  [self buildMenu];
  window = [[NSWindow alloc]
      initWithContentRect:NSMakeRect (200, 200, DSWindowWidth, 300)
                styleMask:NSTitledWindowMask | NSClosableWindowMask
                          | NSMiniaturizableWindowMask
                  backing:NSBackingStoreBuffered
                    defer:NO];
  [window setTitle:@"Displays"];
  [window setReleasedWhenClosed:NO];
  [window setFrameAutosaveName:@"Displays"];

  [[NSNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector (screenParametersChanged:)
             name:NSApplicationDidChangeScreenParametersNotification
           object:nil];

  showAllFor = [[NSMutableSet alloc] init];
  confirmPanel = [[DSConfirmPanel alloc] initWithDelegate:self];
  connection = [[DSDisplayConnection alloc] initWithDelegate:self];
  [self reload];
  [window makeKeyAndOrderFront:self];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app
{
  return YES;
}

- (void)applicationWillTerminate:(NSNotification *)note
{
  /* Quitting with the question up answers it the safe way. */
  if ([confirmPanel isVisible])
    {
      [confirmPanel close];
      [connection revertChanges];
    }
  [connection invalidate];
}

- (void)displayConnectionDidChange:(DSDisplayConnection *)c
{
  [self reload];
}

/* ---- the arrangement ---- */

- (void)arrangementView:(DSArrangementView *)view
       didSelectDisplay:(unsigned)displayID
{
  selectedID = displayID;
  if (reloadAfterDrag)
    [self reload];
  else
    [self rebuildContent];
}

- (void)arrangementView:(DSArrangementView *)view
            moveDisplay:(unsigned)displayID
               toOrigin:(NSPoint)origin
{
  DSDisplay *display = [self displayWithID:displayID];

  selectedID = displayID;
  if (display != nil)
    [self report:[connection setOrigin:origin forDisplay:display]
            what:@"move the display"];
  [self reload];
}

- (void)arrangementView:(DSArrangementView *)view
        makeMainDisplay:(unsigned)displayID
{
  DSDisplay *display = [self displayWithID:displayID];

  if (display != nil)
    [self report:[connection setMainDisplay:display]
            what:@"make it the main display"];
  [self reload];
}

/* ---- "Keep these display settings?" ---- */

- (void)confirmPanelKeep:(DSConfirmPanel *)panel
{
  int e = [connection keepChanges];

  sawPending = NO;
  /* ENOENT: nothing was pending any more. */
  if (e != ENOENT)
    [self report:e what:@"keep the settings"];
  [self reload];
}

- (void)confirmPanelRevert:(DSConfirmPanel *)panel
{
  /* WindowServer may have gone back already: nothing to report. */
  [connection revertChanges];
  sawPending = NO;
  [self reload];
}

/* ---- the table of all resolutions ---- */

- (NSInteger)numberOfRowsInTableView:(NSTableView *)table
{
  return (NSInteger) [resolutions count];
}

- (id)tableView:(NSTableView *)table
    objectValueForTableColumn:(NSTableColumn *)column
                          row:(NSInteger)row
{
  DSDisplayMode *mode;
  NSString *title;

  if (row < 0 || (NSUInteger) row >= [resolutions count])
    return nil;
  mode = [resolutions objectAtIndex:row];
  title = [mode sizeTitle];
  if ([mode isInterlaced])
    title = [title stringByAppendingString:@" (interlaced)"];
  if ([mode isDefault])
    title = [title stringByAppendingString:@" (default)"];
  return title;
}

- (BOOL)tableView:(NSTableView *)table shouldEditTableColumn:(NSTableColumn *)c
              row:(NSInteger)row
{
  return NO;
}

@end

@implementation DSController (Private)

- (void)buildMenu
{
  NSMenu *menu = AUTORELEASE ([[NSMenu alloc] initWithTitle:@"Displays"]);
  NSMenu *windows = AUTORELEASE ([[NSMenu alloc] initWithTitle:@"Window"]);
  id<NSMenuItem> item;

  [menu addItemWithTitle:@"About Displays"
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

- (void)screenParametersChanged:(NSNotification *)note
{
  [self reload];
}

/* Read the displays and settings again, and rebuild the window if
   anything shown changed. */
- (void)reload
{
  NSMutableString *state = [NSMutableString string];
  NSArray *list;
  NSUInteger i;

  /* Not under a drag in the arrangement: it ends with a reload. */
  if ([arrangementView isDragging])
    {
      reloadAfterDrag = YES;
      return;
    }
  reloadAfterDrag = NO;

  list = [connection displays];
  ASSIGN (displays, list);
  ASSIGN (settings, [connection settings]);
  if ([self displayWithID:selectedID] == nil)
    selectedID = [displays count] > 0 ? [[displays objectAtIndex:0] displayID] : 0;
  [self updateConfirmPanel];

  [state appendFormat:@"%d %d\n", (int) [connection isConnected],
         (int) [connection hasDisplayList]];
  for (i = 0; i < [displays count]; i++)
    [state appendFormat:@"%@\n", [[displays objectAtIndex:i] stateDescription]];
  [state appendString:[settings description]];
  if ([state isEqual:shownState])
    return;
  ASSIGN (shownState, state);
  [self rebuildContent];
}

/* After a click: reload and rebuild, so every control shows what
   WindowServer has, even when the change was refused. */
- (void)refresh
{
  DESTROY (shownState);
  [self reload];
}

- (DSDisplay *)displayWithID:(unsigned)displayID
{
  NSEnumerator *e = [displays objectEnumerator];
  DSDisplay *display;

  while ((display = [e nextObject]) != nil)
    if ([display displayID] == displayID)
      return display;
  return nil;
}

- (DSDisplay *)selectedDisplay
{
  return [self displayWithID:selectedID];
}

- (DSDisplay *)mainDisplay
{
  NSEnumerator *e = [displays objectEnumerator];
  DSDisplay *display;

  while ((display = [e nextObject]) != nil)
    if ([display isMain])
      return display;
  return [displays count] > 0 ? [displays objectAtIndex:0] : nil;
}

/* Every display but the main one shows another. */
- (BOOL)isMirroring
{
  NSEnumerator *e = [displays objectEnumerator];
  DSDisplay *display;
  BOOL any = NO;

  while ((display = [e nextObject]) != nil)
    {
      if ([display isMain])
        continue;
      if (![display isMirror])
        return NO;
      any = YES;
    }
  return any;
}

- (void)rebuildContent
{
  DSFlippedView *content;
  NSMutableArray *sections = [NSMutableArray array];
  CGFloat inner = DSGroupInnerWidth ();
  CGFloat height, y;
  DSDisplay *display = [self selectedDisplay];
  NSString *note = nil;
  NSRect frame, newFrame;
  NSUInteger i;

  arrangementView = nil;
  if (![connection isConnected])
    note = @"WindowServer isn't running. Displays will connect when it starts.";
  else if (display == nil)
    note = @"This WindowServer has no display settings.";

  if (display != nil && [connection hasDisplayList] && [displays count] > 1)
    [sections addObject:DSGroup (@"Arrangement",
                                 [self arrangementSection:inner],
                                 DSWindowWidth - 2 * DSMargin)];
  if (display != nil)
    [sections addObject:DSGroup ([displays count] > 1 ? @"Display" : [display name],
                                 [self displaySection:display width:inner],
                                 DSWindowWidth - 2 * DSMargin)];
  if ([settings objectForKey:@"NightShift"] != nil)
    [sections addObject:DSGroup (@"Night Shift",
                                 [self nightShiftSection:inner],
                                 DSWindowWidth - 2 * DSMargin)];

  height = DSMargin;
  for (i = 0; i < [sections count]; i++)
    height += NSHeight ([[sections objectAtIndex:i] frame]) + DSRowGap;
  if (note != nil)
    height += 30;
  height += DSMargin - DSRowGap;
  height = MAX (height, 120);

  content = AUTORELEASE ([[DSFlippedView alloc]
                           initWithFrame:NSMakeRect (0, 0, DSWindowWidth,
                                                     height)]);
  y = DSMargin;
  for (i = 0; i < [sections count]; i++)
    {
      NSView *section = [sections objectAtIndex:i];
      [section setFrameOrigin:NSMakePoint (DSMargin, y)];
      [content addSubview:section];
      y += NSHeight ([section frame]) + DSRowGap;
    }
  if (note != nil)
    [content addSubview:DSLabel (NSMakeRect (DSMargin, y,
                                             DSWindowWidth - 2 * DSMargin, 20),
                                 note, nil)];

  /* Keep the window's top left where it is. */
  frame = [window frame];
  newFrame = [window frameRectForContentRect:
                       NSMakeRect (0, 0, DSWindowWidth, height)];
  newFrame.origin.x = frame.origin.x;
  newFrame.origin.y = NSMaxY (frame) - newFrame.size.height;
  [window setContentView:content];
  [window setFrame:newFrame display:YES];
}

/* ---- the sections ---- */

- (NSView *)arrangementSection:(CGFloat)width
{
  DSFlippedView *view = AUTORELEASE ([[DSFlippedView alloc]
                                       initWithFrame:NSMakeRect (0, 0, width, 10)]);
  NSTextField *help;
  NSButton *mirror;
  CGFloat y = 0;

  help = DSLabel (NSMakeRect (0, y, width, 32),
                  @"Drag the displays to arrange them. Drag the white menu bar "
                  @"to another display to make it the main display.",
                  DSSmallFont ());
  [[help cell] setWraps:YES];
  [view addSubview:help];
  y += 36;

  arrangementView = AUTORELEASE ([[DSArrangementView alloc]
                                   initWithFrame:NSMakeRect (0, y, width,
                                                             DSArrangementHeight)]);
  [arrangementView setDelegate:self];
  [arrangementView setDisplays:displays selected:selectedID];
  [view addSubview:arrangementView];
  y += DSArrangementHeight + DSRowGap;

  mirror = AUTORELEASE ([[NSButton alloc]
                          initWithFrame:NSMakeRect (0, y, 220, 22)]);
  [mirror setButtonType:NSSwitchButton];
  [mirror setTitle:@"Mirror Displays"];
  [mirror setState:[self isMirroring] ? NSOnState : NSOffState];
  [mirror setTarget:self];
  [mirror setAction:@selector (toggleMirror:)];
  [view addSubview:mirror];
  y += 22;

  /*
   * Which display the mirrored picture is made for, as macOS's
   * "Optimize for": it fills its panel, and the others show its shape,
   * with bars where theirs differs. It is the main display, the one
   * the others mirror.
   */
  if ([self isMirroring])
    {
      NSPopUpButton *optimize = AUTORELEASE ([[NSPopUpButton alloc]
          initWithFrame:NSMakeRect (DSLabelWidth + 8, y + DSRowGap, 260, 24)
              pullsDown:NO]);
      NSUInteger i;

      y += DSRowGap;
      [view addSubview:DSRowLabel (y, @"Optimize for:")];
      for (i = 0; i < [displays count]; i++)
        {
          DSDisplay *d = [displays objectAtIndex:i];

          [optimize addItemWithTitle:[d name]];
          [[optimize lastItem] setTag:(NSInteger) [d displayID]];
        }
      [optimize selectItemWithTag:(NSInteger) [[self mainDisplay] displayID]];
      [optimize setTarget:self];
      [optimize setAction:@selector (chooseOptimizeFor:)];
      [view addSubview:optimize];
      y += 24;
    }

  [view setFrameSize:NSMakeSize (width, y)];
  return view;
}

- (NSView *)displaySection:(DSDisplay *)display width:(CGFloat)width
{
  DSFlippedView *view = AUTORELEASE ([[DSFlippedView alloc]
                                       initWithFrame:NSMakeRect (0, 0, width, 10)]);
  BOOL listed = [connection hasDisplayList];
  BOOL several = listed && [displays count] > 1;
  NSArray *sizes = [display looksLikeModes];
  NSArray *panelModes = [display panelModes];
  DSDisplayMode *current = [display currentLooksLike];
  DSDisplayMode *defaultSize = [display defaultLooksLike];
  BOOL showAll = [showAllFor containsObject:
                               [NSNumber numberWithUnsignedInt:[display displayID]]];
  NSFont *bold = [NSFont boldSystemFontOfSize:0];
  NSMutableString *panelText;
  NSString *roleText = nil, *looksText;
  NSImageView *icon;
  CGFloat y = 0, textX, textW;
  NSUInteger i, count = [sizes count];

  /* Which display, when there are several. */
  if (several)
    {
      NSPopUpButton *choose = AUTORELEASE ([[NSPopUpButton alloc]
          initWithFrame:NSMakeRect (DSLabelWidth + 8, y, 260, 24) pullsDown:NO]);

      [view addSubview:DSRowLabel (y, @"Settings for:")];
      for (i = 0; i < [displays count]; i++)
        {
          DSDisplay *d = [displays objectAtIndex:i];
          [choose addItemWithTitle:[NSString stringWithFormat:@"%@%@", [d name],
                                             [d isMain] ? @" (main)" : @""]];
          [[choose lastItem] setTag:(NSInteger) [d displayID]];
        }
      [choose selectItemWithTag:(NSInteger) [display displayID]];
      [choose setTarget:self];
      [choose setAction:@selector (chooseDisplay:)];
      [view addSubview:choose];
      y += 24 + DSRowGap + 4;
    }

  /* The display: its icon, name, panel, role and size. */
  icon = AUTORELEASE ([[NSImageView alloc]
                        initWithFrame:NSMakeRect (0, y, DSIconSize, DSIconSize)]);
  [icon setImage:[NSApp applicationIconImage]];
  [icon setImageScaling:NSScaleProportionally];
  [icon setEditable:NO];
  [view addSubview:icon];
  textX = DSIconSize + 12;
  textW = width - textX;

  panelText = [NSMutableString stringWithFormat:@"%u x %u pixels",
                               [display panelWidth], [display panelHeight]];
  if ([display refreshMHz] > 0)
    [panelText appendFormat:@", %@", DSRefreshTitle ([display refreshMHz])];
  if ([display isBuiltin])
    [panelText appendString:@", built-in"];
  else if ([[display connector] length] > 0)
    [panelText appendFormat:@", %@", [display connector]];
  if (several)
    {
      DSDisplay *of = [self displayWithID:[display mirrorOf]];
      if ([display isMirror])
        roleText = [NSString stringWithFormat:@"Mirroring %@",
                             of != nil ? [of name] : @"another display"];
      else
        roleText = [display isMain] ? @"Main display" : @"Extended display";
    }
  looksText = [NSString stringWithFormat:@"Looks like %.0f x %.0f",
                        NSWidth ([display frame]), NSHeight ([display frame])];
  if ([display scale] > 1)
    looksText = [looksText stringByAppendingFormat:@" (HiDPI, %ux)",
                           [display scale]];
  if (roleText != nil)
    looksText = [NSString stringWithFormat:@"%@. %@", roleText, looksText];

  [view addSubview:DSLabel (NSMakeRect (textX, y, textW, 20), [display name],
                            [NSFont boldSystemFontOfSize:14])];
  [view addSubview:DSLabel (NSMakeRect (textX, y + 20, textW, 16), panelText,
                            DSSmallFont ())];
  [view addSubview:DSLabel (NSMakeRect (textX, y + 36, textW, 16), looksText,
                            DSSmallFont ())];
  y += DSIconSize + DSRowGap + 4;

  /* What it's for: main, extended, or a mirror of another. */
  if (several)
    {
      NSPopUpButton *useAs = AUTORELEASE ([[NSPopUpButton alloc]
          initWithFrame:NSMakeRect (DSLabelWidth + 8, y, 260, 24) pullsDown:NO]);

      [view addSubview:DSRowLabel (y, @"Use as:")];
      [useAs setAutoenablesItems:NO];
      [useAs addItemWithTitle:@"Main Display"];
      [[useAs lastItem] setTag:DSUseAsMain];
      [useAs addItemWithTitle:@"Extended Display"];
      [[useAs lastItem] setTag:DSUseAsExtended];
      for (i = 0; i < [displays count]; i++)
        {
          DSDisplay *d = [displays objectAtIndex:i];
          if ([d displayID] == [display displayID] || [d isMirror])
            continue;
          [useAs addItemWithTitle:[NSString stringWithFormat:@"Mirror for %@",
                                            [d name]]];
          [[useAs lastItem] setTag:(NSInteger) [d displayID]];
        }
      if ([display isMain])
        {
          /* Another display is made main, or mirrors this one. */
          [useAs selectItemWithTag:DSUseAsMain];
          [useAs setEnabled:NO];
        }
      else if ([display isMirror])
        [useAs selectItemWithTag:(NSInteger) [display mirrorOf]];
      else
        [useAs selectItemWithTag:DSUseAsExtended];
      /* A mirror can't be main until it has its own part again. */
      if ([display isMirror])
        [[useAs itemAtIndex:[useAs indexOfItemWithTag:DSUseAsMain]]
          setEnabled:NO];
      [useAs setTarget:self];
      [useAs setAction:@selector (chooseUseAs:)];
      [view addSubview:useAs];
      y += 24 + DSRowGap;
    }

  /* Looks like: Default for display, then Larger Text ... More Space,
     or every resolution the display has. */
  if (count > 1 || showAll)
    {
      NSButton *defaultButton;

      [view addSubview:DSLabel (NSMakeRect (0, y, 200, 20), @"Looks like:", bold)];
      y += 24;
      defaultButton = AUTORELEASE ([[NSButton alloc]
          initWithFrame:NSMakeRect (0, y, 360, 22)]);
      [defaultButton setButtonType:NSSwitchButton];
      [defaultButton setTitle:defaultSize != nil
          ? [NSString stringWithFormat:@"Default for display (%@)",
                      [defaultSize sizeTitle]]
          : @"Default for display"];
      [defaultButton setState:[display followsDefault] ? NSOnState : NSOffState];
      [defaultButton setTarget:self];
      [defaultButton setAction:@selector (chooseDefault:)];
      [view addSubview:defaultButton];
      y += 22 + DSRowGap;
    }

  if (showAll && [panelModes count] > 0)
    {
      NSMutableArray *rows = [NSMutableArray array];
      NSScrollView *scroll;
      NSTableView *table;
      NSTableColumn *column;
      NSInteger selectedRow = -1;
      CGFloat rowHeight = 18, listHeight;

      /* One row per size (interlaced ones apart), largest first. */
      for (i = 0; i < [panelModes count]; i++)
        {
          DSDisplayMode *mode = [panelModes objectAtIndex:i];
          NSUInteger j;
          BOOL seen = NO;

          for (j = 0; j < [rows count] && !seen; j++)
            {
              DSDisplayMode *row = [rows objectAtIndex:j];
              if ([row hasSizeOf:mode] && [row isInterlaced] == [mode isInterlaced])
                {
                  seen = YES;
                  if ([mode isDefault] && ![row isDefault])
                    [rows replaceObjectAtIndex:j withObject:mode];
                }
            }
          if (!seen)
            [rows addObject:mode];
        }
      for (i = 0; i < [rows count]; i++)
        {
          DSDisplayMode *row = [rows objectAtIndex:i];
          if ([row width] == [display panelWidth]
              && [row height] == [display panelHeight] && ![row isInterlaced])
            selectedRow = (NSInteger) i;
        }
      ASSIGN (resolutions, rows);

      listHeight = rowHeight * DSResolutionRows + 4;
      scroll = AUTORELEASE ([[NSScrollView alloc]
                              initWithFrame:NSMakeRect (0, y, 320, listHeight)]);
      [scroll setHasVerticalScroller:YES];
      [scroll setBorderType:NSBezelBorder];
      table = AUTORELEASE ([[NSTableView alloc]
                             initWithFrame:NSMakeRect (0, 0, 300, listHeight)]);
      column = AUTORELEASE ([[NSTableColumn alloc] initWithIdentifier:@"size"]);
      [column setWidth:290];
      [column setEditable:NO];
      [table addTableColumn:column];
      [table setHeaderView:nil];
      [table setCornerView:nil];
      [table setRowHeight:rowHeight];
      [table setAllowsEmptySelection:YES];
      [table setAllowsMultipleSelection:NO];
      [table setDataSource:self];
      [table setDelegate:self];
      [table setTarget:self];
      [table setAction:@selector (chooseResolution:)];
      [scroll setDocumentView:table];
      [table reloadData];
      if (selectedRow >= 0)
        {
          [table selectRow:selectedRow byExtendingSelection:NO];
          [table scrollRowToVisible:selectedRow];
        }
      [view addSubview:scroll];
      [view addSubview:DSLabel (NSMakeRect (336, y, width - 336, 64),
                                @"The modes the display has, in pixels. "
                                @"Choosing one runs the display at it.",
                                DSSmallFont ())];
      [[[[view subviews] lastObject] cell] setWraps:YES];
      y += listHeight + DSRowGap;
    }
  else if (count > 1)
    {
      /* One button per size, Larger Text to More Space. With the
         default chosen, the size it is shows selected too, as the
         size in effect. */
      CGFloat rowWidth = count * DSButtonWidth + (count - 1) * DSButtonGap;
      CGFloat buttonWidth = DSButtonWidth, x0;

      if (rowWidth > width)
        {
          buttonWidth = floor ((width - (count - 1) * DSButtonGap) / count);
          rowWidth = count * buttonWidth + (count - 1) * DSButtonGap;
        }
      x0 = floor ((width - rowWidth) / 2);
      for (i = 0; i < count; i++)
        {
          DSDisplayMode *mode = [sizes objectAtIndex:i];
          CGFloat x = x0 + i * (buttonWidth + DSButtonGap);
          NSButton *button = AUTORELEASE ([[NSButton alloc]
              initWithFrame:NSMakeRect (x, y, buttonWidth, DSButtonHeight)]);
          [button setButtonType:NSPushOnPushOffButton];
          [button setTitle:[mode sizeTitle]];
          [button setTag:(NSInteger) i];
          [button setState:[mode hasSizeOf:current] ? NSOnState : NSOffState];
          [button setTarget:self];
          [button setAction:@selector (chooseSize:)];
          [view addSubview:button];

          if ([mode isDefault])
            {
              NSTextField *mark = DSLabel (
                  NSMakeRect (x, y + DSButtonHeight + 2, buttonWidth, 16),
                  @"Default", DSSmallFont ());
              [mark setAlignment:NSCenterTextAlignment];
              [view addSubview:mark];
            }
        }
      y += DSButtonHeight + 18;
      NSTextField *larger = DSLabel (NSMakeRect (x0, y, 140, 16),
                                     @"Larger Text", DSSmallFont ());
      NSTextField *more = DSLabel (NSMakeRect (x0 + rowWidth - 140, y, 140, 16),
                                   @"More Space", DSSmallFont ());
      [more setAlignment:NSRightTextAlignment];
      [view addSubview:larger];
      [view addSubview:more];
      y += 16 + DSRowGap;
    }
  else if (!listed)
    {
      [view addSubview:DSLabel (NSMakeRect (0, y, width, 20),
                                @"This display offers no other sizes.", nil)];
      y += 20 + DSRowGap;
    }

  if ([panelModes count] > 0)
    {
      NSButton *all = AUTORELEASE ([[NSButton alloc]
          initWithFrame:NSMakeRect (0, y, 260, 22)]);
      NSPopUpButton *rates;
      NSMutableArray *list = [NSMutableArray array];
      NSInteger selectedIndex = -1;
      unsigned best = 0;

      [all setButtonType:NSSwitchButton];
      [all setTitle:@"Show all resolutions"];
      [all setState:showAll ? NSOnState : NSOffState];
      [all setTarget:self];
      [all setAction:@selector (toggleShowAll:)];
      [view addSubview:all];
      y += 22 + DSRowGap;

      /* The rates of the size the display runs at, highest first. */
      for (i = 0; i < [panelModes count]; i++)
        {
          DSDisplayMode *mode = [panelModes objectAtIndex:i];
          NSNumber *mhz = [NSNumber numberWithUnsignedInt:[mode refreshMHz]];
          if ([mode width] == [display panelWidth]
              && [mode height] == [display panelHeight]
              && ![mode isInterlaced] && [mode refreshMHz] > 0
              && ![list containsObject:mhz])
            [list addObject:mhz];
        }
      [list sortUsingSelector:@selector (compare:)];
      list = [NSMutableArray arrayWithArray:
                               [[list reverseObjectEnumerator] allObjects]];
      ASSIGN (refreshRates, list);

      [view addSubview:DSRowLabel (y, @"Refresh rate:")];
      rates = AUTORELEASE ([[NSPopUpButton alloc]
          initWithFrame:NSMakeRect (DSLabelWidth + 8, y, 160, 24) pullsDown:NO]);
      for (i = 0; i < [list count]; i++)
        {
          unsigned mhz = [[list objectAtIndex:i] unsignedIntValue];
          unsigned diff = mhz > [display refreshMHz]
            ? mhz - [display refreshMHz] : [display refreshMHz] - mhz;
          [rates addItemWithTitle:DSRefreshTitle (mhz)];
          [[rates lastItem] setTag:(NSInteger) i];
          if (selectedIndex < 0 || diff < best)
            {
              selectedIndex = (NSInteger) i;
              best = diff;
            }
        }
      if ([list count] == 0)
        {
          [rates addItemWithTitle:[display refreshMHz] > 0
                   ? DSRefreshTitle ([display refreshMHz]) : @"Unknown"];
          [rates setEnabled:NO];
        }
      else
        [rates selectItemAtIndex:selectedIndex];
      if ([list count] == 1)
        [rates setEnabled:NO];
      [rates setTarget:self];
      [rates setAction:@selector (chooseRefresh:)];
      [view addSubview:rates];
      y += 24;
    }
  else
    y -= DSRowGap;

  [view setFrameSize:NSMakeSize (width, y)];
  return view;
}

- (NSView *)nightShiftSection:(CGFloat)width
{
  DSFlippedView *view = AUTORELEASE ([[DSFlippedView alloc]
                                       initWithFrame:NSMakeRect (0, 0, width, 10)]);
  NSString *mode = [settings objectForKey:@"NightShift"];
  NSString *schedule = [settings objectForKey:@"NightShiftSchedule"];
  int kelvin = [[settings objectForKey:@"NightShiftTemperature"] intValue];
  NSPopUpButton *popup;
  NSSlider *slider;
  NSTextField *less, *more;
  CGFloat x = DSLabelWidth + 8, y = 0;

  if (kelvin < DSWarmest || kelvin > DSCoolest)
    kelvin = DSDefaultWarmth;

  [view addSubview:DSLabel (NSMakeRect (0, y, width, 32),
      @"Night Shift warms the colours of every display, which may be easier "
      @"on the eyes at night.", DSSmallFont ())];
  [[[[view subviews] lastObject] cell] setWraps:YES];
  y += 36;

  [view addSubview:DSRowLabel (y, @"Night Shift:")];
  popup = AUTORELEASE ([[NSPopUpButton alloc]
      initWithFrame:NSMakeRect (x, y, 180, 24) pullsDown:NO]);
  [popup addItemWithTitle:@"Off"];
  [[popup lastItem] setRepresentedObject:@"Off"];
  [popup addItemWithTitle:@"On"];
  [[popup lastItem] setRepresentedObject:@"On"];
  [popup addItemWithTitle:@"Scheduled"];
  [[popup lastItem] setRepresentedObject:@"Schedule"];
  if ([mode caseInsensitiveCompare:@"On"] == NSOrderedSame)
    [popup selectItemAtIndex:1];
  else if ([mode caseInsensitiveCompare:@"Schedule"] == NSOrderedSame)
    [popup selectItemAtIndex:2];
  else
    [popup selectItemAtIndex:0];
  [popup setTarget:self];
  [popup setAction:@selector (chooseNightShift:)];
  [view addSubview:popup];
  y += 24 + DSRowGap;

  if ([popup indexOfSelectedItem] == 2)
    {
      NSArray *ends = [(schedule != nil ? schedule : DSDefaultSchedule)
                        componentsSeparatedByString:@"-"];
      NSString *from = [ends count] == 2 ? [ends objectAtIndex:0] : @"22:00";
      NSString *to = [ends count] == 2 ? [ends objectAtIndex:1] : @"07:00";
      NSTextField *field;

      [view addSubview:DSRowLabel (y, @"From:")];
      field = AUTORELEASE ([[NSTextField alloc]
                             initWithFrame:NSMakeRect (x, y + 1, 64, 22)]);
      [field setStringValue:from];
      [[field cell] setSendsActionOnEndEditing:YES];
      [field setTarget:self];
      [field setAction:@selector (setScheduleFrom:)];
      [view addSubview:field];
      [view addSubview:DSLabel (NSMakeRect (x + 72, y + 3, 24, 20), @"to", nil)];
      field = AUTORELEASE ([[NSTextField alloc]
                             initWithFrame:NSMakeRect (x + 100, y + 1, 64, 22)]);
      [field setStringValue:to];
      [[field cell] setSendsActionOnEndEditing:YES];
      [field setTarget:self];
      [field setAction:@selector (setScheduleTo:)];
      [view addSubview:field];
      [view addSubview:DSLabel (NSMakeRect (x + 172, y + 3, width - x - 172, 20),
                                @"24-hour time", DSSmallFont ())];
      y += 24 + DSRowGap;
    }

  /* Less Warm at the left: the slider runs the other way from kelvin. */
  [view addSubview:DSRowLabel (y, @"Colour temperature:")];
  slider = AUTORELEASE ([[NSSlider alloc]
                          initWithFrame:NSMakeRect (x, y + 2, 300, 20)]);
  [slider setMinValue:DSWarmest];
  [slider setMaxValue:DSCoolest];
  [slider setDoubleValue:(DSWarmest + DSCoolest) - kelvin];
  [slider setContinuous:NO];
  [slider setTarget:self];
  [slider setAction:@selector (setWarmth:)];
  [view addSubview:slider];
  y += 24;
  less = DSLabel (NSMakeRect (x, y, 100, 16), @"Less Warm", DSSmallFont ());
  more = DSLabel (NSMakeRect (x + 200, y, 100, 16), @"More Warm", DSSmallFont ());
  [more setAlignment:NSRightTextAlignment];
  [view addSubview:less];
  [view addSubview:more];
  y += 16;

  [view setFrameSize:NSMakeSize (width, y)];
  return view;
}

/* ---- "Keep these display settings?" ---- */

/* Follow what WindowServer says about the pending change. */
- (void)updateConfirmPanel
{
  NSEnumerator *e = [displays objectEnumerator];
  DSDisplay *display, *pending = nil;

  while ((display = [e nextObject]) != nil)
    if ([display isPending])
      pending = display;
  if (pending != nil)
    {
      NSTimeInterval left = [pending revertMS] / 1000.0;

      sawPending = YES;
      if (![confirmPanel isVisible])
        [confirmPanel showOverWindow:window
                             seconds:(left > 0 ? left : DSRevertSeconds)];
      else if (left > 0)
        [confirmPanel setSecondsLeft:left];
    }
  else if (sawPending && [confirmPanel isVisible])
    {
      /* Kept or undone elsewhere, or WindowServer went back by itself. */
      [confirmPanel close];
      sawPending = NO;
    }
}

/* After a change made with DSConfirm. */
- (void)startConfirming
{
  sawPending = NO;
  [confirmPanel showOverWindow:window seconds:DSRevertSeconds];
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
    why = [NSString stringWithFormat:@"The display can't do that, so Displays "
                    @"couldn't %@.", what];
  else if (error == ENOENT)
    why = @"The display was disconnected.";
  else
    why = [NSString stringWithFormat:@"WindowServer couldn't %@ (%s).", what,
                    strerror (error)];
  NSRunAlertPanel (@"Displays", @"%@", @"OK", nil, nil, why);
  return NO;
}

/* ---- actions ---- */

- (void)chooseDisplay:(id)sender
{
  selectedID = (unsigned) [[sender selectedItem] tag];
  [self rebuildContent];
}

- (void)chooseSize:(id)sender
{
  DSDisplay *display = [self selectedDisplay];
  NSArray *sizes = [display looksLikeModes];
  NSInteger i = [sender tag];
  int e;

  if (i < 0 || (NSUInteger) i >= [sizes count])
    return;
  e = [connection setLooksLike:[sizes objectAtIndex:i]
                    forDisplay:display
                       confirm:YES];
  if ([self report:e what:@"change the size"])
    {
      if ([connection hasDisplayList])
        [self startConfirming];
      else
        [self performSelector:@selector (settle) withObject:nil afterDelay:1.0];
    }
  [self refresh];
}

- (void)chooseDefault:(id)sender
{
  DSDisplay *display = [self selectedDisplay];
  DSDisplayMode *current = [display currentLooksLike];
  BOOL toDefault = [sender state] == NSOnState;
  /* Unticking keeps the size in effect, now as the user's choice:
     nothing changes on screen, so there's nothing to confirm. */
  BOOL confirm = toDefault && ![current isDefault];
  int e;

  if (!toDefault && current == nil)
    {
      [self refresh];
      return;
    }
  e = [connection setLooksLike:(toDefault ? nil : current)
                    forDisplay:display
                       confirm:confirm];
  if ([self report:e what:@"change the size"])
    {
      if (![connection hasDisplayList])
        [self performSelector:@selector (settle) withObject:nil afterDelay:1.0];
      else if (confirm)
        [self startConfirming];
    }
  [self refresh];
}

- (void)toggleShowAll:(id)sender
{
  NSNumber *key = [NSNumber numberWithUnsignedInt:selectedID];

  if ([sender state] == NSOnState)
    [showAllFor addObject:key];
  else
    [showAllFor removeObject:key];
  [self rebuildContent];
}

- (void)chooseResolution:(id)sender
{
  DSDisplay *display = [self selectedDisplay];
  NSInteger row = [sender clickedRow];
  DSDisplayMode *mode;
  NSEnumerator *e;
  DSDisplayMode *other;
  unsigned refresh = 0;

  if (row < 0 || (NSUInteger) row >= [resolutions count] || display == nil)
    return;
  mode = [resolutions objectAtIndex:row];
  if ([mode width] == [display panelWidth]
      && [mode height] == [display panelHeight] && ![mode isInterlaced])
    return;
  /* The rate it runs at now, if the new size has it; else the
     highest. */
  e = [[display panelModes] objectEnumerator];
  while ((other = [e nextObject]) != nil)
    if ([other hasSizeOf:mode] && [other refreshMHz] == [display refreshMHz])
      refresh = [display refreshMHz];
  if ([mode isInterlaced])
    refresh = [mode refreshMHz];
  if ([self report:[connection setModeWidth:[mode width]
                                     height:[mode height]
                                 refreshMHz:refresh
                                 forDisplay:display]
              what:@"change the resolution"])
    [self startConfirming];
  [self reload];
}

- (void)chooseRefresh:(id)sender
{
  DSDisplay *display = [self selectedDisplay];
  NSInteger i = [[sender selectedItem] tag];
  unsigned mhz;

  if (display == nil || i < 0 || (NSUInteger) i >= [refreshRates count])
    return;
  mhz = [[refreshRates objectAtIndex:i] unsignedIntValue];
  if (mhz == [display refreshMHz])
    return;
  if ([self report:[connection setModeWidth:[display panelWidth]
                                     height:[display panelHeight]
                                 refreshMHz:mhz
                                 forDisplay:display]
              what:@"change the refresh rate"])
    [self startConfirming];
  [self reload];
}

- (void)chooseUseAs:(id)sender
{
  DSDisplay *display = [self selectedDisplay];
  NSInteger tag = [[sender selectedItem] tag];
  int e;

  if (display == nil)
    return;
  if (tag == DSUseAsMain)
    {
      [self report:[connection setMainDisplay:display]
              what:@"make it the main display"];
      [self reload];
      return;
    }
  if (tag == DSUseAsExtended && ![display isMirror])
    return;
  if (tag != DSUseAsExtended && [display mirrorOf] == (unsigned) tag)
    return;
  e = [connection setMirrorOf:(unsigned) tag forDisplay:display];
  if ([self report:e what:(tag == DSUseAsExtended
                           ? @"stop mirroring" : @"mirror the display")])
    [self startConfirming];
  [self reload];
}

/* Every display shows the main one, or each gets its own part back.
   One request per display; the last is the one Keep or Revert
   answers, as WindowServer keeps the earlier ones. */
- (void)toggleMirror:(id)sender
{
  DSDisplay *main = [self mainDisplay];
  BOOL on = [sender state] == NSOnState;
  NSEnumerator *e = [displays objectEnumerator];
  DSDisplay *display;
  BOOL changed = NO;
  int err = 0;

  while ((display = [e nextObject]) != nil && err == 0)
    {
      if ([display isMain])
        continue;
      if (on && !([display isMirror] && [display mirrorOf] == [main displayID]))
        err = [connection setMirrorOf:[main displayID] forDisplay:display];
      else if (!on && [display isMirror])
        err = [connection setMirrorOf:0 forDisplay:display];
      else
        continue;
      if (err == 0)
        changed = YES;
    }
  [self report:err what:(on ? @"mirror the displays" : @"stop mirroring")];
  if (changed)
    [self startConfirming];
  [self reload];
}

/* Mirror for another display: WindowServer swaps it with the one the
   others show (WS_DISPLAY_SET_MIRROR), and it becomes main. */
- (void)chooseOptimizeFor:(id)sender
{
  DSDisplay *main = [self mainDisplay];
  unsigned target = (unsigned)[[sender selectedItem] tag];
  int err;

  if (main == nil || target == [main displayID])
    return;
  err = [connection setMirrorOf:target forDisplay:main];
  [self report:err what:@"change which display the picture is made for"];
  if (err == 0)
    [self startConfirming];
  [self reload];
}

- (void)chooseNightShift:(id)sender
{
  NSString *value = [[sender selectedItem] representedObject];

  [self report:[connection setSetting:@"NightShift" value:value]
          what:@"change Night Shift"];
  /* A schedule needs its times; give it the default ones if it has
     none. */
  if ([value isEqual:@"Schedule"]
      && [settings objectForKey:@"NightShiftSchedule"] == nil)
    [connection setSetting:@"NightShiftSchedule" value:DSDefaultSchedule];
  [self reload];
}

- (void)setSchedule:(NSString *)typed end:(int)end field:(id)sender
{
  NSString *schedule = [settings objectForKey:@"NightShiftSchedule"];
  NSArray *ends = [(schedule != nil ? schedule : DSDefaultSchedule)
                    componentsSeparatedByString:@"-"];
  NSString *time = DSParseTime (typed);
  NSString *from, *to;

  if ([ends count] != 2)
    ends = [DSDefaultSchedule componentsSeparatedByString:@"-"];
  if (time == nil)
    {
      NSBeep ();
      [sender setStringValue:[ends objectAtIndex:end]];
      return;
    }
  from = end == 0 ? time : [ends objectAtIndex:0];
  to = end == 1 ? time : [ends objectAtIndex:1];
  [sender setStringValue:time];
  if ([time isEqual:[ends objectAtIndex:end]])
    return;
  [self report:[connection setSetting:@"NightShiftSchedule"
                                value:[NSString stringWithFormat:@"%@-%@",
                                                from, to]]
          what:@"change Night Shift's schedule"];
  [self reload];
}

- (void)setScheduleFrom:(id)sender
{
  [self setSchedule:[sender stringValue] end:0 field:sender];
}

- (void)setScheduleTo:(id)sender
{
  [self setSchedule:[sender stringValue] end:1 field:sender];
}

- (void)setWarmth:(id)sender
{
  int kelvin = (DSWarmest + DSCoolest) - (int) lrint ([sender doubleValue]);

  /* Round to 100 K. */
  kelvin = (kelvin + 50) / 100 * 100;
  [self report:[connection setSetting:@"NightShiftTemperature"
                                value:[NSString stringWithFormat:@"%d", kelvin]]
          what:@"change the colour temperature"];
  [self reload];
}

/* A second after a size is set the settings way: show what WindowServer
   has, whether or not its screen change came. */
- (void)settle
{
  [self reload];
}

@end
