/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "SSToolbar.h"
#import "SSOverlay.h"
#import <GNUstepBase/GNUstep.h>

/* Layout, in points. */
#define SSBarHeight 54.0
#define SSPad 10.0
#define SSClose 28.0
#define SSToolSide 38.0
#define SSGap 6.0
#define SSSeparator 21.0	/* the space a separator takes */
#define SSOptions 86.0
#define SSButtonWidth 92.0
#define SSButtonHeight 34.0
#define SSFromBottom 0.12	/* of the screen's height, above the Dock */

/* Items: 0 close, 1..5 the tools, 6 Options, 7 Capture/Record/Stop. */
#define SSItemClose 0
#define SSItemOptions 6
#define SSItemButton 7
#define SSItems 8

static NSColor *
SSRGB (int r, int g, int b, CGFloat a)
{
  return [NSColor colorWithCalibratedRed:r / 255.0 green:g / 255.0
                                    blue:b / 255.0 alpha:a];
}

/* The colours of the mockup's dark toolbar. */
#define SSBarColor SSRGB (30, 31, 34, 0.96)
#define SSBarEdge SSRGB (70, 72, 78, 1.0)
#define SSIconColor SSRGB (232, 233, 236, 1.0)
#define SSAccent SSRGB (24, 198, 240, 1.0)
#define SSChosenBack SSRGB (16, 64, 78, 1.0)
#define SSHoverBack SSRGB (255, 255, 255, 0.08)
#define SSRecordRed SSRGB (240, 68, 56, 1.0)

NSSize
SSToolbarSize (BOOL recording)
{
  if (recording)
    return NSMakeSize (SSPad + SSClose + SSSeparator + SSButtonWidth + SSPad,
                       SSBarHeight);
  return NSMakeSize (SSPad + SSClose + SSSeparator + 3 * SSToolSide + 2 * SSGap
                     + SSSeparator + 2 * SSToolSide + SSGap + SSSeparator
                     + SSOptions + SSGap + SSButtonWidth + SSPad,
                     SSBarHeight);
}

@implementation SSToolbarView

- (id)initWithFrame:(NSRect)frame delegate:(id)delegate
{
  if ((self = [super initWithFrame:frame]) == nil)
    return nil;
  _delegate = delegate;
  _tool = SSToolSelection;
  _pressed = -1;
  _hover = -1;
  return self;
}

- (BOOL)isOpaque
{
  return NO;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event
{
  return YES;
}

- (void)setTool:(SSTool)tool
{
  _tool = tool;
  [self setNeedsDisplay:YES];
}

- (SSTool)tool
{
  return _tool;
}

- (void)setRecording:(BOOL)recording
{
  _recording = recording;
  [self setNeedsDisplay:YES];
}

/* Where item i is, or NSZeroRect when it isn't shown. */
- (NSRect)rectOfItem:(int)i
{
  CGFloat x = SSPad, mid = NSHeight ([self bounds]) / 2;

  if (i == SSItemClose)
    return NSMakeRect (x, mid - SSClose / 2, SSClose, SSClose);
  x += SSClose + SSSeparator;
  if (_recording)
    return i == SSItemButton
      ? NSMakeRect (x, mid - SSButtonHeight / 2, SSButtonWidth,
                    SSButtonHeight)
      : NSZeroRect;
  if (i >= 1 && i <= 3)
    return NSMakeRect (x + (i - 1) * (SSToolSide + SSGap), mid - SSToolSide / 2,
                       SSToolSide, SSToolSide);
  x += 3 * SSToolSide + 2 * SSGap + SSSeparator;
  if (i == 4 || i == 5)
    return NSMakeRect (x + (i - 4) * (SSToolSide + SSGap), mid - SSToolSide / 2,
                       SSToolSide, SSToolSide);
  x += 2 * SSToolSide + SSGap + SSSeparator;
  if (i == SSItemOptions)
    return NSMakeRect (x, mid - SSToolSide / 2, SSOptions, SSToolSide);
  x += SSOptions + SSGap;
  return NSMakeRect (x, mid - SSButtonHeight / 2, SSButtonWidth,
                     SSButtonHeight);
}

- (int)itemAt:(NSPoint)p
{
  int i;

  for (i = 0; i < SSItems; i++)
    if (NSPointInRect (p, NSInsetRect ([self rectOfItem:i], -2, -2)))
      return i;
  return -1;
}

/* ---- the icons, drawn in color inside r ---- */

static void
SSStroke (NSBezierPath *p, CGFloat width)
{
  [p setLineWidth:width];
  [p setLineJoinStyle:NSRoundLineJoinStyle];
  [p setLineCapStyle:NSRoundLineCapStyle];
  [p stroke];
}

static void
SSDrawScreenIcon (NSRect r)
{
  NSRect s = NSMakeRect (NSMidX (r) - 10, NSMidY (r) - 4, 20, 13);
  NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect:s
                                                    xRadius:1.5 yRadius:1.5];

  SSStroke (p, 1.6);
  p = [NSBezierPath bezierPath];
  [p moveToPoint:NSMakePoint (NSMidX (r), NSMinY (s))];
  [p lineToPoint:NSMakePoint (NSMidX (r), NSMinY (s) - 3.5)];
  [p moveToPoint:NSMakePoint (NSMidX (r) - 5, NSMinY (s) - 3.5)];
  [p lineToPoint:NSMakePoint (NSMidX (r) + 5, NSMinY (s) - 3.5)];
  SSStroke (p, 1.6);
}

