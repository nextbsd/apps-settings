/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "SSOverlay.h"
#import <GNUstepBase/GNUstep.h>

#define SSDim 0.38		/* black over what isn't taken */
#define SSScreenDim 0.18	/* screen mode: the whole screen */
#define SSHandleRadius 5.0
#define SSHandleGrab 9.0	/* how near a handle a press takes it */
#define SSMinimumSide 4.0

@implementation SSPanel
- (BOOL)canBecomeKeyWindow
{
  return YES;
}

- (BOOL)canBecomeMainWindow
{
  return NO;
}
@end

/* The eight handles: corners and edges' middles, counterclockwise from
   the bottom left. */
static NSPoint
SSHandlePoint (NSRect r, int i)
{
  CGFloat xs[3] = { NSMinX (r), NSMidX (r), NSMaxX (r) };
  CGFloat ys[3] = { NSMinY (r), NSMidY (r), NSMaxY (r) };
  static const int hx[8] = { 0, 1, 2, 2, 2, 1, 0, 0 };
  static const int hy[8] = { 0, 0, 0, 1, 2, 2, 2, 1 };

  return NSMakePoint (xs[hx[i]], ys[hy[i]]);
}

@implementation SSOverlayView

- (id)initWithFrame:(NSRect)frame delegate:(id)delegate
{
  if ((self = [super initWithFrame:frame]) == nil)
    return nil;
  _delegate = delegate;
  _mode = SSOverlaySelection;
  _handle = -1;
  _highlightWindow = 0;
  return self;
}

- (void)dealloc
{
  RELEASE (_windows);
  [super dealloc];
}

- (BOOL)isOpaque
{
  return NO;
}

