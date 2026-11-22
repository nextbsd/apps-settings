/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Language & Region.app: the preferred languages, the region and its
 * formats, and the system's language, as macOS's Language & Region.
 */

#import <AppKit/AppKit.h>
#import "LRController.h"

int
main (int argc, const char **argv)
{
  CREATE_AUTORELEASE_POOL (pool);
  [NSApplication sharedApplication];
  LRController *controller = [[LRController alloc] init];
  [NSApp setDelegate:controller];
  [NSApp run];
  RELEASE (controller);
  RELEASE (pool);
  return 0;
}
