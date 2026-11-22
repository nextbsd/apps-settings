# Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause
#
# Users & Login.app: the local accounts (add, delete, passwords,
# administrators), automatic login, and the login window's options
# (nextbsd/nextbsd#639). Every change goes through SettingsHelper
# (nextbsd-userland src/SettingsHelper), whose client is
# ../Frameworks/NBSettings. Installed like the other desktop apps, in the
# USER domain (~/Applications) for now.
#
# It's built as UsersLogin.app: gnustep-make names its variables after
# the app (UsersLogin_OBJC_FILES), so the name can't hold a space or
# "&". It's installed as "Users & Login.app", the name people see in the
# File Viewer, the Dock and the menu (UsersLoginInfo.plist), as Date &
# Time is.

ifeq ($(GNUSTEP_MAKEFILES),)
 GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES)
endif
include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = UsersLogin
UsersLogin_OBJC_FILES = main.m ULController.m ULAccounts.m ULAccountPanel.m
UsersLogin_HEADER_FILES = ULController.h ULAccounts.h ULAccountPanel.h
UsersLogin_RESOURCE_FILES = Resources/UsersLogin.png
UsersLogin_APPLICATION_ICON = UsersLogin.png
UsersLogin_OBJCFLAGS = -Wall -Wextra -Wno-unused-parameter
UsersLogin_SUBPROJECTS = ../Frameworks/NBSettings
UsersLogin_INCLUDE_DIRS = -I../Frameworks/NBSettings

# NextBSD's system libraries live in /usr/lib/system: liblaunch and the
# Mach calls for the helper's client.
SYSTEM_LIBDIR = /usr/lib/system
ADDITIONAL_LDFLAGS += -L$(SYSTEM_LIBDIR) -Wl,-rpath,$(SYSTEM_LIBDIR)
UsersLogin_GUI_LIBS += -llaunch -lsystem_kernel

include $(GNUSTEP_MAKEFILES)/application.make

# Installed under its real name, replacing an earlier install of either.
INSTALL_NAME = Users & Login
include ../Shared/InstallName.make
