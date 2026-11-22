/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * LRLocales: the languages and regions Language & Region offers, their
 * names, and the user's choices as GNUstep reads them.
 *
 * GNUstep (libs-base) reads two NSGlobalDomain keys:
 *
 *   NSLanguages   the preferred languages in order. NSBundle looks for
 *                 each one's .lproj in turn (GNUstep's Locale.aliases
 *                 maps "de" to German.lproj), and NSLocale's
 *                 +preferredLanguages lists them. Unset, GNUstep takes
 *                 them from LANGUAGE or LANG.
 *   Locale        NSLocale's +currentLocale and so every formatter,
 *                 through ICU. Unset, it's en_US_POSIX whatever LANG
 *                 says.
 *
 * The formats are the region's, in the first language: the locale is
 * that language with the region ("en_DE": English, with Germany's
 * formats), as on macOS. The rest are ICU's Unicode locale keywords on
 * the same identifier, written only where they differ from the
 * region's own:
 *
 *   calendar=   the calendar ("buddhist"); honored by ICU and
 *               NSCalendar's +currentCalendar.
 *   hours=      h12 or h23; honored by ICU's date formats.
 *   fw=         the first day of the week ("mon"); honored by ICU's
 *               date formats; libs-base's NSCalendar doesn't pass it
 *               on yet.
 *   ms=         metric, ussystem or uksystem; and
 *   mu=         celsius or fahrenhe: kept for what reads them; nothing
 *               in libs-base does yet.
 *
 * So "de_DE@fw=sun;hours=h12" is German formats with weeks starting on
 * Sunday and a 12-hour clock.
 */

#import <Foundation/Foundation.h>

/* The measurement systems and temperature scales, ICU's names. */
extern NSString *const LRMetric;	/* "metric" */
extern NSString *const LRUS;		/* "ussystem" */
extern NSString *const LRUK;		/* "uksystem" */
extern NSString *const LRCelsius;	/* "celsius" */
extern NSString *const LRFahrenheit;	/* "fahrenhe" */

/* A Locale identifier taken apart. */
@interface LRLocaleChoice : NSObject <NSCopying>
{
  NSString *language;		/* "en", "zh_Hans" */
  NSString *region;		/* "DE" */
  NSString *calendar;		/* "gregorian" */
  NSUInteger firstWeekday;	/* 1 Sunday ... 7 Saturday */
  BOOL hour24;
  NSString *measurement;	/* LRMetric, LRUS, LRUK */
  NSString *temperature;	/* LRCelsius, LRFahrenheit */
}

/* Parsed from a Locale default; the region's own for whatever the
 * identifier doesn't say. nil for an empty one. */
+ (LRLocaleChoice *)choiceWithIdentifier:(NSString *)identifier;

/* language with region and everything else the region's own. */
+ (LRLocaleChoice *)choiceWithLanguage:(NSString *)language
                                region:(NSString *)region;

- (NSString *)language;
- (NSString *)region;
- (NSString *)calendar;
- (NSUInteger)firstWeekday;
- (BOOL)hour24;
- (NSString *)measurement;
- (NSString *)temperature;

- (void)setLanguage:(NSString *)language;
/* A new region takes that region's settings for everything. */
- (void)setRegion:(NSString *)region;
- (void)setCalendar:(NSString *)calendar;
- (void)setFirstWeekday:(NSUInteger)day;
- (void)setHour24:(BOOL)flag;
- (void)setMeasurement:(NSString *)system;
- (void)setTemperature:(NSString *)scale;

/* "en_DE": the language with the region, no keywords. */
- (NSString *)baseIdentifier;
/* The base with a keyword for each setting that differs from the
 * region's own: what's written as Locale. */
- (NSString *)identifier;
/* An NSLocale for it. */
- (NSLocale *)locale;

@end

@interface LRLocales : NSObject

/* The languages to offer, ICU's: identifiers ("de", "pt_BR",
 * "zh_Hans"), by English name. */
+ (NSArray *)languages;
/* The regions, ISO 3166 codes ("DE"), by English name. */
+ (NSArray *)regions;
/* The calendars to offer, ICU's names, Gregorian first. */
+ (NSArray *)calendars;

/* "German", "Brazilian Portuguese": the language's English name. */
+ (NSString *)nameOfLanguage:(NSString *)language;
/* "Deutsch": its name in itself. */
+ (NSString *)nativeNameOfLanguage:(NSString *)language;
/* "Germany". */
+ (NSString *)nameOfRegion:(NSString *)region;
+ (NSString *)nameOfCalendar:(NSString *)calendar;
/* "Monday" for 2, in English. */
+ (NSString *)nameOfWeekday:(NSUInteger)day;

/* The region a language is most often spoken in, for a first guess:
 * "DE" for "de", "US" for "en". */
+ (NSString *)likelyRegionForLanguage:(NSString *)language;

/* The system's own locales, for LANG: the UTF-8 ones in
 * /usr/share/locale ("de_DE.UTF-8"), C.UTF-8 first. */
+ (NSArray *)systemLocales;
/* The system locale nearest to language-in-region: exactly that, else
 * the language's in its likely region, else any of the language's;
 * nil when the system has none for the language. */
+ (NSString *)systemLocaleForLanguage:(NSString *)language
                               region:(NSString *)region;
/* The system locale with region's formats: the region's in the
 * language, else the region's in any language; nil if none. */
+ (NSString *)systemLocaleForRegion:(NSString *)region
                           language:(NSString *)language;
/* "German (Germany)" for "de_DE.UTF-8". */
+ (NSString *)nameOfSystemLocale:(NSString *)locale;

@end
