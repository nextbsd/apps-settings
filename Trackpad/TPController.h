/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * TPController: Trackpad's app delegate and its one window, as macOS's
 * Trackpad settings:
 *   - Point & Click: tap to click, tap and drag, three-finger drag,
 *     secondary click (two fingers, the bottom-right corner, or off),
 *     tracking speed;
 *   - Scroll & Zoom: natural scrolling (shared with the mouse, as
 *     WindowServer has one key), momentum, scroll speed;
 *   - More Gestures: the ones WindowServer has, which can't be turned
 *     off yet.
 * A click applies at once; there's no Apply button. Defaults goes back
 * to the system's values, Revert to the ones from when the app opened.
 * Without a touchpad (WindowServer's device list) the window says so
 * instead of showing the controls.
 */

#import <AppKit/AppKit.h>
#import "TPSettings.h"

@interface TPController : NSObject <TPSettingsDelegate>
{
  NSWindow *window;
  TPSettings *settings;
  id openedWith;		/* snapshot for Revert */
  NSString *shownState;		/* what the window was built from */
}
@end
