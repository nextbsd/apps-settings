/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * SSRecorder: screen recordings, as QuickTime movies (.mov) of MPEG-4
 * Part 2 video and, with a microphone, AAC sound, made by the ffmpeg
 * that ships with NextBSD (nextbsd-gnustep-support: its own LGPL
 * encoders and the mov muxer, nextbsd/nextbsd#715).
 *
 * The frames come from WindowServer's capture stream only when the
 * screen changes, and ffmpeg is fed raw BGRA frames through a pipe at
 * a constant rate: a thread writes the newest frame every 1/fps of a
 * second, repeating it while nothing changes, so the movie's time is
 * the wall clock's. The microphone (an OSS device, /dev/dspN) is
 * ffmpeg's second input and runs on the same clock, so picture and
 * sound stay together within a frame or two. ffmpeg's messages go to
 * ~/Library/Logs/Screenshot.log.
 */

#ifndef _SS_RECORDER_H_
#define _SS_RECORDER_H_

#include <stddef.h>

typedef struct SSRecorder SSRecorder;

/* The movie's frame rate. */
#define SSRecorderFPS 30

/* Starts ffmpeg writing path, a new .mov file, width x height pixels
   (both even), with sound from microphone (an OSS device path) or
   none (NULL). log is where ffmpeg's messages go (appended), or NULL.
   NULL with why in error. */
SSRecorder *SSRecorderStart (const char *path, int width, int height,
                             const char *microphone, const char *log,
                             char *error, size_t errorSize);

/* A new picture: the recording's width x height pixels at x, y of
   pixels (XRGB8888, stride bytes a row), copied at once. */
void SSRecorderFrame (SSRecorder *recorder, const unsigned char *pixels,
                      int stride, int x, int y);

/* Seconds recorded so far. */
double SSRecorderSeconds (SSRecorder *recorder);

/* Ends the recording: the last frame, then ffmpeg finishes the file.
   Waits for it (seconds at most); call it off the main thread. 0, or
   -1 with why in error. Frees the recorder either way. */
int SSRecorderFinish (SSRecorder *recorder, char *error, size_t errorSize);

/* The microphones: OSS recording devices from /dev/sndstat, as
   "/dev/dspN" paths and their descriptions, at most max of them.
   Returns how many. */
int SSRecorderMicrophones (char paths[][32], char names[][96], int max);

#endif /* _SS_RECORDER_H_ */
