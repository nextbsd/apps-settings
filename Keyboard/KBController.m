/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "KBController.h"
#import "KBShared.h"
#import "KBXkbRegistry.h"
#import <GNUstepBase/GNUstep.h>

#include <errno.h>
#include <stdint.h>
#include <string.h>

/* notify(3), for daemons and anything without GNUstep. NextBSD's
   <notify.h> needs headers that aren't installed. */
extern uint32_t notify_post (const char *name);

/* Layout, in points. */
#define KBMargin 20.0
#define KBWindowWidth 600.0
#define KBButtonWidth 112.0
#define KBButtonHeight 28.0
#define KBRowGap 10.0
#define KBLabelWidth 150.0	/* "Delay until repeat:" and the like */
#define KBSourceRows 4

static NSString *const KBRowType = @"org.nextbsd.Keyboard.InputSourceRow";

/* KeyRepeatInterval at each stop of the rate slider, Off first;
   KeyRepeatDelay at each stop of the delay slider, longest first. */
static const int KBIntervals[] = { 0, 300, 180, 120, 90, 60, 45, 33, 25, 15 };
static const int KBDelays[] = { 2000, 1500, 1000, 750, 500, 350, 250, 150 };
#define KBCount(a) ((int) (sizeof (a) / sizeof ((a)[0])))

/* KeyboardLayoutShortcut's values and their titles. */
static NSString *const KBShortcutValues[] = {
  @"None", @"ControlSpace", @"WinSpace", @"AltShift", @"CapsLock"
};
static NSString *const KBShortcutTitles[] = {
  @"None", @"Control+Space", @"Command+Space", @"Option+Shift", @"Caps Lock"
};

/* Caps Lock: the XKB option for each item of the popup ("" is Caps
   Lock itself). */
static NSString *const KBCapsOptions[] = {
  @"", @"ctrl:nocaps", @"caps:escape", @"caps:none"
};
static NSString *const KBCapsTitles[] = {
  @"Caps Lock", @"Control", @"Escape", @"No Action"
};
static NSString *const KBSwapOption = @"altwin:swap_alt_win";

static NSArray *
KBKeyboardKeys (void)
{
  return [NSArray arrayWithObjects:KBKeyboardLayout, KBKeyboardVariant,
                  KBKeyboardOptions, KBKeyboardLayoutShortcut,
                  KBKeyRepeatDelay, KBKeyRepeatInterval, nil];
}

/* A view laid out from the top down. */
@interface KBFlippedView : NSView
@end

@implementation KBFlippedView
- (BOOL)isFlipped
{
  return YES;
}
@end

static NSTextField *
KBLabel (NSRect frame, NSString *text, NSFont *font)
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
KBRowLabel (CGFloat y, NSString *text)
{
  NSTextField *label = KBLabel (NSMakeRect (0, y + 3, KBLabelWidth, 20), text,
                                nil);
  [label setAlignment:NSRightTextAlignment];
  return label;
}

static NSFont *
KBSmallFont (void)
{
  return [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
}

/* Small wrapped help text, height lines high. */
static NSTextField *
KBHelp (NSRect frame, NSString *text)
{
  NSTextField *help = KBLabel (frame, text, KBSmallFont ());
  [[help cell] setWraps:YES];
  return help;
}

/* A NeXT-style group: a titled box around inner, at the given width. */
static NSBox *
KBGroup (NSString *title, NSView *inner, CGFloat width)
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

/* The inside width of a group width wide. */
static CGFloat
KBGroupInnerWidth (CGFloat width)
{
  NSBox *box = AUTORELEASE ([[NSBox alloc]
                              initWithFrame:NSMakeRect (0, 0, 400, 100)]);
  [box setTitle:@"X"];
  [box setTitlePosition:NSAtTop];
  [box setBorderType:NSGrooveBorder];
  [box setContentViewMargins:NSMakeSize (12, 10)];
  return width - (400 - NSWidth ([[box contentView] frame]));
}

static NSPopUpButton *
KBPopUp (NSRect frame, NSString *const *titles, int count, id target, SEL action)
{
  NSPopUpButton *popup = AUTORELEASE ([[NSPopUpButton alloc]
                                        initWithFrame:frame pullsDown:NO]);
  int i;

  for (i = 0; i < count; i++)
    {
      [popup addItemWithTitle:titles[i]];
      [[popup lastItem] setTag:i];
    }
  [popup setTarget:target];
  [popup setAction:action];
  return popup;
}

static NSSlider *
KBStopSlider (NSRect frame, int stops, id target, SEL action)
{
  NSSlider *slider = AUTORELEASE ([[NSSlider alloc] initWithFrame:frame]);

  [slider setMinValue:0];
  [slider setMaxValue:stops - 1];
  [slider setNumberOfTickMarks:stops];
  [slider setAllowsTickMarkValuesOnly:YES];
  [slider setContinuous:NO];
  [slider setTarget:target];
  [slider setAction:action];
  return slider;
}

/* The stop of values[] nearest to value. */
static int
KBNearestStop (const int *values, int count, int value)
{
  int i, best = 0;

  for (i = 1; i < count; i++)
    if (abs (values[i] - value) < abs (values[best] - value))
      best = i;
  return best;
}

/* "us,gr" -> ("us", "gr"), each trimmed; "" -> (). */
static NSMutableArray *
KBSplitList (NSString *text)
{
  NSMutableArray *list = [NSMutableArray array];
  NSEnumerator *e = [[text componentsSeparatedByString:@","] objectEnumerator];
  NSString *item;

  while ((item = [e nextObject]) != nil)
    {
      item = [item stringByTrimmingCharactersInSet:
                     [NSCharacterSet whitespaceCharacterSet]];
      if ([item length] > 0)
        [list addObject:item];
    }
  return list;
}

/* Write values (key -> value, NSNull to remove it) into the user's
   defaults domain, and say so. */
static void
KBSaveDefaults (NSString *domainName, NSDictionary *values)
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSMutableDictionary *domain;
  NSEnumerator *e;
  NSString *key;

  /* From the file, so another app's keys in the same domain (Trackpad's
     in org.nextbsd.WindowServer) are kept. */
  [defaults synchronize];
  domain = AUTORELEASE ([KBReadDomain (domainName) mutableCopy]);
  if (domain == nil)
    domain = [NSMutableDictionary dictionary];
  e = [values keyEnumerator];
  while ((key = [e nextObject]) != nil)
    {
      id value = [values objectForKey:key];

      if (value == [NSNull null])
        [domain removeObjectForKey:key];
      else if ([key isEqual:KBKeyRepeatDelay]
               || [key isEqual:KBKeyRepeatInterval])
        [domain setObject:[NSNumber numberWithInt:[value intValue]] forKey:key];
      else
        [domain setObject:value forKey:key];
    }
  [defaults setPersistentDomain:domain forName:domainName];
  [defaults synchronize];

  [[NSDistributedNotificationCenter defaultCenter]
      postNotificationName:KBSettingsChangedNotification
                    object:nil
                  userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
                                           domainName, @"domain",
                                         [values allKeys], @"keys", nil]
        deliverImmediately:YES];
  notify_post ("org.nextbsd.SettingsChanged");
  notify_post ([[@"org.nextbsd.SettingsChanged."
                  stringByAppendingString:domainName] UTF8String]);
}

