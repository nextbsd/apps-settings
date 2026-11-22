/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "WCStripView.h"
#import <GNUstepBase/GNUstep.h>

/* Layout, in points. */
#define WCStripMargin 10.0
#define WCStripGap 8.0

@implementation WCStripView

- (id)initWithFrame:(NSRect)frame
{
  if ((self = [super initWithFrame:frame]) != nil)
    {
      items = [[NSArray alloc] init];
      selected = -1;
    }
  return self;
}

- (void)dealloc
{
  RELEASE (items);
  [super dealloc];
}

/* A thumbnail is 4:3, as tall as the strip lets it be. There's one
   row, so the view needn't be flipped. */
- (NSSize)cellSize
{
  NSScrollView *scroll = [self enclosingScrollView];
  CGFloat height = (scroll != nil ? [scroll contentSize].height
                    : NSHeight ([self bounds])) - 2 * WCStripMargin;

  return NSMakeSize (floor (height * 4 / 3), height);
}

- (NSRect)rectOfItem:(NSUInteger)i
{
  NSSize cell = [self cellSize];

  return NSMakeRect (WCStripMargin + i * (cell.width + WCStripGap),
                     WCStripMargin, cell.width, cell.height);
}

/* As wide as the items, and at least as wide as what shows it. */
- (void)fitWidth
{
  NSScrollView *scroll = [self enclosingScrollView];
  NSSize visible = scroll != nil ? [scroll contentSize] : [self frame].size;
  NSSize cell = [self cellSize];
  CGFloat width = 2 * WCStripMargin + [items count] * (cell.width + WCStripGap);

  [self setFrameSize:NSMakeSize (MAX (width, visible.width), visible.height)];
}

- (void)setItems:(NSArray *)newItems
{
  NSString *path = RETAIN ([self selectedPath]);

  ASSIGNCOPY (items, newItems);
  selected = -1;
  [self selectPath:path];
  RELEASE (path);
  [self fitWidth];
  [self setNeedsDisplay:YES];
}

- (NSString *)selectedPath
{
  if (selected < 0 || (NSUInteger) selected >= [items count])
    return nil;
  return [[items objectAtIndex:selected] objectForKey:WCStripPath];
}

- (void)selectPath:(NSString *)path
{
  NSUInteger i;

  selected = -1;
  for (i = 0; path != nil && i < [items count]; i++)
    if ([[[items objectAtIndex:i] objectForKey:WCStripPath]
          isEqualToString:path])
      {
        selected = (NSInteger) i;
        [self scrollRectToVisible:[self rectOfItem:i]];
        break;
      }
  [self setNeedsDisplay:YES];
}

- (void)setTarget:(id)object openAction:(SEL)action
{
  target = object;
  openAction = action;
}

- (void)resizeWithOldSuperviewSize:(NSSize)oldSize
{
  [super resizeWithOldSuperviewSize:oldSize];
  [self fitWidth];
}

- (void)mouseDown:(NSEvent *)event
{
  NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
  NSUInteger i;

  selected = -1;
  for (i = 0; i < [items count]; i++)
    if (NSPointInRect (p, NSInsetRect ([self rectOfItem:i], -WCStripGap / 2,
                                       -WCStripMargin)))
      {
        selected = (NSInteger) i;
        break;
      }
  [self setNeedsDisplay:YES];
  if (selected >= 0 && [event clickCount] == 2 && target != nil)
    [target performSelector:openAction withObject:self];
}

- (NSMenu *)menuForEvent:(NSEvent *)event
{
  [self mouseDown:event];
  return selected >= 0 ? [self menu] : nil;
}

/* The film mark: sprocket holes down both sides. */
static void
WCDrawFilmMark (NSRect r)
{
  NSRect band = NSMakeRect (NSMinX (r), NSMinY (r), 10, NSHeight (r));
  CGFloat y;
  int side;

  for (side = 0; side < 2; side++)
    {
      [[NSColor colorWithCalibratedWhite:0.0 alpha:0.7] set];
      NSRectFillUsingOperation (band, NSCompositeSourceOver);
      [[NSColor colorWithCalibratedWhite:1.0 alpha:0.85] set];
      for (y = NSMinY (band) + 4; y + 4 <= NSMaxY (band); y += 8)
        NSRectFill (NSMakeRect (NSMinX (band) + 3, y, 4, 4));
      band.origin.x = NSMaxX (r) - NSWidth (band);
    }
}

- (void)drawRect:(NSRect)rect
{
  NSUInteger i;

  [[NSColor colorWithCalibratedWhite:0.12 alpha:1.0] set];
  NSRectFill (rect);
  if ([items count] == 0)
    {
      NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSFont systemFontOfSize:[NSFont smallSystemFontSize]],
        NSFontAttributeName,
        [NSColor colorWithCalibratedWhite:0.6 alpha:1.0],
        NSForegroundColorAttributeName, nil];
      NSString *text = @"Photos and videos you take show here.";
      NSSize size = [text sizeWithAttributes:attributes];
      NSScrollView *scroll = [self enclosingScrollView];
      NSRect visible = scroll != nil ? [[scroll contentView] documentVisibleRect]
        : [self bounds];

      [text drawAtPoint:NSMakePoint (floor (NSMidX (visible)
                                            - size.width / 2),
                                     floor (NSMidY (visible)
                                            - size.height / 2))
         withAttributes:attributes];
      return;
    }

  for (i = 0; i < [items count]; i++)
    {
      NSDictionary *item = [items objectAtIndex:i];
      NSImage *thumb = [item objectForKey:WCStripImage];
      NSRect r = [self rectOfItem:i];

      if (!NSIntersectsRect (r, rect))
        continue;
      [[NSColor blackColor] set];
      NSRectFill (r);
      if (thumb != nil)
        {
          NSSize size = [thumb size];
          CGFloat scale = MIN (NSWidth (r) / size.width,
                               NSHeight (r) / size.height);
          NSRect into = NSMakeRect (0, 0, floor (size.width * scale),
                                    floor (size.height * scale));

          into.origin = NSMakePoint (floor (NSMidX (r) - NSWidth (into) / 2),
                                     floor (NSMidY (r) - NSHeight (into) / 2));
          [thumb drawInRect:into
                   fromRect:NSZeroRect
                  operation:NSCompositeSourceOver
                   fraction:1.0];
        }
      if ([[item objectForKey:WCStripVideo] boolValue])
        WCDrawFilmMark (r);
      if ((NSInteger) i == selected)
        {
          NSBezierPath *frame = [NSBezierPath bezierPathWithRect:
                                                NSInsetRect (r, -2, -2)];

          [frame setLineWidth:3];
          [[NSColor colorWithCalibratedRed:0.25 green:0.6 blue:1.0 alpha:1.0]
            set];
          [frame stroke];
        }
      else
        {
          [[NSColor colorWithCalibratedWhite:1.0 alpha:0.25] set];
          NSFrameRect (r);
        }
    }
}

@end
