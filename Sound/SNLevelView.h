/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * SNLevelView: the input level meter, a row of segments lit up to the
 * level, as macOS's. It holds a short peak so a click still shows.
 */

#import <AppKit/AppKit.h>

@interface SNLevelView : NSView
{
  float level;			/* 0.0-1.0 */
  float held;			/* the recent peak */
  NSTimeInterval heldAt;
  BOOL active;			/* off: drawn dimmed, empty */
}
- (void)setLevel:(float)newLevel;
- (void)setActive:(BOOL)flag;
@end
