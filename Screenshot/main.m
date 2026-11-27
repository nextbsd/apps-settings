/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Screenshot.app: pictures and recordings of the screen, as macOS's
 * Screenshot: the toolbar (Command+Shift+5), and what the screenshot
 * keys ask for, which WindowServer takes in every app and the Dock
 * passes on (SSRequest.h).
 */

#import <AppKit/AppKit.h>
#import "SSController.h"
#import "SSRequest.h"

int
main (int argc, const char **argv)
{
  CREATE_AUTORELEASE_POOL (pool);
  NSDictionary *request =
    SSRequestFromArguments ([[NSProcessInfo processInfo] arguments]);
  SSController *controller;

  /* Already running: that copy takes the request. */
  if ([SSController forwardRequest:request])
    {
      RELEASE (pool);
      return 0;
    }
  [NSApplication sharedApplication];
  controller = [[SSController alloc] initWithRequest:request];
  [NSApp setDelegate:controller];
  [NSApp run];
  RELEASE (controller);
  RELEASE (pool);
  return 0;
}
