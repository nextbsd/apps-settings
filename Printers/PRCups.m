/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "PRCups.h"
#import <GNUstepBase/GNUstep.h>

#include <cups/cups.h>
#include <stdlib.h>
#include <string.h>

NSString *const PRName = @"name";
NSString *const PRInfo = @"info";
NSString *const PRLocation = @"location";
NSString *const PRModel = @"model";
NSString *const PRDeviceURI = @"device-uri";
NSString *const PRState = @"state";
NSString *const PRReasons = @"reasons";
NSString *const PRAccepting = @"accepting";
NSString *const PRDefault = @"default";
NSString *const PRMedia = @"media";
NSString *const PRSides = @"sides";
NSString *const PRJobs = @"jobs";

NSString *const PRJobTitle = @"title";
NSString *const PRJobUser = @"user";
NSString *const PRJobState = @"state";

NSString *const PROptionMedia = @"media";
NSString *const PROptionSides = @"sides";

/* What a queue name can't hold (cupsd's validate_name), beside spaces
   and control characters. */
static const char PRBadNameChars[] = "/\\?'\"#";
#define PRNameMax 127

static NSString *
PRString (const char *s)
{
  return s != NULL ? [NSString stringWithUTF8String:s] : nil;
}

static NSString *
PROption (cups_dest_t *dest, const char *name)
{
  return PRString (cupsGetOption (name, dest->num_options, dest->options));
}

/* A dest as a dictionary, with only what's set. */
static NSMutableDictionary *
PRDestDictionary (cups_dest_t *dest)
{
  NSMutableDictionary *d = [NSMutableDictionary dictionary];
  NSString *info = PROption (dest, "printer-info");
  NSString *v;

  [d setObject:PRString (dest->name) forKey:PRName];
  [d setObject:([info length] > 0 ? info : PRString (dest->name))
        forKey:PRInfo];
  if ((v = PROption (dest, "printer-location")) != nil)
    [d setObject:v forKey:PRLocation];
  if ((v = PROption (dest, "printer-make-and-model")) != nil)
    [d setObject:v forKey:PRModel];
  if ((v = PROption (dest, "device-uri")) != nil)
    [d setObject:v forKey:PRDeviceURI];
  if ((v = PROption (dest, "printer-state")) != nil)
    [d setObject:[NSNumber numberWithInt:[v intValue]] forKey:PRState];
  if ((v = PROption (dest, "printer-state-reasons")) != nil)
    [d setObject:v forKey:PRReasons];
  v = PROption (dest, "printer-is-accepting-jobs");
  [d setObject:[NSNumber numberWithBool:(v == nil || [v isEqual:@"true"])]
        forKey:PRAccepting];
  [d setObject:[NSNumber numberWithBool:dest->is_default != 0]
        forKey:PRDefault];
  if ((v = PROption (dest, CUPS_MEDIA)) != nil)
    [d setObject:v forKey:PRMedia];
  if ((v = PROption (dest, CUPS_SIDES)) != nil)
    [d setObject:v forKey:PRSides];
  return d;
}

/* The queue's waiting and printing jobs, everyone's. */
static NSArray *
PRJobsOf (NSString *printer)
{
  NSMutableArray *list = [NSMutableArray array];
  cups_job_t *jobs = NULL;
  int n, i;

  n = cupsGetJobs2 (CUPS_HTTP_DEFAULT, &jobs, [printer UTF8String], 0,
                    CUPS_WHICHJOBS_ACTIVE);
  for (i = 0; i < n; i++)
    [list addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                       PRString (jobs[i].title), PRJobTitle,
                       PRString (jobs[i].user), PRJobUser,
                       [NSNumber numberWithInt:jobs[i].state], PRJobState,
                       nil]];
  cupsFreeJobs (n, jobs);
  return list;
}

/* A queue cupsd made by itself for a printer it found, when something
   printed to it, and removes again once it's idle: still a printer
   nearby, not one set up. */
static BOOL
PRIsTemporary (cups_dest_t *dest)
{
  const char *v = cupsGetOption ("printer-is-temporary", dest->num_options,
                                 dest->options);

  return v != NULL && strcmp (v, "true") == 0;
}

static int
PRAddQueue (void *user, unsigned flags, cups_dest_t *dest)
{
  /* An lpoptions instance (name/instance) is the same queue. */
  if (!(flags & CUPS_DEST_FLAGS_REMOVED) && dest->instance == NULL
      && !PRIsTemporary (dest))
    [(NSMutableArray *) user addObject:PRDestDictionary (dest)];
  return 1;
}

