/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Displays.app: the display's "looks like" size, as macOS's Displays
 * settings.
 */

#import <AppKit/AppKit.h>
#import "DSController.h"

int
main (int argc, const char **argv)
{
  CREATE_AUTORELEASE_POOL (pool);
  [NSApplication sharedApplication];
  DSController *controller = [[DSController alloc] init];
  [NSApp setDelegate:controller];
  [NSApp run];
  RELEASE (controller);
  RELEASE (pool);
  return 0;
}
