/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#include "WCCapture.h"

#include <stdio.h>

/* By WCCamera*. E44's broker goes here when it exists, and takes the
   V4L2 cameras over. */
static const WCCaptureBackend *const WCBackends[] = {
  &WCCaptureV4L2Backend,
  &WCCaptureTestPatternBackend,
};

#define WCBackendCount ((int) (sizeof (WCBackends) / sizeof (WCBackends[0])))

int
WCCaptureListCameras (WCCameraInfo *cameras, int max)
{
  int count;

  count = WCCaptureV4L2Backend.list (cameras, max);
  if (count == 0)
    count = WCCaptureTestPatternBackend.list (cameras, max);
  return count;
}

WCCapture *
WCCaptureOpen (const WCCameraInfo *camera, char *error, size_t errorSize)
{
  if (camera->backend < 0 || camera->backend >= WCBackendCount)
    {
      snprintf (error, errorSize, "No such camera");
      return NULL;
    }
  return WCBackends[camera->backend]->open (camera, error, errorSize);
}

int
WCCaptureRead (WCCapture *capture, WCFrame *frame, char *error,
               size_t errorSize)
{
  return capture->backend->read (capture, frame, error, errorSize);
}

const char *
WCCaptureDescription (WCCapture *capture)
{
  return capture->description;
}

void
WCCaptureClose (WCCapture *capture)
{
  if (capture != NULL)
    capture->backend->close (capture);
}
