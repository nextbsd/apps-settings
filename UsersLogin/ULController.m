/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "ULController.h"
#import "ULAccountPanel.h"
#import "NBSettingsHelper.h"
#import <GNUstepBase/GNUstep.h>

/* Layout, in points, as Date & Time's. */
#define ULMargin 20.0
#define ULWindowWidth 560.0
#define ULTabHeight 340.0
#define ULLabelWidth 170.0
#define ULFieldX (ULLabelWidth + 8)
#define ULRowGap 10.0
#define ULButtonWidth 100.0
#define ULButtonHeight 26.0
/* The lock and its sentence, beside Defaults and Revert. */
#define ULLockWidth (ULWindowWidth - 2 * ULMargin - 2 * ULButtonWidth - 16)

static NSString *const ULRight = @"org.nextbsd.settings.users";
static NSString *const ULOwnPasswordRight
  = @"org.nextbsd.settings.users.own-password";
static NSString *const ULReason = @"change users and login settings";

/* A view laid out from the top down. */
@interface ULFlippedView : NSView
@end

@implementation ULFlippedView
- (BOOL)isFlipped
{
  return YES;
}
@end

static NSTextField *
ULLabel (NSRect frame, NSString *text, NSFont *font)
{
  NSTextField *label = AUTORELEASE ([[NSTextField alloc] initWithFrame:frame]);
  [label setStringValue:(text != nil ? text : @"")];
  [label setEditable:NO];
  [label setSelectable:NO];
  [label setBordered:NO];
  [label setBezeled:NO];
  [label setDrawsBackground:NO];
  if (font != nil)
    [label setFont:font];
  return label;
}

static NSTextField *
ULRowLabel (CGFloat y, NSString *text)
{
  NSTextField *label = ULLabel (NSMakeRect (0, y + 3, ULLabelWidth, 20), text,
                                nil);
  [label setAlignment:NSRightTextAlignment];
  return label;
}

