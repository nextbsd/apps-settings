# Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause
#
# Keyboard.app: input layouts and switching, key repeat and modifier
# keys, set through NextBSD's WindowServer and kept in the user's
# org.nextbsd.WindowServer defaults. Installed like the other desktop
# apps, in the USER domain (~/Applications) for now.
#
# InputMenu/ is the Dock's Input menu, Input.dockextra, built and
# installed with the app (into ~/Library/DockExtras).

ifeq ($(GNUSTEP_MAKEFILES),)
 GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES)
endif
include $(GNUSTEP_MAKEFILES)/common.make

SUBPROJECTS = InputMenu

APP_NAME = Keyboard
Keyboard_OBJC_FILES = main.m KBController.m KBConnection.m \
	KBXkbRegistry.m KBSourcePicker.m
Keyboard_HEADER_FILES = KBController.h KBConnection.h KBXkbRegistry.h \
	KBSourcePicker.h KBShared.h
Keyboard_RESOURCE_FILES = Resources/Keyboard.png
Keyboard_APPLICATION_ICON = Keyboard.png
Keyboard_OBJCFLAGS = -Wall -Wextra -Wno-unused-parameter

# WindowServer's client library (apps-windowserver).
ADDITIONAL_OBJCFLAGS += $(shell pkg-config --cflags WindowServerClient 2>/dev/null)
Keyboard_GUI_LIBS += $(shell pkg-config --libs WindowServerClient 2>/dev/null || echo -lWindowServerClient)

# notify(3), from NextBSD's system libraries.
SYSTEM_LIBDIR = /usr/lib/system
ADDITIONAL_LDFLAGS += -L$(SYSTEM_LIBDIR) -Wl,-rpath,$(SYSTEM_LIBDIR)
Keyboard_GUI_LIBS += -lnotify

include $(GNUSTEP_MAKEFILES)/aggregate.make
include $(GNUSTEP_MAKEFILES)/application.make