static void
SSDrawWindowIcon (NSRect r)
{
  NSRect w = NSMakeRect (NSMidX (r) - 10, NSMidY (r) - 7, 20, 15);
  NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect:w
                                                    xRadius:1.5 yRadius:1.5];

  SSStroke (p, 1.6);
  p = [NSBezierPath bezierPath];
  [p moveToPoint:NSMakePoint (NSMinX (w), NSMaxY (w) - 4)];
  [p lineToPoint:NSMakePoint (NSMaxX (w), NSMaxY (w) - 4)];
  SSStroke (p, 1.6);
}

/* Four corner brackets around r's middle, size s. */
static void
SSDrawCorners (NSRect r, CGFloat s)
{
  CGFloat x0 = NSMidX (r) - s / 2, x1 = NSMidX (r) + s / 2;
  CGFloat y0 = NSMidY (r) - s / 2 + 0.5, y1 = NSMidY (r) + s / 2 - 0.5;
  CGFloat l = s * 0.32;
  NSBezierPath *p = [NSBezierPath bezierPath];

  [p moveToPoint:NSMakePoint (x0, y0 + l)];
  [p lineToPoint:NSMakePoint (x0, y0)];
  [p lineToPoint:NSMakePoint (x0 + l, y0)];
  [p moveToPoint:NSMakePoint (x1 - l, y0)];
  [p lineToPoint:NSMakePoint (x1, y0)];
  [p lineToPoint:NSMakePoint (x1, y0 + l)];
  [p moveToPoint:NSMakePoint (x1, y1 - l)];
  [p lineToPoint:NSMakePoint (x1, y1)];
  [p lineToPoint:NSMakePoint (x1 - l, y1)];
  [p moveToPoint:NSMakePoint (x0 + l, y1)];
  [p lineToPoint:NSMakePoint (x0, y1)];
  [p lineToPoint:NSMakePoint (x0, y1 - l)];
  SSStroke (p, 1.7);
}

static void
SSDrawRecordDot (NSRect r, CGFloat radius)
{
  NSBezierPath *p = [NSBezierPath bezierPathWithOvalInRect:
                                    NSMakeRect (NSMidX (r) - radius,
                                                NSMidY (r) - radius,
                                                2 * radius, 2 * radius)];
  SSStroke (p, 1.6);
}