static NSFont *
ULSmallFont (void)
{
  return [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
}

static NSButton *
ULButton (NSRect frame, NSString *title, int type, id target, SEL action)
{
  NSButton *b = AUTORELEASE ([[NSButton alloc] initWithFrame:frame]);
  if (type >= 0)
    [b setButtonType:type];
  [b setTitle:title];
  [b setTarget:target];
  [b setAction:action];
  return b;
}

/* The privileged operations, for -apply:value:. */
enum
{
  ULOpCreate,
  ULOpDelete,
  ULOpPassword,
  ULOpAdmin,
  ULOpAutoLogin,
  ULOpOptions
};

@interface ULController (Private)
- (void)buildMenu;
- (NSView *)usersTab:(NSRect)frame;
- (NSView *)optionsTab:(NSRect)frame;
- (NSView *)bottomRow;
- (void)tick:(NSTimer *)t;
- (void)reload;
- (void)updateControls;
- (ULAccount *)selectedAccount;
- (NSString *)autoLoginUser;
- (int)perform:(int)op value:(id)value;
- (BOOL)apply:(int)op value:(id)value;
- (void)addUser:(id)sender;
- (void)deleteUser:(id)sender;
- (void)changePassword:(id)sender;
- (void)toggleAdmin:(id)sender;
- (void)chooseAutoLogin:(id)sender;
- (void)chooseLoginWindow:(id)sender;
- (void)setOptionsNameFields:(BOOL)fields powerButtons:(BOOL)power;
- (void)useDefaults:(id)sender;
- (void)revert:(id)sender;
@end

@implementation ULController

- (void)dealloc
{
  [timer invalidate];
  RELEASE (timer);
  RELEASE (window);
  RELEASE (auth);
  RELEASE (lockView);
  RELEASE (accounts);
  RELEASE (options);
  RELEASE (server);
  RELEASE (stamp);
  RELEASE (shownState);
  RELEASE (originalAutoLogin);
  [super dealloc];
}

- (void)applicationDidFinishLaunching:(NSNotification *)note
{
  NSImage *icon = [NSImage imageNamed:@"UsersLogin.png"];
  ULFlippedView *content;
  NSTabView *tabView;
  NSTabViewItem *item;
  NSView *bottom;
  NSRect inner;
  CGFloat height;

  if (icon != nil)
    [NSApp setApplicationIconImage:icon];
  [self buildMenu];

  auth = RETAIN ([NBAuthorization authorizationWithRight:ULRight]);
  lockView = [[NBLockView alloc]
                initWithFrame:NSMakeRect (0, 0, ULLockWidth, 30)
                authorization:auth
                       reason:ULReason];
  [lockView setDelegate:self];

  ASSIGN (stamp, ULAccountsStamp ());
  ASSIGN (accounts, ULAccountsLoad ());
  ASSIGN (options, [ULLoginOptions load]);
  ASSIGN (server, ULBoundServer ());
  ASSIGN (originalAutoLogin, [self autoLoginUser]);
  originalNameFields = [options showNameFields];
  originalPowerButtons = [options showPowerButtons];

  height = ULMargin + ULTabHeight + ULRowGap + 30 + ULMargin;
  window = [[NSWindow alloc]
      initWithContentRect:NSMakeRect (200, 200, ULWindowWidth, height)
                styleMask:NSTitledWindowMask | NSClosableWindowMask
                          | NSMiniaturizableWindowMask
                  backing:NSBackingStoreBuffered
                    defer:NO];
  [window setTitle:@"Users & Login"];
  [window setReleasedWhenClosed:NO];
  [window setFrameAutosaveName:@"UsersLogin"];

  content = AUTORELEASE ([[ULFlippedView alloc]
                           initWithFrame:NSMakeRect (0, 0, ULWindowWidth,
                                                     height)]);
  tabView = AUTORELEASE ([[NSTabView alloc]
                           initWithFrame:NSMakeRect (ULMargin, ULMargin,
                                                     ULWindowWidth
                                                     - 2 * ULMargin,
                                                     ULTabHeight)]);
  [content addSubview:tabView];
  inner = [tabView contentRect];
  inner.origin = NSZeroPoint;

  item = AUTORELEASE ([[NSTabViewItem alloc] initWithIdentifier:@"users"]);
  [item setLabel:@"Users"];
  [item setView:[self usersTab:inner]];
  [tabView addTabViewItem:item];
  item = AUTORELEASE ([[NSTabViewItem alloc] initWithIdentifier:@"login"]);
  [item setLabel:@"Login Options"];
  [item setView:[self optionsTab:inner]];
  [tabView addTabViewItem:item];

  bottom = [self bottomRow];
  [bottom setFrameOrigin:NSMakePoint (ULMargin,
                                      ULMargin + ULTabHeight + ULRowGap)];
  [content addSubview:bottom];
  [window setContentView:content];

  [userTable reloadData];
  [self reload];
  [window makeKeyAndOrderFront:self];

  ASSIGN (timer, [NSTimer scheduledTimerWithTimeInterval:1.0
                                                  target:self
                                                selector:@selector (tick:)
                                                userInfo:nil
                                                 repeats:YES]);
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app
{
  return YES;
}

/* Users & Login has no documents; a file it's asked to open just brings
   the window forward. */
- (BOOL)application:(NSApplication *)app openFile:(NSString *)filename
{
  [window makeKeyAndOrderFront:self];
  return YES;
}

- (void)lockViewDidChange:(NBLockView *)view
{
  DESTROY (shownState);
  [self reload];
}

/* ---- the user table ---- */

- (NSInteger)numberOfRowsInTableView:(NSTableView *)table
{
  return [accounts count];
}

- (id)tableView:(NSTableView *)table
    objectValueForTableColumn:(NSTableColumn *)column
                          row:(NSInteger)row
{
  ULAccount *account = [accounts objectAtIndex:row];
  NSString *which = [column identifier];

  if ([which isEqual:@"name"])
    return [account name];
  if ([which isEqual:@"kind"])
    return [account isAdmin] ? @"Administrator" : @"Standard";
  if ([[account name] isEqual:NSUserName ()])
    return [NSString stringWithFormat:@"%@ (you)", [account fullName]];
  return [account fullName];
}

- (void)tableViewSelectionDidChange:(NSNotification *)note
{
  DESTROY (shownState);
  [self updateControls];
}

@end

@implementation ULController (Private)

- (void)buildMenu
{
  NSMenu *menu = AUTORELEASE ([[NSMenu alloc] initWithTitle:@"Users & Login"]);
  NSMenu *edit = AUTORELEASE ([[NSMenu alloc] initWithTitle:@"Edit"]);
  NSMenu *windows = AUTORELEASE ([[NSMenu alloc] initWithTitle:@"Window"]);
  id<NSMenuItem> item;

  [menu addItemWithTitle:@"About Users & Login"
                  action:@selector (orderFrontStandardAboutPanel:)
           keyEquivalent:@""];
  /* The panels take typing, so cut, copy and paste. */
  item = [menu addItemWithTitle:@"Edit" action:NULL keyEquivalent:@""];
  [edit addItemWithTitle:@"Cut" action:@selector (cut:) keyEquivalent:@"x"];
  [edit addItemWithTitle:@"Copy" action:@selector (copy:) keyEquivalent:@"c"];
  [edit addItemWithTitle:@"Paste" action:@selector (paste:)
           keyEquivalent:@"v"];
  [edit addItemWithTitle:@"Select All" action:@selector (selectAll:)
           keyEquivalent:@"a"];
  [menu setSubmenu:edit forItem:item];
  item = [menu addItemWithTitle:@"Window" action:NULL keyEquivalent:@""];
  [windows addItemWithTitle:@"Minimize"
                     action:@selector (performMiniaturize:)
              keyEquivalent:@"m"];
  [windows addItemWithTitle:@"Close"
                     action:@selector (performClose:)
              keyEquivalent:@"w"];
  [menu setSubmenu:windows forItem:item];
  [NSApp setWindowsMenu:windows];
  [menu addItemWithTitle:@"Hide" action:@selector (hide:) keyEquivalent:@"h"];
  [menu addItemWithTitle:@"Quit" action:@selector (terminate:) keyEquivalent:@"q"];
  [NSApp setMainMenu:menu];
}

/* ---- the tabs ---- */

- (NSView *)usersTab:(NSRect)frame
{
  ULFlippedView *view = AUTORELEASE ([[ULFlippedView alloc]
                                       initWithFrame:frame]);
  CGFloat width = NSWidth (frame) - 2 * ULMargin, y = ULMargin - 6;
  NSScrollView *scroll;
  NSTableColumn *column;
  NSString *const ids[] = { @"fullName", @"name", @"kind" };
  NSString *const titles[] = { @"Name", @"Short Name", @"Account" };
  const CGFloat widths[] = { 200, 130, 120 };
  int i;

  scroll = AUTORELEASE ([[NSScrollView alloc]
                          initWithFrame:NSMakeRect (ULMargin, y, width,
                                                    170)]);
  [scroll setHasVerticalScroller:YES];
  [scroll setBorderType:NSBezelBorder];
  userTable = AUTORELEASE ([[NSTableView alloc]
                             initWithFrame:[[scroll contentView] bounds]]);
  for (i = 0; i < 3; i++)
    {
      column = AUTORELEASE ([[NSTableColumn alloc]
                              initWithIdentifier:ids[i]]);
      [[column headerCell] setStringValue:titles[i]];
      [column setWidth:widths[i]];
      [column setEditable:NO];
      [userTable addTableColumn:column];
    }
  [userTable setAllowsMultipleSelection:NO];
  [userTable setAllowsEmptySelection:YES];
  [userTable setDataSource:self];
  [userTable setDelegate:self];
  [scroll setDocumentView:userTable];
  [view addSubview:scroll];
  y += 170 + ULRowGap;

  addButton = ULButton (NSMakeRect (ULMargin, y, 110, ULButtonHeight),
                        @"Add User…", -1, self, @selector (addUser:));
  [view addSubview:addButton];
  deleteButton = ULButton (NSMakeRect (ULMargin + 118, y, 110,
                                       ULButtonHeight),
                           @"Delete…", -1, self, @selector (deleteUser:));
  [view addSubview:deleteButton];
  passwordButton = ULButton (NSMakeRect (ULMargin + width - 160, y, 160,
                                         ULButtonHeight),
                             @"Change Password…", -1, self,
                             @selector (changePassword:));
  [view addSubview:passwordButton];
  y += ULButtonHeight + ULRowGap;

  adminButton = ULButton (NSMakeRect (ULMargin, y, width, 22),
                          @"Allow this user to administer this computer",
                          NSSwitchButton, self, @selector (toggleAdmin:));
  [view addSubview:adminButton];
  y += 22 + ULRowGap;

  userNote = ULLabel (NSMakeRect (ULMargin, y, width, 48), nil,
                      ULSmallFont ());
  [[userNote cell] setWraps:YES];
  [view addSubview:userNote];
  return view;
}

- (NSView *)optionsTab:(NSRect)frame
{
  ULFlippedView *view = AUTORELEASE ([[ULFlippedView alloc]
                                       initWithFrame:frame]);
  CGFloat width = NSWidth (frame) - 2 * ULMargin, y = ULMargin;

  [view addSubview:ULRowLabel (y, @"Automatic login:")];
  autoLoginPopup = AUTORELEASE ([[NSPopUpButton alloc]
                                  initWithFrame:NSMakeRect (ULFieldX, y, 220,
                                                            24)
                                      pullsDown:NO]);
  [autoLoginPopup setAutoenablesItems:NO];
  [autoLoginPopup setTarget:self];
  [autoLoginPopup setAction:@selector (chooseAutoLogin:)];
  [view addSubview:autoLoginPopup];
  y += 24 + 4;
  autoLoginNote = ULLabel (NSMakeRect (ULFieldX, y, width - ULFieldX
                                       + ULMargin, 32),
                           @"Only an account without a password can log in "
                           @"automatically.", ULSmallFont ());
  [[autoLoginNote cell] setWraps:YES];
  [view addSubview:autoLoginNote];
  y += 32 + 2 * ULRowGap;

  [view addSubview:ULRowLabel (y - 2, @"Display login window as:")];
  listButton = ULButton (NSMakeRect (ULFieldX, y, 240, 22),
                         @"List of users", NSRadioButton, self,
                         @selector (chooseLoginWindow:));
  [view addSubview:listButton];
  y += 22 + 4;
  fieldsButton = ULButton (NSMakeRect (ULFieldX, y, 240, 22),
                           @"Name and password", NSRadioButton, self,
                           @selector (chooseLoginWindow:));
  [view addSubview:fieldsButton];
  y += 22 + 2 * ULRowGap;

  powerButton = ULButton (NSMakeRect (ULFieldX, y, width - ULFieldX
                                      + ULMargin, 22),
                          @"Show the Restart and Shut Down buttons",
                          NSSwitchButton, self,
                          @selector (chooseLoginWindow:));
  [view addSubview:powerButton];
  y += 22 + 3 * ULRowGap;

  optionsNote = ULLabel (NSMakeRect (ULMargin, y, width, 32),
                         @"Login options take effect the next time the "
                         @"login window opens.", ULSmallFont ());
  [[optionsNote cell] setWraps:YES];
  [view addSubview:optionsNote];
  return view;
}

/* The lock at the left, Defaults and Revert at the right. */
- (NSView *)bottomRow
{
  CGFloat width = ULWindowWidth - 2 * ULMargin;
  ULFlippedView *row = AUTORELEASE ([[ULFlippedView alloc]
                                      initWithFrame:NSMakeRect (0, 0, width,
                                                                30)]);

  [lockView setFrameOrigin:NSMakePoint (0, 0)];
  [row addSubview:lockView];
  [row addSubview:ULButton (NSMakeRect (width - ULButtonWidth, 2,
                                        ULButtonWidth, ULButtonHeight),
                            @"Revert", -1, self, @selector (revert:))];
  [row addSubview:ULButton (NSMakeRect (width - 2 * ULButtonWidth - 8, 2,
                                        ULButtonWidth, ULButtonHeight),
                            @"Defaults", -1, self,
                            @selector (useDefaults:))];
  return row;
}

/* ---- following the system ---- */

/* Every second: the lock's time, and the files if they changed. */
- (void)tick:(NSTimer *)t
{
  NSString *now = ULAccountsStamp ();

  [lockView update];
  if (![now isEqual:stamp])
    {
      ASSIGN (stamp, now);
      [self reload];
    }
  else
    [self updateControls];
}

/* Read the accounts and the login options again, keeping the
   selection. */
- (void)reload
{
  NSString *selected = [[self selectedAccount] name];
  NSUInteger i;

  ASSIGN (accounts, ULAccountsLoad ());
  ASSIGN (options, [ULLoginOptions load]);
  ASSIGN (server, ULBoundServer ());
  [userTable reloadData];
  [userTable deselectAll:self];
  if (selected == nil)
    selected = NSUserName ();
  for (i = 0; i < [accounts count]; i++)
    if ([[[accounts objectAtIndex:i] name] isEqual:selected])
      {
        [userTable selectRow:i byExtendingSelection:NO];
        break;
      }
  DESTROY (shownState);
  [self updateControls];
}

/* Set the controls, if anything they show has changed. */
- (void)updateControls
{
  BOOL unlocked = [lockView isUnlocked], own = server == nil;
  ULAccount *account = [self selectedAccount], *a;
  BOOL me = [[account name] isEqual:NSUserName ()];
  NSString *autoUser = [self autoLoginUser], *state;
  NSEnumerator *e;
  NSMenuItem *item;

  state = [NSString stringWithFormat:@"%d %d %@ %@ %@ %d %d %d", unlocked,
                    own, [account name], accounts, autoUser,
                    [options showNameFields], [options showPowerButtons],
                    [auth status]];
  if ([state isEqual:shownState])
    return;
  ASSIGN (shownState, state);

  [addButton setEnabled:unlocked && own];
  [deleteButton setEnabled:unlocked && own && account != nil && !me];
  [passwordButton setEnabled:own && account != nil && (unlocked || me)];
  [adminButton setState:[account isAdmin] ? NSOnState : NSOffState];
  [adminButton setEnabled:unlocked && own && account != nil];
  if (!own)
    [userNote setStringValue:
        [NSString stringWithFormat:
                    @"This computer is joined to the directory server%@%@. "
                    @"Its accounts are managed there.",
                  [server length] > 0 ? @" " : @"", server]];
  else if (account == nil)
    [userNote setStringValue:@""];
  else
    [userNote setStringValue:
        [NSString stringWithFormat:@"%@%@ Home: /Local/Users/%@.%@",
                  [account hasPassword] ? @"" : @"This account has no "
                                                @"password. ",
                  me ? @"You're logged in as this user." : @"",
                  [account name],
                  !unlocked && me ? @" You can change your own password "
                                    @"without unlocking." : @""]];

  /* Off, then each account; only one without a password can log in
     automatically. */
  [autoLoginPopup removeAllItems];
  [autoLoginPopup addItemWithTitle:@"Off"];
  [[autoLoginPopup lastItem] setRepresentedObject:@""];
  e = [accounts objectEnumerator];
  while ((a = [e nextObject]) != nil)
    {
      [autoLoginPopup addItemWithTitle:
          [NSString stringWithFormat:@"%@ (%@)", [a fullName], [a name]]];
      item = (NSMenuItem *) [autoLoginPopup lastItem];
      [item setRepresentedObject:[a name]];
      [item setEnabled:![a hasPassword]];
      if ([[a name] isEqual:autoUser])
        [autoLoginPopup selectItem:item];
    }
  if (autoUser == nil)
    [autoLoginPopup selectItemAtIndex:0];
  [autoLoginPopup setEnabled:unlocked && own];
  [listButton setState:[options showNameFields] ? NSOffState : NSOnState];
  [fieldsButton setState:[options showNameFields] ? NSOnState : NSOffState];
  [powerButton setState:[options showPowerButtons] ? NSOnState : NSOffState];
  [listButton setEnabled:unlocked];
  [fieldsButton setEnabled:unlocked];
  [powerButton setEnabled:unlocked];
}

- (ULAccount *)selectedAccount
{
  NSInteger row = [userTable selectedRow];

  if (row < 0 || row >= (NSInteger) [accounts count])
    return nil;
  return [accounts objectAtIndex:row];
}

/* Who logs in at startup now, as autologin-user decides it. */
- (NSString *)autoLoginUser
{
  return [options autoLoginUserWithAccounts:accounts];
}

/* ---- changes ---- */

- (int)perform:(int)op value:(id)value
{
  switch (op)
    {
    case ULOpCreate:
      return [NBSettingsHelper
                createUser:[value objectForKey:@"name"]
                  fullName:[value objectForKey:@"fullName"]
                  password:[value objectForKey:@"password"]
                     admin:[[value objectForKey:@"admin"] boolValue]
             authorization:auth];
    case ULOpDelete:
      return [NBSettingsHelper
                deleteUser:[value objectForKey:@"name"]
                  keepHome:[[value objectForKey:@"keepHome"] boolValue]
             authorization:auth];
    case ULOpPassword:
      return [NBSettingsHelper
               setPassword:[value objectForKey:@"password"]
                   forUser:[value objectForKey:@"name"]
             authorization:auth];
    case ULOpAdmin:
      return [NBSettingsHelper
                 setAdmin:[[value objectForKey:@"admin"] boolValue]
                  forUser:[value objectForKey:@"name"]
            authorization:auth];
    case ULOpAutoLogin:
      return [NBSettingsHelper setAutoLoginUser:value authorization:auth];
    case ULOpOptions:
      return [NBSettingsHelper
               setLoginWindowShowsNameFields:
                 [[value objectForKey:@"nameFields"] boolValue]
                                powerButtons:
                 [[value objectForKey:@"powerButtons"] boolValue]
                               authorization:auth];
    }
  return NBAuthorizationInvalid;
}

/* Through the helper, unlocking first if the lock was open but the
   right ran out. */
- (BOOL)apply:(int)op value:(id)value
{
  int status = [self perform:op value:value];

  if (status == NBAuthorizationNeeded)
    {
      /* The helper no longer holds the right (it ran out, or the helper
         was restarted): close the lock, then ask. */
      [auth refresh];
      [lockView update];
      if ([lockView unlock])
        status = [self perform:op value:value];
      else
        return NO;		/* cancelled: nothing to say */
    }
  if (status == NBAuthorizationInvalid && op == ULOpCreate)
    NSRunAlertPanel (@"Users & Login", @"An account named \"%@\" can't be "
                     @"made. Short names use the letters A to Z, digits, "
                     @"\".\", \"_\" and \"-\", and start with a letter.",
                     @"OK", nil, nil, [value objectForKey:@"name"]);
  else if (status != NBAuthorizationOK)
    NSRunAlertPanel (@"Users & Login", @"%@", @"OK", nil, nil,
                     [NBAuthorization messageForStatus:status]);
  ASSIGN (stamp, ULAccountsStamp ());
  [self reload];
  return status == NBAuthorizationOK;
}

- (void)addUser:(id)sender
{
  NSMutableArray *names = [NSMutableArray array];
  NSEnumerator *e = [accounts objectEnumerator];
  NSDictionary *answer;
  ULAccount *account;
  NSUInteger i;

  while ((account = [e nextObject]) != nil)
    [names addObject:[account name]];
  answer = [ULAccountPanel runNewAccountTakenNames:names forWindow:window];
  if (answer == nil || ![self apply:ULOpCreate value:answer])
    return;
  for (i = 0; i < [accounts count]; i++)
    if ([[[accounts objectAtIndex:i] name]
          isEqual:[answer objectForKey:@"name"]])
      [userTable selectRow:i byExtendingSelection:NO];
}

- (void)deleteUser:(id)sender
{
  ULAccount *account = [self selectedAccount];
  NSUInteger i, admins = 0;
  NSInteger answer;

  if (account == nil)
    return;
  for (i = 0; i < [accounts count]; i++)
    if ([[accounts objectAtIndex:i] isAdmin])
      admins++;
  if ([account isAdmin] && admins == 1)
    {
      NSRunAlertPanel (@"Users & Login", @"%@", @"OK", nil, nil,
                       [NBAuthorization messageForStatus:
                                          NBAuthorizationLastAdmin]);
      return;
    }
  answer = NSRunAlertPanel (@"Users & Login",
                            @"Delete the account \"%@\" (%@)? Anything it "
                            @"has running stops. Its home, /Local/Users/%@, "
                            @"can be kept or deleted with it.",
                            @"Keep Home", @"Cancel", @"Delete Home",
                            [account fullName], [account name],
                            [account name]);
  if (answer == NSAlertAlternateReturn)
    return;
  [self apply:ULOpDelete
        value:[NSDictionary dictionaryWithObjectsAndKeys:
                              [account name], @"name",
                              [NSNumber numberWithBool:
                                          answer == NSAlertDefaultReturn],
                              @"keepHome", nil]];
}

- (void)changePassword:(id)sender
{
  ULAccount *account = [self selectedAccount];
  BOOL own = [[account name] isEqual:NSUserName ()]
    && ![lockView isUnlocked];
  NSDictionary *answer;
  NBAuthorization *mine;
  int status;

  if (account == nil)
    return;
  answer = [ULAccountPanel runPasswordFor:account askOldPassword:own
                                forWindow:window];
  if (answer == nil)
    return;
  if (!own)
    {
      [self apply:ULOpPassword
            value:[NSDictionary dictionaryWithObjectsAndKeys:
                                  [account name], @"name",
                                  [answer objectForKey:@"password"],
                                  @"password", nil]];
      return;
    }

  /* Your own, with the lock closed: your old password proves
     own-password for this one change. */
  mine = [NBAuthorization authorizationWithRight:ULOwnPasswordRight];
  status = [mine refresh];
  if (status == NBAuthorizationOK)
    status = [mine authorizeUser:[account name]
                        password:[answer objectForKey:@"oldPassword"]];
  if (status == NBAuthorizationOK)
    status = [NBSettingsHelper setPassword:[answer objectForKey:@"password"]
                                   forUser:[account name]
                             authorization:mine];
  if (status == NBAuthorizationFailed)
    NSRunAlertPanel (@"Users & Login", @"The old password wasn't right.",
                     @"OK", nil, nil);
  else if (status != NBAuthorizationOK)
    NSRunAlertPanel (@"Users & Login", @"%@", @"OK", nil, nil,
                     [NBAuthorization messageForStatus:status]);
  ASSIGN (stamp, ULAccountsStamp ());
  [self reload];
}

- (void)toggleAdmin:(id)sender
{
  ULAccount *account = [self selectedAccount];

  if (account != nil)
    [self apply:ULOpAdmin
          value:[NSDictionary dictionaryWithObjectsAndKeys:
                                [account name], @"name",
                                [NSNumber numberWithBool:
                                            [sender state] == NSOnState],
                                @"admin", nil]];
  DESTROY (shownState);
  [self updateControls];
}

- (void)chooseAutoLogin:(id)sender
{
  NSString *user = [[sender selectedItem] representedObject];
  NSString *now = [self autoLoginUser];

  if ([user isEqual:now != nil ? now : @""])
    return;
  [self apply:ULOpAutoLogin value:[user length] > 0 ? user : nil];
}

/* The radio buttons and the power buttons' checkbox. */
- (void)chooseLoginWindow:(id)sender
{
  BOOL fields = sender == listButton ? NO
    : sender == fieldsButton ? YES : [options showNameFields];
  BOOL power = sender == powerButton ? [sender state] == NSOnState
    : [options showPowerButtons];

  [self setOptionsNameFields:fields powerButtons:power];
}

- (void)setOptionsNameFields:(BOOL)fields powerButtons:(BOOL)power
{
  if (fields == [options showNameFields]
      && power == [options showPowerButtons])
    {
      DESTROY (shownState);
      [self updateControls];
      return;
    }
  [self apply:ULOpOptions
        value:[NSDictionary dictionaryWithObjectsAndKeys:
                              [NSNumber numberWithBool:fields], @"nameFields",
                              [NSNumber numberWithBool:power],
                              @"powerButtons", nil]];
}

/* The login window's own defaults: name and password fields, with
   Restart and Shut Down. Automatic login and the accounts have no
   default: they stay. */
- (void)useDefaults:(id)sender
{
  if ([lockView unlock])
    [self setOptionsNameFields:YES powerButtons:YES];
}

/* Back to the login options from when the window opened. */
- (void)revert:(id)sender
{
  NSString *now = [self autoLoginUser];

  if (![lockView unlock])
    return;
  if (!(now == originalAutoLogin || [now isEqual:originalAutoLogin])
      && server == nil
      && ![self apply:ULOpAutoLogin value:originalAutoLogin])
    return;
  [self setOptionsNameFields:originalNameFields
                powerButtons:originalPowerButtons];
}

@end
