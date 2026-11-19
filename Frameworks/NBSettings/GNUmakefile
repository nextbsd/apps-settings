# Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause
#
# NBSettings: what the settings apps share (nextbsd/nextbsd#627). For
# now only the privileged helper's client (nextbsd/nextbsd#628):
#
#   NBAuthorization        a hold on a right, org.nextbsd.settings.<area>
#   NBAuthorizationPanel   the lock (NBLockView) and the prompt
#   NBSettingsHelper       the helper's operations
#   NBHelperClient         their C side, over the MIG stubs
#
# It's a gnustep-make subproject compiled into each app that lists it
# (xxx_SUBPROJECTS = ../Frameworks/NBSettings), so nothing more is
# installed; #627 turns it into the framework.
#
# The helper's MIG client stubs are made from mig/settingshelper.defs and
# mig/settingshelper_types.h, copied unchanged from nextbsd-userland's
# src/SettingsHelper. Copy both again when an operation is added; message
# ids never move, so an older copy keeps working with a newer helper.

ifeq ($(GNUSTEP_MAKEFILES),)
 GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES)
endif
include $(GNUSTEP_MAKEFILES)/common.make

SUBPROJECT_NAME = NBSettings
NBSettings_OBJC_FILES = NBAuthorization.m NBAuthorizationPanel.m \
	NBSettingsHelper.m
NBSettings_HEADER_FILES = NBAuthorization.h NBAuthorizationPanel.h \
	NBSettingsHelper.h NBHelperClient.h
NBSettings_OBJCFLAGS = -Wall -Wextra -Wno-unused-parameter -Imig

# NBHelperClient.c and the MIG stub are plain C on Mach, compiled apart
# from GNUstep's flags as Bluetooth.app's client is; their objects go into
# the subproject.
MIG ?= mig
MIG_DIR = obj/mig
SYSTEM_DIR = obj/system
SYSTEM_CFLAGS = -fPIC -O2 -g -Wall -Wno-macro-redefined -I$(MIG_DIR) -Imig -I.
SYSTEM_OBJS = $(SYSTEM_DIR)/NBHelperClient.o $(SYSTEM_DIR)/settingshelperUser.o
NBSettings_OBJ_FILES += $(SYSTEM_OBJS)

include $(GNUSTEP_MAKEFILES)/subproject.make

$(MIG_DIR)/settingshelperUser.c $(MIG_DIR)/settingshelperUser.h: \
		mig/settingshelper.defs mig/settingshelper_types.h
	@mkdir -p $(MIG_DIR)
	cd $(MIG_DIR) && $(MIG) -I$(CURDIR)/mig \
		-header settingshelperUser.h -user settingshelperUser.c \
		-server /dev/null -sheader /dev/null \
		$(CURDIR)/mig/settingshelper.defs

$(SYSTEM_DIR)/NBHelperClient.o: NBHelperClient.c NBHelperClient.h \
		$(MIG_DIR)/settingshelperUser.h
	@mkdir -p $(SYSTEM_DIR)
	$(CC) $(SYSTEM_CFLAGS) -c $< -o $@

# MIG's output isn't -Wall clean.
$(SYSTEM_DIR)/settingshelperUser.o: $(MIG_DIR)/settingshelperUser.c
	@mkdir -p $(SYSTEM_DIR)
	$(CC) $(SYSTEM_CFLAGS) -w -c $< -o $@

before-all:: $(SYSTEM_OBJS)

after-clean::
	rm -rf $(MIG_DIR) $(SYSTEM_DIR)