@interface KBController (Private)
- (void)buildMenu;
- (void)buildWindow;
- (NSView *)inputSourcesTab:(CGFloat)width;
- (NSView *)keyboardTab:(CGFloat)width;
- (NSView *)shortcutsTab:(CGFloat)width;
- (NSView *)stack:(NSArray *)groups width:(CGFloat)width;
- (void)reload;
- (void)updateControls;
- (void)updateShortcuts;
- (NSString *)setting:(NSString *)key;
- (BOOL)apply:(NSDictionary *)values what:(NSString *)what;
- (BOOL)setLayouts:(NSArray *)list what:(NSString *)what;
- (void)saveInputSources;
- (NSMutableArray *)options;
- (BOOL)setOptions:(NSArray *)options what:(NSString *)what;
- (void)report:(int)error key:(NSString *)key what:(NSString *)what;
- (void)addSource:(id)sender;
- (void)removeSource:(id)sender;
- (void)switchToSource:(id)sender;
- (void)chooseShortcut:(id)sender;
- (void)toggleShowMenu:(id)sender;
- (void)setRate:(id)sender;
- (void)setDelay:(id)sender;
- (void)chooseCaps:(id)sender;
- (void)toggleSwap:(id)sender;
- (void)useDefaults:(id)sender;
- (void)revert:(id)sender;
@end

@implementation KBController

- (void)dealloc
{
  [NSObject cancelPreviousPerformRequestsWithTarget:self];
  [connection invalidate];
  RELEASE (connection);
  RELEASE (picker);
  RELEASE (window);
  RELEASE (settings);
  RELEASE (sources);
  RELEASE (layouts);
  RELEASE (launchSession);
  RELEASE (launchDefaults);
  [dockExtra invalidate];
  RELEASE (dockExtra);
  RELEASE (shortcuts);
  [super dealloc];
}

- (void)applicationDidFinishLaunching:(NSNotification *)note
{
  NSImage *icon = [NSImage imageNamed:@"Keyboard.png"];
  NSString *section;

  if (icon != nil)
    [NSApp setApplicationIconImage:icon];
  [self buildMenu];
  activeLayout = -1;
  picker = [[KBSourcePicker alloc] initWithDelegate:self];
  dockExtra = [[NBDockExtra alloc] initWithIdentifier:NBDockExtraInput
                                           bundleName:@"Input"];
  [dockExtra setTarget:self action:@selector (dockExtraChanged:)];
  [self buildWindow];
  connection = [[KBConnection alloc] initWithName:@"Keyboard" delegate:self];
  [self reload];

  /* -NBSettingsSection input-sources|keyboard|shortcuts */
  section = [[NSUserDefaults standardUserDefaults]
              stringForKey:@"NBSettingsSection"];
  if ([section length] > 0)
    {
      NSInteger i = [tabView indexOfTabViewItemWithIdentifier:section];
      if (i != NSNotFound)
        [tabView selectTabViewItemAtIndex:i];
    }
  [window makeKeyAndOrderFront:self];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app
{
  return YES;
}

- (void)applicationWillTerminate:(NSNotification *)note
{
  [connection invalidate];
}

- (void)connectionDidChange:(KBConnection *)c
{
  [self reload];
}

- (void)connectionLayoutDidChange:(KBConnection *)c
{
  int active = -1;

  ASSIGN (layouts, [connection layoutsWithActiveIndex:&active]);
  activeLayout = active;
  [sourceTable reloadData];
  [self updateControls];
}

/* ---- the add sheet ---- */

- (void)sourcePicker:(KBSourcePicker *)p
       didPickLayout:(NSString *)layout
             variant:(NSString *)variant
{
  NSMutableArray *list = [NSMutableArray arrayWithArray:layouts];
  NSEnumerator *e = [layouts objectEnumerator];
  NSDictionary *source;

  while ((source = [e nextObject]) != nil)
    if ([[source objectForKey:@"Layout"] isEqual:layout]
        && [[source objectForKey:@"Variant"] isEqual:variant])
      {
        NSRunAlertPanel (@"Keyboard", @"%@ is already in the list.", @"OK",
                         nil, nil,
                         [[KBXkbRegistry sharedRegistry]
                           nameOfLayout:layout variant:variant]);
        return;
      }
  if ([list count] >= KBMaxLayouts)
    return;
  [list addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                                  layout, @"Layout", variant, @"Variant", nil]];
  [self setLayouts:list what:@"add the input source"];
}

/* ---- tables ---- */

- (NSInteger)numberOfRowsInTableView:(NSTableView *)table
{
  if (table == sourceTable)
    return (NSInteger) [layouts count];
  if (table == shortcutTable)
    return (NSInteger) [shortcuts count];
  return 0;
}

- (id)tableView:(NSTableView *)table
    objectValueForTableColumn:(NSTableColumn *)column
                          row:(NSInteger)row
{
  NSString *identifier = [column identifier];

  if (row < 0)
    return nil;
  if (table == shortcutTable)
    {
      if ((NSUInteger) row >= [shortcuts count])
        return nil;
      return [[shortcuts objectAtIndex:row] objectForKey:identifier];
    }
  if ((NSUInteger) row >= [layouts count])
    return nil;
  NSDictionary *source = [layouts objectAtIndex:row];
  NSString *layout = [source objectForKey:@"Layout"];
  NSString *variant = [source objectForKey:@"Variant"];

  if ([identifier isEqual:@"Active"])
    return row == activeLayout
      ? [NSString stringWithUTF8String:"\xE2\x9C\x93"] : @"";	/* a check mark */
  if ([identifier isEqual:@"Short"])
    return KBShortName (layout, variant);
  if ([[source objectForKey:@"Name"] length] > 0)
    return [source objectForKey:@"Name"];
  return [[KBXkbRegistry sharedRegistry] nameOfLayout:layout variant:variant];
}

