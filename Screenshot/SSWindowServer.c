/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#include "SSWindowServer.h"

#include <errno.h>
#include <stdlib.h>
#include <string.h>

#include <WindowServer/WSClient.h>

/* How long to wait for a picture, in milliseconds. A trusted app isn't
   asked; a copy elsewhere waits for the user's answer. */
#define SSCaptureTimeout 60000

static ws_connection_t *SSConnection;

static uint32_t SSStream;
static SSFrameFunction SSFrame;
static SSEndedFunction SSEnded;
static void *SSContext;

/* The stream's buffers' sizes (WS_EVENT_CAPTURE_BUFFER). */
#define SSMaxBuffers 8
static struct
{
  uint32_t generation;
  int width;
  int height;
} SSBuffers[SSMaxBuffers];

int
SSWSOpen (void)
{
  if (SSConnection != NULL)
    return 0;
  SSConnection = ws_connect ("Screenshot", WS_CONNECT_CONTROL);
  if (SSConnection == NULL)
    return -1;
  if ((ws_server_flags (SSConnection) & WS_SERVER_CAPTURE) == 0)
    {
      ws_disconnect (SSConnection);
      SSConnection = NULL;
      errno = ENOTSUP;
      return -1;
    }
  return 0;
}

void
SSWSClose (void)
{
  SSWSStreamStop ();
  if (SSConnection != NULL)
    ws_disconnect (SSConnection);
  SSConnection = NULL;
}

/* A request failed because WindowServer went away (it restarted): the
   next one connects again. */
static void
SSCheckLost (void)
{
  if (errno == EPIPE || errno == ECONNRESET || errno == ENOTCONN
      || errno == EBADF)
    {
      int e = errno;

      SSStream = 0;
      ws_disconnect (SSConnection);
      SSConnection = NULL;
      errno = e;
    }
}

int
SSWSCaptureImage (uint32_t window, int withPointer, SSImage *out)
{
  ws_snapshot_t snap;
  int y;

  memset (out, 0, sizeof (*out));
  if (SSWSOpen () < 0)
    return -1;
  if (ws_capture_image (SSConnection, window,
                        withPointer ? WS_CAPTURE_CURSOR : 0,
                        SSCaptureTimeout, &snap) < 0)
    {
      SSCheckLost ();
      return -1;
    }
  out->width = (int) snap.width;
  out->height = (int) snap.height;
  out->stride = (int) snap.width * 4;
  out->pixels = malloc ((size_t) out->stride * out->height);
  if (out->pixels == NULL)
    {
      ws_snapshot_free (&snap);
      errno = ENOMEM;
      return -1;
    }
  for (y = 0; y < out->height; y++)
    memcpy (out->pixels + (size_t) y * out->stride,
            (const unsigned char *) snap.pixels + (size_t) y * snap.stride,
            (size_t) out->stride);
  ws_snapshot_free (&snap);
  return 0;
}

void
SSImageFree (SSImage *image)
{
  free (image->pixels);
  memset (image, 0, sizeof (*image));
}

typedef struct
{
  SSWindowInfo *list;
  int count;
  int capacity;
} SSWindowList;

static void
SSCollectWindow (const ws_event_window_info_t *info, void *context)
{
  SSWindowList *l = context;
  SSWindowInfo *w;

  if ((info->flags & WS_WINDOW_INFO_VISIBLE) == 0)
    return;
  if (l->count == l->capacity)
    {
      int capacity = l->capacity > 0 ? l->capacity * 2 : 32;
      SSWindowInfo *list = realloc (l->list, capacity * sizeof (*list));

      if (list == NULL)
        return;
      l->list = list;
      l->capacity = capacity;
    }
  w = &l->list[l->count++];
  memset (w, 0, sizeof (*w));
  w->window = info->window;
  w->pid = info->pid;
  w->level = info->level;
  w->x = info->frame.x;
  w->y = info->frame.y;
  w->width = (int) info->frame.width;
  w->height = (int) info->frame.height;
  memcpy (w->app, info->app_name, sizeof (w->app) - 1);
  memcpy (w->title, info->title, sizeof (w->title) - 1);
}

