/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * SSOverlay: the dimmed screen under the toolbar, and what the user
 * points at on it. Selection mode: a dashed rectangle with eight
 * handles and its size in the middle, drawn by dragging, moved by
 * dragging inside it and resized by its handles; the screen outside it
 * stays dimmed. Window mode: the window under the pointer is tinted,
 * and a click takes it. Screen mode: the whole screen, lightly dimmed;
 * a click takes it.
 *
 * A borderless, see-through window over the main display, above the
 * menu bar and the Dock but below pop-up menus (the toolbar's Options
 * menu), so it is level 99 and the toolbar 100.
 */

#import <AppKit/AppKit.h>

#define SSOverlayLevel 99
#define SSToolbarLevel 100

typedef enum
{
  SSOverlayScreen,
  SSOverlayWindow,
  SSOverlaySelection
} SSOverlayMode;

@class SSOverlayView;

@protocol SSOverlayDelegate
/* Escape. */
- (void)overlayDidCancel:(SSOverlayView *)overlay;
/* A click on the screen (screen mode), on a window (window mode), or
   a selection drawn in quick mode (Command+Shift+4). */
- (void)overlayDidChoose:(SSOverlayView *)overlay;
/* Return: take what the toolbar's button would. */
- (void)overlayDidConfirm:(SSOverlayView *)overlay;
/* Space in quick mode: selection and window mode swap. */
- (void)overlayDidSwapMode:(SSOverlayView *)overlay;
@end

/* An NSWindow that may become key without a title bar. */
@interface SSPanel : NSWindow
@end

@interface SSOverlayView : NSView
{
  id _delegate;
  SSOverlayMode _mode;
  BOOL _quick;
  NSRect _selection;		/* view coordinates; empty: none yet */
  NSArray *_windows;		/* [rect value, id number] front first */
  NSRect _highlight;
  uint32_t _highlightWindow;
  /* the drag */
  int _handle;			/* -1 none, 0..7 handles, 8 move, 9 new */
  NSPoint _anchor;
  NSRect _startSelection;
}
- (id)initWithFrame:(NSRect)frame delegate:(id)delegate;
- (void)setMode:(SSOverlayMode)mode quick:(BOOL)quick;
- (SSOverlayMode)mode;
- (BOOL)isQuick;
- (void)setSelection:(NSRect)selection;
- (NSRect)selection;
/* The windows to pick from: rects in view coordinates and their
   WindowServer ids, front first. */
- (void)setWindows:(NSArray *)rects ids:(NSArray *)ids;
- (uint32_t)chosenWindow;
- (NSRect)chosenWindowRect;
@end

/* The overlay window over the main display, with its view. */
SSPanel *SSOverlayWindowCreate (id delegate, SSOverlayView **view);
