/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Date & Time.app: network time, the date and time, the time zone, and
 * the Dock clock's format, as macOS's Date & Time.
 */

#import <AppKit/AppKit.h>
#import "DTController.h"

int
main (int argc, const char **argv)
{
  CREATE_AUTORELEASE_POOL (pool);
  [NSApplication sharedApplication];
  DTController *controller = [[DTController alloc] init];
  [NSApp setDelegate:controller];
  [NSApp run];
  RELEASE (controller);
  RELEASE (pool);
  return 0;
}
