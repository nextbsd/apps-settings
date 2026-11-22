/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * WCRecorder: video recordings, as Motion JPEG in an AVI file, made
 * with the system's libjpeg. Base's ffmpeg has no video encoders (its
 * libavcodec is built for playback), so this is what NextBSD can write
 * today; ffmpeg, VLC and browsers' players read it. Which codec and
 * container recordings should use is E44's nextbsd/nextbsd#660; another
 * one goes behind this same interface.
 *
 * Frames are written as they come, each a JPEG; the frame rate in the
 * header is the one they came at on average, filled in when the
 * recording ends. There's no sound yet.
 */

#ifndef _WC_RECORDER_H_
#define _WC_RECORDER_H_

#include <stddef.h>
#include "WCCapture.h"

/* The file name extension recordings take. */
#define WCRecorderExtension "avi"

typedef struct WCRecorder WCRecorder;

/* Starts a recording at path, a new file, of width x height frames.
   NULL with why in error. */
WCRecorder *WCRecorderStart (const char *path, int width, int height,
                             char *error, size_t errorSize);

/* Adds a frame (one of another size than the recording's is left
   out). 0, or -1 with why in error; the recording is still to be
   finished. */
int WCRecorderAdd (WCRecorder *recorder, const WCFrame *frame,
                   char *error, size_t errorSize);

/* Seconds recorded so far. */
double WCRecorderSeconds (WCRecorder *recorder);

/* Bytes written so far. */
long long WCRecorderBytes (WCRecorder *recorder);

/* Writes the index and header and closes the file. 0, or -1 with why
   in error. Frees the recorder either way. */
int WCRecorderFinish (WCRecorder *recorder, char *error, size_t errorSize);

/* The first frame of a recording made here, for the strip: 0, or -1. */
int WCRecorderReadFirstFrame (const char *path, int scale, WCFrame *frame);

#endif /* _WC_RECORDER_H_ */
