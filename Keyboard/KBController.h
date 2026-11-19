/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * KBController: Keyboard's app delegate and its one window, in three
 * tabs:
 *   - Input Sources: the layouts, up to four, added from
 *     xkeyboard-config's list, removed, dragged into order and switched
 *     to; the keys that switch between them; whether the Dock shows the
 *     Input menu (its Input extra, through NBDockExtra);
 *   - Keyboard: key repeat rate and delay; what Caps Lock does; Command
 *     and Option swapped for PC keyboards;
 *   - Shortcuts: the keyboard shortcuts there are, read-only for now.
 * A change applies at once through WindowServer's settings request,
 * for this session, and is written to the user's
 * org.nextbsd.WindowServer defaults, which loginwindow sends
 * WindowServer at the next login. Defaults goes back to the system's
 * settings; Revert to those from when Keyboard opened.
 */

#import <AppKit/AppKit.h>
#import "KBConnection.h"
#import "KBSourcePicker.h"
#import "NBDockExtra.h"

@interface KBController : NSObject <KBConnectionDelegate,
                                    KBSourcePickerDelegate>
{
  NSWindow *window;
  KBConnection *connection;
  KBSourcePicker *picker;

  NSDictionary *settings;	/* WindowServer's, key -> text */
  NSDictionary *sources;	/* key -> NSNumber KBSource* */
  NSArray *layouts;		/* {Layout, Variant, Name} in order */
  int activeLayout;

  /* For Revert: the session's values when Keyboard opened (NSNull:
     the system's), the user's defaults, and Show Input menu. */
  NSDictionary *launchSession;
  NSDictionary *launchDefaults;
  BOOL launchShowsMenu;
  NBDockExtra *dockExtra;	/* the Dock's Input menu */
  BOOL changed;

  /* Controls, in the window (not retained). */
  NSTabView *tabView;
  NSTableView *sourceTable;
  NSButton *addButton;
  NSButton *removeButton;
  NSButton *switchButton;
  NSPopUpButton *shortcutPopup;
  NSButton *showMenuSwitch;
  NSSlider *rateSlider;
  NSSlider *delaySlider;
  NSTextField *rateValue;
  NSTextField *delayValue;
  NSPopUpButton *capsPopup;
  NSTextField *capsNote;
  NSButton *swapSwitch;
  NSTableView *shortcutTable;
  NSArray *shortcuts;		/* {Action, Keys} */
  NSTextField *statusLabel;
  NSButton *defaultsButton;
  NSButton *revertButton;
}
@end