- (BOOL)tableView:(NSTableView *)table shouldEditTableColumn:(NSTableColumn *)c
              row:(NSInteger)row
{
  return NO;
}

- (void)tableViewSelectionDidChange:(NSNotification *)note
{
  [self updateControls];
}

/* Dragging a source to reorder the list. */
- (BOOL)tableView:(NSTableView *)table
    writeRowsWithIndexes:(NSIndexSet *)rows
            toPasteboard:(NSPasteboard *)pboard
{
  if (table != sourceTable || [rows count] != 1 || [layouts count] < 2)
    return NO;
  [pboard declareTypes:[NSArray arrayWithObject:KBRowType] owner:nil];
  [pboard setString:[NSString stringWithFormat:@"%lu",
                              (unsigned long) [rows firstIndex]]
            forType:KBRowType];
  return YES;
}

- (BOOL)tableView:(NSTableView *)table
        writeRows:(NSArray *)rows
     toPasteboard:(NSPasteboard *)pboard
{
  if ([rows count] != 1)
    return NO;
  return [self tableView:table
            writeRowsWithIndexes:[NSIndexSet indexSetWithIndex:
                                    [[rows objectAtIndex:0] unsignedIntValue]]
                    toPasteboard:pboard];
}

- (NSDragOperation)tableView:(NSTableView *)table
                validateDrop:(id<NSDraggingInfo>)info
                 proposedRow:(NSInteger)row
       proposedDropOperation:(NSTableViewDropOperation)operation
{
  if (table != sourceTable
      || [[[info draggingPasteboard] types] indexOfObject:KBRowType]
         == NSNotFound)
    return NSDragOperationNone;
  [table setDropRow:row dropOperation:NSTableViewDropAbove];
  return NSDragOperationMove;
}

- (BOOL)tableView:(NSTableView *)table
       acceptDrop:(id<NSDraggingInfo>)info
              row:(NSInteger)row
    dropOperation:(NSTableViewDropOperation)operation
{
  NSString *text = [[info draggingPasteboard] stringForType:KBRowType];
  NSMutableArray *list = [NSMutableArray arrayWithArray:layouts];
  NSInteger from;
  id source;

  if (text == nil)
    return NO;
  from = [text intValue];
  if (from < 0 || (NSUInteger) from >= [list count] || row < 0)
    return NO;
  if (row > from)
    row--;
  if (row == from)
    return NO;
  source = RETAIN ([list objectAtIndex:from]);
  [list removeObjectAtIndex:from];
  [list insertObject:source atIndex:MIN ((NSUInteger) row, [list count])];
  RELEASE (source);
  if (![self setLayouts:list what:@"change the order"])
    return NO;
  [sourceTable selectRow:row byExtendingSelection:NO];
  return YES;
}

@end

@implementation KBController (Private)

