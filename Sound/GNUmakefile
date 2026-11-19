# Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause
#
# Sound.app: the output and input devices (kernel pcm devices and
# Bluetooth headsets), the output volume and mute, the input volume and
# level, and the alert sound. Installed like the other desktop apps, in
# the USER domain (~/Applications) for now.
#
# A headset's name, volume and microphone come from bluetoothd, whose
# MIG client stubs aren't installed for apps: the build makes them from
# mig/bluetooth.defs and mig/bluetooth_mig_types.h, copied unchanged from
# nextbsd-userland's src/Bluetooth (c75f393), as Bluetooth/ does.
# virtual_oss's control ioctls are in the system's <virtual_oss.h>.

ifeq ($(GNUSTEP_MAKEFILES),)
 GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES)
endif
include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = Sound
Sound_OBJC_FILES = main.m SNController.m SNLevelView.m SNDockExtra.m
Sound_HEADER_FILES = SNController.h SNLevelView.h SNDockExtra.h SNAudio.h
Sound_RESOURCE_FILES = Resources/Sound.png
Sound_APPLICATION_ICON = Sound.png
Sound_OBJCFLAGS = -Wall -Wextra -Wno-unused-parameter

# SNAudio.c and the MIG stubs use Mach and notify(3), so they're
# compiled without GNUstep's header paths, as Bluetooth/'s BTClient.c
# is. Their objects are linked into the app.
MIG ?= mig
MIG_DIR = obj/mig
SYSTEM_DIR = obj/system
SYSTEM_CFLAGS = -fPIC -fblocks -O2 -g -Wall -Wno-macro-redefined \
	-I$(MIG_DIR) -Imig -I.
SYSTEM_OBJS = $(SYSTEM_DIR)/SNAudio.o $(SYSTEM_DIR)/bluetoothUser.o
Sound_OBJ_FILES += $(SYSTEM_OBJS)

# NextBSD's system libraries live in /usr/lib/system.
SYSTEM_LIBDIR = /usr/lib/system
ADDITIONAL_LDFLAGS += -L$(SYSTEM_LIBDIR) -Wl,-rpath,$(SYSTEM_LIBDIR)
Sound_GUI_LIBS += -lnotify -llaunch -lsystem_kernel -lsystem_dispatch \
	-lsystem_blocks -lm

include $(GNUSTEP_MAKEFILES)/application.make

$(MIG_DIR)/bluetoothUser.c $(MIG_DIR)/bluetoothUser.h: mig/bluetooth.defs \
		mig/bluetooth_mig_types.h
	@mkdir -p $(MIG_DIR)
	cd $(MIG_DIR) && $(MIG) -I$(CURDIR)/mig \
		-header bluetoothUser.h -user bluetoothUser.c \
		-server /dev/null -sheader /dev/null $(CURDIR)/mig/bluetooth.defs

$(SYSTEM_DIR)/SNAudio.o: SNAudio.c SNAudio.h $(MIG_DIR)/bluetoothUser.h
	@mkdir -p $(SYSTEM_DIR)
	$(CC) $(SYSTEM_CFLAGS) -c $< -o $@

# MIG's output isn't -Wall clean.
$(SYSTEM_DIR)/bluetoothUser.o: $(MIG_DIR)/bluetoothUser.c
	@mkdir -p $(SYSTEM_DIR)
	$(CC) $(SYSTEM_CFLAGS) -w -c $< -o $@

before-all:: $(SYSTEM_OBJS)

after-clean::
	rm -rf $(MIG_DIR) $(SYSTEM_DIR)
