/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "PRController.h"
#import "PRCups.h"
#import "NBSettingsHelper.h"
#import <GNUstepBase/GNUstep.h>

#include <cups/cups.h>

/* Layout, in points, as Date & Time's. */
#define PRMargin 20.0
#define PRWindowWidth 640.0
#define PRListWidth 210.0
#define PRTopHeight 340.0
#define PRDetailX (PRMargin + PRListWidth + 16)
#define PRDetailWidth (PRWindowWidth - PRDetailX - PRMargin)
#define PRLabelWidth 88.0
#define PRFieldX (PRLabelWidth + 8)
#define PRRowGap 10.0
#define PRButtonWidth 100.0
#define PRButtonHeight 26.0
/* The lock and its sentence, beside Defaults and Revert. */
#define PRLockWidth (PRWindowWidth - 2 * PRMargin - 2 * PRButtonWidth - 16)

static NSString *const PRRight = @"org.nextbsd.settings.printers";
static NSString *const PRReason = @"add and remove printers";

/* A helper operation, for -run:. */
static NSString *const PROpKey = @"op";
static NSString *const PROpAdd = @"add";
static NSString *const PROpRemove = @"remove";
static NSString *const PROpStatus = @"status";
static NSString *const PROpRetried = @"retried";

/* What's posted back to the main thread runs in a sheet or a panel
   too. */
static NSArray *
PRModes (void)
{
  return [NSArray arrayWithObjects:NSDefaultRunLoopMode,
                  NSModalPanelRunLoopMode, NSEventTrackingRunLoopMode, nil];
}

/* A view laid out from the top down. */
@interface PRFlippedView : NSView
@end

@implementation PRFlippedView
- (BOOL)isFlipped
{
  return YES;
}
@end

static NSTextField *
PRLabel (NSRect frame, NSString *text, NSFont *font)
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
PRRowLabel (CGFloat y, NSString *text)
{
  NSTextField *label = PRLabel (NSMakeRect (0, y + 3, PRLabelWidth, 20), text,
                                nil);
  [label setAlignment:NSRightTextAlignment];
  return label;
}

