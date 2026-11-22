/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * WCStripView: the recent captures, newest first, in a row under the
 * controls, as Photo Booth's strip. Videos have a film mark. A click
 * selects one, a double click opens it; the controller does the
 * opening.
 */

#import <AppKit/AppKit.h>

/* An item's keys. */
#define WCStripPath @"path"		/* NSString */
#define WCStripImage @"image"		/* NSImage, or none */
#define WCStripVideo @"video"		/* NSNumber, BOOL */

@interface WCStripView : NSView
{
  NSArray *items;
  NSInteger selected;
  id target;
  SEL openAction;
}
- (void)setItems:(NSArray *)newItems;
- (NSString *)selectedPath;
- (void)selectPath:(NSString *)path;
- (void)setTarget:(id)object openAction:(SEL)action;
@end
