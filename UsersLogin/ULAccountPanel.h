/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * ULAccountPanel: Users & Login's two prompts, modal panels laid out as
 * NBAuthorizationPanel's (the app's icon, a bold line, the fields, the
 * buttons at the bottom right):
 *   - a new account: full name, short name (suggested from the full
 *     name until it's typed in), password twice, and "Allow this user to
 *     administer this computer";
 *   - a new password for an account, twice, and for your own account
 *     while the lock is closed your old one first.
 * Each checks what it can before it closes: a usable, unused short name
 * and two passwords that match. An empty password means none, which
 * NextBSD allows (the default admin has none).
 */

#import <AppKit/AppKit.h>

@class ULAccount;

@interface ULAccountPanel : NSObject <NSTextFieldDelegate>
{
  NSPanel *panel;
  NSArray *taken;		/* short names in use */
  NSTextField *fullName;
  NSTextField *shortName;
  BOOL shortNameTyped;
  NSSecureTextField *oldPassword;
  NSSecureTextField *password;
  NSSecureTextField *verify;
  NSButton *adminBox;
  NSTextField *error;
}

/* The new account's fullName, name, password and admin (an NSNumber),
 * or nil if cancelled. */
+ (NSDictionary *)runNewAccountTakenNames:(NSArray *)names
                                forWindow:(NSWindow *)window;

/* oldPassword (when asked for) and password, or nil if cancelled. */
+ (NSDictionary *)runPasswordFor:(ULAccount *)account
                    askOldPassword:(BOOL)askOld
                         forWindow:(NSWindow *)window;

@end
