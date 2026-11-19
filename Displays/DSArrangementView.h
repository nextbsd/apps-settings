/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * DSArrangementView: the displays as rectangles to scale, placed as
 * they are in the desktop, as in macOS's Arrange. Drag a display to
 * move it; it snaps to touch the others. The main display has a white
 * menu bar strip along its top; drag the strip to another display to
 * make that one main. Displays that mirror another are stacked behind
 * it. Clicking a display selects it.
 */

#import <AppKit/AppKit.h>

@class DSArrangementView;

@protocol DSArrangementViewDelegate
- (void)arrangementView:(DSArrangementView *)view
       didSelectDisplay:(unsigned)displayID;
/* origin: the display's new top-left corner, desktop points. */
- (void)arrangementView:(DSArrangementView *)view
            moveDisplay:(unsigned)displayID
               toOrigin:(NSPoint)origin;
- (void)arrangementView:(DSArrangementView *)view
        makeMainDisplay:(unsigned)displayID;
@end

@interface DSArrangementView : NSView
{
  NSArray *_displays;		/* DSDisplay */
  unsigned _selected;
  id _delegate;			/* not retained */
  CGFloat _scale;		/* view points per desktop point */
  NSPoint _offset;		/* where the desktop's bounds start */
  NSRect _desktop;		/* desktop points around the displays */
  unsigned _dragged;		/* the display being dragged, or 0 */
  BOOL _draggingMenuBar;
  BOOL _moved;
  NSPoint _grab;		/* pointer minus the dragged rect's origin */
  NSPoint _pointer;
  NSRect _dragRect;		/* view points, snapped */
}

- (void)setDelegate:(id<DSArrangementViewDelegate>)delegate;
- (void)setDisplays:(NSArray *)displays selected:(unsigned)displayID;
- (BOOL)isDragging;

@end
