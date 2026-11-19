/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "NBAuthorizationPanel.h"
#import <GNUstepBase/GNUstep.h>

#include <math.h>

#define NBPanelWidth 440.0
#define NBPanelMargin 20.0
#define NBIconSize 48.0
#define NBLabelWidth 80.0

static NSTextField *
NBLabel (NSRect frame, NSString *text, NSFont *font)
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

static NSString *
NBAppName (void)
{
  NSString *name = [[[NSBundle mainBundle] infoDictionary]
                     objectForKey:@"CFBundleDisplayName"];

  return name != nil ? name : [[NSProcessInfo processInfo] processName];
}

/* ---- the prompt ---- */

@interface NBAuthorizationPanel (Private)
- (id)initWithAuthorization:(NBAuthorization *)auth;
- (NSInteger)runWithReason:(NSString *)reason window:(NSWindow *)window;
- (NSPanel *)newPanelWithHeight:(CGFloat)height;
- (NSButton *)button:(NSString *)title x:(CGFloat)x key:(NSString *)key
              action:(SEL)action;
- (void)buildAllow:(NSString *)reason;
- (void)buildPassword:(NSString *)reason;
- (void)ok:(id)sender;
- (void)cancel:(id)sender;
@end

@implementation NBAuthorizationPanel

+ (BOOL)obtainAuthorization:(NBAuthorization *)auth
                     reason:(NSString *)reason
                  forWindow:(NSWindow *)window
{
  NBAuthorizationPanel *panel;
  NSInteger answer;
  int status;

  status = [auth refresh];
  if (status == NBAuthorizationOK && [auth isAuthorized])
    return YES;
  if (status == NBAuthorizationOK && [auth needsAuthentication])
    {
      panel = AUTORELEASE ([[self alloc] initWithAuthorization:auth]);
      answer = [panel runWithReason:reason window:window];
      return answer == NSOKButton && [auth isAuthorized];
    }
  if (status == NBAuthorizationOK)	/* allow, is-admin or deny */
    status = [auth authorizeUser:@"" password:@""];
  if (status == NBAuthorizationOK)
    return YES;
  NSRunAlertPanel (NBAppName (), @"%@", @"OK", nil, nil,
                   [NBAuthorization messageForStatus:status]);
  return NO;
}

- (void)dealloc
{
  RELEASE (_panel);
  [super dealloc];
}

@end

@implementation NBAuthorizationPanel (Private)

- (id)initWithAuthorization:(NBAuthorization *)auth
{
  if ((self = [super init]) == nil)
    return nil;
  _auth = auth;
  return self;
}

- (NSInteger)runWithReason:(NSString *)reason window:(NSWindow *)window
{
  NSRect over, frame;
  NSInteger answer;
  BOOL owner = [_auth rule] == NBRuleAuthenticateSessionOwner;

  /* An admin (or, for the session owner's rule, the user) whose account
     has no password: nothing to type. */
  if (![_auth userHasPassword] && (owner || [_auth userIsAdmin]))
    [self buildAllow:reason];
  else
    [self buildPassword:reason];

  over = window != nil ? [window frame] : [[NSScreen mainScreen] visibleFrame];
  frame = [_panel frame];
  frame.origin.x = floor (NSMidX (over) - NSWidth (frame) / 2);
  frame.origin.y = floor (NSMaxY (over) - NSHeight (frame) - 40);
  [_panel setFrame:frame display:NO];
  [NSApp activateIgnoringOtherApps:YES];
  answer = [NSApp runModalForWindow:_panel];
  [_panel orderOut:self];
  if (_password != nil)
    [_password setStringValue:@""];
  return answer;
}

- (NSPanel *)newPanelWithHeight:(CGFloat)height
{
  NSPanel *panel = [[NSPanel alloc]
      initWithContentRect:NSMakeRect (0, 0, NBPanelWidth, height)
                styleMask:NSTitledWindowMask
                  backing:NSBackingStoreBuffered
                    defer:NO];
  NSImageView *icon;

  [panel setTitle:NBAppName ()];
  [panel setLevel:NSModalPanelWindowLevel];
  [panel setReleasedWhenClosed:NO];
  [panel setHidesOnDeactivate:NO];
  icon = AUTORELEASE ([[NSImageView alloc]
                        initWithFrame:NSMakeRect (NBPanelMargin,
                                                  height - NBPanelMargin
                                                  - NBIconSize,
                                                  NBIconSize, NBIconSize)]);
  [icon setImage:[NSApp applicationIconImage]];
  [icon setImageScaling:NSScaleProportionally];
  [icon setEditable:NO];
  [[panel contentView] addSubview:icon];
  return panel;
}

- (NSButton *)button:(NSString *)title x:(CGFloat)x key:(NSString *)key
              action:(SEL)action
{
  NSButton *b = AUTORELEASE ([[NSButton alloc]
                               initWithFrame:NSMakeRect (x, 16, 100, 26)]);
  [b setTitle:title];
  [b setKeyEquivalent:key];
  [b setTarget:self];
  [b setAction:action];
  [[_panel contentView] addSubview:b];
  return b;
}

