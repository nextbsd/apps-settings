# Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause
#
# Trackpad.app: tap to click, tap and drag, three-finger drag, secondary
# click, tracking speed, natural and momentum scrolling, scroll speed,
# set through NextBSD's WindowServer and saved in the user's
# org.nextbsd.WindowServer defaults. Installed like the other desktop
# apps, in the USER domain (~/Applications) for now.

ifeq ($(GNUSTEP_MAKEFILES),)
 GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES)
endif
include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = Trackpad
Trackpad_OBJC_FILES = main.m TPController.m TPSettings.m
Trackpad_HEADER_FILES = TPController.h TPSettings.h
Trackpad_RESOURCE_FILES = Resources/Trackpad.png
Trackpad_APPLICATION_ICON = Trackpad.png
Trackpad_OBJCFLAGS = -Wall -Wextra -Wno-unused-parameter

# WindowServer's client library (apps-windowserver).
ADDITIONAL_OBJCFLAGS += $(shell pkg-config --cflags WindowServerClient 2>/dev/null)
Trackpad_GUI_LIBS += $(shell pkg-config --libs WindowServerClient 2>/dev/null || echo -lWindowServerClient)

include $(GNUSTEP_MAKEFILES)/application.make