static int
PRAddFound (void *user, unsigned flags, cups_dest_t *dest)
{
  const char *type = cupsGetOption ("printer-type", dest->num_options,
                                    dest->options);

  if (!(flags & CUPS_DEST_FLAGS_REMOVED) && dest->instance == NULL
      && ((type != NULL && (atoi (type) & CUPS_PRINTER_DISCOVERED))
          || PRIsTemporary (dest)))
    [(NSMutableArray *) user addObject:PRDestDictionary (dest)];
  return 1;
}

static NSInteger
PRByInfo (id a, id b, void *context)
{
  return [[a objectForKey:PRInfo] caseInsensitiveCompare:
                                    [b objectForKey:PRInfo]];
}

NSArray *
PRCupsPrinters (void)
{
  NSMutableArray *list = [NSMutableArray array];
  NSUInteger i;

  /* type 0 under mask DISCOVERED: the queues, not what DNS-SD finds,
     and so no waiting for it. */
  if (!cupsEnumDests (CUPS_DEST_FLAGS_NONE, 0, NULL, 0,
                      CUPS_PRINTER_DISCOVERED, PRAddQueue, list))
    return nil;
  for (i = 0; i < [list count]; i++)
    {
      NSMutableDictionary *p = [list objectAtIndex:i];
      [p setObject:PRJobsOf ([p objectForKey:PRName]) forKey:PRJobs];
    }
  [list sortUsingFunction:PRByInfo context:NULL];
  return list;
}

NSArray *
PRCupsNearby (NSArray *queues, int msec)
{
  NSMutableArray *found = [NSMutableArray array];
  NSMutableArray *list = [NSMutableArray array];
  NSEnumerator *e;
  NSDictionary *p;

  cupsEnumDests (CUPS_DEST_FLAGS_NONE, msec, NULL, 0, 0, PRAddFound, found);
  /* libcups names a printer it finds after its service, as the queue
     added for it is named, and the queue has the same device URI. */
  e = [found objectEnumerator];
  while ((p = [e nextObject]) != nil)
    {
      NSEnumerator *q = [queues objectEnumerator];
      NSDictionary *queue;
      BOOL known = [p objectForKey:PRDeviceURI] == nil;

      while (!known && (queue = [q nextObject]) != nil)
        known = [[queue objectForKey:PRDeviceURI]
                  isEqual:[p objectForKey:PRDeviceURI]]
          || [[queue objectForKey:PRName]
               caseInsensitiveCompare:[p objectForKey:PRName]]
             == NSOrderedSame;
      if (!known)
        [list addObject:p];
    }
  [list sortUsingFunction:PRByInfo context:NULL];
  return list;
}

/* Change the user's lpoptions for printer, as lpoptions(1) does: all
   the dests, one changed, written back. cupsSetDests2 writes only what
   differs from cupsd's own values. */
static BOOL
PRChangeDests (NSString *printer, NSString *option, NSString *value,
               BOOL makeDefault)
{
  cups_dest_t *dests = NULL, *dest;
  const char *name = [printer UTF8String];
  int n, i, rc;

  n = cupsGetDests2 (CUPS_HTTP_DEFAULT, &dests);
  if ((dest = cupsGetDest (name, NULL, n, dests)) == NULL)
    {
      n = cupsAddDest (name, NULL, n, &dests);
      dest = cupsGetDest (name, NULL, n, dests);
    }
  if (dest == NULL)
    {
      cupsFreeDests (n, dests);
      return NO;
    }
  if (makeDefault)
    {
      for (i = 0; i < n; i++)
        dests[i].is_default = 0;
      dest->is_default = 1;
    }
  if (option != nil && value != nil)
    dest->num_options = cupsAddOption ([option UTF8String], [value UTF8String],
                                       dest->num_options, &dest->options);
  else if (option != nil)
    dest->num_options = cupsRemoveOption ([option UTF8String],
                                          dest->num_options, &dest->options);
  rc = cupsSetDests2 (CUPS_HTTP_DEFAULT, n, dests);
  cupsFreeDests (n, dests);
  return rc == 0;
}

BOOL
PRCupsSetDefault (NSString *printer)
{
  return PRChangeDests (printer, nil, nil, YES);
}

BOOL
PRCupsSetOption (NSString *printer, NSString *option, NSString *value)
{
  return PRChangeDests (printer, option, value, NO);
}

