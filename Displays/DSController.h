/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * DSController: Displays' app delegate and its one window, as macOS's
 * Displays settings:
 *   - Arrangement (several displays): the displays to scale, dragged to
 *     place them, the menu bar strip dragged to make another display
 *     main, and Mirror Displays;
 *   - the selected display: its name and panel, what it's used as
 *     (main, extended, mirror), its "looks like" sizes from Larger Text
 *     to More Space plus Default for display, all of its resolutions
 *     on request, and its refresh rate;
 *   - Night Shift: off, on or on a schedule, and how warm.
 * A click applies at once, as on macOS; there's no Apply button. A
 * change to a size, mode or mirroring asks "Keep these display
 * settings?" and goes back after 15 seconds without an answer.
 *
 * Without WindowServer's display list (older servers) the window shows
 * the one display and its "looks like" sizes, set through the
 * DisplayLooksLike setting.
 */

#import <AppKit/AppKit.h>
#import "DSArrangementView.h"
#import "DSConfirmPanel.h"
#import "DSDisplayConnection.h"

@class DSDisplay;

@interface DSController : NSObject <DSDisplayConnectionDelegate,
                                    DSArrangementViewDelegate,
                                    DSConfirmPanelDelegate>
{
  NSWindow *window;
  DSDisplayConnection *connection;
  DSConfirmPanel *confirmPanel;
  NSArray *displays;		/* DSDisplay, the main one first */
  NSDictionary *settings;	/* Display* and NightShift* entries */
  NSString *shownState;		/* what the window was built from */
  unsigned selectedID;		/* the display whose settings show */
  NSMutableSet *showAllFor;	/* display ids with all resolutions */
  NSArray *resolutions;		/* DSDisplayMode rows of the list */
  NSArray *refreshRates;	/* NSNumber mHz, of the popup */
  DSArrangementView *arrangementView; /* in the window, not retained */
  BOOL reloadAfterDrag;
  BOOL sawPending;		/* WindowServer said a change is pending */
}
@end
