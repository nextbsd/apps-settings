# Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause
#
# Printers.app: the printers (the local cupsd's queues) with their status
# and waiting jobs, adding nearby driverless printers or one by address,
# removing them, the default printer, and paper size and two-sided
# printing (nextbsd/nextbsd#640). It talks to cupsd through libcups
# (Apple's CUPS 2.3.4, from nextbsd-printing-support, in /usr/lib and
# /usr/include/cups). Adding and removing go through SettingsHelper's
# CUPSAdmin (nextbsd-userland src/SettingsHelper), whose client is
# ../Frameworks/NBSettings.
#
# It ships with the optional printing package rather than the desktop's
# core; for now it installs like the other desktop apps, in the USER
# domain (~/Applications).

ifeq ($(GNUSTEP_MAKEFILES),)
 GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES)
endif
include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = Printers
Printers_OBJC_FILES = main.m PRController.m PRAddPanel.m PRCups.m
Printers_HEADER_FILES = PRController.h PRAddPanel.h PRCups.h
Printers_RESOURCE_FILES = Resources/Printers.png
Printers_APPLICATION_ICON = Printers.png
Printers_OBJCFLAGS = -Wall -Wextra -Wno-unused-parameter
Printers_SUBPROJECTS = ../Frameworks/NBSettings
Printers_INCLUDE_DIRS = -I../Frameworks/NBSettings

# NextBSD's system libraries live in /usr/lib/system: liblaunch and the
# Mach calls for the helper's client. libcups is in /usr/lib.
SYSTEM_LIBDIR = /usr/lib/system
ADDITIONAL_LDFLAGS += -L$(SYSTEM_LIBDIR) -Wl,-rpath,$(SYSTEM_LIBDIR)
Printers_GUI_LIBS += -lcups -llaunch -lsystem_kernel

include $(GNUSTEP_MAKEFILES)/application.make