- (void)buildMenu
{
  NSMenu *menu = AUTORELEASE ([[NSMenu alloc] initWithTitle:@"Keyboard"]);
  NSMenu *edit = AUTORELEASE ([[NSMenu alloc] initWithTitle:@"Edit"]);
  NSMenu *windows = AUTORELEASE ([[NSMenu alloc] initWithTitle:@"Window"]);
  id<NSMenuItem> item;

  [menu addItemWithTitle:@"About Keyboard"
                  action:@selector (orderFrontStandardAboutPanel:)
           keyEquivalent:@""];
  /* For the "Try it" field. */
  item = [menu addItemWithTitle:@"Edit" action:NULL keyEquivalent:@""];
  [edit addItemWithTitle:@"Cut" action:@selector (cut:) keyEquivalent:@"x"];
  [edit addItemWithTitle:@"Copy" action:@selector (copy:) keyEquivalent:@"c"];
  [edit addItemWithTitle:@"Paste" action:@selector (paste:) keyEquivalent:@"v"];
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

/* The window: the tabs, then Defaults and Revert. Built once; the
   controls follow WindowServer's settings in -updateControls. */
- (void)buildWindow
{
  NSView *content;
  NSArray *tabs, *titles, *identifiers;
  NSTabView *probe;
  NSRect tabFrame, inner;
  CGFloat tabWidth = KBWindowWidth - 2 * KBMargin + 8;
  CGFloat insetW, insetH, pageWidth, pageHeight = 0, height, bottom;
  NSUInteger i;

  /* How much of the tab view the pages get. */
  probe = AUTORELEASE ([[NSTabView alloc]
                         initWithFrame:NSMakeRect (0, 0, 400, 300)]);
  [probe addTabViewItem:AUTORELEASE ([[NSTabViewItem alloc]
                                       initWithIdentifier:@"x"])];
  inner = [probe contentRect];
  insetW = 400 - NSWidth (inner);
  insetH = 300 - NSHeight (inner);
  pageWidth = tabWidth - insetW;

  tabs = [NSArray arrayWithObjects:[self inputSourcesTab:pageWidth],
                  [self keyboardTab:pageWidth],
                  [self shortcutsTab:pageWidth], nil];
  titles = [NSArray arrayWithObjects:@"Input Sources", @"Keyboard",
                    @"Shortcuts", nil];
  identifiers = [NSArray arrayWithObjects:@"input-sources", @"keyboard",
                         @"shortcuts", nil];
  for (i = 0; i < [tabs count]; i++)
    pageHeight = MAX (pageHeight, NSHeight ([[tabs objectAtIndex:i] frame]));

  bottom = KBMargin + KBButtonHeight + KBRowGap;
  height = bottom + pageHeight + insetH + KBMargin - 6;
  window = [[NSWindow alloc]
      initWithContentRect:NSMakeRect (200, 200, KBWindowWidth, height)
                styleMask:NSTitledWindowMask | NSClosableWindowMask
                          | NSMiniaturizableWindowMask
                  backing:NSBackingStoreBuffered
                    defer:NO];
  [window setTitle:@"Keyboard"];
  [window setReleasedWhenClosed:NO];
  [window setFrameAutosaveName:@"Keyboard"];
  content = [window contentView];

  tabFrame = NSMakeRect (KBMargin - 4, bottom, tabWidth, pageHeight + insetH);
  tabView = AUTORELEASE ([[NSTabView alloc] initWithFrame:tabFrame]);
  for (i = 0; i < [tabs count]; i++)
    {
      NSTabViewItem *item = AUTORELEASE ([[NSTabViewItem alloc]
                                           initWithIdentifier:
                                             [identifiers objectAtIndex:i]]);
      NSView *page = AUTORELEASE ([[KBFlippedView alloc]
                                    initWithFrame:NSMakeRect (0, 0, pageWidth,
                                                              pageHeight)]);
      [page addSubview:[tabs objectAtIndex:i]];
      [item setLabel:[titles objectAtIndex:i]];
      [item setView:page];
      [tabView addTabViewItem:item];
    }
  [content addSubview:tabView];

  statusLabel = KBLabel (NSMakeRect (KBMargin, KBMargin + 4,
                                     KBWindowWidth - 2 * KBMargin
                                     - 2 * KBButtonWidth - 16, 20),
                         @"", KBSmallFont ());
  [content addSubview:statusLabel];

  revertButton = AUTORELEASE ([[NSButton alloc]
                                initWithFrame:NSMakeRect (KBWindowWidth - KBMargin
                                                          - KBButtonWidth,
                                                          KBMargin,
                                                          KBButtonWidth,
                                                          KBButtonHeight)]);
  [revertButton setTitle:@"Revert"];
  [revertButton setTarget:self];
  [revertButton setAction:@selector (revert:)];
  [content addSubview:revertButton];

  defaultsButton = AUTORELEASE ([[NSButton alloc]
                                  initWithFrame:NSMakeRect (KBWindowWidth
                                                            - KBMargin
                                                            - 2 * KBButtonWidth
                                                            - 8,
                                                            KBMargin,
                                                            KBButtonWidth,
                                                            KBButtonHeight)]);
  [defaultsButton setTitle:@"Defaults"];
  [defaultsButton setTarget:self];
  [defaultsButton setAction:@selector (useDefaults:)];
  [content addSubview:defaultsButton];
}

/* Groups stacked from the top, in a view width wide. */
- (NSView *)stack:(NSArray *)groups width:(CGFloat)width
{
  KBFlippedView *view = AUTORELEASE ([[KBFlippedView alloc]
                                       initWithFrame:NSMakeRect (0, 0, width,
                                                                 10)]);
  CGFloat y = 12;
  NSUInteger i;

  for (i = 0; i < [groups count]; i++)
    {
      NSView *group = [groups objectAtIndex:i];
      [group setFrameOrigin:NSMakePoint (12, y)];
      [view addSubview:group];
      y += NSHeight ([group frame]) + KBRowGap;
    }
  [view setFrameSize:NSMakeSize (width, y + 2)];
  return view;
}

- (NSView *)inputSourcesTab:(CGFloat)width
{
  CGFloat groupWidth = width - 24;
  CGFloat inner = KBGroupInnerWidth (groupWidth);
  KBFlippedView *list, *switching;
  NSScrollView *scroll;
  NSTableColumn *column;
  NSSize size;
  CGFloat y = 0, rowHeight;

  /* The list. */
  list = AUTORELEASE ([[KBFlippedView alloc]
                        initWithFrame:NSMakeRect (0, 0, inner, 10)]);
  [list addSubview:KBHelp (NSMakeRect (0, y, inner, 18),
                           @"The layouts you type with, up to four. Drag one "
                           @"to reorder; double-click one to switch to it.")];
  y += 24;

  sourceTable = AUTORELEASE ([[NSTableView alloc]
                               initWithFrame:NSMakeRect (0, 0, inner, 80)]);
  rowHeight = [sourceTable rowHeight] + [sourceTable intercellSpacing].height;
  size = [NSScrollView frameSizeForContentSize:
                         NSMakeSize (inner, rowHeight * KBSourceRows
                                     + [[sourceTable headerView] frame].size.height)
                         hasHorizontalScroller:NO
                           hasVerticalScroller:NO
                                    borderType:NSBezelBorder];
  scroll = AUTORELEASE ([[NSScrollView alloc]
                          initWithFrame:NSMakeRect (0, y, inner, size.height)]);
  [scroll setHasVerticalScroller:NO];
  [scroll setHasHorizontalScroller:NO];
  [scroll setBorderType:NSBezelBorder];

  column = AUTORELEASE ([[NSTableColumn alloc] initWithIdentifier:@"Active"]);
  [[column headerCell] setStringValue:@""];
  [[column dataCell] setAlignment:NSCenterTextAlignment];
  [column setWidth:24];
  [column setMinWidth:24];
  [column setEditable:NO];
  [sourceTable addTableColumn:column];
  column = AUTORELEASE ([[NSTableColumn alloc] initWithIdentifier:@"Name"]);
  [[column headerCell] setStringValue:@"Input Source"];
  [column setWidth:inner - 24 - 110 - 12];
  [column setEditable:NO];
  [sourceTable addTableColumn:column];
  column = AUTORELEASE ([[NSTableColumn alloc] initWithIdentifier:@"Short"]);
  [[column headerCell] setStringValue:@"Input Menu"];
  [[column dataCell] setAlignment:NSCenterTextAlignment];
  [column setWidth:110];
  [column setEditable:NO];
  [sourceTable addTableColumn:column];
  [sourceTable setAllowsMultipleSelection:NO];
  [sourceTable setAllowsEmptySelection:YES];
  [sourceTable setAllowsColumnReordering:NO];
  [sourceTable setDataSource:(id)self];
  [sourceTable setDelegate:(id)self];
  [sourceTable setTarget:self];
  [sourceTable setDoubleAction:@selector (switchToSource:)];
  [sourceTable registerForDraggedTypes:[NSArray arrayWithObject:KBRowType]];
  /* GNUstep starts a row drag only on sideways motion, and offers only
     Copy, by default. */
  [sourceTable setVerticalMotionCanBeginDrag:YES];
  [sourceTable setDraggingSourceOperationMask:NSDragOperationMove
                                     forLocal:YES];
  [scroll setDocumentView:sourceTable];
  [list addSubview:scroll];
  y += size.height + 6;

  addButton = AUTORELEASE ([[NSButton alloc]
                             initWithFrame:NSMakeRect (0, y, 28, 24)]);
  [addButton setTitle:@"+"];
  [addButton setTarget:self];
  [addButton setAction:@selector (addSource:)];
  [list addSubview:addButton];
  removeButton = AUTORELEASE ([[NSButton alloc]
                                initWithFrame:NSMakeRect (30, y, 28, 24)]);
  [removeButton setTitle:[NSString stringWithUTF8String:"\xE2\x88\x92"]];
  [removeButton setTarget:self];
  [removeButton setAction:@selector (removeSource:)];
  [list addSubview:removeButton];
  switchButton = AUTORELEASE ([[NSButton alloc]
                                initWithFrame:NSMakeRect (inner - 120, y, 120,
                                                          24)]);
  [switchButton setTitle:@"Switch To"];
  [switchButton setTarget:self];
  [switchButton setAction:@selector (switchToSource:)];
  [list addSubview:switchButton];
  y += 24;
  [list setFrameSize:NSMakeSize (inner, y)];

  /* Switching. */
  y = 0;
  switching = AUTORELEASE ([[KBFlippedView alloc]
                             initWithFrame:NSMakeRect (0, 0, inner, 10)]);
  [switching addSubview:KBRowLabel (y, @"Switch layouts with:")];
  shortcutPopup = KBPopUp (NSMakeRect (KBLabelWidth + 8, y, 200, 24),
                           KBShortcutTitles, KBCount (KBShortcutValues), self,
                           @selector (chooseShortcut:));
  [switching addSubview:shortcutPopup];
  y += 24 + KBRowGap;
  showMenuSwitch = AUTORELEASE ([[NSButton alloc]
                                  initWithFrame:NSMakeRect (KBLabelWidth + 8, y,
                                                            inner - KBLabelWidth
                                                            - 8, 22)]);
  [showMenuSwitch setButtonType:NSSwitchButton];
  [showMenuSwitch setTitle:@"Show Input menu in Dock"];
  [showMenuSwitch setTarget:self];
  [showMenuSwitch setAction:@selector (toggleShowMenu:)];
  [switching addSubview:showMenuSwitch];
  y += 22 + 2;
  [switching addSubview:KBHelp (NSMakeRect (KBLabelWidth + 8 + 20, y,
                                            inner - KBLabelWidth - 28, 18),
                                @"It shows when there are two layouts or "
                                @"more.")];
  y += 18;
  [switching setFrameSize:NSMakeSize (inner, y)];

  return [self stack:[NSArray arrayWithObjects:
                                KBGroup (@"Input Sources", list, groupWidth),
                              KBGroup (@"Switching", switching, groupWidth),
                              nil]
               width:width];
}

- (NSView *)keyboardTab:(CGFloat)width
{
  CGFloat groupWidth = width - 24;
  CGFloat inner = KBGroupInnerWidth (groupWidth);
  CGFloat sliderX = KBLabelWidth + 8, sliderW = inner - sliderX - 70;
  KBFlippedView *repeat, *modifiers;
  NSTextField *label, *tryField;
  CGFloat y = 0;

  repeat = AUTORELEASE ([[KBFlippedView alloc]
                          initWithFrame:NSMakeRect (0, 0, inner, 10)]);
  [repeat addSubview:KBRowLabel (y, @"Key repeat rate:")];
  rateSlider = KBStopSlider (NSMakeRect (sliderX, y, sliderW, 26),
                             KBCount (KBIntervals), self, @selector (setRate:));
  [repeat addSubview:rateSlider];
  rateValue = KBLabel (NSMakeRect (sliderX + sliderW + 8, y + 3, 62, 20), @"",
                       KBSmallFont ());
  [repeat addSubview:rateValue];
  y += 26;
  [repeat addSubview:KBLabel (NSMakeRect (sliderX, y, 60, 16), @"Off",
                              KBSmallFont ())];
  [repeat addSubview:KBLabel (NSMakeRect (sliderX + sliderW / KBCount (KBIntervals),
                                          y, 60, 16), @"Slow", KBSmallFont ())];
  label = KBLabel (NSMakeRect (sliderX + sliderW - 60, y, 60, 16), @"Fast",
                   KBSmallFont ());
  [label setAlignment:NSRightTextAlignment];
  [repeat addSubview:label];
  y += 16 + KBRowGap;

  [repeat addSubview:KBRowLabel (y, @"Delay until repeat:")];
  delaySlider = KBStopSlider (NSMakeRect (sliderX, y, sliderW, 26),
                              KBCount (KBDelays), self, @selector (setDelay:));
  [repeat addSubview:delaySlider];
  delayValue = KBLabel (NSMakeRect (sliderX + sliderW + 8, y + 3, 62, 20), @"",
                        KBSmallFont ());
  [repeat addSubview:delayValue];
  y += 26;
  [repeat addSubview:KBLabel (NSMakeRect (sliderX, y, 60, 16), @"Long",
                              KBSmallFont ())];
  label = KBLabel (NSMakeRect (sliderX + sliderW - 60, y, 60, 16), @"Short",
                   KBSmallFont ());
  [label setAlignment:NSRightTextAlignment];
  [repeat addSubview:label];
  y += 16 + KBRowGap;

  [repeat addSubview:KBRowLabel (y, @"Try it:")];
  tryField = AUTORELEASE ([[NSTextField alloc]
                            initWithFrame:NSMakeRect (sliderX, y, sliderW, 24)]);
  [[tryField cell] setPlaceholderString:@"Hold down a key here"];
  [repeat addSubview:tryField];
  y += 24;
  [repeat setFrameSize:NSMakeSize (inner, y)];

  y = 0;
  modifiers = AUTORELEASE ([[KBFlippedView alloc]
                             initWithFrame:NSMakeRect (0, 0, inner, 10)]);
  [modifiers addSubview:KBRowLabel (y, @"Caps Lock key:")];
  capsPopup = KBPopUp (NSMakeRect (sliderX, y, 160, 24), KBCapsTitles,
                       KBCount (KBCapsOptions), self, @selector (chooseCaps:));
  [modifiers addSubview:capsPopup];
  capsNote = KBLabel (NSMakeRect (sliderX + 168, y + 4, inner - sliderX - 168,
                                  18), @"", KBSmallFont ());
  [modifiers addSubview:capsNote];
  y += 24 + KBRowGap;
  swapSwitch = AUTORELEASE ([[NSButton alloc]
                              initWithFrame:NSMakeRect (sliderX, y,
                                                        inner - sliderX, 22)]);
  [swapSwitch setButtonType:NSSwitchButton];
  [swapSwitch setTitle:@"Swap Command and Option"];
  [swapSwitch setTarget:self];
  [swapSwitch setAction:@selector (toggleSwap:)];
  [modifiers addSubview:swapSwitch];
  y += 22 + 2;
  [modifiers addSubview:KBHelp (NSMakeRect (sliderX + 20, y,
                                            inner - sliderX - 20, 30),
                                @"For PC keyboards: the Alt key beside the "
                                @"space bar becomes Command, and the Windows "
                                @"key Option, as on a Mac keyboard.")];
  y += 30;
  [modifiers setFrameSize:NSMakeSize (inner, y)];

  return [self stack:[NSArray arrayWithObjects:
                                KBGroup (@"Key Repeat", repeat, groupWidth),
                              KBGroup (@"Modifier Keys", modifiers, groupWidth),
                              nil]
               width:width];
}

- (NSView *)shortcutsTab:(CGFloat)width
{
  CGFloat groupWidth = width - 24;
  CGFloat inner = KBGroupInnerWidth (groupWidth);
  KBFlippedView *view;
  NSScrollView *scroll;
  NSTableColumn *column;
  CGFloat y = 0, keysWidth = 200;

  view = AUTORELEASE ([[KBFlippedView alloc]
                        initWithFrame:NSMakeRect (0, 0, inner, 10)]);
  scroll = AUTORELEASE ([[NSScrollView alloc]
                          initWithFrame:NSMakeRect (0, y, inner, 230)]);
  [scroll setHasVerticalScroller:YES];
  [scroll setHasHorizontalScroller:NO];
  [scroll setBorderType:NSBezelBorder];
  shortcutTable = AUTORELEASE ([[NSTableView alloc]
                                 initWithFrame:NSMakeRect (0, 0, inner - 20,
                                                           230)]);
  column = AUTORELEASE ([[NSTableColumn alloc] initWithIdentifier:@"Action"]);
  [[column headerCell] setStringValue:@"Action"];
  [column setWidth:inner - 20 - keysWidth - 8];
  [column setEditable:NO];
  [shortcutTable addTableColumn:column];
  column = AUTORELEASE ([[NSTableColumn alloc] initWithIdentifier:@"Keys"]);
  [[column headerCell] setStringValue:@"Keys"];
  [column setWidth:keysWidth];
  [column setEditable:NO];
  [shortcutTable addTableColumn:column];
  [shortcutTable setAllowsColumnReordering:NO];
  [shortcutTable setAllowsEmptySelection:YES];
  [shortcutTable setDataSource:(id)self];
  [shortcutTable setDelegate:(id)self];
  [scroll setDocumentView:shortcutTable];
  [view addSubview:scroll];
  y += 230 + 6;
  [view addSubview:KBHelp (NSMakeRect (0, y, inner, 30),
                           @"These can't be changed yet. While a layout that "
                           @"isn't Latin is in use, Command shortcuts use the "
                           @"first Latin layout in the list.")];
  y += 30;
  [view setFrameSize:NSMakeSize (inner, y)];

  return [self stack:[NSArray arrayWithObject:
                                KBGroup (@"Keyboard Shortcuts", view,
                                         groupWidth)]
               width:width];
}

/* ---- reading ---- */

- (void)reload
{
  NSDictionary *values, *from = nil;
  int active = -1;

  values = [connection settingsWithSources:&from];
  ASSIGN (settings, values);
  ASSIGN (sources, from);
  ASSIGN (layouts, [connection layoutsWithActiveIndex:&active]);
  activeLayout = active;

  /* What Revert goes back to: the first settings read. */
  if (launchSession == nil && settings != nil)
    {
      NSMutableDictionary *session = [NSMutableDictionary dictionary];
      NSMutableDictionary *saved = [NSMutableDictionary dictionary];
      NSDictionary *domain;
      NSEnumerator *e = [KBKeyboardKeys () objectEnumerator];
      NSString *key;

      domain = KBReadDomain (KBWindowServerDomain);
      while ((key = [e nextObject]) != nil)
        {
          id value = [domain objectForKey:key];

          if ([[sources objectForKey:key] intValue] == KBSourceSession
              && [settings objectForKey:key] != nil)
            [session setObject:[settings objectForKey:key] forKey:key];
          else
            [session setObject:[NSNull null] forKey:key];
          [saved setObject:(value != nil ? value : (id)[NSNull null])
                    forKey:key];
        }
      ASSIGN (launchSession, session);
      ASSIGN (launchDefaults, saved);
      launchShowsMenu = [dockExtra isShown];
    }

  [sourceTable reloadData];
  [self updateShortcuts];
  [self updateControls];
}

- (NSString *)setting:(NSString *)key
{
  NSString *value = [settings objectForKey:key];
  return value != nil ? value : @"";
}

/* Every control shows what WindowServer has. */
- (void)updateControls
{
  BOOL connected = settings != nil;
  NSInteger row = [sourceTable selectedRow];
  NSUInteger count = [layouts count];
  NSString *shortcut = [self setting:KBKeyboardLayoutShortcut];
  NSArray *options = [self options];
  BOOL capsSwitches;
  BOOL anySession = NO;
  NSEnumerator *e;
  NSString *key;
  int i, caps = 0;

  [statusLabel setStringValue:(connected ? @""
                               : @"WindowServer isn't running. Keyboard will "
                               @"connect when it starts.")];

  [addButton setEnabled:connected && count < KBMaxLayouts];
  [removeButton setEnabled:connected && count > 1 && row >= 0];
  [switchButton setEnabled:connected && row >= 0 && row != activeLayout];
  [sourceTable setEnabled:connected];

  [shortcutPopup selectItemAtIndex:0];
  for (i = 0; i < KBCount (KBShortcutValues); i++)
    if ([shortcut caseInsensitiveCompare:KBShortcutValues[i]] == NSOrderedSame)
      [shortcutPopup selectItemAtIndex:i];
  [shortcutPopup setEnabled:connected];
  [showMenuSwitch setState:[dockExtra isInstalled] && [dockExtra isShown]
                   ? NSOnState : NSOffState];
  [showMenuSwitch setEnabled:[dockExtra isInstalled]];

  [rateSlider setIntValue:KBNearestStop (KBIntervals, KBCount (KBIntervals),
                                         [[self setting:KBKeyRepeatInterval]
                                           intValue])];
  [delaySlider setIntValue:KBNearestStop (KBDelays, KBCount (KBDelays),
                                          [[self setting:KBKeyRepeatDelay]
                                            intValue])];
  [rateValue setStringValue:
               !connected ? @""
             : [[self setting:KBKeyRepeatInterval] intValue] == 0 ? @"off"
             : [NSString stringWithFormat:@"%d ms",
                         [[self setting:KBKeyRepeatInterval] intValue]]];
  [delayValue setStringValue:
                connected ? [NSString stringWithFormat:@"%d ms",
                                      [[self setting:KBKeyRepeatDelay] intValue]]
              : @""];
  [rateSlider setEnabled:connected];
  [delaySlider setEnabled:connected];

  for (i = 1; i < KBCount (KBCapsOptions); i++)
    if ([options containsObject:KBCapsOptions[i]])
      caps = i;
  if ([options containsObject:@"caps:ctrl_modifier"])
    caps = 1;
  [capsPopup selectItemAtIndex:caps];
  capsSwitches = [shortcut caseInsensitiveCompare:@"CapsLock"] == NSOrderedSame;
  [capsPopup setEnabled:connected && !capsSwitches];
  [capsNote setStringValue:(capsSwitches ? @"It switches layouts "
                            @"(Input Sources)." : @"")];
  [swapSwitch setState:[options containsObject:KBSwapOption]
                ? NSOnState : NSOffState];
  [swapSwitch setEnabled:connected];

  e = [KBKeyboardKeys () objectEnumerator];
  while ((key = [e nextObject]) != nil)
    if ([[sources objectForKey:key] intValue] == KBSourceSession)
      anySession = YES;
  [defaultsButton setEnabled:connected
                  && (anySession || ![dockExtra isShown])];
  [revertButton setEnabled:connected && changed];
}

/* The shortcuts tab's list, from the settings. */
- (void)updateShortcuts
{
  NSMutableArray *list = [NSMutableArray array];
  NSString *shortcut = [self setting:KBKeyboardLayoutShortcut];
  NSString *keys = @"None";
  int i;

#define KBShortcut(action, k) \
  [list addObject:[NSDictionary dictionaryWithObjectsAndKeys: \
                                  (action), @"Action", (k), @"Keys", nil]]

  for (i = 1; i < KBCount (KBShortcutValues); i++)
    if ([shortcut caseInsensitiveCompare:KBShortcutValues[i]] == NSOrderedSame)
      keys = KBShortcutTitles[i];
  KBShortcut (@"Switch to the next input source", keys);
  if (![[self setting:@"StartKeyShowsOverview"] isEqual:@"false"])
    KBShortcut (@"Show the overview", @"Start key (tap)");
  KBShortcut (@"Show the overview", @"Control+Up");
  KBShortcut (@"Show the overview", @"Mission Control key");
  KBShortcut (@"Switch to the next app", @"Command+Tab");
  KBShortcut (@"Quit the app", @"Command+Q");
  KBShortcut (@"Hide the app", @"Command+H");
  KBShortcut (@"Close the window", @"Command+W");
  KBShortcut (@"Minimize the window", @"Command+M");
  KBShortcut (@"Cut, Copy, Paste", @"Command+X, C, V");
  KBShortcut (@"Undo", @"Command+Z");
#undef KBShortcut
  ASSIGN (shortcuts, list);
  [shortcutTable reloadData];
}

/* ---- changing ---- */

/* Send values (key -> text, NSNull for the system's) to WindowServer
   and, if it takes them, keep them in the user's defaults. */
- (BOOL)apply:(NSDictionary *)values what:(NSString *)what
{
  NSString *failed = nil;
  NSEnumerator *keys = [values keyEnumerator];
  NSString *key;
  BOOL same = YES;
  int e;

  /* Nothing to do if every value is the one in effect already. */
  while (same && (key = [keys nextObject]) != nil)
    same = [[values objectForKey:key] isEqual:[settings objectForKey:key]];
  if (same)
    return YES;
  e = [connection setSettings:values failedKey:&failed];
  if (e != 0)
    {
      [self report:e key:failed what:what];
      [self reload];
      return NO;
    }
  KBSaveDefaults (KBWindowServerDomain, values);
  changed = YES;
  [self reload];
  return YES;
}

/* A new layout list ({Layout, Variant} each): KeyboardLayout and
   KeyboardVariant together, so they always match. */
- (BOOL)setLayouts:(NSArray *)list what:(NSString *)what
{
  NSMutableArray *names = [NSMutableArray array];
  NSMutableArray *variants = [NSMutableArray array];
  NSEnumerator *e = [list objectEnumerator];
  NSDictionary *source;
  BOOL anyVariant = NO;

  while ((source = [e nextObject]) != nil)
    {
      NSString *variant = [source objectForKey:@"Variant"];

      [names addObject:[source objectForKey:@"Layout"]];
      [variants addObject:(variant != nil ? variant : @"")];
      if ([variant length] > 0)
        anyVariant = YES;
    }
  if ([names count] == 0)
    return NO;
  if (![self apply:[NSDictionary dictionaryWithObjectsAndKeys:
                                   [names componentsJoinedByString:@","],
                                 KBKeyboardLayout,
                                 (anyVariant
                                  ? [variants componentsJoinedByString:@","]
                                  : @""), KBKeyboardVariant,
                                 nil]
               what:what])
    return NO;
  [self saveInputSources];
  return YES;
}

/* org.nextbsd.Keyboard InputSources: the list with names, for anything
   that shows it. */
- (void)saveInputSources
{
  NSMutableArray *list = [NSMutableArray array];
  NSEnumerator *e = [layouts objectEnumerator];
  NSDictionary *source;

  while ((source = [e nextObject]) != nil)
    {
      NSString *layout = [source objectForKey:@"Layout"];
      NSString *variant = [source objectForKey:@"Variant"];
      NSString *name = [source objectForKey:@"Name"];

      if ([name length] == 0)
        name = [[KBXkbRegistry sharedRegistry] nameOfLayout:layout
                                                    variant:variant];
      [list addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                                      layout, @"Layout",
                                    variant, @"Variant",
                                    name, @"Name",
                                    KBShortName (layout, variant), @"ShortName",
                                    nil]];
    }
  KBSaveDefaults (KBKeyboardDomain,
                  [NSDictionary dictionaryWithObject:list
                                              forKey:KBInputSources]);
}

