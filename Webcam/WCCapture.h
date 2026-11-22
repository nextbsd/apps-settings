/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * WCCapture: the cameras and their pictures, as a plain C interface the
 * app sees instead of any one capture API. A backend lists its cameras
 * and, once one is opened, hands back frames as packed 8-bit RGB. There
 * are two:
 *
 *   - V4L2 (WCCaptureV4L2.c): USB (UVC) webcams, as FreeBSD's webcamd
 *     makes them, /dev/videoN through cuse. mmap capture, YUYV or MJPEG,
 *     turned into RGB here;
 *   - the test pattern (WCCaptureTestPattern.c): colour bars, a moving
 *     ball and the time, listed only when no camera is, so the app can
 *     be used and tested without one.
 *
 * The camera broker of E44 (nextbsd/nextbsd#658) is to be a third
 * backend: a launchd daemon owns the cameras, asks the user before an
 * app may use one and shows that it's on, and hands the frames over
 * Mach. When it exists, the broker lists the cameras and the V4L2 code
 * moves into it, so apps no longer open /dev/video* themselves; only
 * WCCapture.c's backend table and this file's WCCameraBroker change.
 *
 * Nothing here blocks: WCCaptureRead says whether a new frame is in, and
 * the app asks for one on a timer.
 */

#ifndef _WC_CAPTURE_H_
#define _WC_CAPTURE_H_

#include <stddef.h>

#define WCCaptureMaxCameras 16

/* Where a camera's pictures come from. */
#define WCCameraV4L2 0
#define WCCameraTestPattern 1
/* #define WCCameraBroker 2	   E44's camera broker, to come */

typedef struct
{
  int backend;			/* WCCamera* */
  char ident[64];		/* "/dev/video0", "testpattern": unique */
  char name[128];		/* "Logitech Webcam C925e" */
  int mirror;			/* shown as a mirror by default */
} WCCameraInfo;

/* A picture: rgb is width * height pixels of R, G, B, stride bytes
   apart. The memory is the capture's or the caller's, as said. */
typedef struct
{
  int width;
  int height;
  size_t stride;
  unsigned char *rgb;
  size_t capacity;		/* bytes malloc'd at rgb (WCFrameAlloc) */
} WCFrame;

typedef struct WCCapture WCCapture;

/* Every camera of every backend, up to max; the test pattern alone if
   there's none. Returns how many. */
int WCCaptureListCameras (WCCameraInfo *cameras, int max);

/* Starts the camera. NULL on failure, with why in error. */
WCCapture *WCCaptureOpen (const WCCameraInfo *camera, char *error,
                          size_t errorSize);

/* 1: a new frame is in frame, its memory the capture's until the next
   read or the close; 0: none yet; -1: the camera is gone or failing,
   with why in error. */
int WCCaptureRead (WCCapture *capture, WCFrame *frame, char *error,
                   size_t errorSize);

/* What it delivers, for the window: "MJPEG 1280×720". */
const char *WCCaptureDescription (WCCapture *capture);

void WCCaptureClose (WCCapture *capture);

/* ---- for the backends ---- */

typedef struct
{
  int (*list) (WCCameraInfo *cameras, int max);
  WCCapture *(*open) (const WCCameraInfo *camera, char *error,
                      size_t errorSize);
  int (*read) (WCCapture *capture, WCFrame *frame, char *error,
               size_t errorSize);
  void (*close) (WCCapture *capture);
} WCCaptureBackend;

/* Each backend's capture starts with this. */
struct WCCapture
{
  const WCCaptureBackend *backend;
  char description[64];
};

extern const WCCaptureBackend WCCaptureV4L2Backend;
extern const WCCaptureBackend WCCaptureTestPatternBackend;

#endif /* _WC_CAPTURE_H_ */
