/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * ENController: Energy's app delegate and its one window, as macOS's
 * Energy Saver:
 *   - Battery (on a machine with one): the charge, what the computer is
 *     running on, the battery's condition (maximum capacity against its
 *     design, cycle count), and "Show battery in Dock";
 *   - On Battery and On Power Adapter: turn the display off after, put the
 *     computer to sleep after, and wake for network access where the
 *     machine supports it. On a machine that can't sleep (the root
 *     domain's IOSleepSupported is false) the sleep timers are shown but
 *     disabled, with "This computer can't sleep yet.";
 *   - the lock, Defaults and Revert.
 * The timers are powerd's Energy Saver settings: read as the user with
 * IOPMCopyPMPreferences and written by SettingsHelper's SetPMPreferences
 * (right org.nextbsd.settings.energy) once the lock is open. Every change
 * applies at once; powerd follows kIOPMPrefsChangeNotify, and the window
 * follows it too, so pmset and Energy stay in step. Hibernation and Low
 * Power Mode stay hidden until NextBSD has them.
 *
 * "Show battery in Dock" is the Dock's own setting (DockExtrasHidden in
 * its defaults, apps-dock DockExtrasController): Energy asks the Dock to
 * change it with the org.nextbsd.Dock.SetExtraHidden distributed
 * notification and follows org.nextbsd.Dock.ExtrasChanged (whose
 * userInfo "hidden" is the new list). With no Dock to answer within two
 * seconds it writes the Dock's defaults itself, for the Dock's next
 * start. It reads the list from the Dock's defaults file, since
 * NSUserDefaults in a running app misses another process's change to a
 * domain outside its search list.
 */

#import <AppKit/AppKit.h>
#import "NBAuthorizationPanel.h"
#import "ENPower.h"

@interface ENController : NSObject <NBLockViewDelegate>
{
  NSWindow *window;
  NBAuthorization *auth;
  NBLockView *lockView;
  NSTimer *timer;
  ENSettings settings;
  ENSettings original;		/* for Revert: as the window opened */
  ENBattery battery;
  BOOL dockExtraInstalled;
  BOOL dockHidden;
  BOOL originalDockHidden;
  NSTimeInterval dockAskedAt;	/* waiting for the Dock's answer; 0: not */
  BOOL dockAskedHidden;
  NSString *shownState;		/* what the window was built from */
}
@end
