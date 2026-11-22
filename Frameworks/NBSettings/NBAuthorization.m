/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "NBAuthorization.h"
#import <GNUstepBase/GNUstep.h>

#include "NBHelperClient.h"

#include <stdlib.h>
#include <string.h>
#include <strings.h>

#define NBAuthFormSize 32	/* SH_AUTH_FORM_SIZE */

@implementation NBAuthorization

+ (NBAuthorization *)authorizationWithRight:(NSString *)right
{
  NBAuthorization *auth = AUTORELEASE ([[self alloc] init]);

  ASSIGN (auth->_right, right);
  auth->_status = NBAuthorizationUnavailable;
  auth->_userHasPassword = YES;
  return auth;
}

- (void)dealloc
{
  RELEASE (_right);
  RELEASE (_consoleUser);
  [super dealloc];
}

- (NSString *)right
{
  return _right;
}

- (int)refresh
{
  NBHelperRightInfo info;
  NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];

  _status = NBHelperRightInfoGet ([_right UTF8String], &info);
  _rule = _status == NBAuthorizationOK ? (NBAuthorizationRule) info.rule
                                       : NBRuleDeny;
  _timeout = info.timeout;
  _forever = NO;
  _expires = 0;
  if (_status == NBAuthorizationOK && info.authorized)
    {
      if (_rule == NBRuleAllow || _rule == NBRuleIsAdmin)
        _forever = YES;
      else
        _expires = now + info.secondsLeft;
    }
  ASSIGN (_consoleUser, [NSString stringWithUTF8String:info.consoleUser]);
  _userIsAdmin = info.userIsAdmin ? YES : NO;
  _userHasPassword = info.userHasPassword ? YES : NO;
  return _status;
}

- (int)status
{
  return _status;
}

- (BOOL)isAuthorized
{
  return _forever || [self secondsLeft] > 0;
}

- (NSTimeInterval)secondsLeft
{
  NSTimeInterval left;

  if (_forever)
    return 1e9;
  left = _expires - [NSDate timeIntervalSinceReferenceDate];
  return left > 0 ? left : 0;
}

- (NBAuthorizationRule)rule
{
  return _rule;
}

- (BOOL)needsAuthentication
{
  return _rule == NBRuleAuthenticateAdmin
    || _rule == NBRuleAuthenticateSessionOwner;
}

- (NSString *)consoleUser
{
  return _consoleUser;
}

- (BOOL)userIsAdmin
{
  return _userIsAdmin;
}

- (BOOL)userHasPassword
{
  return _userHasPassword;
}

- (int)authorizeUser:(NSString *)user password:(NSString *)password
{
  char *pw;
  int seconds = 0, status;

  /* A copy the helper's buffer can be wiped from. */
  pw = strdup (password != nil ? [password UTF8String] : "");
  if (pw == NULL)
    return NBAuthorizationChangeFailed;
  status = NBHelperAuthorize ([_right UTF8String],
                              user != nil ? [user UTF8String] : "",
                              pw, &seconds);
  explicit_bzero (pw, strlen (pw));
  free (pw);
  if (status == NBAuthorizationOK)
    {
      _status = NBAuthorizationOK;
      if (_rule == NBRuleAllow || _rule == NBRuleIsAdmin)
        _forever = YES;
      else
        _expires = [NSDate timeIntervalSinceReferenceDate] + seconds;
    }
  return status;
}

- (void)relinquish
{
  NBHelperDeauthorize ();
  _expires = 0;
  _forever = NO;
}

- (NSData *)externalForm
{
  char form[NBAuthFormSize];

  memset (form, 0, sizeof (form));
  return [NSData dataWithBytes:form length:sizeof (form)];
}

+ (NSString *)messageForStatus:(int)status
{
  switch (status)
    {
    case NBAuthorizationOK:
      return @"Done.";
    case NBAuthorizationNotConsole:
      return @"Only the user at the computer's screen can change this.";
    case NBAuthorizationDenied:
      return @"You aren't allowed to change this.";
    case NBAuthorizationNeeded:
      return @"Click the lock to make changes.";
    case NBAuthorizationFailed:
      return @"The name or password wasn't right.";
    case NBAuthorizationNotAdmin:
      return @"That account isn't an administrator's.";
    case NBAuthorizationUnknownRight:
      return @"This setting has no rule in SettingsRights.plist.";
    case NBAuthorizationInvalid:
      return @"That value isn't allowed.";
    case NBAuthorizationUnsupported:
      return @"This computer doesn't support that setting.";
    case NBAuthorizationChangeFailed:
      return @"The change couldn't be made.";
    case NBAuthorizationExists:
      return @"There's already an account with that name.";
    case NBAuthorizationLastAdmin:
      return @"That's the only administrator. Make another account an "
             @"administrator first.";
    case NBAuthorizationLoggedIn:
      return @"That account is logged in at the computer's screen.";
    case NBAuthorizationBusy:
      return @"An update is already being checked for, downloaded or "
             @"installed.";
    case NBAuthorizationUnavailable:
    default:
      return @"The settings helper (org.nextbsd.SettingsHelper) isn't "
             @"available.";
    }
}

@end
