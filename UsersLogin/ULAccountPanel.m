/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "ULAccountPanel.h"
#import "ULAccounts.h"
#import <GNUstepBase/GNUstep.h>

#include <math.h>

/* As NBAuthorizationPanel's. */
#define ULPanelWidth 460.0
#define ULPanelMargin 20.0
#define ULIconSize 48.0
#define ULLabelWidth 120.0
#define ULTextX (ULPanelMargin + ULIconSize + 16)
#define ULFieldX (ULTextX + ULLabelWidth + 8)
#define ULFieldWidth (ULPanelWidth - ULFieldX - ULPanelMargin)

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

@interface ULAccountPanel (Private)
- (void)newPanelWithHeight:(CGFloat)height title:(NSString *)title
                      text:(NSString *)text;
- (id)field:(Class)class label:(NSString *)label y:(CGFloat)y;
- (void)buttons:(NSString *)ok y:(CGFloat)y;
- (NSInteger)runOver:(NSWindow *)window first:(NSView *)first;
- (BOOL)passwordsMatch;
- (void)ok:(id)sender;
- (void)cancel:(id)sender;
@end

@implementation ULAccountPanel

+ (NSDictionary *)runNewAccountTakenNames:(NSArray *)names
                                forWindow:(NSWindow *)window
{
  ULAccountPanel *p = AUTORELEASE ([[self alloc] init]);
  CGFloat height = 330, y = height - 104;

  ASSIGN (p->taken, names);
  [p newPanelWithHeight:height title:@"Add a user"
                   text:@"The account's home will be in /Local/Users. Leave "
                        @"the password empty for an account without one."];
  p->fullName = [p field:[NSTextField class] label:@"Full name:" y:y];
  [p->fullName setDelegate:p];
  y -= 32;
  p->shortName = [p field:[NSTextField class] label:@"Short name:" y:y];
  [p->shortName setDelegate:p];
  y -= 32;
  p->password = [p field:[NSSecureTextField class] label:@"Password:" y:y];
  y -= 32;
  p->verify = [p field:[NSSecureTextField class] label:@"Verify:" y:y];
  y -= 32;
  p->adminBox = AUTORELEASE ([[NSButton alloc]
                               initWithFrame:NSMakeRect (ULFieldX - 2, y,
                                                         ULFieldWidth + 2,
                                                         22)]);
  [p->adminBox setButtonType:NSSwitchButton];
  [p->adminBox setTitle:@"Administrator"];
  [[p->panel contentView] addSubview:p->adminBox];
  [p buttons:@"Create User" y:y - 24];

  if ([p runOver:window first:p->fullName] != NSOKButton)
    return nil;
  return [NSDictionary dictionaryWithObjectsAndKeys:
                         [p->fullName stringValue], @"fullName",
                         [p->shortName stringValue], @"name",
                         [p->password stringValue], @"password",
                         [NSNumber numberWithBool:
                                     [p->adminBox state] == NSOnState],
                         @"admin", nil];
}

+ (NSDictionary *)runPasswordFor:(ULAccount *)account
                    askOldPassword:(BOOL)askOld
                         forWindow:(NSWindow *)window
{
  ULAccountPanel *p = AUTORELEASE ([[self alloc] init]);
  CGFloat height = askOld ? 262 : 230, y = height - 104;
  NSMutableDictionary *answer;

  [p newPanelWithHeight:height
                  title:[NSString stringWithFormat:
                                    @"Change the password of \"%@\"",
                                  [account fullName]]
                   text:@"Leave the new password empty for no password."];
  if (askOld)
    {
      p->oldPassword = [p field:[NSSecureTextField class]
                          label:@"Old password:" y:y];
      y -= 32;
    }
  p->password = [p field:[NSSecureTextField class] label:@"New password:"
                       y:y];
  y -= 32;
  p->verify = [p field:[NSSecureTextField class] label:@"Verify:" y:y];
  [p buttons:@"Change Password" y:y];

  if ([p runOver:window first:askOld ? p->oldPassword : p->password]
      != NSOKButton)
    return nil;
  answer = [NSMutableDictionary dictionaryWithObject:[p->password stringValue]
                                              forKey:@"password"];
  if (askOld)
    [answer setObject:[p->oldPassword stringValue] forKey:@"oldPassword"];
  return answer;
}

- (void)dealloc
{
  /* The passwords aren't left in the fields. */
  [oldPassword setStringValue:@""];
  [password setStringValue:@""];
  [verify setStringValue:@""];
  RELEASE (panel);
  RELEASE (taken);
  [super dealloc];
}

/* The short name follows the full name until it's typed in itself. */
- (void)controlTextDidChange:(NSNotification *)note
{
  if ([note object] == shortName)
    shortNameTyped = [[shortName stringValue] length] > 0;
  else if ([note object] == fullName && !shortNameTyped)
    [shortName setStringValue:ULShortNameFor ([fullName stringValue])];
  [error setStringValue:@""];
}

@end

@implementation ULAccountPanel (Private)

