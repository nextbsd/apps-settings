/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Network.app: the network services and their TCP/IP and DNS settings,
 * Wi-Fi, and the computer's name, as macOS's Network.
 */

#import <AppKit/AppKit.h>
#import "NWController.h"

int
main (int argc, const char **argv)
{
  CREATE_AUTORELEASE_POOL (pool);
  [NSApplication sharedApplication];
  NWController *controller = [[NWController alloc] init];
  [NSApp setDelegate:controller];
  [NSApp run];
  RELEASE (controller);
  RELEASE (pool);
  return 0;
}
