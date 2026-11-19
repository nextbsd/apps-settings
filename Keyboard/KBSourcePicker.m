/*
 * Copyright (c) 2025 Simon Peter
 * Copyright (c) 2026 Παναγιώτης Ἀθανασιάδης
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "KBSourcePicker.h"
#import "KBXkbRegistry.h"
#import <GNUstepBase/GNUstep.h>

#define KBPickerWidth 560.0
#define KBPickerHeight 400.0
#define KBPickerMargin 20.0
#define KBPickerGap 8.0
#define KBPickerButtonWidth 96.0
#define KBPickerButtonHeight 28.0

@interface KBSourcePicker (Private)
- (void)buildPanel;
- (NSTableView *)tableIn:(NSView *)parent frame:(NSRect)frame;
- (void)filter;
- (void)selectLayoutRow;
- (NSString *)query;
- (void)add:(id)sender;
- (void)cancel:(id)sender;
- (void)sheetDidEnd:(NSWindow *)sheet
         returnCode:(NSInteger)code
        contextInfo:(void *)info;
@end

/* Does text contain query (already lowercase)? An empty query matches. */
static BOOL
KBMatches (NSString *text, NSString *query)
{
  return [query length] == 0
    || [[text lowercaseString] rangeOfString:query].location != NSNotFound;
}

@implementation KBSourcePicker

- (id)initWithDelegate:(id<KBSourcePickerDelegate>)aDelegate
{
  if ((self = [super init]) == nil)
    return nil;
  delegate = aDelegate;
  shownLayouts = [NSArray new];
  shownVariants = [NSArray new];
  [self buildPanel];
  return self;
}

- (void)dealloc
{
  [layoutTable setDataSource:nil];
  [layoutTable setDelegate:nil];
  [variantTable setDataSource:nil];
  [variantTable setDelegate:nil];
  [searchField setDelegate:nil];
  RELEASE (panel);
  RELEASE (shownLayouts);
  RELEASE (shownVariants);
  RELEASE (selectedLayout);
  [super dealloc];
}

- (void)beginSheetForWindow:(NSWindow *)window
{
  [searchField setStringValue:@""];
  [self filter];
  [panel makeFirstResponder:searchField];
  [NSApp beginSheet:panel
     modalForWindow:window
      modalDelegate:self
     didEndSelector:@selector (sheetDidEnd:returnCode:contextInfo:)
        contextInfo:NULL];
}

/* ---- the tables ---- */

- (NSInteger)numberOfRowsInTableView:(NSTableView *)table
{
  if (table == layoutTable)
    return (NSInteger) [shownLayouts count];
  if (table == variantTable)
    return selectedLayout != nil ? (NSInteger) [shownVariants count] + 1 : 0;
  return 0;
}

- (id)tableView:(NSTableView *)table
    objectValueForTableColumn:(NSTableColumn *)column
                          row:(NSInteger)row
{
  KBXkbRegistry *registry = [KBXkbRegistry sharedRegistry];

  if (row < 0)
    return nil;
  if (table == layoutTable && (NSUInteger) row < [shownLayouts count])
    return [registry nameOfLayout:[shownLayouts objectAtIndex:row]];
  if (table == variantTable)
    {
      if (row == 0)
        return [registry nameOfLayout:selectedLayout];
      if ((NSUInteger) row - 1 < [shownVariants count])
        return [[shownVariants objectAtIndex:row - 1] objectForKey:@"Name"];
    }
  return nil;
}

- (BOOL)tableView:(NSTableView *)table shouldEditTableColumn:(NSTableColumn *)c
              row:(NSInteger)row
{
  return NO;
}

- (void)tableViewSelectionDidChange:(NSNotification *)note
{
  if ([note object] == layoutTable)
    [self selectLayoutRow];
}

/* The search field. */
- (void)controlTextDidChange:(NSNotification *)note
{
  [self filter];
}

@end

@implementation KBSourcePicker (Private)