- (void)drawItem:(int)i
{
  NSRect r = [self rectOfItem:i];
  BOOL chosen = i >= 1 && i <= 5 && (int) _tool == i - 1;
  BOOL hover = i == _hover || i == _pressed;
  NSColor *ink = chosen ? SSAccent : SSIconColor;

  if (NSIsEmptyRect (r))
    return;
  if (i == SSItemClose)
    {
      NSBezierPath *c = [NSBezierPath bezierPathWithOvalInRect:r];
      NSBezierPath *x = [NSBezierPath bezierPath];
      CGFloat d = 4.5;

      [(hover ? SSRGB (88, 90, 96, 1.0) : SSRGB (62, 64, 70, 1.0)) set];
      [c fill];
      [x moveToPoint:NSMakePoint (NSMidX (r) - d, NSMidY (r) - d)];
      [x lineToPoint:NSMakePoint (NSMidX (r) + d, NSMidY (r) + d)];
      [x moveToPoint:NSMakePoint (NSMidX (r) - d, NSMidY (r) + d)];
      [x lineToPoint:NSMakePoint (NSMidX (r) + d, NSMidY (r) - d)];
      [SSRGB (200, 202, 208, 1.0) set];
      SSStroke (x, 1.5);
      return;
    }
  if (i == SSItemButton)
    {
      NSString *title = _recording ? @"Stop"
        : SSToolRecords (_tool) ? @"Record" : @"Capture";
      NSColor *fill = _recording ? SSRecordRed : SSAccent;
      NSDictionary *attrs;
      NSSize size;

      if (hover)
        fill = [fill blendedColorWithFraction:0.15
                                      ofColor:[NSColor whiteColor]];
      [fill set];
      [[NSBezierPath bezierPathWithRoundedRect:r xRadius:7 yRadius:7] fill];
      attrs = [NSDictionary dictionaryWithObjectsAndKeys:
                              [NSFont boldSystemFontOfSize:14],
                            NSFontAttributeName,
                            (_recording ? [NSColor whiteColor]
                             : SSRGB (4, 34, 44, 1.0)),
                            NSForegroundColorAttributeName, nil];
      size = [title sizeWithAttributes:attrs];
      [title drawAtPoint:NSMakePoint (floor (NSMidX (r) - size.width / 2),
                                      floor (NSMidY (r) - size.height / 2))
          withAttributes:attrs];
      return;
    }
  if (chosen || hover)
    {
      [(chosen ? SSChosenBack : SSHoverBack) set];
      [[NSBezierPath bezierPathWithRoundedRect:r xRadius:7 yRadius:7] fill];
    }
  [ink set];
  switch (i)
    {
    case 1:
      SSDrawScreenIcon (r);
      break;
    case 2:
      SSDrawWindowIcon (r);
      break;
    case 3:
      SSDrawCorners (r, 18);
      break;
    case 4:
      SSDrawRecordDot (r, 6);
      break;
    case 5:
      SSDrawCorners (r, 20);
      SSDrawRecordDot (r, 4);
      break;
    case SSItemOptions:
      {
        NSDictionary *attrs =
          [NSDictionary dictionaryWithObjectsAndKeys:
                          [NSFont boldSystemFontOfSize:14],
                        NSFontAttributeName, SSIconColor,
                        NSForegroundColorAttributeName, nil];
        NSString *title = @"Options";
        NSSize size = [title sizeWithAttributes:attrs];
        CGFloat x = NSMinX (r) + 8;
        NSBezierPath *v = [NSBezierPath bezierPath];

        [title drawAtPoint:NSMakePoint (x, floor (NSMidY (r) - size.height / 2))
            withAttributes:attrs];
        x += size.width + 8;
        [v moveToPoint:NSMakePoint (x, NSMidY (r) + 2)];
        [v lineToPoint:NSMakePoint (x + 4, NSMidY (r) - 2)];
        [v lineToPoint:NSMakePoint (x + 8, NSMidY (r) + 2)];
        [SSIconColor set];
        SSStroke (v, 1.4);
      }
      break;
    }
}

- (void)drawSeparatorAt:(CGFloat)x
{
  [SSRGB (255, 255, 255, 0.14) set];
  NSRectFill (NSMakeRect (floor (x), 12, 1, NSHeight ([self bounds]) - 24));
}

