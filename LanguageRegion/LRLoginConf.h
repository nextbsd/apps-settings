/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * LRLoginConf: the locale the terminal and command-line programs get,
 * from the login class (login.conf(5)).
 *
 * At login, setusercontext(3) sets LANG from the class's `lang` and
 * MM_CHARSET from its `charset`, and any variables in its `setenv`
 * list; then the same from the user's own ~/.login_conf (its record
 * "me"), which wins. login(1), sshd and loginwindow all call it, so a
 * graphical session and a terminal in it, an SSH login and a console
 * login all agree.
 *
 *   - The user's choice is ~/.login_conf: `lang` and `charset`, and,
 *     when the region's formats differ from the language's,
 *     LC_TIME, LC_NUMERIC and LC_MONETARY in `setenv`. It needs no
 *     privilege. Everything else in the file, and in the record, is
 *     kept.
 *   - The system's default is /etc/login.conf's class "default", which
 *     only SettingsHelper changes (SetSystemLocale); it's read here.
 *
 * Plain C, so that a languagesetup-style tool for the installer and the
 * first-boot language picker (nextbsd/nextbsd#501) can share it.
 */

#ifndef _LR_LOGIN_CONF_H_
#define _LR_LOGIN_CONF_H_

#include <stddef.h>

#define LRLocaleNameMax 64

/* What a ~/.login_conf says about the locale; "" where it says
 * nothing. */
typedef struct
{
  char lang[LRLocaleNameMax];		/* LANG */
  char charset[LRLocaleNameMax];	/* MM_CHARSET */
  char time[LRLocaleNameMax];		/* LC_TIME, from setenv */
  char numeric[LRLocaleNameMax];	/* LC_NUMERIC */
  char monetary[LRLocaleNameMax];	/* LC_MONETARY */
} LRLoginLocale;

/* Read path's record "me". 0 on success (a missing file says nothing),
 * -1 if it can't be read. */
int LRLoginConfRead (const char *path, LRLoginLocale *out);

/* Set path's record "me" to say `locale`: lang and charset, and the
 * three LC_ variables; an empty field takes that setting out (all empty:
 * the user has no locale of their own, and the class's applies). The
 * record's other capabilities, and its other setenv variables, are kept;
 * a record left empty is removed, and so is a file left empty. A
 * login_conf.db next to it is built again (cap_mkdb), since getcap(3)
 * reads that first. 0 on success, -1 with errno. */
int LRLoginConfWrite (const char *path, const LRLoginLocale *locale);

/* The default class's lang in /etc/login.conf: the system's language.
 * Copies it to buf; "" when it has none. */
void LRLoginConfSystemLang (char *buf, size_t size);

#endif