static NSFont *
PRSmallFont (void)
{
  return [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
}

/* A value beside a row label; it can be selected and copied. */
static NSTextField *
PRValue (CGFloat y, CGFloat width)
{
  NSTextField *value = PRLabel (NSMakeRect (PRFieldX, y + 3, width - PRFieldX,
                                            20), nil, nil);
  [value setSelectable:YES];
  return value;
}

/* Both nil, or equal. */
static BOOL
PRSame (id a, id b)
{
  return a == b || [a isEqual:b];
}

static NSString *
PRJobStateText (int state)
{
  switch (state)
    {
    case IPP_JSTATE_PROCESSING:
      return @"Printing";
    case IPP_JSTATE_HELD:
      return @"On hold";
    case IPP_JSTATE_STOPPED:
      return @"Stopped";
    default:
      return @"Waiting";
    }
}

@interface PRController (Private)
- (void)buildMenu;
- (NSView *)listView;
- (NSView *)detailView;
- (NSView *)bottomRow;
- (void)tick:(NSTimer *)t;
- (void)reload;
- (void)updateControls;
- (void)updateDetail;
- (void)fillPopup:(NSPopUpButton *)popup option:(NSString *)option
           values:(NSArray *)values byDefault:(NSString *)byDefault
          current:(NSString *)current;
- (void)loadChoices;
- (NSDictionary *)selectedPrinter;
- (void)selectPrinterNamed:(NSString *)name;
- (NSArray *)queueNames;
- (void)run:(NSDictionary *)op;
- (void)perform:(NSDictionary *)op;
- (void)performed:(NSDictionary *)op;
- (void)addPrinter:(id)sender;
- (void)removePrinter:(id)sender;
- (void)chooseDefault:(id)sender;
- (void)chooseOption:(id)sender;
- (void)useDefaults:(id)sender;
- (void)revert:(id)sender;
@end

@implementation PRController

- (void)dealloc
{
  [timer invalidate];
  RELEASE (timer);
  RELEASE (window);
  RELEASE (auth);
  RELEASE (lockView);
  RELEASE (addPanel);
  RELEASE (detailView);
  RELEASE (printers);
  RELEASE (selectedName);
  RELEASE (shownState);
  RELEASE (choicesFor);
  RELEASE (mediaValues);
  RELEASE (mediaDefault);
  RELEASE (sidesValues);
  RELEASE (sidesDefault);
  RELEASE (originalDefault);
  RELEASE (originalOptions);
  [super dealloc];
}

- (void)applicationDidFinishLaunching:(NSNotification *)note
{
  NSImage *icon = [NSImage imageNamed:@"Printers.png"];
  PRFlippedView *content;
  NSView *view;
  NSMutableDictionary *options = [NSMutableDictionary dictionary];
  NSEnumerator *e;
  NSDictionary *p;
  CGFloat height, y;

  if (icon != nil)
    [NSApp setApplicationIconImage:icon];
  [self buildMenu];

  auth = RETAIN ([NBAuthorization authorizationWithRight:PRRight]);
  lockView = [[NBLockView alloc]
                initWithFrame:NSMakeRect (0, 0, PRLockWidth, 30)
                authorization:auth
                       reason:PRReason];
  [lockView setDelegate:self];
  addPanel = [[PRAddPanel alloc] initWithDelegate:self];

  /* For Revert: the default printer and each printer's options. */
  ASSIGN (printers, PRCupsPrinters ());
  e = [printers objectEnumerator];
  while ((p = [e nextObject]) != nil)
    {
      NSMutableDictionary *own = [NSMutableDictionary dictionary];

      if ([[p objectForKey:PRDefault] boolValue])
        ASSIGN (originalDefault, [p objectForKey:PRName]);
      if ([p objectForKey:PRMedia] != nil)
        [own setObject:[p objectForKey:PRMedia] forKey:PROptionMedia];
      if ([p objectForKey:PRSides] != nil)
        [own setObject:[p objectForKey:PRSides] forKey:PROptionSides];
      [options setObject:own forKey:[p objectForKey:PRName]];
    }
  ASSIGN (originalOptions, options);

  height = PRMargin + PRTopHeight + PRRowGap + 26 + 2 * PRRowGap + 30
    + PRMargin;
  window = [[NSWindow alloc]
      initWithContentRect:NSMakeRect (200, 200, PRWindowWidth, height)
                styleMask:NSTitledWindowMask | NSClosableWindowMask
                          | NSMiniaturizableWindowMask
                  backing:NSBackingStoreBuffered
                    defer:NO];
  [window setTitle:@"Printers"];
  [window setReleasedWhenClosed:NO];
  [window setFrameAutosaveName:@"Printers"];

  content = AUTORELEASE ([[PRFlippedView alloc]
                           initWithFrame:NSMakeRect (0, 0, PRWindowWidth,
                                                     height)]);
  view = [self listView];
  [view setFrameOrigin:NSMakePoint (PRMargin, PRMargin)];
  [content addSubview:view];

  detailView = RETAIN ([self detailView]);
  [detailView setFrameOrigin:NSMakePoint (PRDetailX, PRMargin)];
  [content addSubview:detailView];
  emptyNote = PRLabel (NSMakeRect (PRDetailX, PRMargin + PRTopHeight / 2 - 30,
                                   PRDetailWidth, 40), nil, nil);
  [emptyNote setAlignment:NSCenterTextAlignment];
  [content addSubview:emptyNote];

  /* The default printer, under both. */
  y = PRMargin + PRTopHeight + PRRowGap;
  [content addSubview:PRLabel (NSMakeRect (PRMargin, y + 3, 110, 20),
                               @"Default printer:", nil)];
  defaultPopup = AUTORELEASE ([[NSPopUpButton alloc]
                                initWithFrame:NSMakeRect (PRMargin + 118, y,
                                                          280, 26)
                                    pullsDown:NO]);
  [defaultPopup setTarget:self];
  [defaultPopup setAction:@selector (chooseDefault:)];
  [content addSubview:defaultPopup];
  y += 26 + 2 * PRRowGap;

  view = [self bottomRow];
  [view setFrameOrigin:NSMakePoint (PRMargin, y)];
  [content addSubview:view];
  [window setContentView:content];

  if ([printers count] > 0)
    {
      NSString *first = originalDefault;

      if (first == nil)
        first = [[printers objectAtIndex:0] objectForKey:PRName];
      ASSIGN (selectedName, first);
    }
  [self reload];
  [window makeKeyAndOrderFront:self];

  ASSIGN (timer, [NSTimer scheduledTimerWithTimeInterval:2.0
                                                  target:self
                                                selector:@selector (tick:)
                                                userInfo:nil
                                                 repeats:YES]);
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app
{
  return YES;
}

/* Printers has no documents; a file it's asked to open just brings the
   window forward. */
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

/* ---- the tables ---- */

- (NSInteger)numberOfRowsInTableView:(NSTableView *)table
{
  if (table == printerTable)
    return (NSInteger) [printers count];
  return (NSInteger) [[[self selectedPrinter] objectForKey:PRJobs] count];
}

- (id)tableView:(NSTableView *)table
    objectValueForTableColumn:(NSTableColumn *)column
                          row:(NSInteger)row
{
  NSString *which = [column identifier];
  NSArray *rows = table == printerTable
    ? printers : [[self selectedPrinter] objectForKey:PRJobs];
  NSDictionary *item;

  if (row < 0 || (NSUInteger) row >= [rows count])
    return nil;
  item = [rows objectAtIndex:row];
  if (table == printerTable)
    {
      if ([which isEqual:@"default"])
        return [[item objectForKey:PRDefault] boolValue]
          ? [NSString stringWithUTF8String:"\xE2\x9C\x93"] : @"";
      return [item objectForKey:PRInfo];
    }
  if ([which isEqual:@"user"])
    return [item objectForKey:PRJobUser];
  if ([which isEqual:@"state"])
    return PRJobStateText ([[item objectForKey:PRJobState] intValue]);
  return [item objectForKey:PRJobTitle];
}

- (BOOL)tableView:(NSTableView *)table shouldEditTableColumn:(NSTableColumn *)c
              row:(NSInteger)row
{
  return NO;
}

- (BOOL)tableView:(NSTableView *)table shouldSelectRow:(NSInteger)row
{
  return table == printerTable;
}

- (void)tableViewSelectionDidChange:(NSNotification *)note
{
  NSInteger row = [printerTable selectedRow];

  if ([note object] != printerTable || selecting)
    return;
  if (row >= 0 && (NSUInteger) row < [printers count])
    ASSIGN (selectedName, [[printers objectAtIndex:row] objectForKey:PRName]);
  else
    DESTROY (selectedName);
  DESTROY (shownState);
  [self reload];
}

/* ---- adding ---- */

- (void)addPanel:(PRAddPanel *)panel
    didChooseURI:(NSString *)uri
            info:(NSString *)info
        location:(NSString *)location
{
  [self run:[NSDictionary dictionaryWithObjectsAndKeys:
                            PROpAdd, PROpKey,
                            PRCupsQueueName (info, [self queueNames]), PRName,
                            uri, PRDeviceURI, info, PRInfo,
                            location, PRLocation, nil]];
}

@end

@implementation PRController (Private)

- (void)buildMenu
{
  NSMenu *menu = AUTORELEASE ([[NSMenu alloc] initWithTitle:@"Printers"]);
  NSMenu *edit = AUTORELEASE ([[NSMenu alloc] initWithTitle:@"Edit"]);
  NSMenu *windows = AUTORELEASE ([[NSMenu alloc] initWithTitle:@"Window"]);
  id<NSMenuItem> item;

  [menu addItemWithTitle:@"About Printers"
                  action:@selector (orderFrontStandardAboutPanel:)
           keyEquivalent:@""];
  /* The Add Printer sheet takes typing, so cut, copy and paste. */
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

/* ---- the window's parts ---- */

/* The printers, with + and - under them. */
- (NSView *)listView
{
  PRFlippedView *view = AUTORELEASE ([[PRFlippedView alloc]
                                       initWithFrame:NSMakeRect (0, 0,
                                                                 PRListWidth,
                                                                 PRTopHeight)]);
  NSScrollView *scroll;
  NSTableColumn *column;
  NSSize inner;
  CGFloat y = PRTopHeight - 24;

  scroll = AUTORELEASE ([[NSScrollView alloc]
                          initWithFrame:NSMakeRect (0, 0, PRListWidth,
                                                    y - 6)]);
  [scroll setHasVerticalScroller:YES];
  [scroll setBorderType:NSBezelBorder];
  inner = [NSScrollView contentSizeForFrameSize:[scroll frame].size
                          hasHorizontalScroller:NO
                            hasVerticalScroller:YES
                                     borderType:NSBezelBorder];
  printerTable = AUTORELEASE ([[NSTableView alloc]
                                initWithFrame:NSMakeRect (0, 0, inner.width,
                                                          inner.height)]);
  column = AUTORELEASE ([[NSTableColumn alloc] initWithIdentifier:@"default"]);
  [[column headerCell] setStringValue:@""];
  [[column dataCell] setAlignment:NSCenterTextAlignment];
  [column setWidth:20];
  [column setMinWidth:20];
  [column setEditable:NO];
  [printerTable addTableColumn:column];
  column = AUTORELEASE ([[NSTableColumn alloc] initWithIdentifier:@"name"]);
  [[column headerCell] setStringValue:@"Printers"];
  [column setWidth:inner.width - 20 - 8];
  [column setEditable:NO];
  [printerTable addTableColumn:column];
  [printerTable setAllowsMultipleSelection:NO];
  [printerTable setAllowsEmptySelection:YES];
  [printerTable setAllowsColumnReordering:NO];
  [printerTable setDataSource:(id)self];
  [printerTable setDelegate:(id)self];
  [scroll setDocumentView:printerTable];
  [view addSubview:scroll];

  addButton = AUTORELEASE ([[NSButton alloc]
                             initWithFrame:NSMakeRect (0, y, 28, 24)]);
  [addButton setTitle:@"+"];
  [addButton setTarget:self];
  [addButton setAction:@selector (addPrinter:)];
  [view addSubview:addButton];
  removeButton = AUTORELEASE ([[NSButton alloc]
                                initWithFrame:NSMakeRect (30, y, 28, 24)]);
  [removeButton setTitle:[NSString stringWithUTF8String:"\xE2\x88\x92"]];
  [removeButton setTarget:self];
  [removeButton setAction:@selector (removePrinter:)];
  [view addSubview:removeButton];
  progressNote = PRLabel (NSMakeRect (66, y + 4, PRListWidth - 66, 16), nil,
                          PRSmallFont ());
  [view addSubview:progressNote];
  return view;
}

/* The selected printer. */
- (NSView *)detailView
{
  PRFlippedView *view = [[PRFlippedView alloc]
                          initWithFrame:NSMakeRect (0, 0, PRDetailWidth,
                                                    PRTopHeight)];
  CGFloat width = PRDetailWidth, y = 0;
  NSScrollView *scroll;
  NSTableColumn *column;
  NSString *const ids[] = { @"title", @"user", @"state" };
  NSString *const titles[] = { @"Document", @"Owner", @"Status" };
  const CGFloat share[] = { 0.5, 0.25, 0.25 };
  NSSize inner;
  int i;

  nameLabel = PRLabel (NSMakeRect (0, y, width, 22), nil,
                       [NSFont boldSystemFontOfSize:15]);
  [view addSubview:nameLabel];
  y += 22 + PRRowGap;

  [view addSubview:PRRowLabel (y, @"Status:")];
  statusField = PRValue (y, width);
  [view addSubview:statusField];
  y += 22;
  [view addSubview:PRRowLabel (y, @"Location:")];
  locationField = PRValue (y, width);
  [view addSubview:locationField];
  y += 22;
  [view addSubview:PRRowLabel (y, @"Kind:")];
  kindField = PRValue (y, width);
  [view addSubview:kindField];
  y += 22;
  [view addSubview:PRRowLabel (y, @"Address:")];
  addressField = PRValue (y, width);
  [addressField setFont:PRSmallFont ()];
  [view addSubview:addressField];
  y += 22;
  [view addSubview:PRRowLabel (y, @"Queue:")];
  queueField = PRValue (y, width);
  [view addSubview:queueField];
  y += 22 + 4;

  scroll = AUTORELEASE ([[NSScrollView alloc]
                          initWithFrame:NSMakeRect (PRFieldX, y,
                                                    width - PRFieldX, 82)]);
  [scroll setHasVerticalScroller:YES];
  [scroll setBorderType:NSBezelBorder];
  inner = [NSScrollView contentSizeForFrameSize:[scroll frame].size
                          hasHorizontalScroller:NO
                            hasVerticalScroller:YES
                                     borderType:NSBezelBorder];
  jobTable = AUTORELEASE ([[NSTableView alloc]
                            initWithFrame:NSMakeRect (0, 0, inner.width,
                                                      inner.height)]);
  for (i = 0; i < 3; i++)
    {
      column = AUTORELEASE ([[NSTableColumn alloc] initWithIdentifier:ids[i]]);
      [[column headerCell] setStringValue:titles[i]];
      [column setWidth:(inner.width - 12) * share[i]];
      [column setEditable:NO];
      [jobTable addTableColumn:column];
    }
  [jobTable setAllowsEmptySelection:YES];
  [jobTable setDataSource:(id)self];
  [jobTable setDelegate:(id)self];
  [scroll setDocumentView:jobTable];
  [view addSubview:scroll];
  y += 82 + 2 * PRRowGap;

  [view addSubview:PRRowLabel (y, @"Paper size:")];
  mediaPopup = AUTORELEASE ([[NSPopUpButton alloc]
                              initWithFrame:NSMakeRect (PRFieldX, y,
                                                        width - PRFieldX, 26)
                                  pullsDown:NO]);
  [mediaPopup setTarget:self];
  [mediaPopup setAction:@selector (chooseOption:)];
  [view addSubview:mediaPopup];
  y += 26 + 6;
  [view addSubview:PRRowLabel (y, @"Two-sided:")];
  sidesPopup = AUTORELEASE ([[NSPopUpButton alloc]
                              initWithFrame:NSMakeRect (PRFieldX, y, 200, 26)
                                  pullsDown:NO]);
  [sidesPopup setTarget:self];
  [sidesPopup setAction:@selector (chooseOption:)];
  [view addSubview:sidesPopup];
  y += 26 + 6;
  [view addSubview:PRLabel (NSMakeRect (PRFieldX, y, width - PRFieldX, 16),
                            @"Yours alone: no password needed.", PRSmallFont ())];
  return AUTORELEASE (view);
}

/* The lock at the left, Defaults and Revert at the right. */
- (NSView *)bottomRow
{
  CGFloat width = PRWindowWidth - 2 * PRMargin;
  PRFlippedView *row = AUTORELEASE ([[PRFlippedView alloc]
                                      initWithFrame:NSMakeRect (0, 0, width,
                                                                30)]);
  NSButton *defaults, *revert;

  [lockView setFrameOrigin:NSMakePoint (0, 0)];
  [row addSubview:lockView];

  revert = AUTORELEASE ([[NSButton alloc]
                          initWithFrame:NSMakeRect (width - PRButtonWidth, 2,
                                                    PRButtonWidth,
                                                    PRButtonHeight)]);
  [revert setTitle:@"Revert"];
  [revert setTarget:self];
  [revert setAction:@selector (revert:)];
  [row addSubview:revert];

  defaults = AUTORELEASE ([[NSButton alloc]
                            initWithFrame:NSMakeRect (width - 2 * PRButtonWidth
                                                      - 8, 2, PRButtonWidth,
                                                      PRButtonHeight)]);
  [defaults setTitle:@"Defaults"];
  [defaults setTarget:self];
  [defaults setAction:@selector (useDefaults:)];
  [row addSubview:defaults];
  return row;
}

/* ---- following the system ---- */

/* Every two seconds: the lock's time and anything changed elsewhere. */
- (void)tick:(NSTimer *)t
{
  [lockView update];
  [self reload];
}

/* Read the printers again, and set the controls if anything shown
   changed. */
- (void)reload
{
  NSString *state;

  ASSIGN (printers, PRCupsPrinters ());
  if (selectedName != nil && [self selectedPrinter] == nil)
    DESTROY (selectedName);	/* removed */
  if (selectedName == nil && [printers count] > 0)
    ASSIGN (selectedName, [[printers objectAtIndex:0] objectForKey:PRName]);
  state = [NSString stringWithFormat:@"%@ %@ %d %d %d", printers,
                    selectedName, (int) [lockView isUnlocked], [auth status],
                    (int) busy];
  if ([state isEqual:shownState])
    return;
  ASSIGN (shownState, state);
  [self updateControls];
}

- (void)updateControls
{
  BOOL unlocked = [lockView isUnlocked];
  NSDictionary *selected = [self selectedPrinter];
  NSEnumerator *e;
  NSDictionary *p;

  [printerTable reloadData];
  [self selectPrinterNamed:selectedName];
  [addButton setEnabled:unlocked && !busy && printers != nil];
  [removeButton setEnabled:unlocked && !busy && selected != nil];

  [defaultPopup removeAllItems];
  if ([printers count] == 0
      || ![[printers valueForKey:PRDefault]
            containsObject:[NSNumber numberWithBool:YES]])
    [defaultPopup addItemWithTitle:@"None"];	/* rather than the first */
  e = [printers objectEnumerator];
  while ((p = [e nextObject]) != nil)
    {
      [defaultPopup addItemWithTitle:[p objectForKey:PRInfo]];
      [[defaultPopup lastItem] setRepresentedObject:[p objectForKey:PRName]];
      if ([[p objectForKey:PRDefault] boolValue])
        [defaultPopup selectItem:[defaultPopup lastItem]];
    }
  [defaultPopup setEnabled:[printers count] > 0];

  if (printers == nil)
    [emptyNote setStringValue:@"The printing system (cupsd) isn't "
                              @"answering. Is nextbsd-printing-support "
                              @"installed?"];
  else if ([printers count] == 0)
    [emptyNote setStringValue:@"No printers are set up.\n"
                              @"Click + to add one."];
  else
    [emptyNote setStringValue:@""];
  [detailView setHidden:selected == nil];
  [self updateDetail];
}

- (void)updateDetail
{
  NSDictionary *p = [self selectedPrinter];
  NSUInteger jobs;

  if (p == nil)
    return;
  [nameLabel setStringValue:[p objectForKey:PRInfo]];
  [statusField setStringValue:PRCupsStateText (p)];
  [locationField setStringValue:[p objectForKey:PRLocation] != nil
                    ? [p objectForKey:PRLocation] : @""];
  [kindField setStringValue:[p objectForKey:PRModel] != nil
                ? [p objectForKey:PRModel] : @""];
  [addressField setStringValue:[p objectForKey:PRDeviceURI] != nil
                   ? [p objectForKey:PRDeviceURI] : @""];
  jobs = [[p objectForKey:PRJobs] count];
  [queueField setStringValue:jobs == 0 ? @"No documents waiting"
              : jobs == 1 ? @"1 document"
              : [NSString stringWithFormat:@"%lu documents",
                          (unsigned long) jobs]];
  [jobTable reloadData];

  [self loadChoices];
  [self fillPopup:mediaPopup option:PROptionMedia values:mediaValues
        byDefault:mediaDefault current:[p objectForKey:PRMedia]];
  [self fillPopup:sidesPopup option:PROptionSides values:sidesValues
        byDefault:sidesDefault current:[p objectForKey:PRSides]];
}

/* An option's values, the user's (else the printer's default) chosen. */
- (void)fillPopup:(NSPopUpButton *)popup option:(NSString *)option
           values:(NSArray *)values byDefault:(NSString *)byDefault
          current:(NSString *)current
{
  NSEnumerator *e = [values objectEnumerator];
  NSString *value;

  if (current == nil)
    current = byDefault;
  [popup removeAllItems];
  while ((value = [e nextObject]) != nil)
    {
      [popup addItemWithTitle:PRCupsValueName (option, value)];
      [[popup lastItem] setRepresentedObject:value];
      if ([value isEqual:current])
        [popup selectItem:[popup lastItem]];
    }
  if ([values count] == 0)
    [popup addItemWithTitle:@"Not offered"];
  [popup setEnabled:[values count] > 1];
}

/* What the selected printer offers, asked once per selection (and again
   when the printer changes). */
- (void)loadChoices
{
  NSDictionary *p = [self selectedPrinter];
  NSString *key = [NSString stringWithFormat:@"%@ %@ %@", selectedName,
                            [p objectForKey:PRModel],
                            [p objectForKey:PRDeviceURI]];
  NSString *byDefault;

  if ([key isEqual:choicesFor])
    return;
  ASSIGN (choicesFor, key);
  ASSIGN (mediaValues, PRCupsChoices (selectedName, PROptionMedia,
                                      &byDefault));
  ASSIGN (mediaDefault, byDefault);
  ASSIGN (sidesValues, PRCupsChoices (selectedName, PROptionSides,
                                      &byDefault));
  ASSIGN (sidesDefault, byDefault);
}

- (NSDictionary *)selectedPrinter
{
  NSEnumerator *e = [printers objectEnumerator];
  NSDictionary *p;

  while ((p = [e nextObject]) != nil)
    if ([[p objectForKey:PRName] isEqual:selectedName])
      return p;
  return nil;
}

- (void)selectPrinterNamed:(NSString *)name
{
  NSUInteger i;

  selecting = YES;
  [printerTable deselectAll:self];
  for (i = 0; i < [printers count]; i++)
    if ([[[printers objectAtIndex:i] objectForKey:PRName] isEqual:name])
      {
        [printerTable selectRow:i byExtendingSelection:NO];
        break;
      }
  selecting = NO;
}

- (NSArray *)queueNames
{
  return [printers valueForKey:PRName];
}

/* ---- changes through the helper ---- */

/* Add or remove, on another thread: adding asks the printer what it
   can do, which can take seconds. */
- (void)run:(NSDictionary *)op
{
  NSString *info = [op objectForKey:PRInfo];

  if (busy || (![lockView isUnlocked] && ![lockView unlock]))
    return;
  busy = YES;
  [progressNote setStringValue:
      [NSString stringWithFormat:[[op objectForKey:PROpKey] isEqual:PROpAdd]
                                   ? @"Adding %@…" : @"Removing %@…",
                info]];
  DESTROY (shownState);
  [self reload];
  [NSThread detachNewThreadSelector:@selector (perform:)
                           toTarget:self
                         withObject:op];
}

- (void)perform:(NSDictionary *)op
{
  CREATE_AUTORELEASE_POOL (pool);
  NSMutableDictionary *done = [NSMutableDictionary dictionaryWithDictionary:op];
  int status;

  if ([[op objectForKey:PROpKey] isEqual:PROpAdd])
    status = [NBSettingsHelper addPrinter:[op objectForKey:PRName]
                                      uri:[op objectForKey:PRDeviceURI]
                                     info:[op objectForKey:PRInfo]
                                 location:[op objectForKey:PRLocation]
                            authorization:auth];
  else
    status = [NBSettingsHelper removePrinter:[op objectForKey:PRName]
                               authorization:auth];
  [done setObject:[NSNumber numberWithInt:status] forKey:PROpStatus];
  [self performSelectorOnMainThread:@selector (performed:)
                         withObject:done
                      waitUntilDone:NO
                              modes:PRModes ()];
  RELEASE (pool);
}

- (void)performed:(NSDictionary *)op
{
  int status = [[op objectForKey:PROpStatus] intValue];
  BOOL adding = [[op objectForKey:PROpKey] isEqual:PROpAdd];
  NSString *info = [op objectForKey:PRInfo];

  busy = NO;
  [progressNote setStringValue:@""];
  if (status == NBAuthorizationNeeded && [op objectForKey:PROpRetried] == nil)
    {
      /* The helper no longer holds the right (it ran out, or the helper
         was restarted): close the lock, then ask. */
      NSMutableDictionary *again = [NSMutableDictionary
                                     dictionaryWithDictionary:op];

      [auth refresh];
      [lockView update];
      [again setObject:@"yes" forKey:PROpRetried];
      if ([lockView unlock])
        [self run:again];
      else
        {
          DESTROY (shownState);
          [self reload];
        }
      return;
    }
  if (status == NBAuthorizationChangeFailed && adding)
    NSRunAlertPanel (@"Printers", @"%@ couldn't be added. Check that the "
                     @"printer is on and that it's a driverless (IPP "
                     @"Everywhere or AirPrint) printer; others need "
                     @"drivers that aren't installed yet.", @"OK", nil, nil,
                     info);
  else if (status == NBAuthorizationChangeFailed)
    NSRunAlertPanel (@"Printers", @"%@ couldn't be removed.", @"OK", nil, nil,
                     info);
  else if (status == NBAuthorizationUnsupported)
    NSRunAlertPanel (@"Printers", @"Printing isn't installed on this "
                     @"computer (nextbsd-printing-support).", @"OK", nil,
                     nil);
  else if (status != NBAuthorizationOK)
    NSRunAlertPanel (@"Printers", @"%@", @"OK", nil, nil,
                     [NBAuthorization messageForStatus:status]);

  if (status == NBAuthorizationOK && adding)
    {
      NSString *name = [op objectForKey:PRName];
      BOOL anyDefault = [[printers valueForKey:PRDefault]
                          containsObject:[NSNumber numberWithBool:YES]];

      /* The first printer becomes the default, as there's no other. */
      if (!anyDefault)
        PRCupsSetDefault (name);
      ASSIGN (selectedName, name);
    }
  DESTROY (shownState);
  [self reload];
}

- (void)addPrinter:(id)sender
{
  if (busy || (![lockView isUnlocked] && ![lockView unlock]))
    return;
  [addPanel beginSheetForWindow:window queues:printers];
}

- (void)removePrinter:(id)sender
{
  NSDictionary *p = [self selectedPrinter];

  if (p == nil || busy)
    return;
  if (NSRunAlertPanel (@"Printers", @"Remove %@? Documents waiting for it "
                       @"are cancelled.", @"Remove", @"Cancel", nil,
                       [p objectForKey:PRInfo]) != NSAlertDefaultReturn)
    return;
  [self run:[NSDictionary dictionaryWithObjectsAndKeys:
                            PROpRemove, PROpKey,
                            [p objectForKey:PRName], PRName,
                            [p objectForKey:PRInfo], PRInfo, nil]];
}

/* ---- the user's own settings ---- */

- (void)chooseDefault:(id)sender
{
  NSString *name = [[defaultPopup selectedItem] representedObject];

  if (name != nil && !PRCupsSetDefault (name))
    NSRunAlertPanel (@"Printers", @"The default printer couldn't be "
                     @"saved (~/.cups/lpoptions).", @"OK", nil, nil);
  DESTROY (shownState);
  [self reload];
}

/* Paper size or two-sided: the printer's own default is kept as no
   setting at all. */
- (void)chooseOption:(id)sender
{
  NSString *option = sender == mediaPopup ? PROptionMedia : PROptionSides;
  NSString *byDefault = sender == mediaPopup ? mediaDefault : sidesDefault;
  NSString *value = [[sender selectedItem] representedObject];

  if (selectedName == nil || value == nil)
    return;
  if (!PRCupsSetOption (selectedName, option,
                        [value isEqual:byDefault] ? nil : value))
    NSRunAlertPanel (@"Printers", @"The setting couldn't be saved "
                     @"(~/.cups/lpoptions).", @"OK", nil, nil);
  DESTROY (shownState);
  [self reload];
}

/* Every printer's paper size and two-sided back to the printer's own.
   The printers and the default printer stay. */
- (void)useDefaults:(id)sender
{
  NSEnumerator *e = [printers objectEnumerator];
  NSDictionary *p;

  while ((p = [e nextObject]) != nil)
    {
      if ([p objectForKey:PRMedia] != nil)
        PRCupsSetOption ([p objectForKey:PRName], PROptionMedia, nil);
      if ([p objectForKey:PRSides] != nil)
        PRCupsSetOption ([p objectForKey:PRName], PROptionSides, nil);
    }
  DESTROY (shownState);
  [self reload];
}

/* Back to the default printer and options from when the window opened.
   Printers added or removed since stay so: that's done with + and -. */
- (void)revert:(id)sender
{
  NSEnumerator *e = [printers objectEnumerator];
  NSDictionary *p;

  while ((p = [e nextObject]) != nil)
    {
      NSString *name = [p objectForKey:PRName];
      NSDictionary *own = [originalOptions objectForKey:name];

      if (own == nil)
        continue;		/* added since */
      if (!PRSame ([own objectForKey:PROptionMedia], [p objectForKey:PRMedia]))
        PRCupsSetOption (name, PROptionMedia,
                         [own objectForKey:PROptionMedia]);
      if (!PRSame ([own objectForKey:PROptionSides], [p objectForKey:PRSides]))
        PRCupsSetOption (name, PROptionSides,
                         [own objectForKey:PROptionSides]);
      if (originalDefault != nil && [name isEqual:originalDefault]
          && ![[p objectForKey:PRDefault] boolValue])
        PRCupsSetDefault (name);
    }
  DESTROY (shownState);
  [self reload];
}

@end
