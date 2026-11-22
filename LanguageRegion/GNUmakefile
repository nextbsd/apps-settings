# Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause
#
# Language & Region.app: the preferred languages, the region and its
# formats, and the system's language (nextbsd/nextbsd#652). The system's
# language goes through SettingsHelper (nextbsd-userland
# src/SettingsHelper), whose client is ../Frameworks/NBSettings.
# Installed like the other desktop apps, in the USER domain
# (~/Applications) for now.
#
# It's built as LanguageRegion.app: gnustep-make names its variables
# after the app (LanguageRegion_OBJC_FILES), so the name can't hold a
# space or "&". It's installed as "Language & Region.app", the name
# people see in the File Viewer, the Dock and the menu
# (LanguageRegionInfo.plist), as on macOS.

ifeq ($(GNUSTEP_MAKEFILES),)
 GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES)
endif
include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = LanguageRegion
LanguageRegion_OBJC_FILES = main.m LRController.m LRLocales.m \
	LRLanguagePicker.m
LanguageRegion_C_FILES = LRLoginConf.c
LanguageRegion_HEADER_FILES = LRController.h LRLocales.h LRLanguagePicker.h \
	LRLoginConf.h
LanguageRegion_RESOURCE_FILES = Resources/LanguageRegion.png
LanguageRegion_APPLICATION_ICON = LanguageRegion.png
LanguageRegion_OBJCFLAGS = -Wall -Wextra -Wno-unused-parameter
LanguageRegion_CFLAGS = -Wall -Wextra
LanguageRegion_SUBPROJECTS = ../Frameworks/NBSettings
LanguageRegion_INCLUDE_DIRS = -I../Frameworks/NBSettings

# NextBSD's system libraries live in /usr/lib/system: liblaunch and the
# Mach calls for the helper's client. libutil reads login.conf.
SYSTEM_LIBDIR = /usr/lib/system
ADDITIONAL_LDFLAGS += -L$(SYSTEM_LIBDIR) -Wl,-rpath,$(SYSTEM_LIBDIR)
LanguageRegion_GUI_LIBS += -llaunch -lsystem_kernel -lutil

include $(GNUSTEP_MAKEFILES)/application.make

# Installed under its real name, replacing an earlier install of either.
INSTALLED_APPS = $(DESTDIR)$(GNUSTEP_APPS)
after-install::
	rm -rf "$(INSTALLED_APPS)/Language & Region.app"
	mv "$(INSTALLED_APPS)/LanguageRegion.app" "$(INSTALLED_APPS)/Language & Region.app"

after-uninstall::
	rm -rf "$(INSTALLED_APPS)/Language & Region.app"
