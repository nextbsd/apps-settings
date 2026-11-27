/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "SSThumbnail.h"
#import <GNUstepBase/GNUstep.h>

#define SSCardWidth 252.0
#define SSCardHeight 200.0
#define SSPictureHeight 136.0
#define SSMargin 16.0		/* from the screen's usable corner */
#define SSShowSeconds 5.0
#define SSSlideSteps 10
#define SSSlideSeconds 0.22

@interface SSThumbnail (Private)
- (void)cardClicked;
- (void)cardDragged;
- (void)pointerInside:(BOOL)inside;
@end

/* The card: the picture on a band, then its name and what to do. */
@interface SSCardView : NSView
{
  SSThumbnail *_owner;
  NSImage *_image;
  NSString *_title;
  NSString *_detail;
  NSString *_path;
  BOOL _dragged;
}
- (id)initWithFrame:(NSRect)frame owner:(SSThumbnail *)owner
              image:(NSImage *)image path:(NSString *)path
              title:(NSString *)title detail:(NSString *)detail;
@end

@implementation SSCardView

- (id)initWithFrame:(NSRect)frame owner:(SSThumbnail *)owner
              image:(NSImage *)image path:(NSString *)path
              title:(NSString *)title detail:(NSString *)detail
{
  if ((self = [super initWithFrame:frame]) == nil)
    return nil;
  _owner = owner;
  ASSIGN (_image, image);
  ASSIGN (_path, path);
  ASSIGN (_title, title);
  ASSIGN (_detail, detail);
  return self;
}

- (void)dealloc
{
  RELEASE (_image);
  RELEASE (_path);
  RELEASE (_title);
  RELEASE (_detail);
  [super dealloc];
}

- (void)viewDidMoveToWindow
{
  [self addTrackingRect:[self bounds] owner:self userData:NULL
           assumeInside:NO];
}

