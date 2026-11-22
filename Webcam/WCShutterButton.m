/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "WCShutterButton.h"
#import <GNUstepBase/GNUstep.h>

@implementation WCShutterButton

- (id)initWithFrame:(NSRect)frame
{
  if ((self = [super initWithFrame:frame]) != nil)
    {
      [self setBordered:NO];
      [self setTitle:@""];
      [self setButtonType:NSMomentaryChangeButton];
    }
  return self;
}

- (void)setKind:(WCShutterKind)newKind
{
  kind = newKind;
  [self setNeedsDisplay:YES];
}

- (BOOL)isOpaque
{
  return NO;
}

- (void)drawRect:(NSRect)rect
{
  NSRect bounds = [self bounds];
  CGFloat side = MIN (NSWidth (bounds), NSHeight (bounds));
  NSRect ring = NSMakeRect (NSMidX (bounds) - side / 2,
                            NSMidY (bounds) - side / 2, side, side);
  NSRect disc = NSInsetRect (ring, 3, 3);
  BOOL down = [[self cell] isHighlighted];
  CGFloat cx = NSMidX (disc), cy = NSMidY (disc);
  CGFloat u = side / 44.0;	/* drawn for 44 points */
  NSColor *red = [NSColor colorWithCalibratedRed:(down ? 0.75 : 0.95)
                                           green:(down ? 0.16 : 0.24)
                                            blue:(down ? 0.13 : 0.2)
                                           alpha:([self isEnabled]
                                                  ? 1.0 : 0.4)];
  NSColor *white = [NSColor colorWithCalibratedWhite:1.0
                                               alpha:([self isEnabled]
                                                      ? 1.0 : 0.5)];
  NSBezierPath *path;

  [[NSColor colorWithCalibratedWhite:0.85 alpha:0.9] set];
  [[NSBezierPath bezierPathWithOvalInRect:ring] fill];
  [red set];
  [[NSBezierPath bezierPathWithOvalInRect:disc] fill];

  [white set];
  switch (kind)
    {
    case WCShutterPhoto:
      /* A camera: a body, a bump on top, a lens. */
      [[NSBezierPath bezierPathWithRoundedRect:
                       NSMakeRect (cx - 10 * u, cy - 7 * u, 20 * u, 13 * u)
                                       xRadius:2.5 * u yRadius:2.5 * u]
        fill];
      NSRectFill (NSMakeRect (cx - 4 * u, cy + 5 * u, 8 * u, 3 * u));
      [red set];
      [[NSBezierPath bezierPathWithOvalInRect:
                       NSMakeRect (cx - 4.5 * u, cy - 5 * u, 9 * u, 9 * u)]
        fill];
      [white set];
      [[NSBezierPath bezierPathWithOvalInRect:
                       NSMakeRect (cx - 2.5 * u, cy - 3 * u, 5 * u, 5 * u)]
        fill];
      break;

    case WCShutterVideo:
      /* A film camera: a body and a lens hood beside it. */
      [[NSBezierPath bezierPathWithRoundedRect:
                       NSMakeRect (cx - 11 * u, cy - 6 * u, 14 * u, 12 * u)
                                       xRadius:2 * u yRadius:2 * u]
        fill];
      path = [NSBezierPath bezierPath];
      [path moveToPoint:NSMakePoint (cx + 4 * u, cy - 2 * u)];
      [path lineToPoint:NSMakePoint (cx + 11 * u, cy - 6 * u)];
      [path lineToPoint:NSMakePoint (cx + 11 * u, cy + 6 * u)];
      [path lineToPoint:NSMakePoint (cx + 4 * u, cy + 2 * u)];
      [path closePath];
      [path fill];
      break;

    case WCShutterStop:
      [[NSBezierPath bezierPathWithRoundedRect:
                       NSMakeRect (cx - 7 * u, cy - 7 * u, 14 * u, 14 * u)
                                       xRadius:2 * u yRadius:2 * u]
        fill];
      break;
    }
}

@end
