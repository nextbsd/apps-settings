/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * ULController: Users & Login's app delegate and its one window, two
 * tabs as macOS's Users & Groups (nextbsd/nextbsd#639):
 *   - Users: the local accounts (full name, short name, administrator or
 *     standard), Add User…, Delete…, Change Password… and "Allow this
 *     user to administer this computer";
 *   - Login Options: automatic login (off, or an account without a
 *     password), the login window showing a list of users or name and
 *     password fields, and its Restart and Shut Down buttons;
 *   - the lock, Defaults and Revert.
 * Every change goes through SettingsHelper (CreateUser, DeleteUser,
 * SetPassword, SetAdmin, SetAutoLogin, SetLoginWindowOptions; right
 * org.nextbsd.settings.users) once the lock is open. The one exception
 * is your own password: with the lock closed, Change Password… asks for
 * your old one and proves org.nextbsd.settings.users.own-password
 * (authenticate-session-owner, one change) with it instead.
 *
 * Users are live: the window reads the directory's files again whenever
 * they change, so an account added with adduser shows at once. Login
 * options apply at the next login window. Defaults and Revert are the
 * Login Options': accounts aren't put back.
 *
 * On a machine joined to a directory server the accounts are the
 * server's: the list shows them read-only and says so.
 */

#import <AppKit/AppKit.h>
#import "NBAuthorizationPanel.h"
#import "ULAccounts.h"

@interface ULController : NSObject <NBLockViewDelegate>
{
  NSWindow *window;
  NBAuthorization *auth;
  NBLockView *lockView;
  NSTimer *timer;

  /* Users */
  NSTableView *userTable;
  NSButton *addButton;
  NSButton *deleteButton;
  NSButton *passwordButton;
  NSButton *adminButton;
  NSTextField *userNote;

  /* Login Options */
  NSPopUpButton *autoLoginPopup;
  NSTextField *autoLoginNote;
  NSButton *listButton;
  NSButton *fieldsButton;
  NSButton *powerButton;
  NSTextField *optionsNote;

  /* What's in effect, read again when the files change. */
  NSArray *accounts;		/* ULAccount */
  ULLoginOptions *options;
  NSString *server;		/* joined to; nil: the accounts are ours */
  NSString *stamp;		/* the files as last read */
  NSString *shownState;		/* what the controls were set from */

  /* For Revert: as the window opened. */
  NSString *originalAutoLogin;	/* nil: none */
  BOOL originalNameFields;
  BOOL originalPowerButtons;
}
@end