- (BOOL)isOpaque
{
  return NO;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event
{
  return YES;
}

- (NSRect)pictureBand
{
  NSRect b = [self bounds];

  return NSMakeRect (1, NSMaxY (b) - 1 - SSPictureHeight, NSWidth (b) - 2,
                     SSPictureHeight);
}

- (NSRect)pictureRect
{
  NSRect band = NSInsetRect ([self pictureBand], 14, 12);
  NSSize s = [_image size];
  CGFloat k;

  if (s.width <= 0 || s.height <= 0)
    return band;
  k = MIN (NSWidth (band) / s.width, NSHeight (band) / s.height);
  return NSIntegralRect (NSMakeRect (NSMidX (band) - s.width * k / 2,
                                     NSMidY (band) - s.height * k / 2,
                                     s.width * k, s.height * k));
}

- (void)drawRect:(NSRect)rect
{
  NSRect b = NSInsetRect ([self bounds], 0.5, 0.5);
  NSBezierPath *card = [NSBezierPath bezierPathWithRoundedRect:b
                                                       xRadius:10 yRadius:10];
  NSColor *back = [[NSColor windowBackgroundColor]
                    colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
  BOOL dark = back != nil && [back brightnessComponent] < 0.5;
  NSColor *text = dark ? [NSColor colorWithCalibratedWhite:0.95 alpha:1]
    : [NSColor colorWithCalibratedWhite:0.08 alpha:1];
  NSColor *dim = dark ? [NSColor colorWithCalibratedWhite:0.68 alpha:1]
    : [NSColor colorWithCalibratedWhite:0.36 alpha:1];
  NSMutableParagraphStyle *wrap = AUTORELEASE ([[NSParagraphStyle
                                                  defaultParagraphStyle]
                                                 mutableCopy]);
  NSMutableParagraphStyle *one = AUTORELEASE ([[NSParagraphStyle
                                                 defaultParagraphStyle]
                                                mutableCopy]);
  NSRect pic = [self pictureRect];

  [[NSColor clearColor] set];
  NSRectFillUsingOperation ([self bounds], NSCompositeCopy);
  [(dark ? [NSColor colorWithCalibratedWhite:0.15 alpha:0.98]
    : [NSColor colorWithCalibratedWhite:0.985 alpha:0.98]) set];
  [card fill];

  /* The band behind the picture. */
  [NSGraphicsContext saveGraphicsState];
  [card addClip];
  [(dark ? [NSColor colorWithCalibratedWhite:0.24 alpha:1]
    : [NSColor colorWithCalibratedRed:0.70 green:0.75 blue:0.81 alpha:1]) set];
  NSRectFill ([self pictureBand]);
  [NSGraphicsContext restoreGraphicsState];

  [[NSColor colorWithCalibratedWhite:0 alpha:0.18] set];
  NSRectFill (NSOffsetRect (pic, 0, -2));
  [_image drawInRect:pic fromRect:NSZeroRect
           operation:NSCompositeSourceOver fraction:1.0];

  [[NSColor colorWithCalibratedWhite:(dark ? 1 : 0) alpha:0.16] set];
  [card setLineWidth:1.0];
  [card stroke];

  [wrap setLineBreakMode:NSLineBreakByWordWrapping];
  [one setLineBreakMode:NSLineBreakByTruncatingMiddle];
  [_title drawInRect:NSMakeRect (12, NSMinY ([self pictureBand]) - 26,
                                 NSWidth (b) - 24, 18)
      withAttributes:[NSDictionary dictionaryWithObjectsAndKeys:
                                     [NSFont systemFontOfSize:12],
                                   NSFontAttributeName, text,
                                   NSForegroundColorAttributeName, one,
                                   NSParagraphStyleAttributeName, nil]];
  [_detail drawInRect:NSMakeRect (12, 6, NSWidth (b) - 24,
                                  NSMinY ([self pictureBand]) - 34)
       withAttributes:[NSDictionary dictionaryWithObjectsAndKeys:
                                      [NSFont systemFontOfSize:11],
                                    NSFontAttributeName, dim,
                                    NSForegroundColorAttributeName, wrap,
                                    NSParagraphStyleAttributeName, nil]];
}

- (void)mouseEntered:(NSEvent *)event
{
  [_owner pointerInside:YES];
}

- (void)mouseExited:(NSEvent *)event
{
  [_owner pointerInside:NO];
}

- (void)mouseDown:(NSEvent *)event
{
  _dragged = NO;
}

- (void)mouseDragged:(NSEvent *)event
{
  if (_dragged || _path == nil)
    return;
  _dragged = YES;
  /* The file, as a Workspace icon carries it: drop it into a document,
     a folder or a mail. */
  [self dragFile:_path fromRect:[self pictureRect] slideBack:YES event:event];
  [_owner cardDragged];
}

- (void)mouseUp:(NSEvent *)event
{
  if (!_dragged)
    [_owner cardClicked];
}

@end

@implementation SSThumbnail

- (void)dealloc
{
  [_timer invalidate];
  [_slide invalidate];
  [_window orderOut:nil];
  RELEASE (_window);
  RELEASE (_path);
  [super dealloc];
}

- (void)stopTimers
{
  [_timer invalidate];
  _timer = nil;
  [_slide invalidate];
  _slide = nil;
}

- (void)startTimer
{
  [_timer invalidate];
  _timer = [NSTimer scheduledTimerWithTimeInterval:SSShowSeconds
                                            target:self
                                          selector:@selector (expired:)
                                          userInfo:nil
                                           repeats:NO];
}

- (void)slideStep:(NSTimer *)timer
{
  NSRect f = _shown;
  CGFloat t;

  _step++;
  t = (CGFloat) _step / SSSlideSteps;
  /* ease out */
  t = 1 - (1 - t) * (1 - t);
  f.origin.x = floor (_from + (_to - _from) * t);
  [_window setFrameOrigin:f.origin];
  if (_step < SSSlideSteps)
    return;
  [_slide invalidate];
  _slide = nil;
  if (_leaving)
    {
      [_window orderOut:nil];
      DESTROY (_window);
      DESTROY (_path);
    }
}

- (void)slideFrom:(CGFloat)from to:(CGFloat)to leaving:(BOOL)leaving
{
  [_slide invalidate];
  _from = from;
  _to = to;
  _step = 0;
  _leaving = leaving;
  [_window setFrameOrigin:NSMakePoint (from, NSMinY (_shown))];
  _slide = [NSTimer scheduledTimerWithTimeInterval:SSSlideSeconds
                                                    / SSSlideSteps
                                            target:self
                                          selector:@selector (slideStep:)
                                          userInfo:nil
                                           repeats:YES];
}

- (void)showImage:(NSImage *)image path:(NSString *)path
            title:(NSString *)title detail:(NSString *)detail
{
  NSScreen *screen = [NSScreen mainScreen];
  NSRect usable = [screen visibleFrame], full = [screen frame];
  SSCardView *view;

  [self stopTimers];
  [_window orderOut:nil];
  DESTROY (_window);
  ASSIGN (_path, path);

  _shown = NSMakeRect (NSMaxX (usable) - SSMargin - SSCardWidth,
                       NSMinY (usable) + SSMargin, SSCardWidth, SSCardHeight);
  _window = [[NSWindow alloc] initWithContentRect:_shown
                                        styleMask:NSBorderlessWindowMask
                                          backing:NSBackingStoreBuffered
                                            defer:NO];
  [_window setOpaque:NO];
  [_window setBackgroundColor:[NSColor clearColor]];
  [_window setHasShadow:YES];
  [_window setLevel:NSStatusWindowLevel];
  [_window setReleasedWhenClosed:NO];
  view = [[SSCardView alloc] initWithFrame:NSMakeRect (0, 0, SSCardWidth,
                                                       SSCardHeight)
                                     owner:self image:image path:path
                                     title:title detail:detail];
  [_window setContentView:view];
  RELEASE (view);
  [_window orderFrontRegardless];
  [self slideFrom:NSMaxX (full) to:NSMinX (_shown) leaving:NO];
  [self startTimer];
}

- (void)dismiss
{
  [self stopTimers];
  if (_window == nil)
    return;
  [self slideFrom:[_window frame].origin.x
               to:NSMaxX ([[NSScreen mainScreen] frame]) + 4
          leaving:YES];
}

- (void)expired:(NSTimer *)timer
{
  _timer = nil;
  [self dismiss];
}

- (void)pointerInside:(BOOL)inside
{
  if (_window == nil || _leaving)
    return;
  if (inside)
    {
      [_timer invalidate];
      _timer = nil;
    }
  else
    [self startTimer];
}

/* After the card's own mouse-up or drag: its window goes once that
   event is done with it. */
- (void)closeCard
{
  [self stopTimers];
  [_window orderOut:nil];
  AUTORELEASE (_window);
  _window = nil;
}

- (void)cardClicked
{
  NSString *path = AUTORELEASE (RETAIN (_path));

  [self closeCard];
  DESTROY (_path);
  if (path != nil)
    [[NSWorkspace sharedWorkspace] openFile:path];
}

- (void)cardDragged
{
  [self closeCard];
  DESTROY (_path);
}

@end
