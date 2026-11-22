/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * LRController: Language & Region's app delegate and its one window,
 * three tabs, as macOS's Language & Region (nextbsd/nextbsd#652):
 *   - Languages: the preferred languages in order, + and − and drag to
 *     reorder; apps use the first they're translated into;
 *   - Region: the region, whose formats the apps use, and the first day
 *     of the week, the calendar, 24-hour time, measurement units and
 *     temperature, with a live preview of the formats;
 *   - System: what the terminal and command-line programs get, and,
 *     for an administrator, the system's language;
 *   - the lock, Defaults and Revert.
 *
 * Apps: the user's NSGlobalDomain NSLanguages and Locale, the two keys
 * libs-base reads (LRLocales.h has the details), written key by key,
 * then the settings apps' distributed notification
 * org.nextbsd.SettingsChanged {domain NSGlobalDomain, keys}. A running
 * GNUstep app reads NSLanguages only when it starts, and keeps the
 * NSLocale it made; so most apps take a change when they're next
 * opened, and the window says so.
 *
 * The terminal: LANG from the first language (in the region, when the
 * system has that locale), and LC_TIME, LC_NUMERIC and LC_MONETARY from
 * the region when they differ, in ~/.login_conf (LRLoginConf.h), which
 * setusercontext(3) applies at the next login. No privilege.
 *
 * The system's language is /etc/login.conf's default class, through
 * SettingsHelper's SetSystemLocale (right org.nextbsd.settings.locale,
 * is-admin) once the lock is open.
 *
 * What's in effect is read again every second and on
 * org.nextbsd.SettingsChanged, so a change made elsewhere shows.
 */

#import <AppKit/AppKit.h>
#import "NBAuthorizationPanel.h"
#import "LRLanguagePicker.h"
#import "LRLocales.h"
#import "LRLoginConf.h"

@interface LRController : NSObject <NBLockViewDelegate,
                                    LRLanguagePickerDelegate>
{
  NSWindow *window;
  NSTabView *tabView;
  NBAuthorization *auth;
  NBLockView *lockView;
  NSTimer *timer;
  LRLanguagePicker *picker;

  /* Languages */
  NSTableView *languageTable;
  NSButton *addButton;
  NSButton *removeButton;

  /* Region */
  NSPopUpButton *regionPopup;
  NSPopUpButton *weekdayPopup;
  NSPopUpButton *calendarPopup;
  NSButton *hour24Button;
  NSPopUpButton *measurementPopup;
  NSPopUpButton *temperaturePopup;
  NSTextField *previewDate;
  NSTextField *previewShort;
  NSTextField *previewNumbers;
  NSTextField *previewUnits;
  NSTextField *previewWeek;

  /* System */
  NSTextField *terminalLanguage;
  NSTextField *terminalFormats;
  NSTextField *terminalNote;
  NSPopUpButton *systemPopup;

  /* What's in effect, read every second. */
  NSArray *languages;		/* identifiers, first preferred */
  BOOL languagesSet;		/* the user's own NSLanguages */
  LRLocaleChoice *choice;
  BOOL localeSet;		/* the user's own Locale */
  LRLoginLocale login;		/* ~/.login_conf */
  NSString *systemLang;		/* the default class's lang */
  NSString *shownState;		/* what the controls were set from */

  /* For Revert: as the window opened. */
  id originalLanguages;		/* NSLanguages, or nil */
  id originalLocale;		/* Locale, or nil */
  LRLoginLocale originalLogin;
  NSString *originalSystemLang;
}
@end
