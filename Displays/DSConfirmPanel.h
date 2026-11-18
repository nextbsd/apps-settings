/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * DSConfirmPanel: macOS's "Keep these display settings?" after a
 * change to a display's size, mode or mirroring. It counts down the
 * seconds WindowServer gives (WS_DISPLAY_REVERT_MS); Keep Changes keeps
 * the change, and Revert, Escape or the end of the countdown undo it.
 * WindowServer goes back by itself if Displays never answers, so a mode
 * that leaves the screen dark comes back on its own.
 */

#import <AppKit/AppKit.h>

@class DSConfirmPanel;

@protocol DSConfirmPanelDelegate
- (void)confirmPanelKeep:(DSConfirmPanel *)panel;
/* The Revert button, Escape, or the time ran out. */
- (void)confirmPanelRevert:(DSConfirmPanel *)panel;
@end

@interface DSConfirmPanel : NSObject
{
  NSPanel *_panel;
  NSTextField *_countdown;
  NSTimer *_timer;
  NSTimeInterval _deadline;
  id _delegate;			/* not retained */
}

- (id)initWithDelegate:(id<DSConfirmPanelDelegate>)delegate;

/* Show it over window, or count from `seconds` again if it shows. */
- (void)showOverWindow:(NSWindow *)window seconds:(NSTimeInterval)seconds;
/* What WindowServer says is left (revert_ms). */
- (void)setSecondsLeft:(NSTimeInterval)seconds;
- (BOOL)isVisible;
- (void)close;

@end
