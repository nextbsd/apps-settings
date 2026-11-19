/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Mouse.app: tracking speed, acceleration, the primary button,
 * double-click speed and scrolling, as macOS's Mouse settings.
 */

#import <AppKit/AppKit.h>
#import "MSController.h"

int
main (int argc, const char **argv)
{
  CREATE_AUTORELEASE_POOL (pool);
  [NSApplication sharedApplication];
  MSController *controller = [[MSController alloc] init];
  [NSApp setDelegate:controller];
  [NSApp run];
  RELEASE (controller);
  RELEASE (pool);
  return 0;
}
