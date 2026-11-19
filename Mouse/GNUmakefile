# Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause
#
# Mouse.app: tracking speed, pointer acceleration, left or right
# handed, natural scrolling and scroll speed, set through NextBSD's
# WindowServer and saved in the user's org.nextbsd.WindowServer
# defaults, and double-click speed (GNUstep's GSDoubleClickTime).
# Installed like the other desktop apps, in the USER domain
# (~/Applications) for now.

ifeq ($(GNUSTEP_MAKEFILES),)
 GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES)
endif
include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = Mouse
Mouse_OBJC_FILES = main.m MSController.m MSSettings.m
Mouse_HEADER_FILES = MSController.h MSSettings.h
Mouse_RESOURCE_FILES = Resources/Mouse.png
Mouse_APPLICATION_ICON = Mouse.png
Mouse_OBJCFLAGS = -Wall -Wextra -Wno-unused-parameter

# WindowServer's client library (apps-windowserver).
ADDITIONAL_OBJCFLAGS += $(shell pkg-config --cflags WindowServerClient 2>/dev/null)
Mouse_GUI_LIBS += $(shell pkg-config --libs WindowServerClient 2>/dev/null || echo -lWindowServerClient)

include $(GNUSTEP_MAKEFILES)/application.make