- (void)newPanelWithHeight:(CGFloat)height title:(NSString *)title
                      text:(NSString *)text
{
  CGFloat textW = ULPanelWidth - ULTextX - ULPanelMargin;
  NSImageView *icon;
  NSTextField *label;

  panel = [[NSPanel alloc]
      initWithContentRect:NSMakeRect (0, 0, ULPanelWidth, height)
                styleMask:NSTitledWindowMask
                  backing:NSBackingStoreBuffered
                    defer:NO];
  [panel setTitle:@"Users & Login"];
  [panel setLevel:NSModalPanelWindowLevel];
  [panel setReleasedWhenClosed:NO];
  [panel setHidesOnDeactivate:NO];
  icon = AUTORELEASE ([[NSImageView alloc]
                        initWithFrame:NSMakeRect (ULPanelMargin,
                                                  height - ULPanelMargin
                                                  - ULIconSize,
                                                  ULIconSize, ULIconSize)]);
  [icon setImage:[NSApp applicationIconImage]];
  [icon setImageScaling:NSScaleProportionally];
  [icon setEditable:NO];
  [[panel contentView] addSubview:icon];
  [[panel contentView] addSubview:
      ULLabel (NSMakeRect (ULTextX, height - 42, textW, 22), title,
               [NSFont boldSystemFontOfSize:14])];
  label = ULLabel (NSMakeRect (ULTextX, height - 80, textW, 36), text,
                   [NSFont systemFontOfSize:[NSFont smallSystemFontSize]]);
  [[label cell] setWraps:YES];
  [[panel contentView] addSubview:label];
}

- (id)field:(Class)class label:(NSString *)text y:(CGFloat)y
{
  NSTextField *label, *field;

  label = ULLabel (NSMakeRect (ULTextX, y + 2, ULLabelWidth, 20), text, nil);
  [label setAlignment:NSRightTextAlignment];
  [[panel contentView] addSubview:label];
  field = AUTORELEASE ([[class alloc]
                         initWithFrame:NSMakeRect (ULFieldX, y, ULFieldWidth,
                                                   24)]);
  [[panel contentView] addSubview:field];
  return field;
}

/* The error line, then Cancel and the default button. */
- (void)buttons:(NSString *)ok y:(CGFloat)y
{
  NSButton *b;

  error = ULLabel (NSMakeRect (ULTextX, y - 26, ULPanelWidth - ULTextX
                               - ULPanelMargin, 18), @"",
                   [NSFont systemFontOfSize:[NSFont smallSystemFontSize]]);
  [error setTextColor:[NSColor redColor]];
  [[panel contentView] addSubview:error];

  b = AUTORELEASE ([[NSButton alloc]
                     initWithFrame:NSMakeRect (ULPanelWidth - ULPanelMargin
                                               - 140, 16, 140, 26)]);
  [b setTitle:ok];
  [b setKeyEquivalent:@"\r"];
  [b setTarget:self];
  [b setAction:@selector (ok:)];
  [[panel contentView] addSubview:b];
  b = AUTORELEASE ([[NSButton alloc]
                     initWithFrame:NSMakeRect (ULPanelWidth - ULPanelMargin
                                               - 252, 16, 100, 26)]);
  [b setTitle:@"Cancel"];
  [b setKeyEquivalent:@"\e"];
  [b setTarget:self];
  [b setAction:@selector (cancel:)];
  [[panel contentView] addSubview:b];
}

- (NSInteger)runOver:(NSWindow *)window first:(NSView *)first
{
  NSRect over, frame;
  NSInteger answer;

  over = window != nil ? [window frame] : [[NSScreen mainScreen] visibleFrame];
  frame = [panel frame];
  frame.origin.x = floor (NSMidX (over) - NSWidth (frame) / 2);
  frame.origin.y = floor (NSMaxY (over) - NSHeight (frame) - 40);
  [panel setFrame:frame display:NO];
  [panel setInitialFirstResponder:first];
  [NSApp activateIgnoringOtherApps:YES];
  answer = [NSApp runModalForWindow:panel];
  [panel orderOut:self];
  return answer;
}

- (BOOL)passwordsMatch
{
  if ([[password stringValue] isEqual:[verify stringValue]])
    return YES;
  [error setStringValue:@"The two passwords aren't the same."];
  [verify setStringValue:@""];
  [panel makeFirstResponder:verify];
  return NO;
}

- (void)ok:(id)sender
{
  if (shortName != nil)
    {
      NSString *name = [shortName stringValue];
      NSString *problem = ULShortNameProblem (name);

      if ([[[fullName stringValue]
             stringByTrimmingCharactersInSet:
               [NSCharacterSet whitespaceCharacterSet]] length] == 0)
        problem = @"Type the full name of the person the account is for.";
      else if ([[fullName stringValue] rangeOfString:@":"].location
               != NSNotFound)
        problem = @"A full name can't have a \":\".";
      else if (problem == nil && [taken containsObject:name])
        problem = @"There's already an account with that short name.";
      if (problem != nil)
        {
          [error setStringValue:problem];
          return;
        }
    }
  if (![self passwordsMatch])
    return;
  [NSApp stopModalWithCode:NSOKButton];
}

- (void)cancel:(id)sender
{
  [NSApp stopModalWithCode:NSCancelButton];
}

@end
