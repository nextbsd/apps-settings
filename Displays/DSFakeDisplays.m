/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "DSFakeDisplays.h"
#import "DSDisplay.h"
#import <GNUstepBase/GNUstep.h>

#include <errno.h>
#include <stdlib.h>
#include <string.h>

#ifndef DS_FAKE_DISPLAYS

@implementation DSFakeDisplays

+ (id)fakeDisplaysWithTarget:(id)target selector:(SEL)selector
{
  return nil;
}

- (NSArray *)displays
{
  return [NSArray array];
}

- (NSDictionary *)settings
{
  return [NSDictionary dictionary];
}

- (int)configure:(unsigned)op
         display:(unsigned)displayID
               x:(int)x
               y:(int)y
           width:(unsigned)width
          height:(unsigned)height
         refresh:(unsigned)refresh
             arg:(unsigned)arg
           flags:(unsigned)flags
{
  return ENOTSUP;
}

- (int)setSetting:(NSString *)key value:(NSString *)value
{
  return ENOTSUP;
}

@end

#else /* DS_FAKE_DISPLAYS */

#define FakeMax 3
#define FakeMaxSizes 5
#define FakeMaxModes 12

typedef struct {
  unsigned w, h;
} FakeSize;

typedef struct {
  unsigned w, h, mhz, flags;
} FakeMode;

typedef struct {
  unsigned id, flags;
  int x, y;			/* points */
  unsigned lookW, lookH;	/* points */
  unsigned scale;
  unsigned panelW, panelH, mhz;
  unsigned mirrorOf;
  unsigned mmW, mmH;
  const char *name, *edid, *connector;
  FakeSize sizes[FakeMaxSizes];	/* Larger Text to More Space */
  int nsizes, defaultSize;
  FakeMode modes[FakeMaxModes];	/* largest first */
  int nmodes, preferredMode;
} FakeDisplay;

typedef struct {
  FakeDisplay d[FakeMax];
  int n;
  FakeDisplay saved[FakeMax];	/* before the pending change */
  unsigned pending;		/* display id, or 0 */
  NSTimeInterval deadline;
} FakeState;

static const FakeDisplay FakeTemplates[FakeMax] = {
  { 1, DSDisplayMain | DSDisplayBuiltin | DSDisplayHiDPI, 0, 0, 1440, 900, 2,
    2880, 1800, 60000, 0, 302, 189, "Built-in Display", "BOE-0a1c-0",
    "eDP-1",
    { { 1024, 640 }, { 1280, 800 }, { 1440, 900 }, { 1680, 1050 },
      { 1920, 1200 } }, 5, 2,
    { { 2880, 1800, 120000, 0 }, { 2880, 1800, 60000, 0 },
      { 1920, 1200, 60000, 0 }, { 1440, 900, 60000, 0 } }, 4, 0 },
  { 2, DSDisplayHiDPI, 1440, 0, 1920, 1080, 2,
    3840, 2160, 60000, 0, 597, 336, "DELL U2723QE", "DEL-41c6-31474b4c",
    "DP-1",
    { { 1280, 720 }, { 1600, 900 }, { 1920, 1080 }, { 2560, 1440 },
      { 3008, 1692 } }, 5, 2,
    { { 3840, 2160, 60000, 0 }, { 3840, 2160, 59940, 0 },
      { 3840, 2160, 30000, 0 }, { 2560, 1440, 60000, 0 },
      { 1920, 1080, 60000, 0 }, { 1920, 1080, 59940, 0 },
      { 1920, 1080, 50000, 0 }, { 1920, 1080, 60000, DSModeInterlaced },
      { 1280, 720, 60000, 0 }, { 1024, 768, 60000, 0 },
      { 800, 600, 60000, 0 } }, 11, 0 },
  { 3, 0, 3360, 0, 1920, 1080, 1,
    1920, 1080, 144000, 0, 527, 296, "LG 24GN600", "GSM-5b7f-1234",
    "HDMI-A-1",
    { { 1280, 720 }, { 1920, 1080 } }, 2, 1,
    { { 1920, 1080, 144000, 0 }, { 1920, 1080, 120000, 0 },
      { 1920, 1080, 60000, 0 }, { 1280, 720, 60000, 0 } }, 4, 0 },
};

#define STATE ((FakeState *)_state)

static FakeDisplay *
FakeFind (FakeState *s, unsigned id)
{
  int i;

  for (i = 0; i < s->n; i++)
    if (s->d[i].id == id)
      return &s->d[i];
  return NULL;
}

static NSRect
FakeOwnFrame (const FakeDisplay *d)
{
  return NSMakeRect (d->x, d->y, d->lookW, d->lookH);
}