- (NSMutableArray *)options
{
  return KBSplitList ([self setting:KBKeyboardOptions]);
}

- (BOOL)setOptions:(NSArray *)options what:(NSString *)what
{
  return [self apply:[NSDictionary dictionaryWithObject:
                                     [options componentsJoinedByString:@","]
                                                 forKey:KBKeyboardOptions]
                what:what];
}

/* An alert for a change WindowServer refused. */
- (void)report:(int)error key:(NSString *)key what:(NSString *)what
{
  NSString *why;

  if (error == EPERM)
    why = @"Only the user logged in at the display can change the keyboard "
      @"settings.";
  else if (error == EINVAL && [key hasPrefix:@"KeyboardLayout"])
    why = [NSString stringWithFormat:@"WindowServer couldn't make a keymap "
                    @"of that layout, so Keyboard couldn't %@.", what];
  else if (error == EINVAL)
    why = [NSString stringWithFormat:@"WindowServer doesn't take that value "
                    @"of %@, so Keyboard couldn't %@.", key, what];
  else if (error == ENOTSUP)
    why = @"This WindowServer has no keyboard settings.";
  else
    why = [NSString stringWithFormat:@"WindowServer couldn't %@ (%s).", what,
                    strerror (error)];
  NSRunAlertPanel (@"Keyboard", @"%@", @"OK", nil, nil, why);
}

