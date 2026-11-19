/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * DTController: Date & Time's app delegate and its one window, three
 * tabs as macOS's Date & Time (nextbsd/nextbsd#634):
 *   - Date & Time: set the date and time automatically (ntpd, the job
 *     org.nextbsd.ntpd) from a time server, or by hand when that's off;
 *   - Time Zone: a searchable list of /usr/share/zoneinfo's zones;
 *   - Clock: "Show date and time in Dock", and how the Dock's clock
 *     shows the time: digital or analog, 24-hour, seconds, the date;
 *   - the lock, Defaults and Revert.
 * The first two are root's: they go through SettingsHelper's SetDate,
 * SetNetworkTime and SetTimeZone (right org.nextbsd.settings.datetime)
 * once the lock is open. The helper posts com.apple.system.timezone and
 * com.apple.system.clock_set, which the Dock's clock follows.
 *
 * The Clock tab needs no privilege: its settings are the Dock clock
 * extra's own defaults (DockExtraClock* in the Dock's domain, DockWM).
 * Date & Time writes only the keys it changes, which GNUstep merges into
 * the Dock's file key by key, and then posts the distributed
 * notification org.nextbsd.SettingsChanged (userInfo: domain DockWM,
 * keys), the settings apps' change notification, on which the clock
 * reads them again. The clock posts the same when its own menu changes
 * them, and the tab follows.
 *
 * "Show date and time in Dock" is the Dock's own setting
 * (DockExtrasHidden in its defaults, apps-dock DockExtrasSettings.h), as
 * Energy's "Show battery in Dock" is: Date & Time asks the Dock with the
 * org.nextbsd.Dock.SetExtraHidden distributed notification and follows
 * org.nextbsd.Dock.ExtrasChanged. With no Dock to answer within two
 * seconds it writes the Dock's defaults itself, for the Dock's next
 * start.
 *
 * Everything else is read again every second, so a change made with
 * tzsetup, by ntpd or in another copy of the app shows at once.
 */

#import <AppKit/AppKit.h>
#import "NBAuthorizationPanel.h"

@interface DTController : NSObject <NBLockViewDelegate, NSTextFieldDelegate>
{
  NSWindow *window;
  NSTabView *tabView;
  NBAuthorization *auth;
  NBLockView *lockView;
  NSTimer *timer;

  /* Date & Time */
  NSButton *automaticButton;
  NSComboBox *serverBox;
  NSTextField *dateField;
  NSTextField *timeField;
  NSTextField *dateNote;
  NSTextField *zoneNote;

  /* Time Zone */
  NSTextField *zoneLabel;
  NSSearchField *searchField;
  NSTableView *zoneTable;
  NSArray *allZones;		/* DTZone, by name */
  NSMutableArray *shownZones;	/* those matching the search */
  BOOL selectingZone;		/* the window, not the user, selects */

  /* Clock */
  NSButton *showInDockButton;
  NSPopUpButton *stylePopup;
  NSButton *hour24Button;
  NSButton *secondsButton;
  NSButton *showDateButton;

  /* What's in effect, read every second. */
  NSString *zoneName;		/* nil: none recorded */
  BOOL networkTime;
  NSString *server;		/* ntp.conf's first server or pool */
  NSDictionary *clock;		/* the four clock settings, NSNumbers */
  BOOL clockInstalled;		/* the Dock's Clock.dockextra */
  BOOL dockHidden;		/* the clock is in DockExtrasHidden */
  NSTimeInterval dockAskedAt;	/* waiting for the Dock's answer; 0: not */
  BOOL dockAskedHidden;
  NSString *shownState;		/* what the controls were set from */
  /* ntpd restarts after launchd's throttle, so for a while after a
     change "running" isn't the answer: trust the change till then. */
  BOOL expectedNetworkTime;
  NSTimeInterval expectedUntil;

  /* For Revert: as the window opened. */
  NSString *originalZone;
  BOOL originalNetworkTime;
  NSString *originalServer;
  NSDictionary *originalClock;	/* the Dock's own values; absent: unset */
  BOOL originalDockHidden;
}
@end