/* The main display at 0,0, as on macOS. */
static void
FakeNormalize (FakeState *s)
{
  int i, dx = 0, dy = 0;

  for (i = 0; i < s->n; i++)
    if (s->d[i].flags & DSDisplayMain)
      {
        dx = s->d[i].x;
        dy = s->d[i].y;
      }
  for (i = 0; i < s->n; i++)
    {
      s->d[i].x -= dx;
      s->d[i].y -= dy;
    }
}

@interface DSFakeDisplays (Private)
- (void)changed;
- (void)revertTimer:(NSTimer *)timer;
- (void)endPending:(BOOL)keep;
@end

@implementation DSFakeDisplays

+ (id)fakeDisplaysWithTarget:(id)target selector:(SEL)selector
{
  const char *count = getenv ("DS_FAKE_DISPLAYS");
  DSFakeDisplays *fake;
  int n;

  if (count == NULL || (n = atoi (count)) <= 0)
    return nil;
  fake = AUTORELEASE ([[self alloc] init]);
  fake->_state = calloc (1, sizeof (FakeState));
  ((FakeState *)fake->_state)->n = n > FakeMax ? FakeMax : n;
  memcpy (((FakeState *)fake->_state)->d, FakeTemplates,
          sizeof (FakeTemplates));
  fake->_target = target;
  fake->_selector = selector;
  fake->_settings = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
      @"Off", @"NightShift",
      @"22:00-07:00", @"NightShiftSchedule",
      @"3400", @"NightShiftTemperature", nil];
  NSLog (@"Displays: %d made-up displays (DS_FAKE_DISPLAYS)",
         ((FakeState *)fake->_state)->n);
  return fake;
}

- (void)dealloc
{
  [_revertTimer invalidate];
  RELEASE (_revertTimer);
  RELEASE (_settings);
  free (_state);
  [super dealloc];
}

- (NSArray *)displays
{
  NSMutableArray *list = [NSMutableArray array];
  FakeState *s = STATE;
  int pass, i, k;

  /* The main one first. */
  for (pass = 0; pass < 2; pass++)
    for (i = 0; i < s->n; i++)
      {
        FakeDisplay *d = &s->d[i];
        FakeDisplay *of = d->mirrorOf ? FakeFind (s, d->mirrorOf) : NULL;
        NSMutableArray *modes = [NSMutableArray array];
        unsigned flags = d->flags & ~(DSDisplayMirror | DSDisplayPending);
        unsigned revert = 0;

        if (((d->flags & DSDisplayMain) != 0) != (pass == 0))
          continue;
        if (of != NULL)
          flags |= DSDisplayMirror;
        if (s->pending == d->id)
          {
            NSTimeInterval left = s->deadline
              - [NSDate timeIntervalSinceReferenceDate];
            flags |= DSDisplayPending;
            revert = left > 0 ? (unsigned) (left * 1000) : 0;
          }
        for (k = 0; k < d->nsizes; k++)
          {
            unsigned f = 0;
            if (d->sizes[k].w == d->lookW && d->sizes[k].h == d->lookH)
              f |= DSModeCurrent;
            if (k == d->defaultSize)
              f |= DSModeDefault;
            [modes addObject:[DSDisplayMode modeWithKind:DSModeLooksLike
                                                   flags:f
                                                   width:d->sizes[k].w
                                                  height:d->sizes[k].h
                                              refreshMHz:0]];
          }
        for (k = 0; k < d->nmodes; k++)
          {
            FakeMode *m = &d->modes[k];
            unsigned f = m->flags;
            if (m->w == d->panelW && m->h == d->panelH && m->mhz == d->mhz
                && (m->flags & DSModeInterlaced) == 0)
              f |= DSModeCurrent;
            if (k == d->preferredMode)
              f |= DSModeDefault;
            [modes addObject:[DSDisplayMode modeWithKind:DSModePanel
                                                   flags:f
                                                   width:m->w
                                                  height:m->h
                                              refreshMHz:m->mhz]];
          }

        DSDisplay *display = [[DSDisplay alloc]
            initWithID:d->id
                 flags:flags
                 frame:FakeOwnFrame (of != NULL ? of : d)
                 scale:d->scale
            panelWidth:d->panelW
           panelHeight:d->panelH
            refreshMHz:d->mhz
              mirrorOf:(of != NULL ? of->id : 0)
              revertMS:revert
                  name:[NSString stringWithUTF8String:d->name]
                edidID:[NSString stringWithUTF8String:d->edid]
             connector:[NSString stringWithUTF8String:d->connector]];
        [display setModes:modes];
        [display setFollowsDefault:(d->lookW == d->sizes[d->defaultSize].w
                                    && d->lookH == d->sizes[d->defaultSize].h)];
        [list addObject:display];
        RELEASE (display);
      }
  return list;
}

- (NSDictionary *)settings
{
  return AUTORELEASE ([_settings copy]);
}

