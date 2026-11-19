/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * NBAuthorizationPanel: the settings apps' lock and prompt
 * (nextbsd/nextbsd#628, the design's "The panel").
 *
 *   - NBLockView is the lock at the bottom left of a window with
 *     root-only controls: "Click the lock to make changes." A click on
 *     the closed lock asks for the right; a click on the open one closes
 *     it for the whole session. It closes by itself when the right's
 *     timeout runs out.
 *   - +obtainAuthorization:... is the prompt, run as a modal panel:
 *     an administrator's name and password, or (authenticate-session-
 *     owner) the user's own password. For an administrator whose account
 *     has no password, as the default "admin" has, it asks only
 *     "Allow changes?" with Allow and Cancel, the design's proposal for
 *     its open question.
 * The panel draws nothing of its own beyond the lock glyph, so the theme
 * styles it.
 */

#import <AppKit/AppKit.h>
#import "NBAuthorization.h"

@interface NBAuthorizationPanel : NSObject
{
  NBAuthorization *_auth;	/* not retained; lives across the run */
  NSPanel *_panel;
  NSTextField *_name;
  NSSecureTextField *_password;
  NSTextField *_error;
}

/* Hold the right, asking if the rule wants it. reason finishes "<App>
 * wants to ...", for example "change the Energy settings". YES once the
 * right is held; NO if refused or cancelled (an alert says why, except
 * for Cancel). */
+ (BOOL)obtainAuthorization:(NBAuthorization *)auth
                     reason:(NSString *)reason
                  forWindow:(NSWindow *)window;

@end

@class NBLockView;

@protocol NBLockViewDelegate
/* The lock opened or closed. */
- (void)lockViewDidChange:(NBLockView *)lockView;
@end

@interface NBLockView : NSView
{
  NBAuthorization *_auth;
  NSString *_reason;
  NSButton *_button;
  NSTextField *_label;
  id _delegate;			/* not retained */
  BOOL _unlocked;
}

- (id)initWithFrame:(NSRect)frame
      authorization:(NBAuthorization *)auth
             reason:(NSString *)reason;
- (void)setDelegate:(id<NBLockViewDelegate>)delegate;
- (NBAuthorization *)authorization;
- (BOOL)isUnlocked;
/* Ask again (the right may have been opened in another app) and close
 * the lock once the time is up. Call it now and then. */
- (void)update;
/* As a click on the closed lock: YES if it's open afterwards. */
- (BOOL)unlock;

@end
