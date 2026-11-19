/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Keyboard's defaults, how it tells others of a change, and a layout's
 * short name. The Dock's Input menu (Input.dockextra) is the Dock's
 * own now (apps-dock Extras/Input), with a copy of KBShortName; whether
 * it shows is the Dock's DockExtrasHidden, set through NBDockExtra
 * (Shared/).
 */

#ifndef KB_SHARED_H
#define KB_SHARED_H

#import <Foundation/Foundation.h>
#include <string.h>

/* WindowServer's keys, in the user's org.nextbsd.WindowServer domain
   (what loginwindow sends WindowServer at login) and WindowServer's
   session. */
#define KBWindowServerDomain	@"org.nextbsd.WindowServer"
#define KBKeyboardLayout	@"KeyboardLayout"
#define KBKeyboardVariant	@"KeyboardVariant"
#define KBKeyboardOptions	@"KeyboardOptions"
#define KBKeyboardLayoutShortcut @"KeyboardLayoutShortcut"
#define KBKeyRepeatDelay	@"KeyRepeatDelay"
#define KBKeyRepeatInterval	@"KeyRepeatInterval"

/* Keyboard's own domain: the input sources' names for anything that
   wants to show them. */
#define KBKeyboardDomain	@"org.nextbsd.Keyboard"
#define KBInputSources		@"InputSources"

/* The distributed notification that a settings domain changed
   (userInfo: domain, keys), as the settings apps' design has it. */
#define KBSettingsChangedNotification @"org.nextbsd.SettingsChanged"

/* XKB's group limit, WS_MAX_KEYBOARD_LAYOUTS. */
#define KBMaxLayouts 4

/* A domain of the user's defaults as it is in its file now, or nil.
   Read from the file rather than through NSUserDefaults, which in a
   long-running process (the Dock) may not see another process's
   change to a domain outside its own search list. */
static inline NSDictionary *
KBReadDomain (NSString *name)
{
  NSString *path = [GSDefaultsRootForUser (NSUserName ())
                     stringByAppendingPathComponent:
                       [name stringByAppendingPathExtension:@"plist"]];

  return [NSDictionary dictionaryWithContentsOfFile:path];
}

/* What the Input menu shows for a layout: EN, ΕΛ, РУ, DE... (apps-dock
   Extras/Input has a copy, DockInputShortName; keep them in step.) */
static inline NSString *
KBShortName (NSString *layout, NSString *variant)
{
  /* UTF-8, so the table doesn't lean on non-ASCII string constants. */
  static const struct { const char *layout, *name; } names[] = {
    { "us", "EN" }, { "gb", "EN" }, { "au", "EN" }, { "ie", "EN" },
    { "nz", "EN" }, { "za", "EN" },
    { "gr", "\xCE\x95\xCE\x9B" },		/* ΕΛ */
    { "ru", "\xD0\xA0\xD0\xA3" },		/* РУ */
    { "ua", "\xD0\xA3\xD0\x9A" },		/* УК */
    { "bg", "\xD0\x91\xD0\x93" },		/* БГ */
    { "by", "\xD0\x91\xD0\x95" },		/* БЕ */
    { "mk", "\xD0\x9C\xD0\x9A" },		/* МК */
    { "rs", "\xD0\xA1\xD0\xA0" },		/* СР */
    { "il", "HE" }, { "ara", "AR" }, { "ir", "FA" }, { "jp", "JA" },
    { "kr", "KO" }, { "cn", "ZH" }, { "tw", "ZH" }, { "se", "SV" },
    { "dk", "DA" }, { "cz", "CS" }, { "ee", "ET" }, { "in", "HI" },
  };
  size_t i;

  if ([variant isEqual:@"dvorak"])
    return @"DV";
  if ([variant isEqual:@"colemak"])
    return @"CO";
  if ([layout isEqual:@"rs"] && [variant hasPrefix:@"latin"])
    return @"SR";
  for (i = 0; i < sizeof (names) / sizeof (names[0]); i++)
    if (strcmp ([layout UTF8String], names[i].layout) == 0)
      return [NSString stringWithUTF8String:names[i].name];
  if ([layout length] > 3)
    layout = [layout substringToIndex:3];
  return [layout uppercaseString];
}

#endif