/* "Allow changes?" for an account without a password. */
- (void)buildAllow:(NSString *)reason
{
  CGFloat height = 150, textX = NBPanelMargin + NBIconSize + 16;
  CGFloat textW = NBPanelWidth - textX - NBPanelMargin;
  NSTextField *text;
  NSButton *allow;

  _panel = [self newPanelWithHeight:height];
  [[_panel contentView] addSubview:
      NBLabel (NSMakeRect (textX, height - 42, textW, 22), @"Allow changes?",
               [NSFont boldSystemFontOfSize:14])];
  text = NBLabel (NSMakeRect (textX, height - 108, textW, 62),
                  [NSString stringWithFormat:
                     @"%@ wants to %@. Your account (%@) has no password, "
                     @"so none is asked for.", NBAppName (), reason,
                     [_auth consoleUser]],
                  nil);
  [[text cell] setWraps:YES];
  [[_panel contentView] addSubview:text];
  allow = [self button:@"Allow" x:NBPanelWidth - NBPanelMargin - 100
                   key:@"\r" action:@selector (ok:)];
  [self button:@"Cancel" x:NBPanelWidth - NBPanelMargin - 212 key:@"\e"
        action:@selector (cancel:)];
  [_panel setInitialFirstResponder:allow];
}

/* An administrator's (or the user's own) name and password. */
- (void)buildPassword:(NSString *)reason
{
  BOOL owner = [_auth rule] == NBRuleAuthenticateSessionOwner;
  CGFloat height = 226, textX = NBPanelMargin + NBIconSize + 16;
  CGFloat textW = NBPanelWidth - textX - NBPanelMargin;
  CGFloat fieldX = textX + NBLabelWidth + 8, y;
  NSTextField *text, *label;
  NSString *user = [_auth userIsAdmin] || owner ? [_auth consoleUser] : @"";

  _panel = [self newPanelWithHeight:height];
  [[_panel contentView] addSubview:
      NBLabel (NSMakeRect (textX, height - 42, textW, 22),
               [NSString stringWithFormat:@"%@ wants to make changes.",
                         NBAppName ()],
               [NSFont boldSystemFontOfSize:14])];
  text = NBLabel (NSMakeRect (textX, height - 84, textW, 40),
                  [NSString stringWithFormat:
                     owner ? @"Enter your password to allow this: %@."
                           : @"Enter an administrator's name and password "
                             @"to allow this: %@.", reason],
                  nil);
  [[text cell] setWraps:YES];
  [[_panel contentView] addSubview:text];

  y = height - 118;
  label = NBLabel (NSMakeRect (textX, y + 2, NBLabelWidth, 20), @"Name:", nil);
  [label setAlignment:NSRightTextAlignment];
  [[_panel contentView] addSubview:label];
  _name = AUTORELEASE ([[NSTextField alloc]
                         initWithFrame:NSMakeRect (fieldX, y,
                                                   NBPanelWidth - fieldX
                                                   - NBPanelMargin, 24)]);
  [_name setStringValue:user != nil ? user : @""];
  [_name setEditable:!owner];
  [[_panel contentView] addSubview:_name];

  y -= 32;
  label = NBLabel (NSMakeRect (textX, y + 2, NBLabelWidth, 20), @"Password:",
                   nil);
  [label setAlignment:NSRightTextAlignment];
  [[_panel contentView] addSubview:label];
  _password = AUTORELEASE ([[NSSecureTextField alloc]
                             initWithFrame:NSMakeRect (fieldX, y,
                                                       NBPanelWidth - fieldX
                                                       - NBPanelMargin, 24)]);
  [_password setTarget:self];
  [_password setAction:@selector (ok:)];
  [[_panel contentView] addSubview:_password];

  _error = NBLabel (NSMakeRect (fieldX, y - 26, NBPanelWidth - fieldX
                                - NBPanelMargin, 18), @"",
                    [NSFont systemFontOfSize:[NSFont smallSystemFontSize]]);
  [[_panel contentView] addSubview:_error];

  [self button:@"Unlock" x:NBPanelWidth - NBPanelMargin - 100 key:@"\r"
        action:@selector (ok:)];
  [self button:@"Cancel" x:NBPanelWidth - NBPanelMargin - 212 key:@"\e"
        action:@selector (cancel:)];
  [_panel setInitialFirstResponder:([[_name stringValue] length] > 0
                                    ? (NSView *) _password : (NSView *) _name)];
}

