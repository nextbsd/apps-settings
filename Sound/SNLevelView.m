/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "SNLevelView.h"
#import <GNUstepBase/GNUstep.h>

#include <math.h>

#define SNLevelSegments 15
#define SNLevelGap 3.0
#define SNLevelHoldSeconds 1.0
#define SNLevelFall 0.08	/* how far the bar drops per update */

@implementation SNLevelView

- (BOOL)isOpaque
{
  return NO;
}

/* The level's loudness, so speech fills the middle of the bar rather
   than its first segment: -48 dB to 0 dB, linearly. */
static float
SNLevelPosition (float peak)
{
  float db;

  if (peak <= 0.0f)
    return 0.0f;
  db = 20.0f * log10f (peak);
  return db <= -48.0f ? 0.0f : (db >= 0.0f ? 1.0f : 1.0f + db / 48.0f);
}

- (void)setLevel:(float)newLevel
{
  NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
  float position = SNLevelPosition (newLevel);

  /* Up at once, down gently. */
  level = position > level ? position : MAX (position, level - SNLevelFall);
  if (position >= held || now - heldAt > SNLevelHoldSeconds)
    {
      held = position;
      heldAt = now;
    }
  [self setNeedsDisplay:YES];
}

- (void)setActive:(BOOL)flag
{
  active = flag;
  if (!active)
    level = held = 0.0f;
  [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)rect
{
  NSRect bounds = [self bounds];
  CGFloat width = (NSWidth (bounds) - SNLevelGap * (SNLevelSegments - 1))
    / SNLevelSegments;
  NSInteger lit = (NSInteger) lrintf (level * SNLevelSegments);
  NSInteger peak = (NSInteger) lrintf (held * SNLevelSegments) - 1;
  NSInteger i;

  for (i = 0; i < SNLevelSegments; i++)
    {
      NSRect segment = NSMakeRect (NSMinX (bounds) + i * (width + SNLevelGap),
                                   NSMinY (bounds), width, NSHeight (bounds));
      NSColor *on = i >= SNLevelSegments - 2 ? [NSColor redColor]
        : (i >= SNLevelSegments - 5 ? [NSColor orangeColor]
           : [NSColor colorWithCalibratedRed:0.25 green:0.6 blue:1.0
                                       alpha:1.0]);

      if (active && (i < lit || i == peak))
        [on set];
      else
        [[NSColor colorWithCalibratedWhite:0.5
                                     alpha:active ? 0.35 : 0.18] set];
      NSRectFill (segment);
      [[NSColor colorWithCalibratedWhite:0.0 alpha:0.25] set];
      NSFrameRect (segment);
    }
}

@end
