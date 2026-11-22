/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * ULAccounts: what Users & Login shows, read as any user from the files
 * the helper writes (nextbsd/nextbsd#639):
 *   - the local accounts, /Local/Library/DirectoryServices/Users.plist,
 *     with group admin's members from Groups.plist: the files libds and
 *     the account tools write, mode 0644;
 *   - the login window's settings, /Local/Library/Preferences/
 *     org.nextbsd.loginwindow.plist (autoLoginUser, SHOWFULLNAME,
 *     RestartDisabled, ShutDownDisabled; nextbsd-userland SettingsHelper
 *     sh_login.c);
 *   - whether the machine is joined to a directory server, whose
 *     accounts the helper won't change (acct.c's acct_bound_server).
 */

#import <Foundation/Foundation.h>

@interface ULAccount : NSObject
{
  NSString *name;		/* the short name: admin */
  NSString *fullName;		/* realName: Local Administrator */
  unsigned uid;
  BOOL admin;			/* in group admin */
  BOOL hasPassword;		/* not noPassword */
}
- (NSString *)name;
/* The full name, or the short name when it has none. */
- (NSString *)fullName;
- (unsigned)uid;
- (BOOL)isAdmin;
- (BOOL)hasPassword;
@end

/* The regular local accounts (uid above 999, no "_" service accounts),
 * by uid. */
NSArray *ULAccountsLoad (void);

/* The files' modification times, to tell when to read them again. */
NSString *ULAccountsStamp (void);

/* The login window's settings. */
@interface ULLoginOptions : NSObject
{
  NSString *autoLoginKey;	/* autoLoginUser; nil: not set */
  BOOL showNameFields;		/* SHOWFULLNAME, default YES */
  BOOL showPowerButtons;	/* neither Restart- nor ShutDownDisabled */
}
+ (ULLoginOptions *)load;
/* autoLoginUser as written: nil when the key isn't set (autologin-user's
 * built-in rule decides), "" for off. */
- (NSString *)autoLoginKey;
/* The account logged in at startup, as autologin-user decides it from
 * the key and the accounts: nil for none. */
- (NSString *)autoLoginUserWithAccounts:(NSArray *)accounts;
- (BOOL)showNameFields;
- (BOOL)showPowerButtons;
@end

/* The directory server this machine is joined to ("" when it can't be
 * named), or nil when its accounts are its own. */
NSString *ULBoundServer (void);

/* A short name for a full name, as macOS suggests one: "Jane Q. Smith"
 * gives "janeqsmith". "" if nothing usable is left. */
NSString *ULShortNameFor (NSString *fullName);

/* Why a short name can't be used, as a sentence, or nil when it's fine
 * (acct.c's acct_name_problem, and no service account names). */
NSString *ULShortNameProblem (NSString *name);
