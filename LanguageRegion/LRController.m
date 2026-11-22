/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "LRController.h"
#import "NBSettingsHelper.h"
#import <GNUstepBase/GNUstep.h>

#include <errno.h>
#include <string.h>

/* Layout, in points, as Date & Time's. */
#define LRMargin 20.0
#define LRWindowWidth 560.0
#define LRTabHeight 420.0
#define LRLabelWidth 150.0
#define LRFieldX (LRLabelWidth + 8)
#define LRRowGap 10.0
#define LRButtonWidth 100.0
#define LRButtonHeight 26.0
#define LRLanguageRows 9
/* The lock and its sentence, beside Defaults and Revert. */
#define LRLockWidth (LRWindowWidth - 2 * LRMargin - 2 * LRButtonWidth - 16)

static NSString *const LRRight = @"org.nextbsd.settings.locale";
static NSString *const LRReason = @"change the system language";

/* The NSGlobalDomain keys libs-base reads (LRLocales.h). */
static NSString *const LRLanguagesKey = @"NSLanguages";
static NSString *const LRLocaleKey = @"Locale";
/* The settings apps' change notification (the design's NBSettings). */
static NSString *const LRSettingsChanged = @"org.nextbsd.SettingsChanged";
/* A row being dragged in the language list. */
static NSString *const LRRowType = @"LRLanguageRow";

/* The measurement and temperature popups' items, in order. */
static NSString *const LRSystems[] = { @"metric", @"ussystem",
                                       @"uksystem" };
static NSString *const LRSystemTitles[] = { @"Metric", @"US", @"UK" };
static NSString *const LRScales[] = { @"celsius", @"fahrenhe" };
static NSString *const LRScaleTitles[] = { @"Celsius (°C)",
                                           @"Fahrenheit (°F)" };

/* ISO 4217's currencies without minor units, which the preview shows
   without decimals; libs-base's formatter doesn't take ICU's digits. */
static NSString *const LRWholeCurrencies[] = {
  @"BIF", @"CLP", @"DJF", @"GNF", @"ISK", @"JPY", @"KMF", @"KRW", @"PYG",
  @"RWF", @"UGX", @"UYI", @"VND", @"VUV", @"XAF", @"XOF", @"XPF", nil
};

/* A view laid out from the top down. */
@interface LRFlippedView : NSView
@end

@implementation LRFlippedView
- (BOOL)isFlipped
{
  return YES;
}
@end

static NSTextField *
LRLabel (NSRect frame, NSString *text, NSFont *font)
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
LRRowLabel (CGFloat y, NSString *text)
{
  NSTextField *label = LRLabel (NSMakeRect (0, y + 3, LRLabelWidth, 20), text,
                                nil);
  [label setAlignment:NSRightTextAlignment];
  return label;
}