- (void)buildPanel
{
  NSView *content;
  NSTextField *label;
  NSButton *cancel;
  CGFloat y, tablesBottom, tablesHeight, half;

  panel = [[NSPanel alloc]
      initWithContentRect:NSMakeRect (0, 0, KBPickerWidth, KBPickerHeight)
                styleMask:NSTitledWindowMask
                  backing:NSBackingStoreBuffered
                    defer:NO];
  [panel setTitle:@"Add Input Source"];
  [panel setReleasedWhenClosed:NO];
  content = [panel contentView];

  y = KBPickerHeight - KBPickerMargin - 20;
  label = AUTORELEASE ([[NSTextField alloc]
                         initWithFrame:NSMakeRect (KBPickerMargin, y,
                                                   KBPickerWidth
                                                   - 2 * KBPickerMargin, 20)]);
  [label setStringValue:@"Choose a keyboard layout to add:"];
  [label setEditable:NO];
  [label setSelectable:NO];
  [label setBordered:NO];
  [label setBezeled:NO];
  [label setDrawsBackground:NO];
  [content addSubview:label];

  y -= KBPickerGap + 24;
  searchField = AUTORELEASE ([[NSTextField alloc]
                               initWithFrame:NSMakeRect (KBPickerMargin, y,
                                                         KBPickerWidth
                                                         - 2 * KBPickerMargin,
                                                         24)]);
  [searchField setDelegate:(id)self];
  [[searchField cell] setPlaceholderString:@"Search"];
  [content addSubview:searchField];

  tablesBottom = KBPickerMargin + KBPickerButtonHeight + 14;
  tablesHeight = y - KBPickerGap - tablesBottom;
  half = (KBPickerWidth - 2 * KBPickerMargin - KBPickerGap) / 2;
  layoutTable = [self tableIn:content
                        frame:NSMakeRect (KBPickerMargin, tablesBottom, half,
                                          tablesHeight)];
  variantTable = [self tableIn:content
                         frame:NSMakeRect (KBPickerMargin + half + KBPickerGap,
                                           tablesBottom, half, tablesHeight)];

  cancel = AUTORELEASE ([[NSButton alloc]
                          initWithFrame:NSMakeRect (KBPickerWidth - KBPickerMargin
                                                    - 2 * KBPickerButtonWidth
                                                    - KBPickerGap,
                                                    KBPickerMargin,
                                                    KBPickerButtonWidth,
                                                    KBPickerButtonHeight)]);
  [cancel setTitle:@"Cancel"];
  [cancel setTarget:self];
  [cancel setAction:@selector (cancel:)];
  [cancel setKeyEquivalent:@"\033"];
  [content addSubview:cancel];

  addButton = AUTORELEASE ([[NSButton alloc]
                             initWithFrame:NSMakeRect (KBPickerWidth
                                                       - KBPickerMargin
                                                       - KBPickerButtonWidth,
                                                       KBPickerMargin,
                                                       KBPickerButtonWidth,
                                                       KBPickerButtonHeight)]);
  [addButton setTitle:@"Add"];
  [addButton setTarget:self];
  [addButton setAction:@selector (add:)];
  [addButton setKeyEquivalent:@"\r"];
  [addButton setEnabled:NO];
  [content addSubview:addButton];

  [panel setInitialFirstResponder:searchField];
}

- (NSTableView *)tableIn:(NSView *)parent frame:(NSRect)frame
{
  NSScrollView *scroll = AUTORELEASE ([[NSScrollView alloc]
                                        initWithFrame:frame]);
  NSTableView *table;
  NSTableColumn *column;
  NSSize inner;

  [scroll setHasVerticalScroller:YES];
  [scroll setHasHorizontalScroller:NO];
  [scroll setBorderType:NSBezelBorder];
  inner = [NSScrollView contentSizeForFrameSize:frame.size
                          hasHorizontalScroller:NO
                            hasVerticalScroller:YES
                                     borderType:NSBezelBorder];
  table = AUTORELEASE ([[NSTableView alloc]
                         initWithFrame:NSMakeRect (0, 0, inner.width,
                                                   inner.height)]);
  column = AUTORELEASE ([[NSTableColumn alloc] initWithIdentifier:@"Name"]);
  [column setWidth:inner.width - 4];
  [column setEditable:NO];
  [table addTableColumn:column];
  [table setHeaderView:nil];
  [table setCornerView:nil];
  [table setAllowsMultipleSelection:NO];
  [table setAllowsEmptySelection:YES];
  [table setAutoresizesAllColumnsToFit:YES];
  [table setDataSource:(id)self];
  [table setDelegate:(id)self];
  [table setTarget:self];
  [table setDoubleAction:@selector (add:)];
  [scroll setDocumentView:table];
  [parent addSubview:scroll];
  return table;
}

