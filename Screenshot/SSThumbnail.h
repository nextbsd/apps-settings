/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * SSThumbnail: after a picture, a card with it slides into the bottom
 * right corner for a few seconds, as on macOS: drag it into a document
 * (it carries the file), click it to open the file, or let it go (the
 * file is already saved). The pointer over it keeps it. One at a time:
 * a newer picture's card takes its place.
 */

#import <AppKit/AppKit.h>

@interface SSThumbnail : NSObject
{
  NSWindow *_window;
  NSString *_path;
  NSTimer *_timer;
  NSTimer *_slide;
  NSRect _shown;
  CGFloat _from;
  CGFloat _to;
  int _step;
  BOOL _leaving;
}
/* Shows image (path is the file it was saved to, or nil when it went
   to the clipboard) for a few seconds. */
- (void)showImage:(NSImage *)image path:(NSString *)path
            title:(NSString *)title detail:(NSString *)detail;
- (void)dismiss;
@end
