/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "PRAddPanel.h"
#import "PRCups.h"
#import <GNUstepBase/GNUstep.h>

#define PRAddWidth 520.0
#define PRAddHeight 430.0
#define PRAddMargin 20.0
#define PRAddGap 8.0
#define PRAddLabelWidth 80.0
#define PRAddButtonWidth 96.0
#define PRAddButtonHeight 28.0

/* How long one look for printers waits for DNS-SD, and how often. */
#define PRSearchMsec 3000
#define PRSearchSeconds 4.0

/* The sheet runs the run loop modally: what's posted to the main
   thread and the timer have to run then too. */
static NSArray *
PRModes (void)
{
  return [NSArray arrayWithObjects:NSDefaultRunLoopMode,
                  NSModalPanelRunLoopMode, NSEventTrackingRunLoopMode, nil];
}

static NSTextField *
PRAddLabel (NSRect frame, NSString *text)
{
  NSTextField *label = AUTORELEASE ([[NSTextField alloc] initWithFrame:frame]);
  [label setStringValue:text];
  [label setEditable:NO];
  [label setSelectable:NO];
  [label setBordered:NO];
  [label setBezeled:NO];
  [label setDrawsBackground:NO];
  return label;
}

@interface PRAddPanel (Private)
- (void)buildPanel;
- (NSTextField *)fieldWithLabel:(NSString *)text y:(CGFloat)y
                    placeholder:(NSString *)placeholder;
- (void)tick:(NSTimer *)t;
- (void)search:(NSArray *)known;
- (void)searchDone:(NSArray *)found;
- (void)fillFromRow;
- (void)updateAddButton;
- (void)add:(id)sender;
- (void)cancel:(id)sender;
- (void)stop;
- (void)sheetDidEnd:(NSWindow *)sheet
         returnCode:(NSInteger)code
        contextInfo:(void *)info;
@end

@implementation PRAddPanel

- (id)initWithDelegate:(id<PRAddPanelDelegate>)aDelegate
{
  if ((self = [super init]) == nil)
    return nil;
  delegate = aDelegate;
  nearby = [NSArray new];
  queues = [NSArray new];
  [self buildPanel];
  return self;
}

- (void)dealloc
{
  [timer invalidate];
  RELEASE (timer);
  [nearbyTable setDataSource:nil];
  [nearbyTable setDelegate:nil];
  RELEASE (panel);
  RELEASE (nearby);
  RELEASE (queues);
  [super dealloc];
}

- (void)beginSheetForWindow:(NSWindow *)window queues:(NSArray *)known
{
  ASSIGN (queues, known != nil ? known : [NSArray array]);
  ASSIGN (nearby, [NSArray array]);
  [nearbyTable reloadData];
  filling = YES;
  [addressField setStringValue:@""];
  [nameField setStringValue:@""];
  [locationField setStringValue:@""];
  filling = NO;
  nameTyped = NO;
  [searchNote setStringValue:@"Looking for printers nearby…"];
  [self updateAddButton];
  [panel makeFirstResponder:addressField];
  [NSApp beginSheet:panel
     modalForWindow:window
      modalDelegate:self
     didEndSelector:@selector (sheetDidEnd:returnCode:contextInfo:)
        contextInfo:NULL];
  [self tick:nil];
  ASSIGN (timer, [NSTimer timerWithTimeInterval:PRSearchSeconds
                                         target:self
                                       selector:@selector (tick:)
                                       userInfo:nil
                                        repeats:YES]);
  {
    NSEnumerator *e = [PRModes () objectEnumerator];
    NSString *mode;

    while ((mode = [e nextObject]) != nil)
      [[NSRunLoop currentRunLoop] addTimer:timer forMode:mode];
  }
}

/* ---- the table ---- */

- (NSInteger)numberOfRowsInTableView:(NSTableView *)table
{
  return (NSInteger) [nearby count];
}

- (id)tableView:(NSTableView *)table
    objectValueForTableColumn:(NSTableColumn *)column
                          row:(NSInteger)row
{
  NSDictionary *p;

  if (row < 0 || (NSUInteger) row >= [nearby count])
    return nil;
  p = [nearby objectAtIndex:row];
  if ([[column identifier] isEqual:@"kind"])
    return [p objectForKey:PRModel];
  return [p objectForKey:PRInfo];
}

- (BOOL)tableView:(NSTableView *)table shouldEditTableColumn:(NSTableColumn *)c
              row:(NSInteger)row
{
  return NO;
}

- (void)tableViewSelectionDidChange:(NSNotification *)note
{
  if (!filling)
    [self fillFromRow];
}