- (NSString *)query
{
  return [[[searchField stringValue] stringByTrimmingCharactersInSet:
                                       [NSCharacterSet whitespaceCharacterSet]]
           lowercaseString];
}

/* The layouts whose code, name or a variant's name has the search. */
- (void)filter
{
  KBXkbRegistry *registry = [KBXkbRegistry sharedRegistry];
  NSString *query = [self query];
  NSMutableArray *list = [NSMutableArray array];
  NSEnumerator *e = [[registry layoutCodes] objectEnumerator];
  NSString *code;

  while ((code = [e nextObject]) != nil)
    {
      BOOL match = KBMatches (code, query)
        || KBMatches ([registry nameOfLayout:code], query);
      NSEnumerator *v = [[registry variantsOfLayout:code] objectEnumerator];
      NSDictionary *variant;

      while (!match && (variant = [v nextObject]) != nil)
        match = KBMatches ([variant objectForKey:@"Name"], query);
      if (match)
        [list addObject:code];
    }
  ASSIGN (shownLayouts, list);
  [layoutTable reloadData];
  [layoutTable deselectAll:nil];
  if ([list count] > 0)
    [layoutTable selectRow:0 byExtendingSelection:NO];
  [self selectLayoutRow];
}

/* Show the selected layout's variants: all of them, or only those
   with the search when the layout's own name hasn't it. */
- (void)selectLayoutRow
{
  KBXkbRegistry *registry = [KBXkbRegistry sharedRegistry];
  NSInteger row = [layoutTable selectedRow];
  NSString *query = [self query];
  NSMutableArray *list = [NSMutableArray array];
  BOOL layoutMatches = YES;

  DESTROY (selectedLayout);
  if (row >= 0 && (NSUInteger) row < [shownLayouts count])
    {
      NSArray *all;
      NSEnumerator *e;
      NSDictionary *variant;

      ASSIGN (selectedLayout, [shownLayouts objectAtIndex:row]);
      all = [registry variantsOfLayout:selectedLayout];
      layoutMatches = KBMatches (selectedLayout, query)
        || KBMatches ([registry nameOfLayout:selectedLayout], query);
      e = [all objectEnumerator];
      while ((variant = [e nextObject]) != nil)
        if (layoutMatches || KBMatches ([variant objectForKey:@"Name"], query))
          [list addObject:variant];
    }
  ASSIGN (shownVariants, list);
  [variantTable reloadData];
  [variantTable deselectAll:nil];
  /* The layout itself, or the first variant the search found. */
  if (selectedLayout != nil)
    [variantTable selectRow:(!layoutMatches && [list count] > 0 ? 1 : 0)
       byExtendingSelection:NO];
  [addButton setEnabled:(selectedLayout != nil)];
}

- (void)add:(id)sender
{
  NSInteger row = [variantTable selectedRow];
  NSString *variant = @"";
  NSString *layout;

  if (selectedLayout == nil)
    return;
  if (row >= 1 && (NSUInteger) row - 1 < [shownVariants count])
    variant = [[shownVariants objectAtIndex:row - 1] objectForKey:@"Code"];
  layout = AUTORELEASE (RETAIN (selectedLayout));
  [NSApp endSheet:panel returnCode:NSOKButton];
  [delegate sourcePicker:self didPickLayout:layout variant:variant];
}

- (void)cancel:(id)sender
{
  [NSApp endSheet:panel returnCode:NSCancelButton];
}

- (void)sheetDidEnd:(NSWindow *)sheet
         returnCode:(NSInteger)code
        contextInfo:(void *)info
{
  [sheet orderOut:self];
}

@end
