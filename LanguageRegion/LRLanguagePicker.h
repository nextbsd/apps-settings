/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * LRLanguagePicker: the sheet the + under the language list shows. A
 * search field over ICU's languages, each by its English name and its
 * own, less those already listed, and Cancel and Add; shaped like
 * Keyboard's source picker.
 */

#import <AppKit/AppKit.h>

@class LRLanguagePicker;

/* A language's name in itself ("Deutsch"), or "" when font hasn't the
   glyphs for it (it would show as question marks). */
NSString *LRNativeNameForDisplay (NSString *language, NSFont *font);

@protocol LRLanguagePickerDelegate
/* Add pressed (or a double-click): a language identifier ("de"). */
- (void)languagePicker:(LRLanguagePicker *)picker
        didPickLanguage:(NSString *)language;
@end

@interface LRLanguagePicker : NSObject
{
  NSPanel *panel;
  NSTextField *searchField;
  NSTableView *table;
  NSButton *addButton;
  NSArray *excluded;		/* already in the list */
  NSArray *shown;		/* after the search */
  id delegate;			/* not retained */
}

- (id)initWithDelegate:(id<LRLanguagePickerDelegate>)delegate;

/* Show the sheet over window, the search empty, without the languages
   in `listed`. */
- (void)beginSheetForWindow:(NSWindow *)window excluding:(NSArray *)listed;

@end