/* ---- actions ---- */

- (void)addSource:(id)sender
{
  if ([layouts count] >= KBMaxLayouts)
    return;
  [picker beginSheetForWindow:window];
}

- (void)removeSource:(id)sender
{
  NSInteger row = [sourceTable selectedRow];
  NSMutableArray *list = [NSMutableArray arrayWithArray:layouts];

  if (row < 0 || (NSUInteger) row >= [list count] || [list count] < 2)
    return;
  [list removeObjectAtIndex:row];
  if ([self setLayouts:list what:@"remove the input source"])
    [sourceTable selectRow:MIN ((NSUInteger) row, [layouts count] - 1)
      byExtendingSelection:NO];
}

- (void)switchToSource:(id)sender
{
  NSInteger row = [sourceTable selectedRow];
  int e;

  if (sender == sourceTable)
    row = [sourceTable clickedRow] >= 0 ? [sourceTable clickedRow] : row;
  if (row < 0 || (NSUInteger) row >= [layouts count])
    return;
  e = [connection setActiveLayout:(unsigned) row];
  if (e != 0)
    [self report:e key:nil what:@"switch to the layout"];
  [self connectionLayoutDidChange:connection];
}

- (void)chooseShortcut:(id)sender
{
  NSInteger i = [sender indexOfSelectedItem];

  if (i < 0 || i >= KBCount (KBShortcutValues))
    return;
  [self apply:[NSDictionary dictionaryWithObject:KBShortcutValues[i]
                                          forKey:KBKeyboardLayoutShortcut]
         what:@"change the switching keys"];
}

