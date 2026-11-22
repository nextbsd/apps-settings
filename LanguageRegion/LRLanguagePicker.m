/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "LRLanguagePicker.h"
#import "LRLocales.h"
#import <GNUstepBase/GNUstep.h>

#define LRPickerWidth 460.0
#define LRPickerHeight 400.0
#define LRPickerMargin 20.0
#define LRPickerGap 8.0
#define LRPickerButtonWidth 96.0
#define LRPickerButtonHeight 28.0

@interface LRLanguagePicker (Private)
- (void)buildPanel;
- (void)filter;
- (void)add:(id)sender;
- (void)cancel:(id)sender;
- (void)sheetDidEnd:(NSWindow *)sheet
         returnCode:(NSInteger)code
        contextInfo:(void *)info;
@end

/* Does text contain query (already lowercase)? An empty query matches. */
static BOOL
LRMatches (NSString *text, NSString *query)
{
  return [query length] == 0
    || [[text lowercaseString] rangeOfString:query].location != NSNotFound;
}

NSString *
LRNativeNameForDisplay (NSString *language, NSFont *font)
{
  NSString *name = [LRLocales nativeNameOfLanguage:language];
  NSCharacterSet *covered = [font coveredCharacterSet];
  NSUInteger i, n = [name length];

  /* A backend that doesn't say what the font covers: show it. */
  if (covered == nil)
    return name;
  for (i = 0; i < n; i++)
    {
      unichar c = [name characterAtIndex:i];

      if (c > 0x7F && ![covered characterIsMember:c])
        return @"";
    }
  return name;
}

@implementation LRLanguagePicker

- (id)initWithDelegate:(id<LRLanguagePickerDelegate>)aDelegate
{
  if ((self = [super init]) == nil)
    return nil;
  delegate = aDelegate;
  excluded = [NSArray new];
  shown = [NSArray new];
  [self buildPanel];
  return self;
}

- (void)dealloc
{
  [table setDataSource:nil];
  [table setDelegate:nil];
  [searchField setDelegate:nil];
  RELEASE (panel);
  RELEASE (excluded);
  RELEASE (shown);
  [super dealloc];
}

- (void)beginSheetForWindow:(NSWindow *)window excluding:(NSArray *)listed
{
  ASSIGN (excluded, listed);
  [searchField setStringValue:@""];
  [self filter];
  [panel makeFirstResponder:searchField];
  [NSApp beginSheet:panel
     modalForWindow:window
      modalDelegate:self
     didEndSelector:@selector (sheetDidEnd:returnCode:contextInfo:)
        contextInfo:NULL];
}

/* ---- the table ---- */

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTable
{
  return (NSInteger) [shown count];
}

- (id)tableView:(NSTableView *)aTable
    objectValueForTableColumn:(NSTableColumn *)column
                          row:(NSInteger)row
{
  NSString *language;

  if (row < 0 || (NSUInteger) row >= [shown count])
    return nil;
  language = [shown objectAtIndex:row];
  if ([[column identifier] isEqual:@"Native"])
    return LRNativeNameForDisplay (language, [[column dataCell] font]);
  return [LRLocales nameOfLanguage:language];
}

- (BOOL)tableView:(NSTableView *)aTable shouldEditTableColumn:(NSTableColumn *)c
              row:(NSInteger)row
{
  return NO;
}

- (void)tableViewSelectionDidChange:(NSNotification *)note
{
  [addButton setEnabled:[table selectedRow] >= 0];
}

/* The search field. */
- (void)controlTextDidChange:(NSNotification *)note
{
  [self filter];
}

@end

@implementation LRLanguagePicker (Private)

