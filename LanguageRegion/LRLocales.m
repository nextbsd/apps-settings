/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "LRLocales.h"
#import <GNUstepBase/GNUstep.h>

NSString *const LRMetric = @"metric";
NSString *const LRUS = @"ussystem";
NSString *const LRUK = @"uksystem";
NSString *const LRCelsius = @"celsius";
NSString *const LRFahrenheit = @"fahrenhe";

static NSString *const LRLocaleDir = @"/usr/share/locale";
static NSString *const LRUTF8 = @".UTF-8";

/* ICU's first-day keyword values, Sunday first, as NSCalendar counts. */
static NSString *const LRWeekdayKeys[] = { @"sun", @"mon", @"tue", @"wed",
                                           @"thu", @"fri", @"sat" };
static NSString *const LRWeekdayNames[] = { @"Sunday", @"Monday",
                                            @"Tuesday", @"Wednesday",
                                            @"Thursday", @"Friday",
                                            @"Saturday" };

/* Regional variants offered beside ICU's plain languages, as macOS
   offers them. */
static NSString *const LRVariants[] = {
  @"en_GB", @"en_AU", @"en_CA", @"en_IN", @"fr_CA", @"es_419", @"pt_BR",
  @"pt_PT", @"de_CH", @"zh_HK", nil
};

/* Where the measurement system or the temperature scale isn't metric
   and Celsius (CLDR's measurementSystem and temperature unit data). */
static NSString *const LRUSRegions[] = { @"US", @"LR", @"MM", nil };
static NSString *const LRFahrenheitRegions[] = { @"US", @"BS", @"BZ", @"KY",
                                                 @"PR", @"PW", nil };

/* Languages not spoken mostly in the country with their own code. */
static NSDictionary *
LRLikelyRegions (void)
{
  static NSDictionary *regions = nil;

  if (regions == nil)
    regions = [[NSDictionary alloc] initWithObjectsAndKeys:
        @"US", @"en", @"JP", @"ja", @"CN", @"zh", @"CN", @"zh_Hans",
        @"TW", @"zh_Hant", @"KR", @"ko", @"SE", @"sv", @"DK", @"da",
        @"CZ", @"cs", @"GR", @"el", @"UA", @"uk", @"IL", @"he",
        @"IN", @"hi", @"SA", @"ar", @"IR", @"fa", @"VN", @"vi",
        @"EE", @"et", @"SI", @"sl", @"NO", @"nb", @"NO", @"nn",
        @"ES", @"ca", @"ES", @"eu", @"ES", @"gl", @"AL", @"sq",
        @"RS", @"sr", @"BD", @"bn", @"PK", @"ur", @"IE", @"ga",
        @"MY", @"ms", @"KE", @"sw", @"IN", @"ta", @"IN", @"te",
        @"KZ", @"kk", @"AM", @"hy", @"GE", @"ka", @"BY", @"be",
        @"ZA", @"af", @"ZA", @"zu", @"ET", @"am", @"KH", @"km",
        @"LA", @"lo", @"MM", @"my", @"NP", @"ne", @"LK", @"si",
        @"PH", @"fil", @"US", @"es_419", @"DE", @"de", nil];
  return regions;
}

static BOOL
LRListed (NSString *const *list, NSString *value)
{
  for (; *list != nil; list++)
    if ([*list isEqual:value])
      return YES;
  return NO;
}

static NSLocale *
LREnglish (void)
{
  static NSLocale *english = nil;

  if (english == nil)
    english = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];
  return english;
}

/* A region subtag: two capital letters or three digits ("419"). */
static BOOL
LRIsRegion (NSString *part)
{
  NSUInteger i, n = [part length];
  BOOL letters = YES, digits = YES;

  for (i = 0; i < n; i++)
    {
      unichar c = [part characterAtIndex:i];
      letters = letters && c >= 'A' && c <= 'Z';
      digits = digits && c >= '0' && c <= '9';
    }
  return (n == 2 && letters) || (n == 3 && digits);
}

/* "de_DE.UTF-8" -> "de"; "zh_Hans" -> "zh". */
static NSString *
LRLanguageCode (NSString *identifier)
{
  return [[identifier componentsSeparatedByString:@"_"] objectAtIndex:0];
}

/* ---- the region's own settings ---- */

/* Sunday 2026-11-22, noon UTC: its local day number ('e') says which
   day the week starts on. */
#define LRSunday 1795348800.0

