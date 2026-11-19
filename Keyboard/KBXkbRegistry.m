/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "KBXkbRegistry.h"
#import <GNUstepBase/GNUstep.h>

/* Where xkeyboard-config's lists may be, the evdev rules first (what
   WindowServer's KeyboardRules is by default). */
static NSArray *
KBRulesLists (void)
{
  return [NSArray arrayWithObjects:
                    @"/usr/share/X11/xkb/rules/evdev.lst",
                  @"/usr/share/xkeyboard-config-2/rules/evdev.lst",
                  @"/usr/local/share/X11/xkb/rules/evdev.lst",
                  @"/usr/X11/share/X11/xkb/rules/evdev.lst",
                  @"/usr/share/X11/xkb/rules/base.lst",
                  @"/usr/share/xkeyboard-config-2/rules/base.lst",
                  @"/usr/local/share/X11/xkb/rules/base.lst",
                  @"/usr/X11/share/X11/xkb/rules/base.lst",
                  nil];
}

static KBXkbRegistry *shared = nil;

@interface KBXkbRegistry (Private)
- (void)readList:(NSString *)file;
@end

@implementation KBXkbRegistry

+ (KBXkbRegistry *)sharedRegistry
{
  if (shared == nil)
    shared = [[KBXkbRegistry alloc] init];
  return shared;
}

- (id)init
{
  NSEnumerator *e;
  NSString *file;

  if ((self = [super init]) == nil)
    return nil;
  e = [KBRulesLists () objectEnumerator];
  while ((file = [e nextObject]) != nil)
    if ([[NSFileManager defaultManager] isReadableFileAtPath:file])
      {
        [self readList:file];
        if ([layouts count] > 0)
          {
            ASSIGN (path, file);
            break;
          }
      }
  if (layouts == nil)
    {
      layouts = [NSDictionary new];
      variants = [NSDictionary new];
    }
  ASSIGN (sortedLayouts,
          [layouts keysSortedByValueUsingSelector:
                     @selector (caseInsensitiveCompare:)]);
  return self;
}

- (void)dealloc
{
  RELEASE (layouts);
  RELEASE (variants);
  RELEASE (sortedLayouts);
  RELEASE (path);
  [super dealloc];
}

- (NSString *)path
{
  return path;
}

- (NSArray *)layoutCodes
{
  return sortedLayouts;
}

- (NSString *)nameOfLayout:(NSString *)layout
{
  return [layouts objectForKey:layout];
}

- (NSArray *)variantsOfLayout:(NSString *)layout
{
  NSArray *list = [variants objectForKey:layout];
  return list != nil ? list : [NSArray array];
}

- (NSString *)nameOfLayout:(NSString *)layout variant:(NSString *)variant
{
  if ([variant length] > 0)
    {
      NSEnumerator *e = [[self variantsOfLayout:layout] objectEnumerator];
      NSDictionary *v;

      while ((v = [e nextObject]) != nil)
        if ([[v objectForKey:@"Code"] isEqual:variant])
          return [v objectForKey:@"Name"];
      return [NSString stringWithFormat:@"%@ (%@)",
                       [self nameOfLayout:layout variant:@""], variant];
    }
  if ([layouts objectForKey:layout] != nil)
    return [layouts objectForKey:layout];
  return layout;
}

@end

@implementation KBXkbRegistry (Private)

/*
 * The list's sections, two columns each:
 *
 *   ! layout
 *     us              English (US)
 *   ! variant
 *     polytonic       gr: Greek (polytonic)
 */
- (void)readList:(NSString *)file
{
  NSString *text = [NSString stringWithContentsOfFile:file];
  NSMutableDictionary *l = [NSMutableDictionary dictionary];
  NSMutableDictionary *v = [NSMutableDictionary dictionary];
  NSCharacterSet *space = [NSCharacterSet whitespaceCharacterSet];
  NSEnumerator *e;
  NSString *line, *section = nil;

  if (text == nil)
    return;
  e = [[text componentsSeparatedByString:@"\n"] objectEnumerator];
  while ((line = [e nextObject]) != nil)
    {
      NSRange gap;
      NSString *code, *rest;

      if ([line hasPrefix:@"!"])
        {
          section = [[line substringFromIndex:1]
                      stringByTrimmingCharactersInSet:space];
          continue;
        }
      line = [line stringByTrimmingCharactersInSet:space];
      gap = [line rangeOfCharacterFromSet:space];
      if ([line length] == 0 || gap.location == NSNotFound)
        continue;
      code = [line substringToIndex:gap.location];
      rest = [[line substringFromIndex:gap.location]
                stringByTrimmingCharactersInSet:space];
      if ([section isEqual:@"layout"])
        [l setObject:rest forKey:code];
      else if ([section isEqual:@"variant"])
        {
          NSRange colon = [rest rangeOfString:@": "];
          NSString *layout;
          NSMutableArray *list;

          if (colon.location == NSNotFound)
            continue;
          layout = [rest substringToIndex:colon.location];
          list = [v objectForKey:layout];
          if (list == nil)
            {
              list = [NSMutableArray array];
              [v setObject:list forKey:layout];
            }
          [list addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                                          code, @"Code",
                                        [rest substringFromIndex:
                                                NSMaxRange (colon)], @"Name",
                                        nil]];
        }
    }
  ASSIGN (layouts, l);
  ASSIGN (variants, v);
}

@end
