/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Bluetooth.app: Bluetooth on or off, the paired and nearby devices,
 * pairing, and each headset's audio, as macOS's Bluetooth settings.
 */

#import <AppKit/AppKit.h>
#import "BTController.h"

int
main (int argc, const char **argv)
{
  CREATE_AUTORELEASE_POOL (pool);
  [NSApplication sharedApplication];
  BTController *controller = [[BTController alloc] init];
  [NSApp setDelegate:controller];
  [NSApp run];
  RELEASE (controller);
  RELEASE (pool);
  return 0;
}
