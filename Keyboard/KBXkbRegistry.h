/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * KBXkbRegistry: the layouts and variants xkeyboard-config describes,
 * read from its rules list (evdev.lst, or base.lst: the ones
 * WindowServer's KeyboardRules names), for the add sheet's search and
 * for names when WindowServer isn't there to give them.
 */

#import <Foundation/Foundation.h>

@interface KBXkbRegistry : NSObject
{
  NSDictionary *layouts;	/* code -> description */
  NSDictionary *variants;	/* layout code -> array of {Code, Name} */
  NSArray *sortedLayouts;	/* codes, by description */
  NSString *path;
}

/* Read once, on first use. */
+ (KBXkbRegistry *)sharedRegistry;

/* Where the list was read from, or nil if none was found. */
- (NSString *)path;

/* Layout codes, sorted by description. */
- (NSArray *)layoutCodes;
- (NSString *)nameOfLayout:(NSString *)layout;

/* The layout's variants, each {Code, Name}, as the list orders them. */
- (NSArray *)variantsOfLayout:(NSString *)layout;

/* "Greek (polytonic)", "English (US)": the variant's description, or
   the layout's when variant is empty; the code if neither is known. */
- (NSString *)nameOfLayout:(NSString *)layout variant:(NSString *)variant;

@end
