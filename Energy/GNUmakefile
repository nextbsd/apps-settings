# Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause
#
# Energy.app: when the display and the computer sleep, on battery and on
# the power adapter, wake for network access, and the battery's charge
# and condition (nextbsd/nextbsd#636). It reads powerd's settings through
# libIOKit and changes them through SettingsHelper (nextbsd-userland
# src/SettingsHelper), whose client is ../Frameworks/NBSettings.
# Installed like the other desktop apps, in the USER domain
# (~/Applications) for now.

ifeq ($(GNUSTEP_MAKEFILES),)
 GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES)
endif
include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = Energy
Energy_OBJC_FILES = main.m ENController.m
Energy_HEADER_FILES = ENController.h ENPower.h
Energy_RESOURCE_FILES = Resources/Energy.png
Energy_APPLICATION_ICON = Energy.png
Energy_OBJCFLAGS = -Wall -Wextra -Wno-unused-parameter
Energy_SUBPROJECTS = ../Frameworks/NBSettings
Energy_INCLUDE_DIRS = -I../Frameworks/NBSettings

# ENPower.c uses NextBSD's CoreFoundation and IOKit headers, so it's
# compiled without GNUstep's header paths, whose CoreFoundation
# (gnustep-corebase) would be found first, as the Dock extras' sources
# are (apps-dock Extras/Common/SystemC.make). Its object is linked in.
SYSTEM_DIR = obj/system
SYSTEM_OBJS = $(SYSTEM_DIR)/ENPower.o
Energy_OBJ_FILES += $(SYSTEM_OBJS)

# NextBSD's system libraries live in /usr/lib/system: IOKit and
# CoreFoundation for ENPower.c, notify(3) for its notifications, and
# liblaunch and the Mach calls for the helper's client.
SYSTEM_LIBDIR = /usr/lib/system
ADDITIONAL_LDFLAGS += -L$(SYSTEM_LIBDIR) -Wl,-rpath,$(SYSTEM_LIBDIR)
Energy_GUI_LIBS += -lIOKit -lCoreFoundation -lnotify -llaunch \
	-lsystem_kernel -lsystem_dispatch -lsystem_blocks

include $(GNUSTEP_MAKEFILES)/application.make

$(SYSTEM_DIR)/ENPower.o: ENPower.c ENPower.h
	@mkdir -p $(SYSTEM_DIR)
	$(CC) -fPIC -fblocks -O2 -g -Wall -c $< -o $@

before-all:: $(SYSTEM_OBJS)

after-clean::
	rm -rf $(SYSTEM_DIR)