static NSFont *
LRSmallFont (void)
{
  return [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
}

/* Small wrapped help text. */
static NSTextField *
LRHelp (NSRect frame, NSString *text)
{
  NSTextField *help = LRLabel (frame, text, LRSmallFont ());
  [[help cell] setWraps:YES];
  return help;
}

static NSPopUpButton *
LRPopUp (NSRect frame, id target, SEL action)
{
  NSPopUpButton *popup = AUTORELEASE ([[NSPopUpButton alloc]
                                        initWithFrame:frame pullsDown:NO]);
  [popup setTarget:target];
  [popup setAction:action];
  return popup;
}

/* NSString or nil, from a C string; nil for "". */
static NSString *
LRString (const char *s)
{
  return s[0] != '\0' ? [NSString stringWithUTF8String:s] : nil;
}

static BOOL
LRSameLogin (const LRLoginLocale *a, const LRLoginLocale *b)
{
  return memcmp (a, b, sizeof (*a)) == 0;
}

static void
LRSetField (char *field, NSString *value)
{
  strlcpy (field, value != nil ? [value UTF8String] : "", LRLocaleNameMax);
}

@interface LRController (Private)
- (void)buildMenu;
- (NSView *)languagesTab:(NSRect)frame;
- (NSView *)regionTab:(NSRect)frame;
- (NSView *)systemTab:(NSRect)frame;
- (NSView *)bottomRow;
- (void)tick:(NSTimer *)t;
- (void)reload;
- (void)updateControls;
- (void)updatePreview;
- (NSString *)loginConfPath;
- (NSDictionary *)globalDomain;
- (void)setGlobalValues:(NSDictionary *)values;
- (void)settingsChanged:(NSNotification *)note;
- (LRLoginLocale)loginLocaleFor:(LRLocaleChoice *)aChoice;
- (void)writeLogin:(LRLoginLocale)value;
- (void)setLanguages:(NSArray *)list;
- (void)writeChoice:(LRLocaleChoice *)aChoice;
- (void)addLanguage:(id)sender;
- (void)removeLanguage:(id)sender;
- (void)chooseRegion:(id)sender;
- (void)chooseFormat:(id)sender;
- (BOOL)applySystemLocale:(NSString *)locale;
- (void)chooseSystemLanguage:(id)sender;
- (void)useDefaults:(id)sender;
- (void)revert:(id)sender;
@end

@implementation LRController

- (void)dealloc
{
  [[NSDistributedNotificationCenter defaultCenter] removeObserver:self];
  [timer invalidate];
  RELEASE (timer);
  RELEASE (window);
  RELEASE (auth);
  RELEASE (lockView);
  RELEASE (picker);
  RELEASE (languages);
  RELEASE (choice);
  RELEASE (systemLang);
  RELEASE (shownState);
  RELEASE (originalLanguages);
  RELEASE (originalLocale);
  RELEASE (originalSystemLang);
  [super dealloc];
}

- (void)applicationDidFinishLaunching:(NSNotification *)note
{
  NSImage *icon = [NSImage imageNamed:@"LanguageRegion.png"];
  NSDictionary *domain;
  NSString *section;
  LRFlippedView *content;
  NSTabViewItem *item;
  NSView *bottom;
  NSRect inner;
  CGFloat height;

  if (icon != nil)
    [NSApp setApplicationIconImage:icon];
  [self buildMenu];

  auth = RETAIN ([NBAuthorization authorizationWithRight:LRRight]);
  lockView = [[NBLockView alloc]
                initWithFrame:NSMakeRect (0, 0, LRLockWidth, 30)
                authorization:auth
                       reason:LRReason];
  [lockView setDelegate:self];
  picker = [[LRLanguagePicker alloc] initWithDelegate:self];

  [self reload];
  domain = [self globalDomain];
  ASSIGN (originalLanguages, [domain objectForKey:LRLanguagesKey]);
  ASSIGN (originalLocale, [domain objectForKey:LRLocaleKey]);
  originalLogin = login;
  ASSIGN (originalSystemLang, systemLang);

  height = LRMargin + LRTabHeight + LRRowGap + 30 + LRMargin;
  window = [[NSWindow alloc]
      initWithContentRect:NSMakeRect (200, 200, LRWindowWidth, height)
                styleMask:NSTitledWindowMask | NSClosableWindowMask
                          | NSMiniaturizableWindowMask
                  backing:NSBackingStoreBuffered
                    defer:NO];
  [window setTitle:@"Language & Region"];
  [window setReleasedWhenClosed:NO];
  [window setFrameAutosaveName:@"LanguageRegion"];

  content = AUTORELEASE ([[LRFlippedView alloc]
                           initWithFrame:NSMakeRect (0, 0, LRWindowWidth,
                                                     height)]);
  tabView = AUTORELEASE ([[NSTabView alloc]
                           initWithFrame:NSMakeRect (LRMargin, LRMargin,
                                                     LRWindowWidth
                                                     - 2 * LRMargin,
                                                     LRTabHeight)]);
  [content addSubview:tabView];
  inner = [tabView contentRect];
  inner.origin = NSZeroPoint;

  item = AUTORELEASE ([[NSTabViewItem alloc] initWithIdentifier:@"languages"]);
  [item setLabel:@"Languages"];
  [item setView:[self languagesTab:inner]];
  [tabView addTabViewItem:item];
  item = AUTORELEASE ([[NSTabViewItem alloc] initWithIdentifier:@"region"]);
  [item setLabel:@"Region"];
  [item setView:[self regionTab:inner]];
  [tabView addTabViewItem:item];
  item = AUTORELEASE ([[NSTabViewItem alloc] initWithIdentifier:@"system"]);
  [item setLabel:@"System"];
  [item setView:[self systemTab:inner]];
  [tabView addTabViewItem:item];

  bottom = [self bottomRow];
  [bottom setFrameOrigin:NSMakePoint (LRMargin,
                                      LRMargin + LRTabHeight + LRRowGap)];
  [content addSubview:bottom];
  [window setContentView:content];

  [[NSDistributedNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector (settingsChanged:)
             name:LRSettingsChanged
           object:nil];

  DESTROY (shownState);
  [self reload];

  /* -NBSettingsSection languages|region|system */
  section = [[NSUserDefaults standardUserDefaults]
              stringForKey:@"NBSettingsSection"];
  if ([section length] > 0)
    {
      NSInteger i = [tabView indexOfTabViewItemWithIdentifier:section];
      if (i != NSNotFound)
        [tabView selectTabViewItemAtIndex:i];
    }
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

/* Language & Region has no documents; a file it's asked to open just
   brings the window forward. */
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

- (void)languagePicker:(LRLanguagePicker *)aPicker
        didPickLanguage:(NSString *)language
{
  NSMutableArray *list = [NSMutableArray arrayWithArray:languages];

  if ([list containsObject:language])
    return;
  [list addObject:language];
  [self setLanguages:list];
  [languageTable selectRow:[list count] - 1 byExtendingSelection:NO];
}

/* ---- the language list ---- */

- (NSInteger)numberOfRowsInTableView:(NSTableView *)table
{
  return (NSInteger) [languages count];
}

- (id)tableView:(NSTableView *)table
    objectValueForTableColumn:(NSTableColumn *)column
                          row:(NSInteger)row
{
  NSString *language;

  if (row < 0 || (NSUInteger) row >= [languages count])
    return nil;
  language = [languages objectAtIndex:row];
  if ([[column identifier] isEqual:@"Native"])
    return LRNativeNameForDisplay (language, [[column dataCell] font]);
  if (row == 0)
    return [NSString stringWithFormat:@"%@ — Primary",
                     [LRLocales nameOfLanguage:language]];
  return [LRLocales nameOfLanguage:language];
}

- (BOOL)tableView:(NSTableView *)table shouldEditTableColumn:(NSTableColumn *)c
              row:(NSInteger)row
{
  return NO;
}

- (void)tableViewSelectionDidChange:(NSNotification *)note
{
  [removeButton setEnabled:[languages count] > 1
                && [languageTable selectedRow] >= 0];
}

/* Dragging a language to reorder the list, as Keyboard's sources. */
- (BOOL)tableView:(NSTableView *)table
    writeRowsWithIndexes:(NSIndexSet *)rows
            toPasteboard:(NSPasteboard *)pboard
{
  if ([rows count] != 1 || [languages count] < 2)
    return NO;
  [pboard declareTypes:[NSArray arrayWithObject:LRRowType] owner:nil];
  [pboard setString:[NSString stringWithFormat:@"%lu",
                              (unsigned long) [rows firstIndex]]
            forType:LRRowType];
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
  if ([[[info draggingPasteboard] types] indexOfObject:LRRowType]
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
  NSString *text = [[info draggingPasteboard] stringForType:LRRowType];
  NSMutableArray *list = [NSMutableArray arrayWithArray:languages];
  NSInteger from;
  id language;

  if (text == nil)
    return NO;
  from = [text intValue];
  if (from < 0 || (NSUInteger) from >= [list count] || row < 0)
    return NO;
  if (row > from)
    row--;
  if (row == from)
    return NO;
  language = RETAIN ([list objectAtIndex:from]);
  [list removeObjectAtIndex:from];
  [list insertObject:language atIndex:MIN ((NSUInteger) row, [list count])];
  RELEASE (language);
  [self setLanguages:list];
  [languageTable selectRow:row byExtendingSelection:NO];
  return YES;
}

@end

@implementation LRController (Private)

- (void)buildMenu
{
  NSMenu *menu = AUTORELEASE ([[NSMenu alloc]
                                initWithTitle:@"Language & Region"]);
  NSMenu *edit = AUTORELEASE ([[NSMenu alloc] initWithTitle:@"Edit"]);
  NSMenu *windows = AUTORELEASE ([[NSMenu alloc] initWithTitle:@"Window"]);
  id<NSMenuItem> item;

  [menu addItemWithTitle:@"About Language & Region"
                  action:@selector (orderFrontStandardAboutPanel:)
           keyEquivalent:@""];
  /* The picker's search field takes typing, so cut, copy and paste. */
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

- (NSView *)languagesTab:(NSRect)frame
{
  LRFlippedView *view = AUTORELEASE ([[LRFlippedView alloc]
                                       initWithFrame:frame]);
  CGFloat width = NSWidth (frame) - 2 * LRMargin, y = LRMargin;
  NSScrollView *scroll;
  NSTableColumn *column;
  NSSize size;
  CGFloat rowHeight;

  [view addSubview:LRLabel (NSMakeRect (LRMargin, y, width, 20),
                            @"Preferred languages:",
                            [NSFont boldSystemFontOfSize:13])];
  y += 20 + 4;
  [view addSubview:LRHelp (NSMakeRect (LRMargin, y, width, 30),
                           @"Apps use the first language in the list that "
                           @"they're translated into. Drag a language to "
                           @"change the order.")];
  y += 30 + 6;

  languageTable = AUTORELEASE ([[NSTableView alloc]
                                 initWithFrame:NSMakeRect (0, 0, width, 80)]);
  rowHeight = [languageTable rowHeight] + [languageTable intercellSpacing].height;
  size = [NSScrollView frameSizeForContentSize:
                         NSMakeSize (width, rowHeight * LRLanguageRows)
                         hasHorizontalScroller:NO
                           hasVerticalScroller:YES
                                    borderType:NSBezelBorder];
  scroll = AUTORELEASE ([[NSScrollView alloc]
                          initWithFrame:NSMakeRect (LRMargin, y, width,
                                                    size.height)]);
  [scroll setHasVerticalScroller:YES];
  [scroll setHasHorizontalScroller:NO];
  [scroll setBorderType:NSBezelBorder];
  column = AUTORELEASE ([[NSTableColumn alloc] initWithIdentifier:@"Name"]);
  [column setWidth:floor (width * 0.55)];
  [column setEditable:NO];
  [languageTable addTableColumn:column];
  column = AUTORELEASE ([[NSTableColumn alloc] initWithIdentifier:@"Native"]);
  [column setWidth:floor (width * 0.45) - 24];
  [column setEditable:NO];
  [languageTable addTableColumn:column];
  [languageTable setHeaderView:nil];
  [languageTable setCornerView:nil];
  [languageTable setAllowsMultipleSelection:NO];
  [languageTable setAllowsEmptySelection:YES];
  [languageTable setAllowsColumnReordering:NO];
  [languageTable setDataSource:(id)self];
  [languageTable setDelegate:(id)self];
  [languageTable registerForDraggedTypes:[NSArray arrayWithObject:LRRowType]];
  /* GNUstep starts a row drag only on sideways motion, and offers only
     Copy, by default. */
  [languageTable setVerticalMotionCanBeginDrag:YES];
  [languageTable setDraggingSourceOperationMask:NSDragOperationMove
                                       forLocal:YES];
  [scroll setDocumentView:languageTable];
  [view addSubview:scroll];
  y += size.height + 6;

  addButton = AUTORELEASE ([[NSButton alloc]
                             initWithFrame:NSMakeRect (LRMargin, y, 28, 24)]);
  [addButton setTitle:@"+"];
  [addButton setTarget:self];
  [addButton setAction:@selector (addLanguage:)];
  [view addSubview:addButton];
  removeButton = AUTORELEASE ([[NSButton alloc]
                                initWithFrame:NSMakeRect (LRMargin + 30, y, 28,
                                                          24)]);
  [removeButton setTitle:[NSString stringWithUTF8String:"\xE2\x88\x92"]];
  [removeButton setTarget:self];
  [removeButton setAction:@selector (removeLanguage:)];
  [view addSubview:removeButton];
  y += 24 + 2 * LRRowGap;

  [view addSubview:LRHelp (NSMakeRect (LRMargin, y, width, 32),
                           @"Apps you open from now on use the new order; "
                           @"apps that are open keep theirs until you quit "
                           @"and reopen them. No password is needed.")];
  return view;
}

- (NSView *)regionTab:(NSRect)frame
{
  LRFlippedView *view = AUTORELEASE ([[LRFlippedView alloc]
                                       initWithFrame:frame]);
  CGFloat width = NSWidth (frame) - 2 * LRMargin, y = LRMargin;
  CGFloat popupWidth = width - LRFieldX - 10;
  LRFlippedView *preview;
  NSBox *box;
  NSEnumerator *e;
  NSString *value;
  NSUInteger i;

  [view addSubview:LRRowLabel (y, @"Region:")];
  regionPopup = LRPopUp (NSMakeRect (LRFieldX, y, popupWidth, 24), self,
                         @selector (chooseRegion:));
  e = [[LRLocales regions] objectEnumerator];
  while ((value = [e nextObject]) != nil)
    {
      [regionPopup addItemWithTitle:[LRLocales nameOfRegion:value]];
      [[regionPopup lastItem] setRepresentedObject:value];
    }
  [view addSubview:regionPopup];
  y += 24 + LRRowGap;

  [view addSubview:LRRowLabel (y, @"First day of week:")];
  weekdayPopup = LRPopUp (NSMakeRect (LRFieldX, y, 160, 24), self,
                          @selector (chooseFormat:));
  for (i = 1; i <= 7; i++)
    [weekdayPopup addItemWithTitle:[LRLocales nameOfWeekday:i]];
  [view addSubview:weekdayPopup];
  y += 24 + LRRowGap;

  [view addSubview:LRRowLabel (y, @"Calendar:")];
  calendarPopup = LRPopUp (NSMakeRect (LRFieldX, y, 200, 24), self,
                           @selector (chooseFormat:));
  e = [[LRLocales calendars] objectEnumerator];
  while ((value = [e nextObject]) != nil)
    {
      [calendarPopup addItemWithTitle:[LRLocales nameOfCalendar:value]];
      [[calendarPopup lastItem] setRepresentedObject:value];
    }
  [view addSubview:calendarPopup];
  y += 24 + LRRowGap;

  [view addSubview:LRRowLabel (y, @"Time format:")];
  hour24Button = AUTORELEASE ([[NSButton alloc]
                                initWithFrame:NSMakeRect (LRFieldX, y + 1,
                                                          popupWidth, 22)]);
  [hour24Button setButtonType:NSSwitchButton];
  [hour24Button setTitle:@"24-hour time"];
  [hour24Button setTarget:self];
  [hour24Button setAction:@selector (chooseFormat:)];
  [view addSubview:hour24Button];
  y += 24 + LRRowGap;

  [view addSubview:LRRowLabel (y, @"Measurement units:")];
  measurementPopup = LRPopUp (NSMakeRect (LRFieldX, y, 160, 24), self,
                              @selector (chooseFormat:));
  for (i = 0; i < 3; i++)
    [measurementPopup addItemWithTitle:LRSystemTitles[i]];
  [view addSubview:measurementPopup];
  y += 24 + LRRowGap;

  [view addSubview:LRRowLabel (y, @"Temperature:")];
  temperaturePopup = LRPopUp (NSMakeRect (LRFieldX, y, 160, 24), self,
                              @selector (chooseFormat:));
  for (i = 0; i < 2; i++)
    [temperaturePopup addItemWithTitle:LRScaleTitles[i]];
  [view addSubview:temperaturePopup];
  y += 24 + LRRowGap + 4;

  /* The preview: five lines in the region's formats. */
  preview = AUTORELEASE ([[LRFlippedView alloc]
                           initWithFrame:NSMakeRect (0, 0, width - 24,
                                                     5 * 20)]);
  previewDate = LRLabel (NSMakeRect (0, 0, width - 24, 18), nil, nil);
  previewShort = LRLabel (NSMakeRect (0, 20, width - 24, 18), nil, nil);
  previewNumbers = LRLabel (NSMakeRect (0, 40, width - 24, 18), nil, nil);
  previewUnits = LRLabel (NSMakeRect (0, 60, width - 24, 18), nil, nil);
  previewWeek = LRLabel (NSMakeRect (0, 80, width - 24, 18), nil, nil);
  [preview addSubview:previewDate];
  [preview addSubview:previewShort];
  [preview addSubview:previewNumbers];
  [preview addSubview:previewUnits];
  [preview addSubview:previewWeek];
  box = AUTORELEASE ([[NSBox alloc]
                       initWithFrame:NSMakeRect (LRMargin, y, width, 100)]);
  [box setTitle:@"Preview"];
  [box setTitlePosition:NSAtTop];
  [box setBorderType:NSGrooveBorder];
  [box setContentViewMargins:NSMakeSize (12, 8)];
  [box setContentView:preview];
  [box sizeToFit];
  [box setFrame:NSMakeRect (LRMargin, y, width, NSHeight ([box frame]))];
  [view addSubview:box];
  y += NSHeight ([box frame]) + LRRowGap;

  [view addSubview:LRHelp (NSMakeRect (LRMargin, y, width, 32),
                           @"Apps you open from now on use these formats; "
                           @"apps that are open may keep the old ones until "
                           @"you reopen them.")];
  return view;
}

- (NSView *)systemTab:(NSRect)frame
{
  LRFlippedView *view = AUTORELEASE ([[LRFlippedView alloc]
                                       initWithFrame:frame]);
  CGFloat width = NSWidth (frame) - 2 * LRMargin, y = LRMargin;
  NSEnumerator *e;
  NSString *locale;

  [view addSubview:LRLabel (NSMakeRect (LRMargin, y, width, 20),
                            @"Terminal and command-line programs",
                            [NSFont boldSystemFontOfSize:13])];
  y += 20 + LRRowGap;
  [view addSubview:LRRowLabel (y - 3, @"Language:")];
  terminalLanguage = LRLabel (NSMakeRect (LRFieldX, y, width - LRFieldX + LRMargin,
                                          18), nil, nil);
  [view addSubview:terminalLanguage];
  y += 18 + 6;
  [view addSubview:LRRowLabel (y - 3, @"Formats:")];
  terminalFormats = LRLabel (NSMakeRect (LRFieldX, y, width - LRFieldX + LRMargin,
                                         18), nil, nil);
  [view addSubview:terminalFormats];
  y += 18 + 6;
  terminalNote = LRHelp (NSMakeRect (LRMargin, y, width, 46), nil);
  [view addSubview:terminalNote];
  y += 46 + 2 * LRRowGap;

  [view addSubview:LRLabel (NSMakeRect (LRMargin, y, width, 20),
                            @"System language",
                            [NSFont boldSystemFontOfSize:13])];
  y += 20 + LRRowGap;
  [view addSubview:LRRowLabel (y, @"Language:")];
  systemPopup = LRPopUp (NSMakeRect (LRFieldX, y, width - LRFieldX + LRMargin
                                     - 10, 24),
                         self, @selector (chooseSystemLanguage:));
  e = [[LRLocales systemLocales] objectEnumerator];
  while ((locale = [e nextObject]) != nil)
    {
      [systemPopup addItemWithTitle:
                     [NSString stringWithFormat:@"%@ (%@)",
                               [LRLocales nameOfSystemLocale:locale], locale]];
      [[systemPopup lastItem] setRepresentedObject:locale];
    }
  [view addSubview:systemPopup];
  y += 24 + LRRowGap;
  [view addSubview:LRHelp (NSMakeRect (LRMargin, y, width, 46),
                           @"The language of every account that hasn't "
                           @"chosen its own, new accounts included, from "
                           @"their next login. Changing it needs an "
                           @"administrator: click the lock.")];
  return view;
}

/* The lock at the left, Defaults and Revert at the right. */
- (NSView *)bottomRow
{
  CGFloat width = LRWindowWidth - 2 * LRMargin;
  LRFlippedView *row = AUTORELEASE ([[LRFlippedView alloc]
                                      initWithFrame:NSMakeRect (0, 0, width,
                                                                30)]);
  NSButton *defaults, *revert;

  [lockView setFrameOrigin:NSMakePoint (0, 0)];
  [row addSubview:lockView];

  revert = AUTORELEASE ([[NSButton alloc]
                          initWithFrame:NSMakeRect (width - LRButtonWidth, 2,
                                                    LRButtonWidth,
                                                    LRButtonHeight)]);
  [revert setTitle:@"Revert"];
  [revert setTarget:self];
  [revert setAction:@selector (revert:)];
  [row addSubview:revert];

  defaults = AUTORELEASE ([[NSButton alloc]
                            initWithFrame:NSMakeRect (width - 2 * LRButtonWidth
                                                      - 8, 2, LRButtonWidth,
                                                      LRButtonHeight)]);
  [defaults setTitle:@"Defaults"];
  [defaults setTarget:self];
  [defaults setAction:@selector (useDefaults:)];
  [row addSubview:defaults];
  return row;
}

/* ---- following the system ---- */

/* Every second: the lock's time, and anything changed elsewhere. */
- (void)tick:(NSTimer *)t
{
  [lockView update];
  [self reload];
}

/* Read everything again, and set the controls if anything shown
   changed. */
- (void)reload
{
  NSDictionary *domain = [self globalDomain];
  id list = [domain objectForKey:LRLanguagesKey];
  id identifier = [domain objectForKey:LRLocaleKey];
  NSMutableArray *effective = [NSMutableArray array];
  LRLocaleChoice *newChoice = nil;
  char lang[LRLocaleNameMax];
  NSString *state;

  /* The languages: the user's, else GNUstep's own guess from LANG. */
  languagesSet = [list isKindOfClass:[NSArray class]] && [list count] > 0;
  if (!languagesSet)
    list = [NSUserDefaults userLanguages];
  if ([list isKindOfClass:[NSArray class]])
    {
      NSEnumerator *e = [list objectEnumerator];
      NSString *name;

      while ((name = [e nextObject]) != nil)
        {
          if (![name isKindOfClass:[NSString class]])
            continue;
          /* GNUstep's own names ("German") as identifiers ("de"). */
          if (!languagesSet)
            name = [NSLocale canonicalLanguageIdentifierFromString:name];
          if ([name length] > 0 && ![effective containsObject:name])
            [effective addObject:name];
        }
    }
  if ([effective count] == 0)
    [effective addObject:@"en"];
  ASSIGN (languages, effective);

  /* The formats: the user's Locale, else the first language in LANG's
     region (or the language's own). */
  localeSet = [identifier isKindOfClass:[NSString class]]
    && [identifier length] > 0;
  if (localeSet)
    newChoice = [LRLocaleChoice choiceWithIdentifier:identifier];
  if (newChoice == nil)
    {
      LRLocaleChoice *env = [LRLocaleChoice choiceWithIdentifier:
          [[[[NSProcessInfo processInfo] environment] objectForKey:@"LANG"]
            stringByDeletingPathExtension]];
      NSString *first = [languages objectAtIndex:0];

      newChoice = [LRLocaleChoice
                    choiceWithLanguage:first
                                region:env != nil && ![[env language]
                                                         isEqual:@"C"]
                                       ? [env region]
                                       : [LRLocales
                                           likelyRegionForLanguage:first]];
    }
  ASSIGN (choice, newChoice);

  if (LRLoginConfRead ([[self loginConfPath] fileSystemRepresentation],
                       &login) != 0)
    memset (&login, 0, sizeof (login));
  LRLoginConfSystemLang (lang, sizeof (lang));
  ASSIGN (systemLang, LRString (lang));

  state = [NSString stringWithFormat:@"%@ %d %@ %d %s %s %s %s %@ %d %d",
                    languages, (int) languagesSet, [choice identifier],
                    (int) localeSet, login.lang, login.time, login.numeric,
                    login.monetary, systemLang, (int) [lockView isUnlocked],
                    [auth status]];
  if ([state isEqual:shownState])
    return;
  ASSIGN (shownState, state);
  [self updateControls];
}

- (void)updateControls
{
  NSString *lang = LRString (login.lang), *formats = LRString (login.time);
  NSString *session = [[[NSProcessInfo processInfo] environment]
                        objectForKey:@"LANG"];
  NSInteger row = [languageTable selectedRow];
  NSInteger index;

  [languageTable reloadData];
  if (row >= (NSInteger) [languages count])
    [languageTable deselectAll:nil];
  [removeButton setEnabled:[languages count] > 1
                && [languageTable selectedRow] >= 0];

  index = [regionPopup indexOfItemWithRepresentedObject:[choice region]];
  if (index < 0)
    {
      /* A region ICU has no locale for: show it anyway. */
      [regionPopup addItemWithTitle:[LRLocales nameOfRegion:[choice region]]];
      [[regionPopup lastItem] setRepresentedObject:[choice region]];
      index = [regionPopup numberOfItems] - 1;
    }
  [regionPopup selectItemAtIndex:index];
  [weekdayPopup selectItemAtIndex:[choice firstWeekday] - 1];
  index = [calendarPopup indexOfItemWithRepresentedObject:[choice calendar]];
  if (index < 0)
    {
      [calendarPopup addItemWithTitle:[choice calendar]];
      [[calendarPopup lastItem] setRepresentedObject:[choice calendar]];
      index = [calendarPopup numberOfItems] - 1;
    }
  [calendarPopup selectItemAtIndex:index];
  [hour24Button setState:[choice hour24] ? NSOnState : NSOffState];
  for (index = 0; index < 3; index++)
    if ([LRSystems[index] isEqual:[choice measurement]])
      [measurementPopup selectItemAtIndex:index];
  for (index = 0; index < 2; index++)
    if ([LRScales[index] isEqual:[choice temperature]])
      [temperaturePopup selectItemAtIndex:index];
  [self updatePreview];

  /* The terminal. */
  if (lang != nil)
    [terminalLanguage setStringValue:
        [NSString stringWithFormat:@"%@ (%@)",
                  [LRLocales nameOfSystemLocale:lang], lang]];
  else
    [terminalLanguage setStringValue:
        [NSString stringWithFormat:@"The system's: %@ (%@)",
                  [LRLocales nameOfSystemLocale:
                               systemLang != nil ? systemLang : @"C"],
                  systemLang != nil ? systemLang : @"C"]];
  if (formats != nil)
    [terminalFormats setStringValue:
        [NSString stringWithFormat:@"%@ (%@)",
                  [LRLocales nameOfSystemLocale:formats], formats]];
  else
    [terminalFormats setStringValue:@"The language's"];
  [terminalNote setStringValue:
      [NSString stringWithFormat:
                  @"LANG, and LC_TIME, LC_NUMERIC and LC_MONETARY for the "
                  @"formats, from the nearest locales the system has, in "
                  @"~/.login_conf. They take effect at your next login; "
                  @"this session has LANG=%@.",
                session != nil ? session : @"(none)"]];

  index = systemLang != nil
    ? [systemPopup indexOfItemWithRepresentedObject:systemLang] : -1;
  if (index < 0 && systemLang != nil)
    {
      [systemPopup addItemWithTitle:systemLang];
      [[systemPopup lastItem] setRepresentedObject:systemLang];
      index = [systemPopup numberOfItems] - 1;
    }
  if (index >= 0)
    [systemPopup selectItemAtIndex:index];
  [systemPopup setEnabled:[lockView isUnlocked]];
}

/* The formats as the apps will show them, now. */
- (void)updatePreview
{
  NSLocale *locale = [choice locale];
  NSDate *now = [NSDate date];
  NSDateFormatter *dates = AUTORELEASE ([NSDateFormatter new]);
  NSNumberFormatter *numbers = AUTORELEASE ([NSNumberFormatter new]);
  NSNumberFormatter *money = AUTORELEASE ([NSNumberFormatter new]);
  NSMutableArray *week = [NSMutableArray array];
  NSArray *days;
  NSString *distance, *temperature, *code;
  BOOL whole;
  NSUInteger i;

  [dates setFormatterBehavior:NSDateFormatterBehavior10_4];
  [dates setLocale:locale];
  [dates setDateStyle:NSDateFormatterFullStyle];
  [dates setTimeStyle:NSDateFormatterShortStyle];
  [previewDate setStringValue:[dates stringFromDate:now]];
  [dates setDateStyle:NSDateFormatterShortStyle];
  [previewShort setStringValue:[dates stringFromDate:now]];

  [numbers setFormatterBehavior:NSNumberFormatterBehavior10_4];
  [numbers setLocale:locale];
  [numbers setNumberStyle:NSNumberFormatterDecimalStyle];
  [numbers setMinimumFractionDigits:2];
  [numbers setMaximumFractionDigits:2];
  [money setFormatterBehavior:NSNumberFormatterBehavior10_4];
  [money setLocale:locale];
  [money setNumberStyle:NSNumberFormatterCurrencyStyle];
  code = [money currencyCode];
  whole = NO;
  for (i = 0; LRWholeCurrencies[i] != nil; i++)
    whole = whole || [LRWholeCurrencies[i] isEqual:code];
  [money setMinimumFractionDigits:whole ? 0 : 2];
  [money setMaximumFractionDigits:whole ? 0 : 2];
  [previewNumbers setStringValue:
      [NSString stringWithFormat:@"%@      %@",
                [numbers stringFromNumber:
                           [NSNumber numberWithDouble:1234567.89]],
                [money stringFromNumber:
                         [NSNumber numberWithDouble:whole ? 1234.0
                                                          : 1234.56]]]];

  [numbers setMinimumFractionDigits:0];
  [numbers setMaximumFractionDigits:1];
  if ([[choice measurement] isEqual:@"metric"])
    distance = [NSString stringWithFormat:@"%@ km, %@ kg",
                         [numbers stringFromNumber:
                                    [NSNumber numberWithDouble:12.5]],
                         [numbers stringFromNumber:
                                    [NSNumber numberWithDouble:70]]];
  else
    /* The UK goes by miles but weighs in stone. */
    distance = [NSString stringWithFormat:@"%@ mi, %@",
                         [numbers stringFromNumber:
                                    [NSNumber numberWithDouble:7.8]],
                         [[choice measurement] isEqual:@"uksystem"]
                           ? @"11 st"
                           : [[numbers stringFromNumber:
                                         [NSNumber numberWithDouble:154]]
                               stringByAppendingString:@" lb"]];
  temperature = [[choice temperature] isEqual:@"celsius"]
    ? [NSString stringWithFormat:@"%@ °C",
                [numbers stringFromNumber:[NSNumber numberWithDouble:21]]]
    : [NSString stringWithFormat:@"%@ °F",
                [numbers stringFromNumber:[NSNumber numberWithDouble:70]]];
  [previewUnits setStringValue:
      [NSString stringWithFormat:@"%@      %@", distance, temperature]];

  days = [dates shortStandaloneWeekdaySymbols];
  if ([days count] == 7)
    for (i = 0; i < 7; i++)
      [week addObject:[days objectAtIndex:([choice firstWeekday] - 1 + i)
                                           % 7]];
  [previewWeek setStringValue:[week componentsJoinedByString:@"   "]];
}

- (NSString *)loginConfPath
{
  return [NSHomeDirectory () stringByAppendingPathComponent:@".login_conf"];
}

/* The user's NSGlobalDomain as it is on disk. */
- (NSDictionary *)globalDomain
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

  [defaults synchronize];
  return [defaults persistentDomainForName:NSGlobalDomain];
}

/* Write these NSGlobalDomain keys (NSNull: unset) and say so, as the
   settings apps' shared NBSettings is to (org.nextbsd.SettingsChanged
   {domain, keys}). */
- (void)setGlobalValues:(NSDictionary *)values
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSMutableDictionary *domain = [NSMutableDictionary dictionaryWithDictionary:
                                                       [self globalDomain]];
  NSEnumerator *e = [values keyEnumerator];
  NSString *key;

  while ((key = [e nextObject]) != nil)
    {
      id value = [values objectForKey:key];

      if (value == [NSNull null])
        [domain removeObjectForKey:key];
      else
        [domain setObject:value forKey:key];
    }
  [defaults setPersistentDomain:domain forName:NSGlobalDomain];
  [defaults synchronize];
  NS_DURING
    [[NSDistributedNotificationCenter defaultCenter]
        postNotificationName:LRSettingsChanged
                      object:nil
                    userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
                                NSGlobalDomain, @"domain",
                                [values allKeys], @"keys", nil]
          deliverImmediately:YES];
  NS_HANDLER
    NSLog (@"Language & Region: can't announce %@: %@", [values allKeys],
           [localException reason]);
  NS_ENDHANDLER
  [self reload];
}

/* Another app (or another copy of this one) changed a key we show. */
- (void)settingsChanged:(NSNotification *)note
{
  if ([[[note userInfo] objectForKey:@"domain"] isEqual:NSGlobalDomain])
    [self reload];
}

/* What ~/.login_conf should say for these choices: LANG the first
   language's (in the region, if the system has it), and the region's
   formats where the system has them and they're another locale. */
- (LRLoginLocale)loginLocaleFor:(LRLocaleChoice *)aChoice
{
  NSString *language = [languages objectAtIndex:0];
  NSString *lang = [LRLocales systemLocaleForLanguage:language
                                               region:[aChoice region]];
  NSString *formats = [LRLocales systemLocaleForRegion:[aChoice region]
                                              language:language];
  LRLoginLocale value;

  memset (&value, 0, sizeof (value));
  if (lang == nil)
    lang = formats != nil ? formats : @"C.UTF-8";
  LRSetField (value.lang, lang);
  LRSetField (value.charset, @"UTF-8");
  if (formats != nil && ![formats isEqual:lang])
    {
      LRSetField (value.time, formats);
      LRSetField (value.numeric, formats);
      LRSetField (value.monetary, formats);
    }
  return value;
}

- (void)writeLogin:(LRLoginLocale)value
{
  if (LRSameLogin (&value, &login))
    return;
  if (LRLoginConfWrite ([[self loginConfPath] fileSystemRepresentation],
                        &value) != 0)
    NSRunAlertPanel (@"Language & Region",
                     @"The terminal's language couldn't be saved in %@: %s.",
                     @"OK", nil, nil, [self loginConfPath], strerror (errno));
  [self reload];
}

/* A new list: written as it is, and the formats follow a new first
   language. */
- (void)setLanguages:(NSArray *)list
{
  LRLocaleChoice *newChoice = AUTORELEASE ([choice copy]);
  NSMutableDictionary *values = [NSMutableDictionary dictionary];

  if ([list count] == 0)
    return;
  [values setObject:list forKey:LRLanguagesKey];
  [newChoice setLanguage:[list objectAtIndex:0]];
  if (!localeSet || ![[newChoice identifier] isEqual:[choice identifier]])
    [values setObject:[newChoice identifier] forKey:LRLocaleKey];
  [self setGlobalValues:values];
  [self writeLogin:[self loginLocaleFor:choice]];
}

- (void)writeChoice:(LRLocaleChoice *)aChoice
{
  NSMutableDictionary *values = [NSMutableDictionary dictionary];

  [values setObject:[aChoice identifier] forKey:LRLocaleKey];
  /* The first choice made fixes the languages too, so that the formats'
     language and the apps' agree. */
  if (!languagesSet)
    [values setObject:languages forKey:LRLanguagesKey];
  [self setGlobalValues:values];
  [self writeLogin:[self loginLocaleFor:choice]];
}

- (void)addLanguage:(id)sender
{
  [picker beginSheetForWindow:window excluding:languages];
}

- (void)removeLanguage:(id)sender
{
  NSInteger row = [languageTable selectedRow];
  NSMutableArray *list = [NSMutableArray arrayWithArray:languages];

  if (row < 0 || (NSUInteger) row >= [list count] || [list count] < 2)
    return;
  [list removeObjectAtIndex:row];
  [self setLanguages:list];
  [languageTable selectRow:MIN ((NSUInteger) row, [list count] - 1)
      byExtendingSelection:NO];
}

/* A region brings its own settings for everything else, as on macOS. */
- (void)chooseRegion:(id)sender
{
  LRLocaleChoice *newChoice = AUTORELEASE ([choice copy]);

  [newChoice setRegion:[[regionPopup selectedItem] representedObject]];
  [self writeChoice:newChoice];
}

- (void)chooseFormat:(id)sender
{
  LRLocaleChoice *newChoice = AUTORELEASE ([choice copy]);

  [newChoice setFirstWeekday:[weekdayPopup indexOfSelectedItem] + 1];
  [newChoice setCalendar:[[calendarPopup selectedItem] representedObject]];
  [newChoice setHour24:[hour24Button state] == NSOnState];
  [newChoice setMeasurement:LRSystems[[measurementPopup indexOfSelectedItem]]];
  [newChoice setTemperature:LRScales[[temperaturePopup indexOfSelectedItem]]];
  if (![newChoice isEqual:choice] || !localeSet)
    [self writeChoice:newChoice];
}

/* Through the helper, unlocking first if the lock was open but the
   right ran out. */
- (BOOL)applySystemLocale:(NSString *)locale
{
  int status = [NBSettingsHelper setSystemLocale:locale authorization:auth];

  if (status == NBAuthorizationNeeded)
    {
      [auth refresh];
      [lockView update];
      if ([lockView unlock])
        status = [NBSettingsHelper setSystemLocale:locale authorization:auth];
      else
        return NO;		/* cancelled: nothing to say */
    }
  if (status != NBAuthorizationOK)
    NSRunAlertPanel (@"Language & Region", @"%@", @"OK", nil, nil,
                     [NBAuthorization messageForStatus:status]);
  return status == NBAuthorizationOK;
}

- (void)chooseSystemLanguage:(id)sender
{
  NSString *locale = [[systemPopup selectedItem] representedObject];

  if (locale != nil && ![locale isEqual:systemLang] && [lockView isUnlocked])
    [self applySystemLocale:locale];
  DESTROY (shownState);
  [self reload];
}

/* The system's language and formats: the user's own keys and login
   class settings go. The system's language stays. */
- (void)useDefaults:(id)sender
{
  LRLoginLocale none;

  [self setGlobalValues:[NSDictionary dictionaryWithObjectsAndKeys:
                                        [NSNull null], LRLanguagesKey,
                                        [NSNull null], LRLocaleKey, nil]];
  memset (&none, 0, sizeof (none));
  [self writeLogin:none];
}

/* Back to the settings from when the window opened. */
- (void)revert:(id)sender
{
  [self setGlobalValues:
          [NSDictionary dictionaryWithObjectsAndKeys:
                          originalLanguages != nil ? originalLanguages
                                                   : (id) [NSNull null],
                          LRLanguagesKey,
                          originalLocale != nil ? originalLocale
                                                : (id) [NSNull null],
                          LRLocaleKey, nil]];
  [self writeLogin:originalLogin];
  if (originalSystemLang != nil && ![originalSystemLang isEqual:systemLang]
      && [lockView unlock])
    [self applySystemLocale:originalSystemLang];
  DESTROY (shownState);
  [self reload];
}

@end
