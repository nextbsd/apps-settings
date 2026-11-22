/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "ULAccounts.h"
#import <GNUstepBase/GNUstep.h>

#define ULDirectory @"/Local/Library/DirectoryServices"
#define ULUsersPlist ULDirectory @"/Users.plist"
#define ULGroupsPlist ULDirectory @"/Groups.plist"
#define ULLocalDomain ULDirectory @"/Domain.plist"
#define ULNetworkDomain @"/Network/Library/DirectoryServices/Domain.plist"
#define ULBindingPlist ULDirectory @"/Binding.plist"
#define ULLoginPrefs \
  @"/Local/Library/Preferences/org.nextbsd.loginwindow.plist"

#define ULSystemMax 999		/* acct.h's ACCT_SYSTEM_MAX */
#define ULAdminGroup @"admin"
#define ULNameMax 31		/* acct_name_problem's limit */

/* autologin-user's built-in rule: the one account there is. */
#define ULBuiltInAutoLogin @"admin"

static BOOL
ULBool (id value, BOOL fallback)
{
  return [value respondsToSelector:@selector (boolValue)]
    ? [value boolValue] : fallback;
}

@implementation ULAccount

- (id)initWithRecord:(NSDictionary *)record key:(NSString *)key
              admins:(NSArray *)admins
{
  NSString *n = [record objectForKey:@"username"];
  NSString *f = [record objectForKey:@"realName"];

  if ((self = [super init]) == nil)
    return nil;
  /* The record's own username wins; the key it's filed under is the
     fallback, as nss_directory_services and autologin-user read it. */
  if (![n isKindOfClass:[NSString class]] || [n length] == 0)
    n = key;
  ASSIGNCOPY (name, n);
  ASSIGNCOPY (fullName, [f isKindOfClass:[NSString class]] && [f length] > 0
                          ? f : n);
  uid = [[record objectForKey:@"uid"] respondsToSelector:@selector (intValue)]
    ? (unsigned) [[record objectForKey:@"uid"] intValue] : 0;
  admin = [admins containsObject:name];
  hasPassword = !ULBool ([record objectForKey:@"noPassword"], NO);
  return self;
}

- (void)dealloc
{
  RELEASE (name);
  RELEASE (fullName);
  [super dealloc];
}

- (NSString *)name
{
  return name;
}

- (NSString *)fullName
{
  return fullName;
}

- (unsigned)uid
{
  return uid;
}

- (BOOL)isAdmin
{
  return admin;
}

- (BOOL)hasPassword
{
  return hasPassword;
}

- (NSComparisonResult)compareUID:(ULAccount *)other
{
  if (uid != [other uid])
    return uid < [other uid] ? NSOrderedAscending : NSOrderedDescending;
  return [name compare:[other name]];
}

@end

NSArray *
ULAccountsLoad (void)
{
  NSDictionary *users = [NSDictionary dictionaryWithContentsOfFile:
                                         ULUsersPlist];
  NSDictionary *groups = [NSDictionary dictionaryWithContentsOfFile:
                                          ULGroupsPlist];
  NSArray *admins = [[groups objectForKey:ULAdminGroup]
                      objectForKey:@"members"];
  NSMutableArray *accounts = [NSMutableArray array];
  NSEnumerator *e = [users keyEnumerator];
  NSString *key;

  if (![admins isKindOfClass:[NSArray class]])
    admins = [NSArray array];
  while ((key = [e nextObject]) != nil)
    {
      NSDictionary *record = [users objectForKey:key];
      ULAccount *account;

      if (![record isKindOfClass:[NSDictionary class]])
        continue;
      account = AUTORELEASE ([[ULAccount alloc] initWithRecord:record
                                                           key:key
                                                        admins:admins]);
      if ([account uid] > ULSystemMax && ![[account name] hasPrefix:@"_"])
        [accounts addObject:account];
    }
  [accounts sortUsingSelector:@selector (compareUID:)];
  return accounts;
}