static NSUInteger
LRFirstWeekdayOf (NSLocale *locale)
{
  NSDateFormatter *f = AUTORELEASE ([NSDateFormatter new]);
  int e;

  [f setFormatterBehavior:NSDateFormatterBehavior10_4];
  [f setLocale:[NSLocale localeWithLocaleIdentifier:
                           [[locale localeIdentifier]
                             stringByAppendingString:@"@numbers=latn"]]];
  [f setTimeZone:[NSTimeZone timeZoneWithName:@"UTC"]];
  [f setDateFormat:@"e"];
  e = [[f stringFromDate:[NSDate dateWithTimeIntervalSince1970:LRSunday]]
        intValue];
  if (e < 1 || e > 7)
    return 1;
  /* Sunday is day e of a week starting on day (2 - e) mod 7. */
  return (NSUInteger) ((2 - e + 14) % 7 == 0 ? 7 : (2 - e + 14) % 7);
}

static BOOL
LRHour24Of (NSLocale *locale)
{
  NSString *format = [NSDateFormatter dateFormatFromTemplate:@"j"
                                                     options:0
                                                      locale:locale];

  return [format rangeOfString:@"H"].location != NSNotFound
    || [format rangeOfString:@"k"].location != NSNotFound;
}

static NSString *
LRCalendarOf (NSLocale *locale)
{
  NSString *calendar = [[locale objectForKey:NSLocaleCalendar]
                         calendarIdentifier];

  return [calendar length] > 0 ? calendar : @"gregorian";
}

/* ---- LRLocaleChoice ---- */

@interface LRLocaleChoice (Private)
- (void)takeRegionDefaults;
- (LRLocaleChoice *)regionDefaults;
@end

@implementation LRLocaleChoice

+ (LRLocaleChoice *)choiceWithLanguage:(NSString *)aLanguage
                                region:(NSString *)aRegion
{
  LRLocaleChoice *choice = AUTORELEASE ([LRLocaleChoice new]);

  ASSIGN (choice->language, aLanguage);
  ASSIGN (choice->region, aRegion);
  [choice takeRegionDefaults];
  return choice;
}

+ (LRLocaleChoice *)choiceWithIdentifier:(NSString *)identifier
{
  NSArray *halves = [identifier componentsSeparatedByString:@"@"];
  NSMutableArray *parts;
  NSString *lang, *reg = nil;
  LRLocaleChoice *choice;
  NSEnumerator *e;
  NSString *keyword;

  if ([identifier length] == 0)
    return nil;
  parts = [NSMutableArray arrayWithArray:
             [[halves objectAtIndex:0] componentsSeparatedByString:@"_"]];
  if ([parts count] > 1 && LRIsRegion ([parts lastObject]))
    {
      reg = [parts lastObject];
      [parts removeLastObject];
    }
  lang = [parts componentsJoinedByString:@"_"];
  if ([lang length] == 0)
    return nil;
  if (reg == nil)
    reg = [LRLocales likelyRegionForLanguage:lang];
  choice = [self choiceWithLanguage:lang region:reg];

  e = [[halves count] > 1
        ? [[halves objectAtIndex:1] componentsSeparatedByString:@";"]
        : [NSArray array] objectEnumerator];
  while ((keyword = [e nextObject]) != nil)
    {
      NSArray *kv = [keyword componentsSeparatedByString:@"="];
      NSString *key, *value;
      int i;

      if ([kv count] != 2)
        continue;
      key = [[kv objectAtIndex:0] lowercaseString];
      value = [[kv objectAtIndex:1] lowercaseString];
      if ([key isEqual:@"calendar"])
        [choice setCalendar:value];
      else if ([key isEqual:@"hours"])
        [choice setHour24:![value isEqual:@"h12"] && ![value isEqual:@"h11"]];
      else if ([key isEqual:@"fw"])
        {
          for (i = 0; i < 7; i++)
            if ([value isEqual:LRWeekdayKeys[i]])
              [choice setFirstWeekday:i + 1];
        }
      else if ([key isEqual:@"ms"]
               && ([value isEqual:LRMetric] || [value isEqual:LRUS]
                   || [value isEqual:LRUK]))
        [choice setMeasurement:value];
      else if ([key isEqual:@"mu"]
               && ([value isEqual:LRCelsius] || [value isEqual:LRFahrenheit]))
        [choice setTemperature:value];
    }
  return choice;
}