- (void)buildPanel
{
  NSView *content;
  NSTextField *label;
  NSScrollView *scroll;
  NSTableColumn *column;
  NSButton *cancel;
  NSSize inner;
  CGFloat y, bottom, width = LRPickerWidth - 2 * LRPickerMargin;

  panel = [[NSPanel alloc]
      initWithContentRect:NSMakeRect (0, 0, LRPickerWidth, LRPickerHeight)
                styleMask:NSTitledWindowMask
                  backing:NSBackingStoreBuffered
                    defer:NO];
  [panel setTitle:@"Add Language"];
  [panel setReleasedWhenClosed:NO];
  content = [panel contentView];

  y = LRPickerHeight - LRPickerMargin - 20;
  label = AUTORELEASE ([[NSTextField alloc]
                         initWithFrame:NSMakeRect (LRPickerMargin, y, width,
                                                   20)]);
  [label setStringValue:@"Choose a language to add:"];
  [label setEditable:NO];
  [label setSelectable:NO];
  [label setBordered:NO];
  [label setBezeled:NO];
  [label setDrawsBackground:NO];
  [content addSubview:label];

  y -= LRPickerGap + 24;
  searchField = AUTORELEASE ([[NSTextField alloc]
                               initWithFrame:NSMakeRect (LRPickerMargin, y,
                                                         width, 24)]);
  [searchField setDelegate:(id)self];
  [[searchField cell] setPlaceholderString:@"Search"];
  [content addSubview:searchField];

  bottom = LRPickerMargin + LRPickerButtonHeight + 14;
  scroll = AUTORELEASE ([[NSScrollView alloc]
                          initWithFrame:NSMakeRect (LRPickerMargin, bottom,
                                                    width,
                                                    y - LRPickerGap
                                                    - bottom)]);
  [scroll setHasVerticalScroller:YES];
  [scroll setHasHorizontalScroller:NO];
  [scroll setBorderType:NSBezelBorder];
  inner = [NSScrollView contentSizeForFrameSize:[scroll frame].size
                          hasHorizontalScroller:NO
                            hasVerticalScroller:YES
                                     borderType:NSBezelBorder];
  table = AUTORELEASE ([[NSTableView alloc]
                         initWithFrame:NSMakeRect (0, 0, inner.width,
                                                   inner.height)]);
  column = AUTORELEASE ([[NSTableColumn alloc] initWithIdentifier:@"Name"]);
  [column setWidth:floor (inner.width / 2) - 4];
  [column setEditable:NO];
  [table addTableColumn:column];
  column = AUTORELEASE ([[NSTableColumn alloc] initWithIdentifier:@"Native"]);
  [column setWidth:floor (inner.width / 2) - 4];
  [column setEditable:NO];
  [table addTableColumn:column];
  [table setHeaderView:nil];
  [table setCornerView:nil];
  [table setAllowsMultipleSelection:NO];
  [table setAllowsEmptySelection:YES];
  [table setDataSource:(id)self];
  [table setDelegate:(id)self];
  [table setTarget:self];
  [table setDoubleAction:@selector (add:)];
  [scroll setDocumentView:table];
  [content addSubview:scroll];

  cancel = AUTORELEASE ([[NSButton alloc]
                          initWithFrame:NSMakeRect (LRPickerWidth
                                                    - LRPickerMargin
                                                    - 2 * LRPickerButtonWidth
                                                    - LRPickerGap,
                                                    LRPickerMargin,
                                                    LRPickerButtonWidth,
                                                    LRPickerButtonHeight)]);
  [cancel setTitle:@"Cancel"];
  [cancel setTarget:self];
  [cancel setAction:@selector (cancel:)];
  [cancel setKeyEquivalent:@"\033"];
  [content addSubview:cancel];

  addButton = AUTORELEASE ([[NSButton alloc]
                             initWithFrame:NSMakeRect (LRPickerWidth
                                                       - LRPickerMargin
                                                       - LRPickerButtonWidth,
                                                       LRPickerMargin,
                                                       LRPickerButtonWidth,
                                                       LRPickerButtonHeight)]);
  [addButton setTitle:@"Add"];
  [addButton setTarget:self];
  [addButton setAction:@selector (add:)];
  [addButton setKeyEquivalent:@"\r"];
  [addButton setEnabled:NO];
  [content addSubview:addButton];

  [panel setInitialFirstResponder:searchField];
}

/* The languages not listed whose identifier or either name has the
   search. */
- (void)filter
{
  NSString *query = [[[searchField stringValue]
                       stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceCharacterSet]]
                      lowercaseString];
  NSMutableArray *list = [NSMutableArray array];
  NSEnumerator *e = [[LRLocales languages] objectEnumerator];
  NSString *language;

  while ((language = [e nextObject]) != nil)
    {
      if ([excluded containsObject:language])
        continue;
      if (LRMatches (language, query)
          || LRMatches ([LRLocales nameOfLanguage:language], query)
          || LRMatches ([LRLocales nativeNameOfLanguage:language], query))
        [list addObject:language];
    }
  ASSIGN (shown, list);
  [table reloadData];
  [table deselectAll:nil];
  if ([list count] > 0)
    [table selectRow:0 byExtendingSelection:NO];
  [addButton setEnabled:[list count] > 0];
}

- (void)add:(id)sender
{
  NSInteger row = [table selectedRow];
  NSString *language;

  if (row < 0 || (NSUInteger) row >= [shown count])
    return;
  language = AUTORELEASE (RETAIN ([shown objectAtIndex:row]));
  [NSApp endSheet:panel returnCode:NSOKButton];
  [delegate languagePicker:self didPickLanguage:language];
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
