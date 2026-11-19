/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * NBDockExtra: a settings app's "Show X in Dock" checkbox, the way a
 * macOS settings pane's "Show X in menu bar" works. The Dock (apps-dock)
 * owns its extras; this asks it to show or hide one, and follows the
 * Dock's answer.
 *
 * The mechanism (apps-dock DockExtrasSettings.h; keep the two in step):
 *
 *   - The Dock's defaults domain DockWM has DockExtrasHidden, an array
 *     of the hidden extras' CFBundleIdentifiers. An extra not in it is
 *     shown, when its hardware is there.
 *   - An app asks with the distributed notification
 *     org.nextbsd.Dock.SetExtraHidden {identifier, hidden}. The Dock
 *     shows or hides the extra at once, saves the list, and posts
 *     org.nextbsd.Dock.ExtrasChanged {hidden}, as it also does when the
 *     user changes it in the Dock's own Settings -> Extras.
 *   - If no Dock answers within 2 seconds, none is running: the app
 *     writes DockExtrasHidden itself, and the Dock reads it when it
 *     starts.
 *
 * Use: make one per checkbox with the extra's identifier and bundle
 * name, give it a target and action (sent whenever the shown state may
 * have changed, to set the checkbox from -isShown), call -setShown: from
 * the checkbox's action, and -invalidate it before releasing it.
 * Shared/ is compiled into each app that has such a checkbox.
 */

#import <Foundation/Foundation.h>

/* The Dock's extras' identifiers. */
#define NBDockExtraWiFi		@"org.nextbsd.dockextra.wifi"
#define NBDockExtraBluetooth	@"org.nextbsd.dockextra.bluetooth"
#define NBDockExtraBattery	@"org.nextbsd.dockextra.battery"
#define NBDockExtraSound	@"org.nextbsd.dockextra.sound"
#define NBDockExtraInput	@"org.nextbsd.dockextra.input"
#define NBDockExtraClock	@"org.nextbsd.dockextra.clock"

/* The mechanism's names. */
#define NBDockDomain			@"DockWM"
#define NBDockExtrasHiddenKey		@"DockExtrasHidden"
#define NBDockSetExtraHiddenNotification @"org.nextbsd.Dock.SetExtraHidden"
#define NBDockExtrasChangedNotification	@"org.nextbsd.Dock.ExtrasChanged"

@interface NBDockExtra : NSObject
{
  NSString *identifier;
  NSString *bundleName;
  id target;			/* not retained */
  SEL action;
  BOOL pending;			/* asked, and no answer yet */
  BOOL pendingHidden;
  NSTimer *answerTimer;
}

/* identifier: the extra's CFBundleIdentifier (NBDockExtraBluetooth);
   bundleName: its bundle, without .dockextra ("Bluetooth"). */
- (id)initWithIdentifier:(NSString *)identifier
              bundleName:(NSString *)bundleName;
- (void)setTarget:(id)target action:(SEL)action;
- (void)invalidate;

/* The extra is installed where the Dock looks for extras. Without it
   there's nothing to show; the app can disable its checkbox. */
- (BOOL)isInstalled;
/* Not in DockExtrasHidden (or, while the Dock hasn't answered yet,
   what was asked). */
- (BOOL)isShown;
- (void)setShown:(BOOL)shown;

/* DockExtrasHidden as it is in the Dock's defaults file now. */
+ (NSArray *)hiddenExtras;

@end