NSString *
ULAccountsStamp (void)
{
  NSFileManager *fm = [NSFileManager defaultManager];
  NSArray *paths = [NSArray arrayWithObjects:ULUsersPlist, ULGroupsPlist,
                            ULLoginPrefs, ULLocalDomain, ULNetworkDomain,
                            nil];
  NSMutableString *stamp = [NSMutableString string];
  NSEnumerator *e = [paths objectEnumerator];
  NSString *path;

  while ((path = [e nextObject]) != nil)
    {
      NSDictionary *a = [fm fileAttributesAtPath:path traverseLink:YES];

      [stamp appendFormat:@"%@/%llu;", [a fileModificationDate],
             [a fileSize]];
    }
  return stamp;
}

@implementation ULLoginOptions

+ (ULLoginOptions *)load
{
  NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:
                                         ULLoginPrefs];
  ULLoginOptions *options = AUTORELEASE ([[self alloc] init]);
  id key = [prefs objectForKey:@"autoLoginUser"];

  if ([key isKindOfClass:[NSString class]])
    ASSIGNCOPY (options->autoLoginKey, key);
  options->showNameFields = ULBool ([prefs objectForKey:@"SHOWFULLNAME"],
                                    YES);
  options->showPowerButtons
    = !ULBool ([prefs objectForKey:@"RestartDisabled"], NO)
      && !ULBool ([prefs objectForKey:@"ShutDownDisabled"], NO);
  return options;
}

- (void)dealloc
{
  RELEASE (autoLoginKey);
  [super dealloc];
}

- (NSString *)autoLoginKey
{
  return autoLoginKey;
}

- (NSString *)autoLoginUserWithAccounts:(NSArray *)accounts
{
  NSEnumerator *e = [accounts objectEnumerator];
  ULAccount *account;

  if (ULBoundServer () != nil)
    return nil;			/* a joined client never does */
  if (autoLoginKey == nil)
    {
      /* Not chosen: the only account, admin, without a password. */
      account = [accounts count] == 1 ? [accounts objectAtIndex:0] : nil;
      return account != nil && [[account name] isEqual:ULBuiltInAutoLogin]
        && ![account hasPassword] ? ULBuiltInAutoLogin : nil;
    }
  /* Chosen: that account, while it has no password. */
  while ((account = [e nextObject]) != nil)
    if ([[account name] isEqual:autoLoginKey])
      return [account hasPassword] ? nil : autoLoginKey;
  return nil;
}

- (BOOL)showNameFields
{
  return showNameFields;
}

- (BOOL)showPowerButtons
{
  return showPowerButtons;
}

@end

NSString *
ULBoundServer (void)
{
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *server;

  /* Asked in acct_bound_server's order: a server owns its accounts. */
  if ([fm fileExistsAtPath:ULLocalDomain]
      || ![fm fileExistsAtPath:ULNetworkDomain])
    return nil;
  server = [[NSDictionary dictionaryWithContentsOfFile:ULBindingPlist]
             objectForKey:@"server"];
  return [server isKindOfClass:[NSString class]] ? server : @"";
}

NSString *
ULShortNameFor (NSString *fullName)
{
  NSString *lower = [fullName lowercaseString];
  NSMutableString *name = [NSMutableString string];
  NSUInteger i;

  for (i = 0; i < [lower length] && [name length] < ULNameMax; i++)
    {
      unichar c = [lower characterAtIndex:i];

      if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9' && [name length]))
        [name appendFormat:@"%C", c];
    }
  return name;
}

NSString *
ULShortNameProblem (NSString *name)
{
  NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
      @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"];
  unichar first;

  if ([name length] == 0)
    return @"Type a short name for the account.";
  if ([name length] > ULNameMax)
    return [NSString stringWithFormat:
                       @"A short name can't be longer than %d characters.",
                     ULNameMax];
  if ([name rangeOfCharacterFromSet:[allowed invertedSet]].location
      != NSNotFound)
    return @"A short name can only have the letters A to Z, digits, and "
           @"\".\", \"_\" and \"-\".";
  first = [name characterAtIndex:0];
  if ((first >= '0' && first <= '9') || first == '-' || first == '.')
    return @"A short name has to start with a letter.";
  if (first == '_')
    return @"Names starting with \"_\" are for the system's own accounts.";
  return nil;
}