- (BOOL)acceptsFirstResponder
{
  return YES;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event
{
  return YES;
}

- (void)setMode:(SSOverlayMode)mode quick:(BOOL)quick
{
  _mode = mode;
  _quick = quick;
  _highlight = NSZeroRect;
  _highlightWindow = 0;
  if (mode == SSOverlayWindow)
    [self updateHighlight:[[self window] mouseLocationOutsideOfEventStream]];
  [[self window] invalidateCursorRectsForView:self];
  [self setNeedsDisplay:YES];
}

- (SSOverlayMode)mode
{
  return _mode;
}

- (BOOL)isQuick
{
  return _quick;
}

- (void)setSelection:(NSRect)selection
{
  _selection = NSIntegralRect (selection);
  [self setNeedsDisplay:YES];
}

- (NSRect)selection
{
  return _selection;
}

- (void)setWindows:(NSArray *)rects ids:(NSArray *)ids
{
  NSMutableArray *list = [NSMutableArray array];
  NSUInteger i;

  for (i = 0; i < [rects count] && i < [ids count]; i++)
    [list addObject:[NSArray arrayWithObjects:[rects objectAtIndex:i],
                             [ids objectAtIndex:i], nil]];
  ASSIGN (_windows, list);
}

- (uint32_t)chosenWindow
{
  return _highlightWindow;
}

- (NSRect)chosenWindowRect
{
  return _highlight;
}

- (void)resetCursorRects
{
  [self addCursorRect:[self bounds]
               cursor:(_mode == SSOverlayScreen ? [NSCursor arrowCursor]
                       : _mode == SSOverlayWindow
                       ? [NSCursor pointingHandCursor]
                       : [NSCursor crosshairCursor])];
}

/* ---- drawing ---- */

- (void)drawSizeLabel
{
  NSString *text = [NSString stringWithFormat:@"%d × %d",
                             (int) NSWidth (_selection),
                             (int) NSHeight (_selection)];
  NSDictionary *attrs =
    [NSDictionary dictionaryWithObjectsAndKeys:
                    [NSFont boldSystemFontOfSize:13], NSFontAttributeName,
                  [NSColor whiteColor], NSForegroundColorAttributeName,
                  nil];
  NSSize size = [text sizeWithAttributes:attrs];
  NSRect plate = NSMakeRect (floor (NSMidX (_selection) - size.width / 2 - 8),
                             floor (NSMidY (_selection) - size.height / 2 - 4),
                             ceil (size.width + 16), ceil (size.height + 8));

  if (NSWidth (_selection) < NSWidth (plate) + 8
      || NSHeight (_selection) < NSHeight (plate) + 8)
    {
      /* Too small to hold it: below it. */
      plate.origin.y = NSMinY (_selection) - NSHeight (plate) - 10;
    }
  [[NSColor colorWithCalibratedWhite:0.08 alpha:0.85] set];
  [[NSBezierPath bezierPathWithRoundedRect:plate xRadius:6 yRadius:6] fill];
  [text drawAtPoint:NSMakePoint (NSMinX (plate) + 8, NSMinY (plate) + 4)
     withAttributes:attrs];
}

- (void)drawSelection
{
  NSBezierPath *border;
  CGFloat dash[2] = { 6.0, 4.0 };
  int i;

  [[NSColor colorWithCalibratedWhite:0.0 alpha:SSDim] set];
  NSRectFill ([self bounds]);
  if (NSIsEmptyRect (_selection))
    return;
  [[NSColor clearColor] set];
  NSRectFillUsingOperation (_selection, NSCompositeCopy);

  border = [NSBezierPath bezierPathWithRect:NSInsetRect (_selection, 0.5, 0.5)];
  [border setLineWidth:1.0];
  [[NSColor colorWithCalibratedWhite:0.0 alpha:0.5] set];
  [border stroke];
  [border setLineDash:dash count:2 phase:0.0];
  [[NSColor whiteColor] set];
  [border stroke];
  if (!_quick || _handle < 0)
    for (i = 0; i < 8; i++)
      {
        NSPoint p = SSHandlePoint (_selection, i);
        NSBezierPath *dot = [NSBezierPath bezierPathWithOvalInRect:
                                            NSMakeRect (p.x - SSHandleRadius,
                                                        p.y - SSHandleRadius,
                                                        2 * SSHandleRadius,
                                                        2 * SSHandleRadius)];
        [[NSColor whiteColor] set];
        [dot fill];
        [[NSColor colorWithCalibratedWhite:0.35 alpha:1.0] set];
        [dot setLineWidth:1.0];
        [dot stroke];
      }
  [self drawSizeLabel];
}

- (void)drawRect:(NSRect)rect
{
  switch (_mode)
    {
    case SSOverlayScreen:
      [[NSColor clearColor] set];
      NSRectFillUsingOperation ([self bounds], NSCompositeCopy);
      [[NSColor colorWithCalibratedWhite:0.0 alpha:SSScreenDim] set];
      NSRectFill ([self bounds]);
      break;
    case SSOverlayWindow:
      [[NSColor clearColor] set];
      NSRectFillUsingOperation ([self bounds], NSCompositeCopy);
      [[NSColor colorWithCalibratedWhite:0.0 alpha:SSScreenDim] set];
      NSRectFill ([self bounds]);
      if (!NSIsEmptyRect (_highlight))
        {
          [[NSColor clearColor] set];
          NSRectFillUsingOperation (_highlight, NSCompositeCopy);
          [[NSColor colorWithCalibratedRed:0.25 green:0.55 blue:1.0
                                     alpha:0.28] set];
          NSRectFillUsingOperation (_highlight, NSCompositeSourceOver);
        }
      break;
    case SSOverlaySelection:
      [[NSColor clearColor] set];
      NSRectFillUsingOperation ([self bounds], NSCompositeCopy);
      [self drawSelection];
      break;
    }
}

/* ---- the pointer ---- */

- (void)updateHighlight:(NSPoint)p
{
  NSEnumerator *e = [_windows objectEnumerator];
  NSArray *item;
  NSRect found = NSZeroRect;
  uint32_t window = 0;

  while ((item = [e nextObject]) != nil)
    {
      NSRect r = [[item objectAtIndex:0] rectValue];

      if (NSPointInRect (p, r))
        {
          found = r;
          window = [[item objectAtIndex:1] unsignedIntValue];
          break;
        }
    }
  if (window != _highlightWindow || !NSEqualRects (found, _highlight))
    {
      _highlight = found;
      _highlightWindow = window;
      [self setNeedsDisplay:YES];
    }
}

- (void)mouseMoved:(NSEvent *)event
{
  if (_mode == SSOverlayWindow)
    [self updateHighlight:[self convertPoint:[event locationInWindow]
                                    fromView:nil]];
}

- (int)handleAt:(NSPoint)p
{
  int i;

  if (NSIsEmptyRect (_selection))
    return 9;
  if (!_quick)
    for (i = 0; i < 8; i++)
      {
        NSPoint h = SSHandlePoint (_selection, i);

        if (fabs (h.x - p.x) <= SSHandleGrab && fabs (h.y - p.y) <= SSHandleGrab)
          return i;
      }
  if (!_quick && NSPointInRect (p, _selection))
    return 8;
  return 9;
}

- (void)mouseDown:(NSEvent *)event
{
  NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];

  if (_mode == SSOverlayScreen)
    {
      [_delegate overlayDidChoose:self];
      return;
    }
  if (_mode == SSOverlayWindow)
    {
      [self updateHighlight:p];
      if (_highlightWindow != 0)
        [_delegate overlayDidChoose:self];
      return;
    }
  _handle = [self handleAt:p];
  _anchor = p;
  _startSelection = _selection;
  if (_handle == 9)
    [self setSelection:NSMakeRect (p.x, p.y, 0, 0)];
}

