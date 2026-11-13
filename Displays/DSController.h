/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * DSController: Displays' app delegate and its one window, the main
 * display's name and panel size and a "looks like" row of sizes, from
 * Larger Text to More Space, plus Default for display. A click applies
 * the size at once, as on macOS; there's no Apply button.
 */

#import <AppKit/AppKit.h>
#import "DSDisplayConnection.h"

@interface DSController : NSObject <DSDisplayConnectionDelegate>
{
  NSWindow *window;
  DSDisplayConnection *connection;
  NSDictionary *settings;	/* the last Display* entries read */
  NSArray *modes;		/* "WxH" strings, Larger Text first */
  NSString *pending;		/* the choice just sent, until it shows */
}
@end
