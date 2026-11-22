# Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause
#
# Webcam.app: the camera's live view, photos and video recordings, as
# macOS's Photo Booth. Installed like the other desktop apps, in the
# USER domain (~/Applications) for now.
#
# Pictures come through WCCapture (WCCapture.h): V4L2 for USB webcams,
# and a test pattern when there's no camera. Photos are written with
# libpng and libjpeg, and recordings are MJPEG in AVI with libjpeg; all
# three are in base. NextBSD has no <linux/videodev2.h> yet, so WCV4L2.h
# carries the part of V4L2 the app uses.

ifeq ($(GNUSTEP_MAKEFILES),)
 GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES)
endif
include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = Webcam
Webcam_OBJC_FILES = main.m WCController.m WCPreviewView.m WCShutterButton.m \
	WCStripView.m
Webcam_C_FILES = WCCapture.c WCCaptureV4L2.c WCCaptureTestPattern.c \
	WCImage.c WCRecorder.c
Webcam_HEADER_FILES = WCController.h WCPreviewView.h WCShutterButton.h \
	WCStripView.h WCCapture.h WCV4L2.h WCImage.h WCRecorder.h
Webcam_RESOURCE_FILES = Resources/Webcam.png
Webcam_APPLICATION_ICON = Webcam.png
Webcam_OBJCFLAGS = -Wall -Wextra -Wno-unused-parameter
Webcam_CFLAGS = -Wall -Wextra -Wno-unused-parameter
Webcam_GUI_LIBS += -lpng16 -ljpeg

include $(GNUSTEP_MAKEFILES)/application.make