/* The Dock owns its extras: ask it (NBDockExtra). */
- (void)toggleShowMenu:(id)sender
{
  [dockExtra setShown:[sender state] == NSOnState];
  changed = YES;
  [self updateControls];
}

/* The Dock answered, or its extras changed some other way. */
- (void)dockExtraChanged:(NBDockExtra *)extra
{
  [self updateControls];
}

- (void)setRate:(id)sender
{
  int i = MAX (0, MIN ([sender intValue], KBCount (KBIntervals) - 1));

  [self apply:[NSDictionary dictionaryWithObject:
                              [NSString stringWithFormat:@"%d", KBIntervals[i]]
                                          forKey:KBKeyRepeatInterval]
         what:@"change the key repeat rate"];
}

- (void)setDelay:(id)sender
{
  int i = MAX (0, MIN ([sender intValue], KBCount (KBDelays) - 1));

  [self apply:[NSDictionary dictionaryWithObject:
                              [NSString stringWithFormat:@"%d", KBDelays[i]]
                                          forKey:KBKeyRepeatDelay]
         what:@"change the key repeat delay"];
}

- (void)chooseCaps:(id)sender
{
  NSMutableArray *options = [self options];
  NSInteger choice = [sender indexOfSelectedItem];
  int i;

  for (i = 1; i < KBCount (KBCapsOptions); i++)
    [options removeObject:KBCapsOptions[i]];
  [options removeObject:@"caps:ctrl_modifier"];
  if (choice > 0 && choice < KBCount (KBCapsOptions))
    [options addObject:KBCapsOptions[choice]];
  [self setOptions:options what:@"change what Caps Lock does"];
}

