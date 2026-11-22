/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * WCImage: pictures in and out of packed RGB (WCFrame), with the
 * system's libjpeg and libpng: a camera's YUYV and MJPEG, photos written
 * as PNG or JPEG, JPEG frames for recordings, and small copies for the
 * strip of recent captures.
 */

#ifndef _WC_IMAGE_H_
#define _WC_IMAGE_H_

#include <stddef.h>
#include "WCCapture.h"

/* Makes room in frame for width x height (frame->rgb is malloc'd and
   kept while big enough). 0, or -1 out of memory. */
int WCFrameAlloc (WCFrame *frame, int width, int height);
void WCFrameFree (WCFrame *frame);

/* to = from, turned left to right; to is allocated as needed. */
int WCFrameMirror (const WCFrame *from, WCFrame *to);

/* to = from scaled down to fit within maxWidth x maxHeight (averaging),
   allocated as needed. */
int WCFrameShrink (const WCFrame *from, int maxWidth, int maxHeight,
                   WCFrame *to);

/* YUYV 4:2:2, bytesPerLine apart, into frame (allocated). */
int WCImageFromYUYV (const unsigned char *yuyv, size_t length,
                     int width, int height, size_t bytesPerLine,
                     WCFrame *frame);

/* A JPEG (an MJPEG frame: its Huffman tables may be left out, and
   libjpeg-turbo puts in the standard ones) into frame (allocated).
   scale 1, 2, 4 or 8 decodes at 1/scale size, for small copies. 0, or
   -1 if it isn't a JPEG it can read. */
int WCImageFromJPEG (const unsigned char *jpeg, size_t length, int scale,
                     WCFrame *frame);

/* frame as a JPEG in memory, *jpeg malloc'd; the caller frees it. */
int WCImageToJPEG (const WCFrame *frame, int quality, unsigned char **jpeg,
                   size_t *length);

/* Writes frame to path, made anew. 0, or -1 with errno or why in
   error. */
int WCImageWritePNG (const WCFrame *frame, const char *path, char *error,
                     size_t errorSize);
int WCImageWriteJPEG (const WCFrame *frame, int quality, const char *path,
                      char *error, size_t errorSize);

/* Reads a PNG or JPEG file into frame (allocated), at least minWidth
   wide where it can (JPEGs are decoded scaled down). 0, or -1. */
int WCImageRead (const char *path, int minWidth, WCFrame *frame);

#endif /* _WC_IMAGE_H_ */
