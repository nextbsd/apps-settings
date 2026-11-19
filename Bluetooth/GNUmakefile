# Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause
#
# Bluetooth.app: Bluetooth on or off, the paired and nearby devices,
# pairing, and each headset's audio, through bluetoothd's MIG interface
# (org.nextbsd.bluetooth). Installed like the other desktop apps, in the
# USER domain (~/Applications) for now.
#
# bluetoothd's MIG client stubs aren't installed for apps, so the build
# makes them from mig/bluetooth.defs and mig/bluetooth_mig_types.h,
# copied unchanged from nextbsd-userland's src/Bluetooth (c75f393).
# Copy both again when bluetooth.defs grows; message ids never move, so
# an older copy keeps working with a newer bluetoothd.
#
#   gmake fake_pairing=yes	a test build in which a made-up device asks
#				to pair when BT_FAKE_PAIRING=1..5 is set
#				(BTClient.c); never installed

ifeq ($(GNUSTEP_MAKEFILES),)
 GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES)
endif
include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = Bluetooth
Bluetooth_OBJC_FILES = main.m BTController.m BTDevice.m BTPairingPanel.m
Bluetooth_HEADER_FILES = BTController.h BTDevice.h BTPairingPanel.h BTClient.h
Bluetooth_RESOURCE_FILES = Resources/Bluetooth.png
Bluetooth_APPLICATION_ICON = Bluetooth.png
Bluetooth_OBJCFLAGS = -Wall -Wextra -Wno-unused-parameter

# BTClient.c and the MIG stubs use Mach, notify(3), CoreFoundation and
# SystemConfiguration, so they're compiled without GNUstep's header
# paths, whose CoreFoundation (gnustep-corebase) would be found first,
# as the Dock extras' are (apps-dock Extras/Common/SystemC.make). Their
# objects are linked into the app.
MIG ?= mig
MIG_DIR = obj/mig
SYSTEM_DIR = obj/system
SYSTEM_CFLAGS = -fPIC -fblocks -O2 -g -Wall -Wno-macro-redefined \
	-I$(MIG_DIR) -Imig -I.
ifeq ($(fake_pairing),yes)
SYSTEM_CFLAGS += -DBT_FAKE_PAIRING
endif
SYSTEM_OBJS = $(SYSTEM_DIR)/BTClient.o $(SYSTEM_DIR)/bluetoothUser.o
Bluetooth_OBJ_FILES += $(SYSTEM_OBJS)

# NextBSD's system libraries live in /usr/lib/system.
SYSTEM_LIBDIR = /usr/lib/system
ADDITIONAL_LDFLAGS += -L$(SYSTEM_LIBDIR) -Wl,-rpath,$(SYSTEM_LIBDIR)
Bluetooth_GUI_LIBS += -lnotify -lSystemConfiguration -lCoreFoundation \
	-llaunch -lsystem_kernel -lsystem_dispatch -lsystem_blocks

include $(GNUSTEP_MAKEFILES)/application.make

$(MIG_DIR)/bluetoothUser.c $(MIG_DIR)/bluetoothUser.h: mig/bluetooth.defs \
		mig/bluetooth_mig_types.h
	@mkdir -p $(MIG_DIR)
	cd $(MIG_DIR) && $(MIG) -I$(CURDIR)/mig \
		-header bluetoothUser.h -user bluetoothUser.c \
		-server /dev/null -sheader /dev/null $(CURDIR)/mig/bluetooth.defs

$(SYSTEM_DIR)/BTClient.o: BTClient.c BTClient.h $(MIG_DIR)/bluetoothUser.h
	@mkdir -p $(SYSTEM_DIR)
	$(CC) $(SYSTEM_CFLAGS) -c $< -o $@

# MIG's output isn't -Wall clean.
$(SYSTEM_DIR)/bluetoothUser.o: $(MIG_DIR)/bluetoothUser.c
	@mkdir -p $(SYSTEM_DIR)
	$(CC) $(SYSTEM_CFLAGS) -w -c $< -o $@

before-all:: $(SYSTEM_OBJS)

after-clean::
	rm -rf $(MIG_DIR) $(SYSTEM_DIR)
