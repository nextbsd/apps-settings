# Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause
#
# NextBSD's settings apps. Each subdirectory is one app, built and
# installed on its own; this file builds them all.

ifeq ($(GNUSTEP_MAKEFILES),)
 GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES)
endif
include $(GNUSTEP_MAKEFILES)/common.make

SUBPROJECTS =

include $(GNUSTEP_MAKEFILES)/aggregate.make