- (void)ok:(id)sender
{
  NSString *user = _name != nil ? [_name stringValue] : [_auth consoleUser];
  NSString *password = _password != nil ? [_password stringValue] : @"";
  int status;

  status = [_auth authorizeUser:user password:password];
  if (status == NBAuthorizationOK)
    {
      [NSApp stopModalWithCode:NSOKButton];
      return;
    }
  if (_password == nil)
    {
      /* "Allow changes?" refused: say why and stop. */
      [NSApp stopModalWithCode:NSCancelButton];
      NSRunAlertPanel (NBAppName (), @"%@", @"OK", nil, nil,
                       [NBAuthorization messageForStatus:status]);
      return;
    }
  [_error setStringValue:[NBAuthorization messageForStatus:status]];
  [_password setStringValue:@""];
  [_panel makeFirstResponder:_password];
}

- (void)cancel:(id)sender
{
  [NSApp stopModalWithCode:NSCancelButton];
}

@end

/* ---- the lock ---- */

/* The lock glyph, closed or open, in the text colour. */
static NSImage *
NBLockImage (BOOL open)
{
  NSImage *image = AUTORELEASE ([[NSImage alloc]
                                  initWithSize:NSMakeSize (20, 24)]);
  NSBezierPath *shackle = [NSBezierPath bezierPath];
  NSBezierPath *body;
  CGFloat left = open ? 9.5 : 5.5, right = left + 9;

  [image lockFocus];
  [[NSColor controlTextColor] set];
  body = [NSBezierPath bezierPathWithRect:NSMakeRect (3, 1, 14, 11)];
  [body fill];
  [shackle setLineWidth:2.2];
  [shackle moveToPoint:NSMakePoint (left, open ? 15 : 12)];
  [shackle lineToPoint:NSMakePoint (left, 17)];
  [shackle appendBezierPathWithArcWithCenter:NSMakePoint ((left + right) / 2,
                                                          17)
                                      radius:(right - left) / 2
                                  startAngle:180
                                    endAngle:0
                                   clockwise:YES];
  [shackle lineToPoint:NSMakePoint (right, 12)];
  [shackle stroke];
  [[NSColor controlBackgroundColor] set];
  [[NSBezierPath bezierPathWithRect:NSMakeRect (9, 4, 2, 5)] fill];
  [image unlockFocus];
  return image;
}

@interface NBLockView (Private)
- (void)click:(id)sender;
- (void)show;
@end

@implementation NBLockView

- (id)initWithFrame:(NSRect)frame
      authorization:(NBAuthorization *)auth
             reason:(NSString *)reason
{
  if ((self = [super initWithFrame:frame]) == nil)
    return nil;
  ASSIGN (_auth, auth);
  ASSIGN (_reason, reason);
  _button = AUTORELEASE ([[NSButton alloc]
                           initWithFrame:NSMakeRect (0, 0, 30, 30)]);
  [_button setImagePosition:NSImageOnly];
  [_button setBordered:NO];
  [_button setTarget:self];
  [_button setAction:@selector (click:)];
  [self addSubview:_button];
  _label = NBLabel (NSMakeRect (34, 5, NSWidth (frame) - 34, 20), @"", nil);
  [self addSubview:_label];
  [_auth refresh];
  _unlocked = [_auth isAuthorized];
  [self show];
  return self;
}

- (void)dealloc
{
  RELEASE (_auth);
  RELEASE (_reason);
  [super dealloc];
}

- (void)setDelegate:(id<NBLockViewDelegate>)delegate
{
  _delegate = delegate;
}

- (NBAuthorization *)authorization
{
  return _auth;
}

- (BOOL)isUnlocked
{
  return _unlocked;
}

- (void)update
{
  BOOL now = [_auth isAuthorized];

  /* Out of time here: the helper may hold a newer credential (another
     settings app unlocked), so ask before closing. */
  if (_unlocked && !now)
    {
      [_auth refresh];
      now = [_auth isAuthorized];
    }
  if (now != _unlocked)
    {
      _unlocked = now;
      [self show];
      [_delegate lockViewDidChange:self];
    }
}

- (BOOL)unlock
{
  if (!_unlocked)
    {
      _unlocked = [NBAuthorizationPanel obtainAuthorization:_auth
                                                     reason:_reason
                                                  forWindow:[self window]];
      [self show];
      if (_unlocked)
        [_delegate lockViewDidChange:self];
    }
  return _unlocked;
}

@end

@implementation NBLockView (Private)

- (void)click:(id)sender
{
  if (_unlocked)
    {
      [_auth relinquish];
      _unlocked = NO;
      [self show];
      [_delegate lockViewDidChange:self];
    }
  else
    [self unlock];
}

- (void)show
{
  [_button setImage:NBLockImage (_unlocked)];
  if ([_auth status] == NBAuthorizationUnavailable)
    [_label setStringValue:@"The settings helper isn't available."];
  else if ([_auth status] == NBAuthorizationNotConsole)
    [_label setStringValue:@"Only the user at the screen can unlock."];
  else
    [_label setStringValue:_unlocked
                           ? @"Click the lock to prevent further changes."
                           : @"Click the lock to make changes."];
}

@end