- (void)drawRect:(NSRect)rect
{
  NSRect b = NSInsetRect ([self bounds], 0.5, 0.5);
  NSBezierPath *bar = [NSBezierPath bezierPathWithRoundedRect:b
                                                      xRadius:12 yRadius:12];
  int i;

  [[NSColor clearColor] set];
  NSRectFillUsingOperation ([self bounds], NSCompositeCopy);
  [SSBarColor set];
  [bar fill];
  [SSBarEdge set];
  [bar setLineWidth:1.0];
  [bar stroke];
  [self drawSeparatorAt:NSMaxX ([self rectOfItem:SSItemClose])
        + SSSeparator / 2];
  if (!_recording)
    {
      [self drawSeparatorAt:NSMaxX ([self rectOfItem:3]) + SSSeparator / 2];
      [self drawSeparatorAt:NSMaxX ([self rectOfItem:5]) + SSSeparator / 2];
    }
  for (i = 0; i < SSItems; i++)
    [self drawItem:i];
}

- (void)setHover:(int)item
{
  if (item != _hover)
    {
      _hover = item;
      [self setNeedsDisplay:YES];
    }
}

- (void)mouseMoved:(NSEvent *)event
{
  [self setHover:[self itemAt:[self convertPoint:[event locationInWindow]
                                        fromView:nil]]];
}

- (void)mouseExited:(NSEvent *)event
{
  [self setHover:-1];
}

- (void)mouseDown:(NSEvent *)event
{
  int item = [self itemAt:[self convertPoint:[event locationInWindow]
                                    fromView:nil]];

  if (item == SSItemOptions)
    {
      [_delegate toolbar:self showOptions:event
                  inRect:[self rectOfItem:SSItemOptions]];
      return;
    }
  _pressed = item;
  [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)event
{
  int item = [self itemAt:[self convertPoint:[event locationInWindow]
                                    fromView:nil]];
  int pressed = _pressed;

  _pressed = -1;
  [self setNeedsDisplay:YES];
  if (item != pressed || item < 0)
    return;
  if (item == SSItemClose)
    [_delegate toolbarClose:self];
  else if (item == SSItemButton)
    [_delegate toolbarCapture:self];
  else if (item >= 1 && item <= 5)
    [_delegate toolbar:self choseTool:(SSTool) (item - 1)];
}

- (void)keyDown:(NSEvent *)event
{
  /* The toolbar may be key: Escape and Return as on the overlay. */
  NSString *chars = [event charactersIgnoringModifiers];
  unichar c = [chars length] > 0 ? [chars characterAtIndex:0] : 0;

  if (c == 0x1b)
    [_delegate toolbarClose:self];
  else if (c == '\r' || c == '\n' || c == 0x03)
    [_delegate toolbarCapture:self];
  else
    [super keyDown:event];
}

- (BOOL)acceptsFirstResponder
{
  return YES;
}

@end

NSWindow *
SSToolbarWindowCreate (id delegate, SSToolbarView **view)
{
  NSSize size = SSToolbarSize (NO);
  NSRect screen = [[NSScreen mainScreen] frame];
  NSRect frame = NSMakeRect (floor (NSMidX (screen) - size.width / 2),
                             floor (NSMinY (screen)
                                    + NSHeight (screen) * SSFromBottom),
                             size.width, size.height);
  SSPanel *window = [[SSPanel alloc] initWithContentRect:frame
                                               styleMask:NSBorderlessWindowMask
                                                 backing:NSBackingStoreBuffered
                                                   defer:NO];
  SSToolbarView *v =
    [[SSToolbarView alloc] initWithFrame:NSMakeRect (0, 0, size.width,
                                                     size.height)
                                delegate:delegate];

  [window setOpaque:NO];
  [window setBackgroundColor:[NSColor clearColor]];
  [window setHasShadow:YES];
  [window setLevel:SSToolbarLevel];
  [window setAcceptsMouseMovedEvents:YES];
  [window setReleasedWhenClosed:NO];
  [window setContentView:v];
  [window setInitialFirstResponder:v];
  *view = AUTORELEASE (v);
  return AUTORELEASE (window);
}