- (void)dealloc
{
  RELEASE (language);
  RELEASE (region);
  RELEASE (calendar);
  RELEASE (measurement);
  RELEASE (temperature);
  [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone
{
  LRLocaleChoice *copy = [[LRLocaleChoice allocWithZone:zone] init];

  ASSIGN (copy->language, language);
  ASSIGN (copy->region, region);
  ASSIGN (copy->calendar, calendar);
  copy->firstWeekday = firstWeekday;
  copy->hour24 = hour24;
  ASSIGN (copy->measurement, measurement);
  ASSIGN (copy->temperature, temperature);
  return copy;
}

- (BOOL)isEqual:(id)other
{
  return [other isKindOfClass:[LRLocaleChoice class]]
    && [[self identifier] isEqual:[other identifier]];
}

- (NSUInteger)hash
{
  return [[self identifier] hash];
}

- (NSString *)language
{
  return language;
}

- (NSString *)region
{
  return region;
}

- (NSString *)calendar
{
  return calendar;
}

- (NSUInteger)firstWeekday
{
  return firstWeekday;
}

- (BOOL)hour24
{
  return hour24;
}

- (NSString *)measurement
{
  return measurement;
}

- (NSString *)temperature
{
  return temperature;
}

- (void)setLanguage:(NSString *)aLanguage
{
  ASSIGN (language, aLanguage);
}

- (void)setRegion:(NSString *)aRegion
{
  ASSIGN (region, aRegion);
  [self takeRegionDefaults];
}

- (void)setCalendar:(NSString *)aCalendar
{
  ASSIGN (calendar, aCalendar);
}

- (void)setFirstWeekday:(NSUInteger)day
{
  if (day >= 1 && day <= 7)
    firstWeekday = day;
}

- (void)setHour24:(BOOL)flag
{
  hour24 = flag;
}

- (void)setMeasurement:(NSString *)system
{
  ASSIGN (measurement, system);
}

- (void)setTemperature:(NSString *)scale
{
  ASSIGN (temperature, scale);
}

- (NSString *)baseIdentifier
{
  /* A language that names a region of its own (pt_BR, es_419) gives it
     up to the chosen one. */
  NSMutableArray *parts = [NSMutableArray arrayWithArray:
                             [language componentsSeparatedByString:@"_"]];

  if ([parts count] > 1 && LRIsRegion ([parts lastObject]))
    [parts removeLastObject];
  [parts addObject:region];
  return [parts componentsJoinedByString:@"_"];
}

- (NSString *)identifier
{
  LRLocaleChoice *own = [self regionDefaults];
  NSMutableArray *keywords = [NSMutableArray array];

  /* Alphabetical, as ICU writes them. */
  if (![calendar isEqual:[own calendar]])
    [keywords addObject:[@"calendar=" stringByAppendingString:calendar]];
  if (firstWeekday != [own firstWeekday])
    [keywords addObject:[@"fw=" stringByAppendingString:
                                  LRWeekdayKeys[firstWeekday - 1]]];
  if (hour24 != [own hour24])
    [keywords addObject:hour24 ? @"hours=h23" : @"hours=h12"];
  if (![measurement isEqual:[own measurement]])
    [keywords addObject:[@"ms=" stringByAppendingString:measurement]];
  if (![temperature isEqual:[own temperature]])
    [keywords addObject:[@"mu=" stringByAppendingString:temperature]];
  if ([keywords count] == 0)
    return [self baseIdentifier];
  return [NSString stringWithFormat:@"%@@%@", [self baseIdentifier],
                   [keywords componentsJoinedByString:@";"]];
}

- (NSLocale *)locale
{
  return [NSLocale localeWithLocaleIdentifier:[self identifier]];
}

- (NSString *)description
{
  return [self identifier];
}

@end

@implementation LRLocaleChoice (Private)

/* Everything but the language and region: the region's own. */
- (void)takeRegionDefaults
{
  LRLocaleChoice *own = [self regionDefaults];

  ASSIGN (calendar, [own calendar]);
  firstWeekday = [own firstWeekday];
  hour24 = [own hour24];
  ASSIGN (measurement, [own measurement]);
  ASSIGN (temperature, [own temperature]);
}

/* The region's own settings in this language, from ICU, kept per
   base identifier: they're asked for on every change. */
- (LRLocaleChoice *)regionDefaults
{
  static NSMutableDictionary *cache = nil;
  NSString *base = [self baseIdentifier];
  LRLocaleChoice *own;
  NSLocale *locale;

  if (cache == nil)
    cache = [NSMutableDictionary new];
  if ((own = [cache objectForKey:base]) != nil)
    return own;
  own = AUTORELEASE ([LRLocaleChoice new]);
  locale = [NSLocale localeWithLocaleIdentifier:base];
  ASSIGN (own->language, language);
  ASSIGN (own->region, region);
  ASSIGN (own->calendar, LRCalendarOf (locale));
  own->firstWeekday = LRFirstWeekdayOf (locale);
  own->hour24 = LRHour24Of (locale);
  ASSIGN (own->measurement, LRListed (LRUSRegions, region) ? LRUS
          : [region isEqual:@"GB"] ? LRUK : LRMetric);
  ASSIGN (own->temperature, LRListed (LRFahrenheitRegions, region)
          ? LRFahrenheit : LRCelsius);
  [cache setObject:own forKey:base];
  return own;
}

@end

/* ---- LRLocales ---- */

static NSComparisonResult
LRByName (id a, id b, void *namer)
{
  NSString *(*name) (id) = (NSString *(*) (id)) namer;
  return [name (a) caseInsensitiveCompare:name (b)];
}

static NSString *
LRLanguageName (id language)
{
  return [LRLocales nameOfLanguage:language];
}

static NSString *
LRRegionName (id region)
{
  return [LRLocales nameOfRegion:region];
}

@implementation LRLocales

+ (NSArray *)languages
{
  static NSArray *languages = nil;

  if (languages == nil)
    {
      NSMutableSet *set = [NSMutableSet set];
      NSEnumerator *e = [[NSLocale availableLocaleIdentifiers]
                          objectEnumerator];
      NSString *identifier;
      int i;

      while ((identifier = [e nextObject]) != nil)
        {
          NSArray *parts = [identifier componentsSeparatedByString:@"_"];

          /* "de", and a script ("zh_Hans", "sr_Latn"), not a region. */
          if ([parts count] == 1
              || ([parts count] == 2
                  && [[parts objectAtIndex:1] length] == 4))
            [set addObject:identifier];
        }
      for (i = 0; LRVariants[i] != nil; i++)
        [set addObject:LRVariants[i]];
      [set removeObject:@"root"];
      languages = RETAIN ([[set allObjects]
                            sortedArrayUsingFunction:LRByName
                                             context:(void *) LRLanguageName]);
    }
  return languages;
}

+ (NSArray *)regions
{
  static NSArray *regions = nil;

  if (regions == nil)
    {
      NSMutableSet *set = [NSMutableSet set];
      NSEnumerator *e = [[NSLocale availableLocaleIdentifiers]
                          objectEnumerator];
      NSString *identifier;

      while ((identifier = [e nextObject]) != nil)
        {
          NSString *last = [[identifier componentsSeparatedByString:@"_"]
                             lastObject];

          /* Countries only: not "001" (the world) or "419". */
          if ([last length] == 2 && LRIsRegion (last))
            [set addObject:last];
        }
      regions = RETAIN ([[set allObjects]
                          sortedArrayUsingFunction:LRByName
                                           context:(void *) LRRegionName]);
    }
  return regions;
}

+ (NSArray *)calendars
{
  return [NSArray arrayWithObjects:@"gregorian", @"buddhist", @"chinese",
                  @"coptic", @"ethiopic", @"hebrew", @"indian", @"islamic",
                  @"islamic-civil", @"japanese", @"persian", @"roc", nil];
}

+ (NSString *)nameOfLanguage:(NSString *)language
{
  NSString *name = [LREnglish () displayNameForKey:NSLocaleIdentifier
                                             value:language];

  return [name length] > 0 ? name : language;
}

+ (NSString *)nativeNameOfLanguage:(NSString *)language
{
  NSString *name = [[NSLocale localeWithLocaleIdentifier:language]
                     displayNameForKey:NSLocaleIdentifier
                                 value:language];

  return [name length] > 0 ? name : [self nameOfLanguage:language];
}

+ (NSString *)nameOfRegion:(NSString *)region
{
  /* ICU reads the value as a locale: "und_DE" is Germany, "DE" would be
     the language "de". */
  NSString *name = [LREnglish () displayNameForKey:NSLocaleCountryCode
                                             value:[@"und_" stringByAppendingString:
                                                              region]];

  return [name length] > 0 ? name : region;
}

+ (NSString *)nameOfCalendar:(NSString *)calendar
{
  NSDictionary *names = [NSDictionary dictionaryWithObjectsAndKeys:
      @"Gregorian", @"gregorian", @"Buddhist", @"buddhist",
      @"Chinese", @"chinese", @"Coptic", @"coptic",
      @"Ethiopic", @"ethiopic", @"Hebrew", @"hebrew",
      @"Indian National", @"indian", @"Islamic", @"islamic",
      @"Islamic (Civil)", @"islamic-civil", @"Japanese", @"japanese",
      @"Persian", @"persian", @"Republic of China", @"roc", nil];
  NSString *name = [names objectForKey:calendar];

  return name != nil ? name : calendar;
}

+ (NSString *)nameOfWeekday:(NSUInteger)day
{
  return day >= 1 && day <= 7 ? LRWeekdayNames[day - 1] : @"";
}

+ (NSString *)likelyRegionForLanguage:(NSString *)language
{
  NSString *region = [LRLikelyRegions () objectForKey:language];
  NSArray *parts = [language componentsSeparatedByString:@"_"];
  NSString *code = [parts objectAtIndex:0];
  NSArray *available = [NSLocale availableLocaleIdentifiers];
  NSEnumerator *e;
  NSString *identifier;

  if (region != nil)
    return region;
  if ([parts count] > 1 && LRIsRegion ([parts lastObject]))
    return [parts lastObject];
  if ((region = [LRLikelyRegions () objectForKey:code]) != nil)
    return region;
  /* German in Germany, French in France... */
  if ([available containsObject:[NSString stringWithFormat:@"%@_%@", code,
                                          [code uppercaseString]]])
    return [code uppercaseString];
  e = [available objectEnumerator];
  while ((identifier = [e nextObject]) != nil)
    {
      NSArray *p = [identifier componentsSeparatedByString:@"_"];
      if ([[p objectAtIndex:0] isEqual:code] && [p count] > 1
          && [[p lastObject] length] == 2 && LRIsRegion ([p lastObject]))
        return [p lastObject];
    }
  return @"US";
}

+ (NSArray *)systemLocales
{
  static NSArray *locales = nil;

  if (locales == nil)
    {
      NSMutableArray *list = [NSMutableArray array];
      NSEnumerator *e = [[[[NSFileManager defaultManager]
                            directoryContentsAtPath:LRLocaleDir]
                           sortedArrayUsingSelector:@selector (compare:)]
                          objectEnumerator];
      NSString *name;

      while ((name = [e nextObject]) != nil)
        if ([name hasSuffix:LRUTF8] && ![name isEqual:@"C.UTF-8"])
          [list addObject:name];
      [list insertObject:@"C.UTF-8" atIndex:0];
      locales = [list copy];
    }
  return locales;
}

+ (NSString *)systemLocaleForLanguage:(NSString *)language
                               region:(NSString *)region
{
  NSArray *locales = [self systemLocales];
  NSString *code = LRLanguageCode (language);
  NSString *candidate;
  NSEnumerator *e;

  /* Chinese by script: Simplified is China's, Traditional Taiwan's. */
  if ([language isEqual:@"zh_Hans"] && ![region isEqual:@"SG"])
    region = @"CN";
  else if ([language isEqual:@"zh_Hant"] && ![region isEqual:@"HK"])
    region = @"TW";
  candidate = [NSString stringWithFormat:@"%@_%@%@", code, region, LRUTF8];
  if ([locales containsObject:candidate])
    return candidate;
  candidate = [NSString stringWithFormat:@"%@_%@%@", code,
                        [self likelyRegionForLanguage:language], LRUTF8];
  if ([locales containsObject:candidate])
    return candidate;
  e = [locales objectEnumerator];
  while ((candidate = [e nextObject]) != nil)
    if ([LRLanguageCode (candidate) isEqual:code])
      return candidate;
  return nil;
}

+ (NSString *)systemLocaleForRegion:(NSString *)region
                           language:(NSString *)language
{
  NSArray *locales = [self systemLocales];
  NSString *suffix = [NSString stringWithFormat:@"_%@%@", region, LRUTF8];
  NSString *candidate = [LRLanguageCode (language)
                          stringByAppendingString:suffix];
  NSEnumerator *e;

  if ([locales containsObject:candidate])
    return candidate;
  e = [locales objectEnumerator];
  while ((candidate = [e nextObject]) != nil)
    if ([candidate hasSuffix:suffix])
      return candidate;
  return nil;
}

+ (NSString *)nameOfSystemLocale:(NSString *)locale
{
  NSString *base = [locale stringByDeletingPathExtension];

  if ([base isEqual:@"C"] || [base isEqual:@"POSIX"])
    return @"POSIX default";
  return [self nameOfLanguage:base];
}

@end
