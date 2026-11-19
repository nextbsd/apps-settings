/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Keyboard.app: input layouts and switching between them, the Input
 * menu, key repeat and modifier keys, as macOS's Keyboard settings.
 */

#import <AppKit/AppKit.h>
#import "KBController.h"

int
main (int argc, const char **argv)
{
  CREATE_AUTORELEASE_POOL (pool);
  [NSApplication sharedApplication];
  KBController *controller = [[KBController alloc] init];
  [NSApp setDelegate:controller];
  [NSApp run];
  RELEASE (controller);
  RELEASE (pool);
  return 0;
}
