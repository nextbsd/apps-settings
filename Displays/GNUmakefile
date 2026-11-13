# Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause
#
# Displays.app: the display's "looks like" size (HiDPI scaling), set
# through NextBSD's WindowServer. Installed in the SYSTEM domain's
# applications, /System/Applications on NextBSD.

ifeq ($(GNUSTEP_MAKEFILES),)
 GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES)
endif
include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = Displays
Displays_OBJC_FILES = main.m DSController.m DSDisplayConnection.m
Displays_HEADER_FILES = DSController.h DSDisplayConnection.h
Displays_RESOURCE_FILES = Resources/Displays.png
Displays_APPLICATION_ICON = Displays.png
Displays_OBJCFLAGS = -Wall -Wextra -Wno-unused-parameter

# WindowServer's client library (apps-windowserver).
ADDITIONAL_OBJCFLAGS += $(shell pkg-config --cflags WindowServerClient 2>/dev/null)
Displays_GUI_LIBS += $(shell pkg-config --libs WindowServerClient 2>/dev/null || echo -lWindowServerClient)

include $(GNUSTEP_MAKEFILES)/application.make
