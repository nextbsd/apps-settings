/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * NBAuthorization: a settings app's hold on one right,
 * "org.nextbsd.settings.<area>" (nextbsd/nextbsd#628). It is the only way
 * the apps ask for privilege.
 *
 * Today SettingsHelper itself checks the rights: it keeps one credential
 * per console session for the rule's timeout, so an unlock in one app is
 * seen by another, and the lock opens for 5 minutes by default. The API
 * has the shape of Darwin's Authorization Services so that a later authd
 * (AuthorizationCreate / AuthorizationCopyRights with a SecurityAgent)
 * can take that over without changing the apps:
 *
 *   +authorizationWithRight:            AuthorizationCreate + the item
 *   -refresh, -isAuthorized              AuthorizationCopyRights without
 *                                        interaction
 *   NBAuthorizationPanel's
 *     +obtainAuthorization:...           AuthorizationCopyRights with
 *                                        interaction (the prompt)
 *   -relinquish                          AuthorizationFree with
 *                                        kAuthorizationFlagDestroyRights
 *   -externalForm                        AuthorizationMakeExternalForm,
 *                                        which every helper operation
 *                                        carries (all zeroes for now)
 *
 * -authorizeUser:password: is the panel's; under an authd the
 * SecurityAgent would ask instead and the password would never pass
 * through the app.
 */

#import <Foundation/Foundation.h>

/* SettingsHelper's answers (settingshelper_types.h's SH_*), and
 * NBAuthorizationUnavailable when there is no helper. */
enum
{
  NBAuthorizationOK = 0,
  NBAuthorizationNotConsole = 1,
  NBAuthorizationDenied = 2,
  NBAuthorizationNeeded = 3,
  NBAuthorizationFailed = 4,
  NBAuthorizationNotAdmin = 5,
  NBAuthorizationUnknownRight = 6,
  NBAuthorizationInvalid = 7,
  NBAuthorizationUnsupported = 8,
  NBAuthorizationChangeFailed = 9,
  NBAuthorizationExists = 10,
  NBAuthorizationLastAdmin = 11,
  NBAuthorizationLoggedIn = 12,
  NBAuthorizationBusy = 13,
  NBAuthorizationUnavailable = 100
};

/* What the right's rule asks for (SH_RULE_*). */
typedef enum
{
  NBRuleDeny = 0,
  NBRuleAllow = 1,
  NBRuleIsAdmin = 2,
  NBRuleAuthenticateAdmin = 3,
  NBRuleAuthenticateSessionOwner = 4
} NBAuthorizationRule;

@interface NBAuthorization : NSObject
{
  NSString *_right;
  int _status;			/* of the last refresh */
  NBAuthorizationRule _rule;
  int _timeout;
  NSTimeInterval _expires;	/* reference date; 0: not authorized */
  BOOL _forever;		/* the rule needs no credential */
  NSString *_consoleUser;
  BOOL _userIsAdmin;
  BOOL _userHasPassword;
}

+ (NBAuthorization *)authorizationWithRight:(NSString *)right;

- (NSString *)right;

/* Ask the helper what the right needs and whether it's held now.
 * Returns the status (NBAuthorizationOK when the helper answered). */
- (int)refresh;
- (int)status;

/* Held now: granted at the last refresh and not expired since. */
- (BOOL)isAuthorized;
/* Seconds the right is still held for; 0 when not held. */
- (NSTimeInterval)secondsLeft;

- (NBAuthorizationRule)rule;
/* The rule wants a name and password (or, for a passwordless admin,
 * "Allow changes?"). */
- (BOOL)needsAuthentication;
- (NSString *)consoleUser;
- (BOOL)userIsAdmin;
- (BOOL)userHasPassword;

/* The panel's: prove the right with an account's name and password. */
- (int)authorizeUser:(NSString *)user password:(NSString *)password;

/* The lock closed: forget this session's credentials. */
- (void)relinquish;

/* What every helper operation carries; see the top of this file. */
- (NSData *)externalForm;

/* A sentence for a status, for alerts. */
+ (NSString *)messageForStatus:(int)status;

@end
