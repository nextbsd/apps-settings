# Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause
#
# Network.app: the network services and their TCP/IP and DNS settings,
# Wi-Fi, and the computer's name (nextbsd/nextbsd#638). It reads configd
# (SCPreferences and SCDynamicStore) as the user, changes services and
# names through SettingsHelper (nextbsd-userland src/SettingsHelper),
# whose client is ../Frameworks/NBSettings, and joins Wi-Fi networks
# through wland (org.nextbsd.wlan). Installed like the other desktop
# apps, in the USER domain (~/Applications) for now.
#
# wland's MIG client stubs aren't installed for apps, so the build makes
# them from mig/wlan.defs and mig/wlan_mig_types.h, copied unchanged from
# nextbsd-userland's src/WLAN (39073bb). Copy both again when wlan.defs
# grows; message ids never move, so an older copy keeps working with a
# newer wland.

ifeq ($(GNUSTEP_MAKEFILES),)
 GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES)
endif
include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = Network
Network_OBJC_FILES = main.m NWController.m NWJoinPanel.m NBDockExtra.m
Network_HEADER_FILES = NWController.h NWJoinPanel.h NWSystem.h NWWiFi.h
Network_RESOURCE_FILES = Resources/Network.png
Network_APPLICATION_ICON = Network.png
Network_OBJCFLAGS = -Wall -Wextra -Wno-unused-parameter
Network_SUBPROJECTS = ../Frameworks/NBSettings
# Shared/: the "Show Wi-Fi status in Dock" checkbox's side of the Dock's
# extras (NBDockExtra).
Network_INCLUDE_DIRS = -I../Frameworks/NBSettings -I../Shared
vpath NBDockExtra.m ../Shared

# NWSystem.c and NWWiFi.c use NextBSD's CoreFoundation,
# SystemConfiguration and Mach headers, so they're compiled without
# GNUstep's header paths, whose CoreFoundation (gnustep-corebase) would be
# found first, as the Dock extras' are (apps-dock
# Extras/Common/SystemC.make). Their objects, and wland's MIG stub, are
# linked into the app.
MIG ?= mig
MIG_DIR = obj/mig
SYSTEM_DIR = obj/system
SYSTEM_CFLAGS = -fPIC -fblocks -O2 -g -Wall -Wno-macro-redefined \
	-I$(MIG_DIR) -Imig -I.
SYSTEM_OBJS = $(SYSTEM_DIR)/NWSystem.o $(SYSTEM_DIR)/NWWiFi.o \
	$(SYSTEM_DIR)/wlanUser.o
Network_OBJ_FILES += $(SYSTEM_OBJS)

# NextBSD's system libraries live in /usr/lib/system: SystemConfiguration
# and CoreFoundation for NWSystem.c, and liblaunch and the Mach calls for
# wland's and the helper's clients.
SYSTEM_LIBDIR = /usr/lib/system
ADDITIONAL_LDFLAGS += -L$(SYSTEM_LIBDIR) -Wl,-rpath,$(SYSTEM_LIBDIR)
Network_GUI_LIBS += -lSystemConfiguration -lCoreFoundation -llaunch \
	-lsystem_kernel -lsystem_dispatch -lsystem_blocks

include $(GNUSTEP_MAKEFILES)/application.make

$(MIG_DIR)/wlanUser.c $(MIG_DIR)/wlanUser.h: mig/wlan.defs \
		mig/wlan_mig_types.h
	@mkdir -p $(MIG_DIR)
	cd $(MIG_DIR) && $(MIG) -I$(CURDIR)/mig \
		-header wlanUser.h -user wlanUser.c \
		-server /dev/null -sheader /dev/null $(CURDIR)/mig/wlan.defs

$(SYSTEM_DIR)/NWSystem.o: NWSystem.c NWSystem.h
	@mkdir -p $(SYSTEM_DIR)
	$(CC) $(SYSTEM_CFLAGS) -c $< -o $@

$(SYSTEM_DIR)/NWWiFi.o: NWWiFi.c NWWiFi.h $(MIG_DIR)/wlanUser.h
	@mkdir -p $(SYSTEM_DIR)
	$(CC) $(SYSTEM_CFLAGS) -c $< -o $@

# MIG's output isn't -Wall clean.
$(SYSTEM_DIR)/wlanUser.o: $(MIG_DIR)/wlanUser.c
	@mkdir -p $(SYSTEM_DIR)
	$(CC) $(SYSTEM_CFLAGS) -w -c $< -o $@

before-all:: $(SYSTEM_OBJS)

after-clean::
	rm -rf $(MIG_DIR) $(SYSTEM_DIR)
