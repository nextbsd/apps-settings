/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "DSArrangementView.h"
#import "DSDisplay.h"
#import <GNUstepBase/GNUstep.h>

#include <math.h>

/* View points. */
#define DSPadding 16.0
#define DSStackStep 6.0		/* each mirror behind the one it shows */
#define DSSnapDistance 8.0	/* edges this close line up */
#define DSDragSlop 3.0

/* The most view points per desktop point, so a lone display isn't
   drawn huge. */
#define DSMaxScale 0.1

@interface DSArrangementView (Private)
- (NSArray *)placedDisplays;
- (DSDisplay *)displayWithID:(unsigned)displayID;
- (NSRect)viewRectFor:(NSRect)desktop;
- (NSRect)menuBarRectIn:(NSRect)rect;
- (DSDisplay *)placedDisplayAt:(NSPoint)p;
- (void)drawDisplay:(DSDisplay *)display
             inRect:(NSRect)rect
              front:(BOOL)front;
@end

@implementation DSArrangementView

- (void)dealloc
{
  RELEASE (_displays);
  [super dealloc];
}

- (BOOL)isFlipped
{
  return YES;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event
{
  return YES;
}

- (void)setDelegate:(id<DSArrangementViewDelegate>)delegate
{
  _delegate = delegate;
}

- (BOOL)isDragging
{
  return _dragged != 0 || _draggingMenuBar;
}

- (void)setDisplays:(NSArray *)displays selected:(unsigned)displayID
{
  NSArray *placed;
  NSSize size = [self bounds].size;
  NSUInteger i;

  ASSIGN (_displays, displays);
  _selected = displayID;
  _dragged = 0;
  _draggingMenuBar = NO;

  /* Fit the displays, with room to drag around them. */
  placed = [self placedDisplays];
  _desktop = NSZeroRect;
  for (i = 0; i < [placed count]; i++)
    {
      NSRect f = [[placed objectAtIndex:i] frame];
      _desktop = i == 0 ? f : NSUnionRect (_desktop, f);
    }
  if (NSWidth (_desktop) <= 0 || NSHeight (_desktop) <= 0)
    {
      _scale = DSMaxScale;
      _offset = NSMakePoint (size.width / 2, size.height / 2);
    }
  else
    {
      _scale = MIN ((size.width - 2 * DSPadding) / NSWidth (_desktop),
                    (size.height - 2 * DSPadding) / NSHeight (_desktop));
      _scale = MIN (_scale * 0.85, DSMaxScale);
      _offset = NSMakePoint (
          floor ((size.width - NSWidth (_desktop) * _scale) / 2),
          floor ((size.height - NSHeight (_desktop) * _scale) / 2));
    }
  [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirty
{
  NSArray *placed = [self placedDisplays];
  NSUInteger i, j;

  [[NSColor controlBackgroundColor] set];
  NSRectFill ([self bounds]);
  [[NSColor controlShadowColor] set];
  NSFrameRect ([self bounds]);

  for (i = 0; i < [placed count]; i++)
    {
      DSDisplay *display = [placed objectAtIndex:i];
      NSRect rect = [self viewRectFor:[display frame]];
      NSMutableArray *mirrors = [NSMutableArray array];

      if ([display displayID] == _dragged)
        continue;			/* drawn last, on top */
      for (j = 0; j < [_displays count]; j++)
        {
          DSDisplay *other = [_displays objectAtIndex:j];
          if ([other isMirror] && [other mirrorOf] == [display displayID])
            [mirrors addObject:other];
        }
      /* Back to front: the last mirror furthest back. */
      for (j = [mirrors count]; j > 0; j--)
        [self drawDisplay:[mirrors objectAtIndex:j - 1]
                   inRect:NSOffsetRect (rect, j * DSStackStep, j * DSStackStep)
                    front:NO];
      [self drawDisplay:display inRect:rect front:YES];
    }

  /* The selected display's outline over its neighbours. */
  for (i = 0; i < [placed count] && _dragged == 0; i++)
    {
      DSDisplay *display = [placed objectAtIndex:i];
      DSDisplay *selected = [self displayWithID:_selected];

      if (selected != nil && [selected isMirror])
        selected = [self displayWithID:[selected mirrorOf]];
      if (display == selected)
        {
          [[NSColor selectedControlColor] set];
          NSFrameRectWithWidth (NSInsetRect ([self viewRectFor:[display frame]],
                                             -3, -3), 3);
        }
    }

  if (_dragged != 0)
    {
      DSDisplay *display = [self displayWithID:_dragged];
      if (display != nil)
        {
          [self drawDisplay:display inRect:_dragRect front:YES];
          [[NSColor selectedControlColor] set];
          NSFrameRectWithWidth (NSInsetRect (_dragRect, -3, -3), 3);
        }
    }

  if (_draggingMenuBar)
    {
      /* The strip follows the pointer; the display under it is where
         it goes. */
      DSDisplay *target = [self placedDisplayAt:_pointer];
      NSRect under = target != nil
        ? [self viewRectFor:[target frame]] : NSZeroRect;
      NSRect strip = [self menuBarRectIn:(target != nil ? under
                         : NSMakeRect (_pointer.x - 40, _pointer.y, 80, 50))];

      if (target != nil)
        {
          [[NSColor selectedControlColor] set];
          NSFrameRectWithWidth (NSInsetRect (under, -2, -2), 2);
        }
      strip.origin.x = _pointer.x - NSWidth (strip) / 2;
      strip.origin.y = _pointer.y - NSHeight (strip) / 2;
      [[NSColor whiteColor] set];
      NSRectFill (strip);
      [[NSColor darkGrayColor] set];
      NSFrameRect (strip);
    }
}

- (void)mouseDown:(NSEvent *)event
{
  NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
  DSDisplay *display = [self placedDisplayAt:p];
  NSRect rect;

  _moved = NO;
  _pointer = p;
  if (display == nil)
    return;
  rect = [self viewRectFor:[display frame]];
  if ([display isMain] && [[self placedDisplays] count] > 1
      && NSPointInRect (p, NSInsetRect ([self menuBarRectIn:rect], 0, -3)))
    {
      _draggingMenuBar = YES;
      [self setNeedsDisplay:YES];
      return;
    }
  /* Select it now; the controller hears on mouse up, so the window
     isn't rebuilt under the drag. */
  _selected = [display displayID];
  if ([[self placedDisplays] count] > 1)
    {
      _dragged = [display displayID];
      _grab = NSMakePoint (p.x - rect.origin.x, p.y - rect.origin.y);
      _dragRect = rect;
    }
  [self setNeedsDisplay:YES];
}

- (void)mouseDragged:(NSEvent *)event
{
  NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
  DSDisplay *display;
  NSMutableArray *others;
  NSArray *placed;
  NSRect desktop;
  NSPoint origin;
  NSUInteger i;

  if (fabs (p.x - _pointer.x) > DSDragSlop || fabs (p.y - _pointer.y) > DSDragSlop)
    _moved = YES;
  if (_draggingMenuBar)
    {
      _pointer = p;
      [self setNeedsDisplay:YES];
      return;
    }
  if (_dragged == 0 || !_moved
      || (display = [self displayWithID:_dragged]) == nil)
    return;

  /* Where the pointer puts it, in desktop points, snapped against the
     others as WindowServer will place it. */
  desktop = [display frame];
  desktop.origin.x = (p.x - _grab.x - _offset.x) / _scale + NSMinX (_desktop);
  desktop.origin.y = (p.y - _grab.y - _offset.y) / _scale + NSMinY (_desktop);
  others = [NSMutableArray array];
  placed = [self placedDisplays];
  for (i = 0; i < [placed count]; i++)
    if ([[placed objectAtIndex:i] displayID] != _dragged)
      [others addObject:[NSValue valueWithRect:
                                   [[placed objectAtIndex:i] frame]]];
  origin = DSSnapOrigin (desktop, others, DSSnapDistance / _scale);
  desktop.origin = origin;
  _dragRect = [self viewRectFor:desktop];
  [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)event
{
  NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
  unsigned dragged = _dragged;
  BOOL menuBar = _draggingMenuBar;
  BOOL moved = _moved;

  _dragged = 0;
  _draggingMenuBar = NO;
  [self setNeedsDisplay:YES];

  if (menuBar)
    {
      DSDisplay *target = [self placedDisplayAt:p];
      if (moved && target != nil && ![target isMain])
        [_delegate arrangementView:self makeMainDisplay:[target displayID]];
      return;
    }
  if (dragged != 0 && moved)
    {
      NSPoint origin = NSMakePoint (
          floor ((NSMinX (_dragRect) - _offset.x) / _scale + NSMinX (_desktop) + 0.5),
          floor ((NSMinY (_dragRect) - _offset.y) / _scale + NSMinY (_desktop) + 0.5));
      DSDisplay *display = [self displayWithID:dragged];

      if (display != nil
          && !NSEqualPoints (origin, [display frame].origin))
        {
          [_delegate arrangementView:self moveDisplay:dragged toOrigin:origin];
          return;
        }
    }
  if (_selected != 0)
    [_delegate arrangementView:self didSelectDisplay:_selected];
}

@end

@implementation DSArrangementView (Private)

/* The displays with their own part of the desktop. */
- (NSArray *)placedDisplays
{
  NSMutableArray *placed = [NSMutableArray array];
  NSEnumerator *e = [_displays objectEnumerator];
  DSDisplay *display;

  while ((display = [e nextObject]) != nil)
    if (![display isMirror])
      [placed addObject:display];
  return placed;
}

- (DSDisplay *)displayWithID:(unsigned)displayID
{
  NSEnumerator *e = [_displays objectEnumerator];
  DSDisplay *display;

  while ((display = [e nextObject]) != nil)
    if ([display displayID] == displayID)
      return display;
  return nil;
}

- (NSRect)viewRectFor:(NSRect)desktop
{
  return NSMakeRect (
      floor (_offset.x + (NSMinX (desktop) - NSMinX (_desktop)) * _scale),
      floor (_offset.y + (NSMinY (desktop) - NSMinY (_desktop)) * _scale),
      floor (NSWidth (desktop) * _scale), floor (NSHeight (desktop) * _scale));
}

- (NSRect)menuBarRectIn:(NSRect)rect
{
  CGFloat h = MAX (4.0, floor (NSHeight (rect) * 0.07));

  return NSMakeRect (NSMinX (rect) + 1, NSMinY (rect) + 1,
                     NSWidth (rect) - 2, h);
}

- (DSDisplay *)placedDisplayAt:(NSPoint)p
{
  NSArray *placed = [self placedDisplays];
  NSUInteger i;

  for (i = 0; i < [placed count]; i++)
    {
      DSDisplay *display = [placed objectAtIndex:i];
      if (NSPointInRect (p, [self viewRectFor:[display frame]]))
        return display;
    }
  return nil;
}

- (void)drawDisplay:(DSDisplay *)display
             inRect:(NSRect)rect
              front:(BOOL)front
{
  NSColor *desktop = [NSColor colorWithCalibratedRed:0.22
                                               green:0.42
                                                blue:0.72
                                               alpha:1.0];

  [(front ? desktop : [desktop shadowWithLevel:0.3]) set];
  NSRectFill (rect);
  [[NSColor blackColor] set];
  NSFrameRect (rect);
  if (!front)
    return;

  if ([display isMain] && !_draggingMenuBar)
    {
      NSRect strip = [self menuBarRectIn:rect];
      [[NSColor whiteColor] set];
      NSRectFill (strip);
    }

  /* Its name, if there's room. */
  NSMutableParagraphStyle *style = AUTORELEASE ([[NSParagraphStyle
                                                  defaultParagraphStyle]
                                                 mutableCopy]);
  [style setAlignment:NSCenterTextAlignment];
  NSDictionary *attrs = [NSDictionary dictionaryWithObjectsAndKeys:
      [NSFont systemFontOfSize:[NSFont smallSystemFontSize]], NSFontAttributeName,
      [NSColor whiteColor], NSForegroundColorAttributeName,
      style, NSParagraphStyleAttributeName, nil];
  NSString *name = [display name];
  NSSize size = [name sizeWithAttributes:attrs];
  if (size.width < NSWidth (rect) - 6 && size.height < NSHeight (rect) - 12)
    [name drawInRect:NSMakeRect (NSMinX (rect) + 3,
                                 floor (NSMidY (rect) - size.height / 2),
                                 NSWidth (rect) - 6, size.height)
      withAttributes:attrs];
}

@end
