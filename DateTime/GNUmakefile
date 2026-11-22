# Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause
#
# Date & Time.app: network time and the time server, the date and time by
# hand, the time zone, and the Dock clock's format (nextbsd/nextbsd#634).
# Root's changes go through SettingsHelper (nextbsd-userland
# src/SettingsHelper), whose client is ../Frameworks/NBSettings.
# Installed like the other desktop apps, in the USER domain
# (~/Applications) for now.
#
# It's built as DateTime.app: gnustep-make names its variables after the
# app (DateTime_OBJC_FILES), so the name can't hold a space or "&". It's
# installed as "Date & Time.app", the name people see in the File
# Viewer, the Dock and the menu (DateTimeInfo.plist), as on macOS.

ifeq ($(GNUSTEP_MAKEFILES),)
 GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES)
endif
include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = DateTime
DateTime_OBJC_FILES = main.m DTController.m DTZones.m
DateTime_C_FILES = DTSystem.c
DateTime_HEADER_FILES = DTController.h DTZones.h DTSystem.h
DateTime_RESOURCE_FILES = Resources/DateTime.png
DateTime_APPLICATION_ICON = DateTime.png
DateTime_OBJCFLAGS = -Wall -Wextra -Wno-unused-parameter
DateTime_CFLAGS = -Wall -Wextra
DateTime_SUBPROJECTS = ../Frameworks/NBSettings
DateTime_INCLUDE_DIRS = -I../Frameworks/NBSettings

# NextBSD's system libraries live in /usr/lib/system: liblaunch and the
# Mach calls for the helper's client.
SYSTEM_LIBDIR = /usr/lib/system
ADDITIONAL_LDFLAGS += -L$(SYSTEM_LIBDIR) -Wl,-rpath,$(SYSTEM_LIBDIR)
DateTime_GUI_LIBS += -llaunch -lsystem_kernel

include $(GNUSTEP_MAKEFILES)/application.make

# Installed under its real name, replacing an earlier install of either.
INSTALL_NAME = Date & Time
include ../Shared/InstallName.make
