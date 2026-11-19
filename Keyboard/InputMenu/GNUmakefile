# Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause
#
# Input.dockextra: the Dock's Input menu. It shows the keyboard layout
# in use (EN, ΕΛ) and switches to another, through WindowServer. Keyboard
# shares its WindowServer connection (../KBConnection.m) and defaults
# (../KBShared.h) with it. Installed in the domain's Library/DockExtras,
# where the Dock looks for extras when it starts.

ifeq ($(GNUSTEP_MAKEFILES),)
 GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES)
endif
include $(GNUSTEP_MAKEFILES)/common.make

BUNDLE_NAME = Input
BUNDLE_EXTENSION = .dockextra
BUNDLE_INSTALL_DIR = $(GNUSTEP_LIBRARY)/DockExtras
Input_PRINCIPAL_CLASS = KBInputMenuExtra
Input_OBJC_FILES = KBInputMenuExtra.m KBConnection.m
Input_INCLUDE_DIRS = -I..
Input_OBJCFLAGS = -Wall -Wextra -Wno-unused-parameter

# KBConnection.m is Keyboard's own.
vpath KBConnection.m ..

ADDITIONAL_OBJCFLAGS += $(shell pkg-config --cflags WindowServerClient 2>/dev/null)
Input_BUNDLE_LIBS += $(shell pkg-config --libs WindowServerClient 2>/dev/null || echo -lWindowServerClient)

include $(GNUSTEP_MAKEFILES)/bundle.make