NSArray *
PRCupsChoices (NSString *printer, NSString *option, NSString **byDefault)
{
  NSMutableArray *list = [NSMutableArray array];
  const char *name = [option UTF8String];
  cups_dest_t *dest;
  cups_dinfo_t *info;
  ipp_attribute_t *attr;
  int i;

  if (byDefault != NULL)
    *byDefault = nil;
  dest = cupsGetNamedDest (CUPS_HTTP_DEFAULT, [printer UTF8String], NULL);
  if (dest == NULL)
    return nil;
  info = cupsCopyDestInfo (CUPS_HTTP_DEFAULT, dest);
  if (info == NULL)
    {
      cupsFreeDests (1, dest);
      return nil;
    }
  attr = cupsFindDestSupported (CUPS_HTTP_DEFAULT, dest, info, name);
  for (i = 0; i < ippGetCount (attr); i++)
    {
      const char *v = ippGetString (attr, i, NULL);

      /* The ends of a custom size's range aren't sizes. */
      if (v != NULL && strncmp (v, "custom_", 7) != 0)
        [list addObject:PRString (v)];
    }
  attr = cupsFindDestDefault (CUPS_HTTP_DEFAULT, dest, info, name);
  if (byDefault != NULL && attr != NULL && ippGetString (attr, 0, NULL))
    *byDefault = PRString (ippGetString (attr, 0, NULL));
  cupsFreeDestInfo (info);
  cupsFreeDests (1, dest);
  return [list count] > 0 ? list : nil;
}

/* "8.5", "4.125", "210": a length without trailing zeros. */
static NSString *
PRLength (double v)
{
  NSString *s = [NSString stringWithFormat:@"%.3f", v];

  while ([s hasSuffix:@"0"])
    s = [s substringToIndex:[s length] - 1];
  if ([s hasSuffix:@"."])
    s = [s substringToIndex:[s length] - 1];
  return s;
}

/* The usual sizes' names, by the PWG name's class and size name. */
static NSString *
PRMediaKnownName (NSString *pwg)
{
  static NSDictionary *names;

  if (names == nil)
    names = [[NSDictionary alloc] initWithObjectsAndKeys:
                @"US Letter", @"na_letter",
                @"US Legal", @"na_legal",
                @"Executive", @"na_executive",
                @"Tabloid", @"na_ledger",
                @"Statement", @"na_invoice",
                @"Envelope #10", @"na_number-10",
                @"Envelope Monarch", @"na_monarch",
                @"Index card 3 × 5", @"na_index-3x5",
                @"Index card 4 × 6", @"na_index-4x6",
                @"Photo 5 × 7", @"na_5x7",
                @"A3", @"iso_a3", @"A4", @"iso_a4", @"A5", @"iso_a5",
                @"A6", @"iso_a6", @"B5", @"iso_b5", @"JIS B5", @"jis_b5",
                @"Envelope DL", @"iso_dl", @"Envelope C5", @"iso_c5",
                @"Envelope C6", @"iso_c6",
                @"Hagaki", @"jpn_hagaki", nil];
  {
    NSRange last = [pwg rangeOfString:@"_" options:NSBackwardsSearch];

    if (last.location == NSNotFound)
      return nil;
    return [names objectForKey:[pwg substringToIndex:last.location]];
  }
}

NSString *
PRCupsValueName (NSString *option, NSString *value)
{
  if ([option isEqual:PROptionSides])
    {
      if ([value isEqual:@"one-sided"])
        return @"Off";
      if ([value isEqual:@"two-sided-long-edge"])
        return @"Long-edge binding";
      if ([value isEqual:@"two-sided-short-edge"])
        return @"Short-edge binding";
      return value;
    }
  if ([option isEqual:PROptionMedia])
    {
      pwg_media_t *m = pwgMediaForPWG ([value UTF8String]);
      NSString *name = PRMediaKnownName (value), *size;

      if (m == NULL)
        return value;
      if (name == nil)
        name = m->ppd != NULL ? PRString (m->ppd) : value;
      /* North American sizes in inches, the others in millimetres. */
      if ([value hasPrefix:@"na_"] || [value hasSuffix:@"in"])
        size = [NSString stringWithFormat:@"%@ × %@ in",
                         PRLength (m->width / 2540.0),
                         PRLength (m->length / 2540.0)];
      else
        size = [NSString stringWithFormat:@"%@ × %@ mm",
                         PRLength (m->width / 100.0),
                         PRLength (m->length / 100.0)];
      return [NSString stringWithFormat:@"%@ (%@)", name, size];
    }
  return value;
}

/* A printer-state-reasons keyword as words: "media-empty-error" ->
   "out of paper". Those that only say what the state says: nil. */
static NSString *
PRReasonText (NSString *reason)
{
  static NSDictionary *texts;
  NSString *const suffixes[] = { @"-error", @"-warning", @"-report", nil };
  NSString *text;
  int i;

  if (texts == nil)
    texts = [[NSDictionary alloc] initWithObjectsAndKeys:
                @"out of paper", @"media-empty",
                @"out of paper", @"media-needed",
                @"paper jam", @"media-jam",
                @"toner low", @"toner-low",
                @"out of toner", @"toner-empty",
                @"ink low", @"marker-supply-low",
                @"out of ink", @"marker-supply-empty",
                @"a door is open", @"door-open",
                @"a cover is open", @"cover-open",
                @"offline", @"offline",
                @"connecting", @"connecting-to-device",
                @"", @"none", @"", @"paused", @"", @"other", nil];
  for (i = 0; suffixes[i] != nil; i++)
    if ([reason hasSuffix:suffixes[i]])
      {
        reason = [reason substringToIndex:[reason length]
                                          - [suffixes[i] length]];
        break;
      }
  text = [texts objectForKey:reason];
  if (text == nil)
    text = [reason stringByReplacingOccurrencesOfString:@"-" withString:@" "];
  return [text length] > 0 ? text : nil;
}

