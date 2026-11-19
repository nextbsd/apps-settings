/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * MSController: Mouse's app delegate and its one window, as macOS's
 * Mouse settings:
 *   - Mouse: tracking speed, pointer acceleration (adaptive or flat),
 *     the primary button (left or right handed), double-click speed;
 *   - Scrolling: natural scrolling and scroll speed, shared with the
 *     trackpad as WindowServer has one key for each.
 * A click applies at once; there's no Apply button. Defaults goes back
 * to the system's values, Revert to the ones from when the app opened.
 * Without a mouse (WindowServer's device list) the window says so
 * instead of showing the controls.
 *
 * Double-click speed is GNUstep's GSDoubleClickTime default in
 * NSGlobalDomain, in milliseconds, not a WindowServer setting.
 */

#import <AppKit/AppKit.h>
#import "MSSettings.h"

@interface MSController : NSObject <MSSettingsDelegate>
{
  NSWindow *window;
  MSSettings *settings;
  id openedWith;		/* snapshot for Revert */
  id openedDoubleClick;		/* GSDoubleClickTime then, or NSNull */
  NSString *shownState;		/* what the window was built from */
}
@end
