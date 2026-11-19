/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "DTZones.h"
#import <GNUstepBase/GNUstep.h>

#define DTZoneInfo @"/usr/share/zoneinfo"
#define DTZoneDB @"/var/db/zoneinfo"
/* FreeBSD's country list: code, alpha-3 code, number, name. */
#define DTMiscISO3166 @"/usr/share/misc/iso3166"

/* The last part of a zone's name, as people say it. */
static NSString *
DTCityOfZone (NSString *name)
{
  return [[name lastPathComponent]
           stringByReplacingOccurrencesOfString:@"_" withString:@" "];
}

@implementation DTZone

- (id)initWithName:(NSString *)n country:(NSString *)c comment:(NSString *)m
{
  NSString *text;

  if ((self = [super init]) != nil)
    {
      ASSIGNCOPY (name, n);
      ASSIGN (city, DTCityOfZone (n));
      ASSIGNCOPY (country, c != nil ? c : @"");
      ASSIGNCOPY (comment, m != nil ? m : @"");
      text = [NSString stringWithFormat:@"%@ %@ %@ %@",
                       [name stringByReplacingOccurrencesOfString:@"_"
                                                       withString:@" "],
                       city, country, comment];
      ASSIGN (searchText, [text lowercaseString]);
    }
  return self;
}

- (void)dealloc
{
  RELEASE (name);
  RELEASE (city);
  RELEASE (country);
  RELEASE (comment);
  RELEASE (searchText);
  [super dealloc];
}

- (NSString *)name
{
  return name;
}

- (NSString *)city
{
  return city;
}

- (NSString *)country
{
  return country;
}

- (NSString *)comment
{
  return comment;
}

- (BOOL)matches:(NSArray *)words
{
  NSUInteger i;

  for (i = 0; i < [words count]; i++)
    if ([searchText rangeOfString:[words objectAtIndex:i]].location
        == NSNotFound)
      return NO;
  return YES;
}

- (NSComparisonResult)compareName:(DTZone *)other
{
  return [name compare:[other name]];
}

@end

/* A tab-separated table's lines, without comments. */
static NSArray *
DTTableLines (NSString *path)
{
  NSString *text = [NSString stringWithContentsOfFile:path];
  NSMutableArray *lines = [NSMutableArray array];
  NSEnumerator *e;
  NSString *line;

  e = [[text componentsSeparatedByString:@"\n"] objectEnumerator];
  while ((line = [e nextObject]) != nil)
    if ([line length] > 0 && ![line hasPrefix:@"#"])
      [lines addObject:[line componentsSeparatedByString:@"\t"]];
  return lines;
}

NSArray *
DTZonesLoad (void)
{
  NSMutableDictionary *countries = [NSMutableDictionary dictionary];
  NSMutableDictionary *zones = [NSMutableDictionary dictionary];
  NSEnumerator *e;
  NSArray *fields;

  /* The countries' names: tzdata's iso3166.tab (code, name) where it's
     installed, else FreeBSD's own list, which NextBSD has. */
  e = [DTTableLines ([DTZoneInfo stringByAppendingPathComponent:
                                   @"iso3166.tab"]) objectEnumerator];
  while ((fields = [e nextObject]) != nil)
    if ([fields count] >= 2)
      [countries setObject:[fields objectAtIndex:1]
                    forKey:[fields objectAtIndex:0]];
  if ([countries count] == 0)
    {
      e = [DTTableLines (DTMiscISO3166) objectEnumerator];
      while ((fields = [e nextObject]) != nil)
        if ([fields count] >= 4)
          [countries setObject:[fields objectAtIndex:3]
                        forKey:[fields objectAtIndex:0]];
    }

  /* zone.tab: code, coordinates, zone, comment. */
  e = [DTTableLines ([DTZoneInfo stringByAppendingPathComponent:@"zone.tab"])
          objectEnumerator];
  while ((fields = [e nextObject]) != nil)
    {
      NSString *name, *code;
      DTZone *zone;

      if ([fields count] < 3)
        continue;
      code = [fields objectAtIndex:0];
      name = [fields objectAtIndex:2];
      zone = [[DTZone alloc]
                initWithName:name
                     country:[countries objectForKey:code] != nil
                               ? [countries objectForKey:code] : code
                     comment:[fields count] > 3 ? [fields objectAtIndex:3]
                                                : nil];
      [zones setObject:zone forKey:name];
      RELEASE (zone);
    }
  if ([zones objectForKey:@"UTC"] == nil)
    [zones setObject:AUTORELEASE ([[DTZone alloc]
                                     initWithName:@"UTC"
                                          country:@""
                                          comment:@"Coordinated Universal Time"])
              forKey:@"UTC"];
  return [[zones allValues] sortedArrayUsingSelector:@selector (compareName:)];
}

DTZone *
DTZoneNamed (NSString *name)
{
  return AUTORELEASE ([[DTZone alloc] initWithName:name country:nil
                                           comment:nil]);
}

NSString *
DTCurrentZoneName (void)
{
  NSString *text = [NSString stringWithContentsOfFile:DTZoneDB];
  NSString *name;

  if (text == nil)
    return nil;
  name = [[[text componentsSeparatedByString:@"\n"] objectAtIndex:0]
           stringByTrimmingCharactersInSet:
             [NSCharacterSet whitespaceCharacterSet]];
  return [name length] > 0 ? name : nil;
}