NSString *
PRCupsStateText (NSDictionary *printer)
{
  NSMutableArray *parts = [NSMutableArray array];
  NSEnumerator *e;
  NSString *reason, *state;

  switch ([[printer objectForKey:PRState] intValue])
    {
    case IPP_PSTATE_PROCESSING:
      state = @"Printing";
      break;
    case IPP_PSTATE_STOPPED:
      state = @"Stopped";
      break;
    default:
      state = @"Idle";
    }
  e = [[[printer objectForKey:PRReasons] componentsSeparatedByString:@","]
        objectEnumerator];
  while ((reason = [e nextObject]) != nil)
    {
      NSString *text = PRReasonText (reason);
      if (text != nil && ![parts containsObject:text])
        [parts addObject:text];
    }
  if (![[printer objectForKey:PRAccepting] boolValue])
    [parts addObject:@"not accepting jobs"];
  if ([parts count] == 0)
    return state;
  return [NSString stringWithFormat:@"%@, %@", state,
                   [parts componentsJoinedByString:@", "]];
}

NSString *
PRCupsQueueName (NSString *info, NSArray *taken)
{
  NSMutableString *name = [NSMutableString string];
  NSString *base, *candidate;
  NSUInteger i;
  int n;

  for (i = 0; i < [info length]; i++)
    {
      unichar c = [info characterAtIndex:i];

      if (c <= ' ' || c == 127 || (c < 128 && strchr (PRBadNameChars, c)))
        c = '_';
      if (c == '_' && [name hasSuffix:@"_"])
        continue;
      [name appendString:[NSString stringWithCharacters:&c length:1]];
    }
  while ([name hasPrefix:@"_"] || [name hasPrefix:@"-"])
    [name deleteCharactersInRange:NSMakeRange (0, 1)];
  while ([name hasSuffix:@"_"])
    [name deleteCharactersInRange:NSMakeRange ([name length] - 1, 1)];
  if ([name length] == 0)
    [name setString:@"Printer"];
  /* Room for "_99" within cupsd's limit, in bytes. */
  while (strlen ([name UTF8String]) > PRNameMax - 3)
    [name deleteCharactersInRange:
            [name rangeOfComposedCharacterSequenceAtIndex:[name length] - 1]];
  base = AUTORELEASE ([name copy]);
  candidate = base;
  for (n = 2; n < 100; n++)
    {
      NSEnumerator *e = [taken objectEnumerator];
      NSString *t;
      BOOL used = NO;

      /* cupsd's names are case-insensitive. */
      while (!used && (t = [e nextObject]) != nil)
        used = [t caseInsensitiveCompare:candidate] == NSOrderedSame;
      if (!used)
        break;
      candidate = [NSString stringWithFormat:@"%@_%d", base, n];
    }
  return candidate;
}

NSString *
PRCupsURIForAddress (NSString *address)
{
  NSCharacterSet *hostChars = [NSCharacterSet characterSetWithCharactersInString:
      @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-:[]"];
  NSString *a = [address stringByTrimmingCharactersInSet:
                           [NSCharacterSet whitespaceCharacterSet]];
  NSUInteger i;

  if ([a length] == 0)
    return nil;
  if ([a rangeOfString:@"://"].location != NSNotFound)
    {
      /* A URI as it is: the ones a driverless queue takes. */
      if (!([a hasPrefix:@"ipp://"] || [a hasPrefix:@"ipps://"]
            || [a hasPrefix:@"dnssd://"]))
        return nil;
      for (i = 0; i < [a length]; i++)
        if ([a characterAtIndex:i] <= ' ' || [a characterAtIndex:i] >= 127)
          return nil;
      /* Something after the scheme. */
      return [a length] > NSMaxRange ([a rangeOfString:@"://"]) ? a : nil;
    }
  if ([[a stringByTrimmingCharactersInSet:hostChars] length] != 0)
    return nil;
  /* An IPv6 address goes in brackets. */
  if ([[a componentsSeparatedByString:@":"] count] > 2 && ![a hasPrefix:@"["])
    a = [NSString stringWithFormat:@"[%@]", a];
  /* IPP Everywhere's resource. */
  return [NSString stringWithFormat:@"ipp://%@/ipp/print", a];
}