int
SSWSListWindows (SSWindowInfo **out, int *count)
{
  SSWindowList l = { NULL, 0, 0 };
  int i;

  *out = NULL;
  *count = 0;
  if (SSWSOpen () < 0)
    return -1;
  if (ws_list_windows (SSConnection, SSCollectWindow, &l) < 0)
    {
      SSCheckLost ();
      free (l.list);
      return -1;
    }
  /* Listed bottom to top: front first. */
  for (i = 0; i < l.count / 2; i++)
    {
      SSWindowInfo t = l.list[i];

      l.list[i] = l.list[l.count - 1 - i];
      l.list[l.count - 1 - i] = t;
    }
  *out = l.list;
  *count = l.count;
  return 0;
}

int
SSWSStreamStart (int withPointer, int fps, SSFrameFunction frame,
                 SSEndedFunction ended, void *context)
{
  if (SSWSOpen () < 0)
    return -1;
  SSWSStreamStop ();
  SSFrame = frame;
  SSEnded = ended;
  SSContext = context;
  memset (SSBuffers, 0, sizeof (SSBuffers));
  SSStream = ws_capture_start (SSConnection, 0,
                               withPointer ? WS_CAPTURE_CURSOR : 0, 0, 0,
                               (uint32_t) fps, NULL);
  if (SSStream == 0)
    {
      SSCheckLost ();
      return -1;
    }
  return 0;
}

void
SSWSStreamStop (void)
{
  if (SSStream != 0 && SSConnection != NULL)
    {
      (void) ws_capture_stop (SSConnection, SSStream);
      (void) ws_sync (SSConnection);
    }
  SSStream = 0;
  SSFrame = NULL;
  SSEnded = NULL;
  SSContext = NULL;
}

int
SSWSFileDescriptor (void)
{
  return SSConnection != NULL ? ws_connection_fd (SSConnection) : -1;
}

static void
SSHandleEvent (ws_connection_t *conn, const ws_event_t *ev, void *ctx)
{
  const ws_event_capture_frame_t *f;
  const unsigned char *pixels;
  uint32_t stride;

  (void) ctx;
  switch (ev->hdr.type)
    {
    case WS_EVENT_CAPTURE_FRAME:
      f = &ev->u.capture_frame;
      if (f->stream != SSStream || SSStream == 0)
        {
          (void) ws_capture_release (conn, f);
          break;
        }
      pixels = ws_capture_frame_data (conn, f, &stride);
      if (pixels != NULL && SSFrame != NULL && f->index < SSMaxBuffers
          && SSBuffers[f->index].generation == f->generation)
        SSFrame (pixels, (int) stride, SSBuffers[f->index].width,
                 SSBuffers[f->index].height, SSContext);
      (void) ws_capture_release (conn, f);
      break;
    case WS_EVENT_CAPTURE_BUFFER:
      /* Each buffer's size, for the frames that use it. */
      if (ev->u.capture_buffer.stream == SSStream
          && ev->u.capture_buffer.index < SSMaxBuffers)
        {
          SSBuffers[ev->u.capture_buffer.index].generation =
            ev->u.capture_buffer.generation;
          SSBuffers[ev->u.capture_buffer.index].width =
            (int) ev->u.capture_buffer.width;
          SSBuffers[ev->u.capture_buffer.index].height =
            (int) ev->u.capture_buffer.height;
        }
      break;
    case WS_EVENT_CAPTURE_STATE:
      if (ev->u.capture_state.stream == SSStream
          && (ev->u.capture_state.state == WS_CAPTURE_DENIED
              || ev->u.capture_state.state == WS_CAPTURE_STOPPED))
        {
          SSEndedFunction ended = SSEnded;
          void *context = SSContext;

          SSStream = 0;
          SSFrame = NULL;
          SSEnded = NULL;
          if (ended != NULL)
            ended (ev->u.capture_state.error, context);
        }
      break;
    default:
      break;
    }
}

void
SSWSDispatch (void)
{
  if (SSConnection == NULL)
    return;
  if (ws_dispatch (SSConnection, SSHandleEvent, NULL) < 0)
    {
      SSEndedFunction ended = SSEnded;
      void *context = SSContext;

      SSCheckLost ();
      if (SSConnection == NULL && ended != NULL)
        {
          SSStream = 0;
          SSFrame = NULL;
          SSEnded = NULL;
          ended (EPIPE, context);
        }
    }
}
