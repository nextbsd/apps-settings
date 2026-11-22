/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "WCPreviewView.h"
#import <GNUstepBase/GNUstep.h>

#define WCFlashSeconds 0.5
#define WCFlashStep (1.0 / 60.0)

@implementation WCPreviewView

- (void)dealloc
{
  [flashTimer invalidate];
  RELEASE (flashTimer);
  RELEASE (image);
  RELEASE (message);
  RELEASE (badge);
  RELEASE (recording);
  [super dealloc];
}

- (BOOL)isOpaque
{
  return YES;
}

- (void)setImage:(NSBitmapImageRep *)newImage
{
  ASSIGN (image, newImage);
  [self setNeedsDisplay:YES];
}

- (void)setMirror:(BOOL)flag
{
  mirror = flag;
  [self setNeedsDisplay:YES];
}

- (void)setMessage:(NSString *)text
{
  ASSIGNCOPY (message, text);
  [self setNeedsDisplay:YES];
}

- (void)setBadge:(NSString *)text
{
  ASSIGNCOPY (badge, text);
  [self setNeedsDisplay:YES];
}

- (void)setRecording:(NSString *)text
{
  ASSIGNCOPY (recording, text);
  [self setNeedsDisplay:YES];
}

- (void)setCountdown:(NSInteger)number
{
  countdown = number;
  [self setNeedsDisplay:YES];
}

- (void)flashStep:(NSTimer *)timer
{
  flash -= (float) (WCFlashStep / WCFlashSeconds);
  if (flash <= 0.0f)
    {
      flash = 0.0f;
      [flashTimer invalidate];
      DESTROY (flashTimer);
    }
  [self setNeedsDisplay:YES];
}

- (void)flash
{
  flash = 1.0f;
  [flashTimer invalidate];
  RELEASE (flashTimer);
  flashTimer = RETAIN ([NSTimer timerWithTimeInterval:WCFlashStep
                                               target:self
                                             selector:@selector (flashStep:)
                                             userInfo:nil
                                              repeats:YES]);
  [[NSRunLoop currentRunLoop] addTimer:flashTimer
                               forMode:NSDefaultRunLoopMode];
  [[NSRunLoop currentRunLoop] addTimer:flashTimer
                               forMode:NSEventTrackingRunLoopMode];
  [self setNeedsDisplay:YES];
}

/* The picture's rectangle: as big as fits, in the middle. */
- (NSRect)imageRect
{
  NSRect bounds = [self bounds];
  CGFloat w = (CGFloat) [image pixelsWide], h = (CGFloat) [image pixelsHigh];
  CGFloat scale;
  NSRect r;

  if (w <= 0 || h <= 0)
    return NSZeroRect;
  scale = MIN (NSWidth (bounds) / w, NSHeight (bounds) / h);
  r.size = NSMakeSize (floor (w * scale), floor (h * scale));
  r.origin = NSMakePoint (floor (NSMidX (bounds) - r.size.width / 2),
                          floor (NSMidY (bounds) - r.size.height / 2));
  return r;
}

/* text in a dark rounded box at origin (its bottom left). */
static NSRect
WCDrawLabel (NSString *text, NSPoint origin, NSDictionary *attributes,
             BOOL rightAligned, CGFloat dotSpace)
{
  NSSize size = [text sizeWithAttributes:attributes];
  NSRect box = NSMakeRect (origin.x, origin.y, size.width + 16 + dotSpace,
                           size.height + 8);
  NSBezierPath *path;

  if (rightAligned)
    box.origin.x -= NSWidth (box);
  path = [NSBezierPath bezierPathWithRoundedRect:box xRadius:6 yRadius:6];
  [[NSColor colorWithCalibratedWhite:0.0 alpha:0.6] set];
  [path fill];
  [text drawAtPoint:NSMakePoint (NSMinX (box) + 8 + dotSpace,
                                 NSMinY (box) + 4)
     withAttributes:attributes];
  return box;
}

- (void)drawRect:(NSRect)rect
{
  NSRect bounds = [self bounds];
  NSDictionary *small = [NSDictionary dictionaryWithObjectsAndKeys:
    [NSFont boldSystemFontOfSize:12], NSFontAttributeName,
    [NSColor whiteColor], NSForegroundColorAttributeName, nil];

  [[NSColor blackColor] set];
  NSRectFill (rect);

  if (image != nil)
    {
      NSRect r = [self imageRect];

      [NSGraphicsContext saveGraphicsState];
      if (mirror)
        {
          NSAffineTransform *flip = [NSAffineTransform transform];

          [flip translateXBy:NSMinX (r) * 2 + NSWidth (r) yBy:0];
          [flip scaleXBy:-1.0 yBy:1.0];
          [flip concat];
        }
      [image drawInRect:r];
      [NSGraphicsContext restoreGraphicsState];
    }
  else if (message != nil)
    {
      NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSFont systemFontOfSize:15], NSFontAttributeName,
        [NSColor colorWithCalibratedWhite:0.75 alpha:1.0],
        NSForegroundColorAttributeName, nil];
      NSSize size = [message sizeWithAttributes:attributes];

      [message drawAtPoint:NSMakePoint (floor (NSMidX (bounds)
                                               - size.width / 2),
                                        floor (NSMidY (bounds)
                                               - size.height / 2))
            withAttributes:attributes];
    }

  if (badge != nil)
    WCDrawLabel (badge, NSMakePoint (NSMinX (bounds) + 12,
                                     NSMaxY (bounds) - 36),
                 small, NO, 0);

  if (recording != nil)
    {
      NSRect box = WCDrawLabel (recording,
                                NSMakePoint (NSMaxX (bounds) - 12,
                                             NSMaxY (bounds) - 36),
                                small, YES, 14);

      [[NSColor colorWithCalibratedRed:1.0 green:0.23 blue:0.19 alpha:1.0]
        set];
      [[NSBezierPath bezierPathWithOvalInRect:
                       NSMakeRect (NSMinX (box) + 8, NSMidY (box) - 5, 10, 10)]
        fill];
    }

  if (countdown > 0)
    {
      NSString *number = [NSString stringWithFormat:@"%ld", (long) countdown];
      NSDictionary *big = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSFont boldSystemFontOfSize:96], NSFontAttributeName,
        [NSColor whiteColor], NSForegroundColorAttributeName, nil];
      NSSize size = [number sizeWithAttributes:big];
      NSRect disc = NSMakeRect (NSMidX (bounds) - 80, NSMidY (bounds) - 80,
                                160, 160);

      [[NSColor colorWithCalibratedWhite:0.0 alpha:0.45] set];
      [[NSBezierPath bezierPathWithOvalInRect:disc] fill];
      [number drawAtPoint:NSMakePoint (floor (NSMidX (bounds)
                                              - size.width / 2),
                                       floor (NSMidY (bounds)
                                              - size.height / 2))
           withAttributes:big];
    }

  if (flash > 0.0f)
    {
      [[NSColor colorWithCalibratedWhite:1.0 alpha:flash] set];
      NSRectFillUsingOperation (bounds, NSCompositeSourceOver);
    }
}

@end
