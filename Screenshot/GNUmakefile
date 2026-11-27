# Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause
#
# Screenshot.app: pictures and recordings of the screen, as macOS's
# Screenshot (nextbsd/nextbsd#715): the Command+Shift+5 toolbar, and
# what the screenshot keys ask for. Installed with the settings apps in
# /System/Applications, where WindowServer trusts it to capture without
# asking (its CaptureTrustedApps).
#
# It talks to WindowServer through its client library (apps-windowserver)
# and records with the ffmpeg that ships (nextbsd-gnustep-support), run
# as a program, so it links no ffmpeg library.

ifeq ($(GNUSTEP_MAKEFILES),)
 GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES)
endif
include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = Screenshot
Screenshot_OBJC_FILES = main.m SSController.m SSOverlay.m SSToolbar.m \
	SSThumbnail.m
Screenshot_C_FILES = SSWindowServer.c SSRecorder.c
Screenshot_HEADER_FILES = SSController.h SSOverlay.h SSToolbar.h \
	SSThumbnail.h SSWindowServer.h SSRecorder.h SSRequest.h
Screenshot_RESOURCE_FILES = Resources/Screenshot.png
Screenshot_APPLICATION_ICON = Screenshot.png
Screenshot_OBJCFLAGS = -Wall -Wextra -Wno-unused-parameter
Screenshot_CFLAGS = -Wall -Wextra -Wno-unused-parameter

# WindowServer's client library (apps-windowserver).
ADDITIONAL_OBJCFLAGS += $(shell pkg-config --cflags WindowServerClient 2>/dev/null)
ADDITIONAL_CFLAGS += $(shell pkg-config --cflags WindowServerClient 2>/dev/null)
Screenshot_GUI_LIBS += $(shell pkg-config --libs WindowServerClient 2>/dev/null || echo -lWindowServerClient) -lpthread

include $(GNUSTEP_MAKEFILES)/application.make
