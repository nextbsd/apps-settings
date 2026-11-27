/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * SSWindowServer: what Screenshot asks of WindowServer, through its
 * client library, on a tool connection of its own (the app's windows
 * are the backend's). Pictures of the screen or of a window, the
 * window list (to pick a window), and the stream a recording is made
 * from. WindowServer trusts Screenshot.app where it's installed
 * (/System/Applications/Screenshot.app, its CaptureTrustedApps), so
 * none of these asks the user for consent; a copy anywhere else asks
 * like any app, the first time.
 *
 * Pictures and frames are XRGB8888 (B, G, R, x in memory) in pixels,
 * the screen's backing pixels; frames and the window list are in
 * WindowServer's coordinates: points, from the top left of the main
 * display.
 */

#ifndef _SS_WINDOWSERVER_H_
#define _SS_WINDOWSERVER_H_

#include <stddef.h>
#include <stdint.h>

typedef struct
{
  int width;
  int height;
  int stride;			/* bytes a row */
  unsigned char *pixels;	/* malloc'd; SSImageFree */
} SSImage;

typedef struct
{
  uint32_t window;
  int pid;
  int level;
  int x, y, width, height;	/* points, top-left origin */
  char app[32];
  char title[64];
} SSWindowInfo;

/* Connects if needed. 0, or -1 with errno set. */
int SSWSOpen (void);
void SSWSClose (void);

/* One picture of the screen (window 0) or of a window. 0, or -1 with
   errno (EPERM: refused). */
int SSWSCaptureImage (uint32_t window, int withPointer, SSImage *out);
void SSImageFree (SSImage *image);

/* The windows on screen, front to back. *out is malloc'd. 0, or -1. */
int SSWSListWindows (SSWindowInfo **out, int *count);

/* A stream of the screen for a recording, at most fps frames a second.
   Then poll SSWSFileDescriptor() and call SSWSDispatch(), which calls
   frame() with each new frame's pixels (valid during the call only)
   and ended() if the stream ends (stopped from outside, or refused).
   0, or -1 with errno. */
typedef void (*SSFrameFunction) (const unsigned char *pixels, int stride,
                                 int width, int height, void *context);
typedef void (*SSEndedFunction) (int error, void *context);

int SSWSStreamStart (int withPointer, int fps, SSFrameFunction frame,
                     SSEndedFunction ended, void *context);
void SSWSStreamStop (void);
int SSWSFileDescriptor (void);
void SSWSDispatch (void);

#endif /* _SS_WINDOWSERVER_H_ */