- (int)configure:(unsigned)op
         display:(unsigned)displayID
               x:(int)x
               y:(int)y
           width:(unsigned)width
          height:(unsigned)height
         refresh:(unsigned)refresh
             arg:(unsigned)arg
           flags:(unsigned)flags
{
  FakeState *s = STATE;
  FakeDisplay before[FakeMax];
  FakeDisplay *d;
  int i, k;

  if (op == DSOpKeep || op == DSOpRevert)
    {
      if (s->pending == 0)
        return ENOENT;
      [self endPending:(op == DSOpKeep)];
      return 0;
    }
  if ((d = FakeFind (s, displayID)) == NULL)
    return ENOENT;
  memcpy (before, s->d, sizeof (before));

  switch (op)
    {
    case DSOpSetLooksLike:
      if (width == 0 && height == 0)
        k = d->defaultSize;
      else
        for (k = 0; k < d->nsizes; k++)
          if (d->sizes[k].w == width && d->sizes[k].h == height)
            break;
      if (k >= d->nsizes)
        return EINVAL;
      d->lookW = d->sizes[k].w;
      d->lookH = d->sizes[k].h;
      break;

    case DSOpSetMode:
      {
        int found = -1;

        if (width == 0 && height == 0)
          found = d->preferredMode;
        else
          for (k = 0; k < d->nmodes && found < 0; k++)
            if (d->modes[k].w == width && d->modes[k].h == height
                && (refresh == 0 || d->modes[k].mhz == refresh))
              found = k;
        if (found < 0)
          return EINVAL;
        d->panelW = d->modes[found].w;
        d->panelH = d->modes[found].h;
        d->mhz = d->modes[found].mhz;
        d->lookW = d->panelW / d->scale;
        d->lookH = d->panelH / d->scale;
        break;
      }

    case DSOpSetOrigin:
      {
        NSMutableArray *others = [NSMutableArray array];
        NSPoint p;

        if (d->mirrorOf)
          return EINVAL;
        for (i = 0; i < s->n; i++)
          if (&s->d[i] != d && s->d[i].mirrorOf == 0)
            [others addObject:[NSValue valueWithRect:FakeOwnFrame (&s->d[i])]];
        p = DSSnapOrigin (NSMakeRect (x, y, d->lookW, d->lookH), others, 0);
        d->x = (int) p.x;
        d->y = (int) p.y;
        FakeNormalize (s);
        break;
      }

    case DSOpSetMain:
      if (d->mirrorOf)
        return EINVAL;
      for (i = 0; i < s->n; i++)
        s->d[i].flags &= ~DSDisplayMain;
      d->flags |= DSDisplayMain;
      FakeNormalize (s);
      break;

    case DSOpSetMirror:
      if (arg == displayID || (arg != 0 && FakeFind (s, arg) == NULL))
        return EINVAL;
      if (arg != 0 && (d->flags & DSDisplayMain))
        return EINVAL;
      d->mirrorOf = arg;
      if (arg == 0)
        {
          /* Back to its own part, to the right of the others. */
          int right = 0;
          for (i = 0; i < s->n; i++)
            if (&s->d[i] != d && s->d[i].mirrorOf == 0
                && s->d[i].x + (int) s->d[i].lookW > right)
              right = s->d[i].x + (int) s->d[i].lookW;
          d->x = right;
          d->y = 0;
        }
      break;

    default:
      return EINVAL;
    }

  if (flags & DSConfirm)
    {
      /* A second change keeps the first. */
      memcpy (s->saved, before, sizeof (before));
      s->pending = displayID;
      s->deadline = [NSDate timeIntervalSinceReferenceDate] + DSRevertSeconds;
      [_revertTimer invalidate];
      ASSIGN (_revertTimer,
              [NSTimer scheduledTimerWithTimeInterval:DSRevertSeconds
                                               target:self
                                             selector:@selector (revertTimer:)
                                             userInfo:nil
                                              repeats:NO]);
    }
  [self changed];
  return 0;
}

- (int)setSetting:(NSString *)key value:(NSString *)value
{
  if (![key hasPrefix:@"NightShift"])
    return EINVAL;
  [_settings setObject:value forKey:key];
  NSLog (@"Displays: (made up) %@ = %@", key, value);
  [self changed];
  return 0;
}

@end

@implementation DSFakeDisplays (Private)

- (void)changed
{
  [_target performSelector:_selector withObject:nil afterDelay:0];
}

- (void)revertTimer:(NSTimer *)timer
{
  NSLog (@"Displays: (made up) no answer in %d s, going back",
         DSRevertSeconds);
  [self endPending:NO];
}

- (void)endPending:(BOOL)keep
{
  FakeState *s = STATE;

  if (!keep)
    memcpy (s->d, s->saved, sizeof (s->d));
  s->pending = 0;
  [_revertTimer invalidate];
  DESTROY (_revertTimer);
  [self changed];
}

@end

#endif /* DS_FAKE_DISPLAYS */
