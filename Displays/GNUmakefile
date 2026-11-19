# Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause
#
# Displays.app: every display's arrangement, "looks like" size,
# resolution and refresh rate, mirroring, and Night Shift, set through
# NextBSD's WindowServer. Installed like the other desktop apps, in the
# USER domain (~/Applications) for now.
#
#   gmake fake_displays=yes	a test build that shows made-up displays
#				when DS_FAKE_DISPLAYS=1..3 is set
#				(DSFakeDisplays.h); never installed

ifeq ($(GNUSTEP_MAKEFILES),)
 GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES)
endif
include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = Displays
Displays_OBJC_FILES = main.m DSController.m DSDisplayConnection.m \
	DSDisplay.m DSArrangementView.m DSConfirmPanel.m DSFakeDisplays.m
Displays_HEADER_FILES = DSController.h DSDisplayConnection.h DSDisplay.h \
	DSArrangementView.h DSConfirmPanel.h DSFakeDisplays.h
Displays_RESOURCE_FILES = Resources/Displays.png
Displays_APPLICATION_ICON = Displays.png
Displays_OBJCFLAGS = -Wall -Wextra -Wno-unused-parameter

ifeq ($(fake_displays),yes)
Displays_OBJCFLAGS += -DDS_FAKE_DISPLAYS
endif

# WindowServer's client library (apps-windowserver).
ADDITIONAL_OBJCFLAGS += $(shell pkg-config --cflags WindowServerClient 2>/dev/null)
Displays_GUI_LIBS += $(shell pkg-config --libs WindowServerClient 2>/dev/null || echo -lWindowServerClient)

include $(GNUSTEP_MAKEFILES)/application.make