- (void)toggleSwap:(id)sender
{
  NSMutableArray *options = [self options];

  [options removeObject:KBSwapOption];
  if ([sender state] == NSOnState)
    [options addObject:KBSwapOption];
  [self setOptions:options what:@"swap Command and Option"];
}

/* Back to the system's settings: the session's values and the user's
   defaults of every keyboard key go. */
- (void)useDefaults:(id)sender
{
  NSMutableDictionary *values = [NSMutableDictionary dictionary];
  NSEnumerator *e = [KBKeyboardKeys () objectEnumerator];
  NSString *key;

  while ((key = [e nextObject]) != nil)
    [values setObject:[NSNull null] forKey:key];
  KBSaveDefaults (KBKeyboardDomain,
                  [NSDictionary dictionaryWithObject:[NSNull null]
                                              forKey:KBInputSources]);
  if (![dockExtra isShown])
    [dockExtra setShown:YES];
  if ([self apply:values what:@"go back to the default settings"])
    changed = YES;
  [self updateControls];
}

/* Back to the settings from when Keyboard opened. */
- (void)revert:(id)sender
{
  NSString *failed = nil;
  int e;

  if (launchSession == nil)
    return;
  e = [connection setSettings:launchSession failedKey:&failed];
  if (e != 0)
    {
      [self report:e key:failed what:@"revert the settings"];
      [self reload];
      return;
    }
  KBSaveDefaults (KBWindowServerDomain, launchDefaults);
  if ([dockExtra isShown] != launchShowsMenu)
    [dockExtra setShown:launchShowsMenu];
  [self reload];
  [self saveInputSources];
  changed = NO;
  [self updateControls];
}

@end