- (void)mouseDragged:(NSEvent *)event
{
  NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
  NSRect b = [self bounds], r = _startSelection;
  CGFloat dx = p.x - _anchor.x, dy = p.y - _anchor.y;
  CGFloat x0 = NSMinX (r), y0 = NSMinY (r), x1 = NSMaxX (r), y1 = NSMaxY (r);

  if (_mode != SSOverlaySelection || _handle < 0)
    return;
  p.x = MAX (NSMinX (b), MIN (NSMaxX (b), p.x));
  p.y = MAX (NSMinY (b), MIN (NSMaxY (b), p.y));
  switch (_handle)
    {
    case 9:			/* a new one, from the press */
      x0 = MIN (_anchor.x, p.x);
      x1 = MAX (_anchor.x, p.x);
      y0 = MIN (_anchor.y, p.y);
      y1 = MAX (_anchor.y, p.y);
      break;
    case 8:			/* moved, kept on the screen */
      dx = MAX (NSMinX (b) - x0, MIN (NSMaxX (b) - x1, dx));
      dy = MAX (NSMinY (b) - y0, MIN (NSMaxY (b) - y1, dy));
      x0 += dx;
      x1 += dx;
      y0 += dy;
      y1 += dy;
      break;
    default:
      if (_handle == 0 || _handle == 6 || _handle == 7)
        x0 = MIN (p.x, x1 - SSMinimumSide);
      if (_handle == 2 || _handle == 3 || _handle == 4)
        x1 = MAX (p.x, x0 + SSMinimumSide);
      if (_handle == 0 || _handle == 1 || _handle == 2)
        y0 = MIN (p.y, y1 - SSMinimumSide);
      if (_handle == 4 || _handle == 5 || _handle == 6)
        y1 = MAX (p.y, y0 + SSMinimumSide);
      break;
    }
  [self setSelection:NSMakeRect (x0, y0, x1 - x0, y1 - y0)];
}

- (void)mouseUp:(NSEvent *)event
{
  int handle = _handle;

  _handle = -1;
  if (_mode != SSOverlaySelection || handle < 0)
    return;
  if (NSWidth (_selection) < SSMinimumSide
      || NSHeight (_selection) < SSMinimumSide)
    {
      /* A click, not a drag: keep what was there. */
      [self setSelection:_startSelection];
      if (_quick)
        [self setSelection:NSZeroRect];
      return;
    }
  [self setNeedsDisplay:YES];
  if (_quick)
    [_delegate overlayDidChoose:self];
}

- (void)keyDown:(NSEvent *)event
{
  NSString *chars = [event charactersIgnoringModifiers];
  unichar c = [chars length] > 0 ? [chars characterAtIndex:0] : 0;

  if (c == 0x1b)
    [_delegate overlayDidCancel:self];
  else if (c == ' ' && _quick && _handle < 0)
    [_delegate overlayDidSwapMode:self];
  else if (c == '\r' || c == '\n' || c == 0x03)
    [_delegate overlayDidConfirm:self];
  else
    [super keyDown:event];
}

@end

SSPanel *
SSOverlayWindowCreate (id delegate, SSOverlayView **view)
{
  NSRect frame = [[NSScreen mainScreen] frame];
  SSPanel *window = [[SSPanel alloc] initWithContentRect:frame
                                               styleMask:NSBorderlessWindowMask
                                                 backing:NSBackingStoreBuffered
                                                   defer:NO];
  SSOverlayView *v =
    [[SSOverlayView alloc] initWithFrame:NSMakeRect (0, 0, NSWidth (frame),
                                                     NSHeight (frame))
                                delegate:delegate];

  [window setOpaque:NO];
  [window setBackgroundColor:[NSColor clearColor]];
  [window setHasShadow:NO];
  [window setLevel:SSOverlayLevel];
  [window setAcceptsMouseMovedEvents:YES];
  [window setReleasedWhenClosed:NO];
  [window setContentView:v];
  [window setInitialFirstResponder:v];
  *view = AUTORELEASE (v);
  return AUTORELEASE (window);
}
