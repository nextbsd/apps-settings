/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Printers.app: the printers (CUPS queues), adding and removing them,
 * the default printer, and each printer's paper size and two-sided
 * printing, as macOS's Printers & Scanners.
 */

#import <AppKit/AppKit.h>
#import "PRController.h"

int
main (int argc, const char **argv)
{
  CREATE_AUTORELEASE_POOL (pool);
  [NSApplication sharedApplication];
  PRController *controller = [[PRController alloc] init];
  [NSApp setDelegate:controller];
  [NSApp run];
  RELEASE (controller);
  RELEASE (pool);
  return 0;
}