/* Typing: a typed address is no longer the list's printer. */
- (void)controlTextDidChange:(NSNotification *)note
{
  if (filling)
    return;
  if ([note object] == nameField)
    nameTyped = [[nameField stringValue] length] > 0;
  else if ([note object] == addressField)
    {
      filling = YES;
      [nearbyTable deselectAll:nil];
      filling = NO;
    }
  [self updateAddButton];
}

@end

@implementation PRAddPanel (Private)

- (void)buildPanel
{
  NSView *content;
  NSScrollView *scroll;
  NSTableColumn *column;
  NSButton *cancel;
  NSSize inner;
  CGFloat y, width = PRAddWidth - 2 * PRAddMargin, tableBottom;

  panel = [[NSPanel alloc]
      initWithContentRect:NSMakeRect (0, 0, PRAddWidth, PRAddHeight)
                styleMask:NSTitledWindowMask
                  backing:NSBackingStoreBuffered
                    defer:NO];
  [panel setTitle:@"Add Printer"];
  [panel setReleasedWhenClosed:NO];
  content = [panel contentView];

  y = PRAddHeight - PRAddMargin - 20;
  [content addSubview:PRAddLabel (NSMakeRect (PRAddMargin, y, width, 20),
                                  @"Printers nearby:")];

  /* From the bottom up: buttons, the three fields, the note. */
  tableBottom = PRAddMargin + PRAddButtonHeight + 16 + 3 * (24 + PRAddGap)
    + 4 + 16 + PRAddGap;
  scroll = AUTORELEASE ([[NSScrollView alloc]
                          initWithFrame:NSMakeRect (PRAddMargin, tableBottom,
                                                    width,
                                                    y - PRAddGap
                                                    - tableBottom)]);
  [scroll setHasVerticalScroller:YES];
  [scroll setBorderType:NSBezelBorder];
  inner = [NSScrollView contentSizeForFrameSize:[scroll frame].size
                          hasHorizontalScroller:NO
                            hasVerticalScroller:YES
                                     borderType:NSBezelBorder];
  nearbyTable = AUTORELEASE ([[NSTableView alloc]
                               initWithFrame:NSMakeRect (0, 0, inner.width,
                                                         inner.height)]);
  column = AUTORELEASE ([[NSTableColumn alloc] initWithIdentifier:@"name"]);
  [[column headerCell] setStringValue:@"Name"];
  [column setWidth:inner.width * 0.55];
  [column setEditable:NO];
  [nearbyTable addTableColumn:column];
  column = AUTORELEASE ([[NSTableColumn alloc] initWithIdentifier:@"kind"]);
  [[column headerCell] setStringValue:@"Kind"];
  [column setWidth:inner.width * 0.45 - 8];
  [column setEditable:NO];
  [nearbyTable addTableColumn:column];
  [nearbyTable setAllowsMultipleSelection:NO];
  [nearbyTable setAllowsEmptySelection:YES];
  [nearbyTable setDataSource:(id)self];
  [nearbyTable setDelegate:(id)self];
  [nearbyTable setTarget:self];
  [nearbyTable setDoubleAction:@selector (add:)];
  [scroll setDocumentView:nearbyTable];
  [content addSubview:scroll];

  y = tableBottom - PRAddGap / 2 - 16;
  searchNote = PRAddLabel (NSMakeRect (PRAddMargin, y, width, 16), @"");
  [searchNote setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
  [content addSubview:searchNote];

  y -= 4 + 24 + PRAddGap;
  addressField = [self fieldWithLabel:@"Address:" y:y
                          placeholder:@"printer.local, 192.168.1.20 or "
                                      @"ipp://…"];
  y -= 24 + PRAddGap;
  nameField = [self fieldWithLabel:@"Name:" y:y placeholder:@""];
  y -= 24 + PRAddGap;
  locationField = [self fieldWithLabel:@"Location:" y:y
                           placeholder:@"Optional"];

  cancel = AUTORELEASE ([[NSButton alloc]
                          initWithFrame:NSMakeRect (PRAddWidth - PRAddMargin
                                                    - 2 * PRAddButtonWidth
                                                    - PRAddGap,
                                                    PRAddMargin,
                                                    PRAddButtonWidth,
                                                    PRAddButtonHeight)]);
  [cancel setTitle:@"Cancel"];
  [cancel setTarget:self];
  [cancel setAction:@selector (cancel:)];
  [cancel setKeyEquivalent:@"\033"];
  [content addSubview:cancel];

  addButton = AUTORELEASE ([[NSButton alloc]
                             initWithFrame:NSMakeRect (PRAddWidth - PRAddMargin
                                                       - PRAddButtonWidth,
                                                       PRAddMargin,
                                                       PRAddButtonWidth,
                                                       PRAddButtonHeight)]);
  [addButton setTitle:@"Add"];
  [addButton setTarget:self];
  [addButton setAction:@selector (add:)];
  [addButton setKeyEquivalent:@"\r"];
  [addButton setEnabled:NO];
  [content addSubview:addButton];

  [panel setInitialFirstResponder:addressField];
}

- (NSTextField *)fieldWithLabel:(NSString *)text y:(CGFloat)y
                    placeholder:(NSString *)placeholder
{
  NSTextField *label = PRAddLabel (NSMakeRect (PRAddMargin, y + 3,
                                               PRAddLabelWidth, 20), text);
  NSTextField *field = AUTORELEASE ([[NSTextField alloc]
      initWithFrame:NSMakeRect (PRAddMargin + PRAddLabelWidth + PRAddGap, y,
                                PRAddWidth - 2 * PRAddMargin
                                - PRAddLabelWidth - PRAddGap, 24)]);

  [label setAlignment:NSRightTextAlignment];
  [[panel contentView] addSubview:label];
  [[field cell] setPlaceholderString:placeholder];
  [field setDelegate:(id)self];
  [[panel contentView] addSubview:field];
  return field;
}

/* Look again, unless a look is still running. */
- (void)tick:(NSTimer *)t
{
  if (looking)
    return;
  looking = YES;
  [NSThread detachNewThreadSelector:@selector (search:)
                           toTarget:self
                         withObject:queues];
}

/* On its own thread: DNS-SD can take its time. */
- (void)search:(NSArray *)known
{
  CREATE_AUTORELEASE_POOL (pool);
  NSArray *found = PRCupsNearby (known, PRSearchMsec);

  [self performSelectorOnMainThread:@selector (searchDone:)
                         withObject:found
                      waitUntilDone:NO
                              modes:PRModes ()];
  RELEASE (pool);
}

- (void)searchDone:(NSArray *)found
{
  NSInteger row = [nearbyTable selectedRow];
  NSString *selected = nil;
  NSUInteger i;

  looking = NO;
  if (timer == nil)
    return;			/* the sheet has gone */
  if (row >= 0 && (NSUInteger) row < [nearby count])
    selected = [[nearby objectAtIndex:row] objectForKey:PRDeviceURI];
  ASSIGN (nearby, found);
  filling = YES;
  [nearbyTable reloadData];
  [nearbyTable deselectAll:nil];
  for (i = 0; selected != nil && i < [nearby count]; i++)
    if ([[[nearby objectAtIndex:i] objectForKey:PRDeviceURI]
          isEqual:selected])
      [nearbyTable selectRow:i byExtendingSelection:NO];
  filling = NO;
  [searchNote setStringValue:
      [nearby count] > 0
        ? @"Choose a printer, or type its address."
        : @"No driverless (IPP Everywhere) printers found nearby. "
          @"Type a printer's address instead."];
}

/* The chosen printer's address, name and location. */
- (void)fillFromRow
{
  NSInteger row = [nearbyTable selectedRow];
  NSDictionary *p;

  if (row < 0 || (NSUInteger) row >= [nearby count])
    return;
  p = [nearby objectAtIndex:row];
  filling = YES;
  [addressField setStringValue:[p objectForKey:PRDeviceURI]];
  if (!nameTyped)
    [nameField setStringValue:[p objectForKey:PRInfo]];
  if ([[locationField stringValue] length] == 0
      && [p objectForKey:PRLocation] != nil)
    [locationField setStringValue:[p objectForKey:PRLocation]];
  filling = NO;
  [self updateAddButton];
}

- (void)updateAddButton
{
  NSString *name = [[nameField stringValue]
                     stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceCharacterSet]];

  [addButton setEnabled:PRCupsURIForAddress ([addressField stringValue]) != nil
                        && ([name length] > 0 || !nameTyped)];
}

- (void)add:(id)sender
{
  NSString *uri = PRCupsURIForAddress ([addressField stringValue]);
  NSCharacterSet *space = [NSCharacterSet whitespaceCharacterSet];
  NSString *info = [[nameField stringValue]
                     stringByTrimmingCharactersInSet:space];
  NSString *location = [[locationField stringValue]
                         stringByTrimmingCharactersInSet:space];

  if (uri == nil)
    return;
  /* No name: the address's host stands for it. */
  if ([info length] == 0)
    info = [[NSURL URLWithString:uri] host];
  if ([info length] == 0)
    info = @"Printer";
  RETAIN (self);
  [self stop];
  [NSApp endSheet:panel returnCode:NSOKButton];
  [delegate addPanel:self didChooseURI:uri info:info location:location];
  RELEASE (self);
}

- (void)cancel:(id)sender
{
  [self stop];
  [NSApp endSheet:panel returnCode:NSCancelButton];
}

- (void)stop
{
  [timer invalidate];
  DESTROY (timer);
}

- (void)sheetDidEnd:(NSWindow *)sheet
         returnCode:(NSInteger)code
        contextInfo:(void *)info
{
  [sheet orderOut:self];
}

@end
