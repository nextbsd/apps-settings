/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * DTZones: the time zones the Time Zone tab lists, from
 * /usr/share/zoneinfo: zone.tab's zones (one per country and region,
 * with the region's description), the countries' names from
 * iso3166.tab (or FreeBSD's /usr/share/misc/iso3166), and UTC. A map can come later (nextbsd/nextbsd#634).
 */

#import <Foundation/Foundation.h>

@interface DTZone : NSObject
{
  NSString *name;		/* America/Argentina/Buenos_Aires */
  NSString *city;		/* Buenos Aires */
  NSString *country;		/* Argentina */
  NSString *comment;		/* "Buenos Aires (BA, CF)" */
  NSString *searchText;		/* all of it, lowercase */
}
- (NSString *)name;
- (NSString *)city;
- (NSString *)country;
- (NSString *)comment;
/* Every word of text (lowercase, space separated) is in the zone's
 * name, city, country or comment. */
- (BOOL)matches:(NSArray *)words;
@end

/* The zones, sorted by name. */
NSArray *DTZonesLoad (void);

/* A zone of that name, for one zone.tab doesn't list (Etc/GMT+5). */
DTZone *DTZoneNamed (NSString *name);

/* The system's zone, as SetTimeZone and tzsetup record it in
 * /var/db/zoneinfo, or nil when none is recorded. */
NSString *DTCurrentZoneName (void);
