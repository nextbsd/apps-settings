/*
 * Copyright (c) 2025 Simon Peter
 * Copyright (c) 2026 Παναγιώτης Ἀθανασιάδης
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * KBSourcePicker: the sheet the + button shows. A search field over the
 * layouts xkeyboard-config lists, the layouts on the left, the selected
 * one's variants on the right, and Cancel and Add. Adapted from the
 * Keyboard preferences' source picker in gershwin-components#141.
 */

#import <AppKit/AppKit.h>

@class KBSourcePicker;

@protocol KBSourcePickerDelegate
/* Add pressed (or a double-click): layout and variant ("" for the
   default). */
- (void)sourcePicker:(KBSourcePicker *)picker
        didPickLayout:(NSString *)layout
              variant:(NSString *)variant;
@end

@interface KBSourcePicker : NSObject
{
  NSPanel *panel;
  NSTextField *searchField;
  NSTableView *layoutTable;
  NSTableView *variantTable;
  NSButton *addButton;
  NSArray *shownLayouts;	/* codes after the search */
  NSArray *shownVariants;	/* {Code, Name} of the selected layout */
  NSString *selectedLayout;
  id delegate;			/* not retained */
}

- (id)initWithDelegate:(id<KBSourcePickerDelegate>)delegate;

/* Show the sheet over window, the search empty. */
- (void)beginSheetForWindow:(NSWindow *)window;

@end
