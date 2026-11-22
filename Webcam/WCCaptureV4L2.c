/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * The V4L2 backend: USB (UVC) webcams. On FreeBSD, and NextBSD once it
 * has webcamd (E44's nextbsd/nextbsd#657), webcamd runs Linux's uvcvideo
 * in userspace and makes each camera /dev/videoN through cuse. Frames
 * come by mmap streaming: a few buffers queued to the driver, and each
 * one dequeued when full, read and queued again. The camera's MJPEG is
 * preferred, since it reaches 720p and more over USB 2; otherwise YUYV.
 *
 * Who may open /dev/videoN is up to webcamd's -U/-G/-m (root only by
 * default). With E44's camera broker this moves into the broker, which
 * alone opens the devices.
 */

#include "WCCapture.h"
#include "WCImage.h"
#include "WCV4L2.h"

#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/stat.h>

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define WCV4L2MaxDevices 64	/* /dev/video0 .. 63 */
#define WCV4L2Buffers 4
#define WCV4L2Width 1280	/* asked for; the driver picks the nearest */
#define WCV4L2Height 720

typedef struct
{
  void *start;
  size_t length;
} WCV4L2Buffer;

typedef struct
{
  WCCapture capture;
  int fd;
  uint32_t pixelformat;
  int width;
  int height;
  size_t bytesPerLine;
  WCV4L2Buffer buffers[WCV4L2Buffers];
  int bufferCount;
  int streaming;
  WCFrame frame;
} WCV4L2;

/* An ioctl, again when interrupted. */
static int
WCIoctl (int fd, unsigned long request, void *arg)
{
  int r;

  do
    r = ioctl (fd, request, arg);
  while (r == -1 && errno == EINTR);
  return r;
}

static void
WCCopyName (char *to, size_t size, const uint8_t *from, size_t fromSize)
{
  size_t n = strnlen ((const char *) from, fromSize);

  if (n >= size)
    n = size - 1;
  memcpy (to, from, n);
  to[n] = '\0';
}

/* A device that captures video by streaming, and its name. */
static int
WCV4L2Query (int fd, struct v4l2_capability *cap)
{
  uint32_t caps;

  memset (cap, 0, sizeof (*cap));
  if (WCIoctl (fd, VIDIOC_QUERYCAP, cap) != 0)
    return -1;
  /* A driver may make several nodes for one camera (metadata too);
     device_caps says what this one does. */
  caps = (cap->capabilities & V4L2_CAP_DEVICE_CAPS) != 0
    ? cap->device_caps : cap->capabilities;
  if ((caps & V4L2_CAP_VIDEO_CAPTURE) == 0
      || (caps & V4L2_CAP_STREAMING) == 0)
    {
      errno = ENODEV;
      return -1;
    }
  return 0;
}

/* Fills in camera for the device at path: 0, or -1 if it isn't one to
   list. */
static int
WCV4L2Probe (const char *path, WCCameraInfo *camera)
{
  struct v4l2_capability cap;
  int fd, usable;

  memset (camera, 0, sizeof (*camera));
  camera->backend = WCCameraV4L2;
  camera->mirror = 1;
  snprintf (camera->ident, sizeof (camera->ident), "%s", path);

  /* One that's in use, or not ours to open, is still listed, by its
     path, so choosing it says why. Any other failure is a device that's
     going or gone. */
  fd = open (path, O_RDWR | O_NONBLOCK | O_CLOEXEC);
  if (fd < 0)
    {
      if (errno != EACCES && errno != EPERM && errno != EBUSY)
        return -1;
      snprintf (camera->name, sizeof (camera->name), "%s", path);
      return 0;
    }
  usable = WCV4L2Query (fd, &cap) == 0;
  close (fd);
  if (!usable)
    return -1;
  WCCopyName (camera->name, sizeof (camera->name), cap.card,
              sizeof (cap.card));
  if (camera->name[0] == '\0')
    snprintf (camera->name, sizeof (camera->name), "%s", path);
  return 0;
}

/* A device node, as stat(2) sees it: a change means a camera came, went
   or changed hands. */
typedef struct
{
  int n;
  dev_t rdev;
  mode_t mode;
  uid_t uid;
  gid_t gid;
} WCV4L2Node;

/* The app lists the cameras every few seconds to see them come and go.
   Opening each one to ask its name could disturb one that's streaming
   (and wakes a sleeping USB device), so the devices are only asked
   again when the nodes in /dev change. */
static WCV4L2Node WCLastNodes[WCV4L2MaxDevices];
static int WCLastNodeCount = -1;
static WCCameraInfo WCLastCameras[WCV4L2MaxDevices];
static int WCLastCameraCount;

static int
WCV4L2List (WCCameraInfo *cameras, int max)
{
  WCV4L2Node nodes[WCV4L2MaxDevices];
  int nodeCount = 0, count = 0, n;

  memset (nodes, 0, sizeof (nodes));
  for (n = 0; n < WCV4L2MaxDevices; n++)
    {
      char path[32];
      struct stat st;

      snprintf (path, sizeof (path), "/dev/video%d", n);
      if (stat (path, &st) != 0 || !S_ISCHR (st.st_mode))
        continue;
      nodes[nodeCount].n = n;
      nodes[nodeCount].rdev = st.st_rdev;
      nodes[nodeCount].mode = st.st_mode;
      nodes[nodeCount].uid = st.st_uid;
      nodes[nodeCount].gid = st.st_gid;
      nodeCount++;
    }

  if (nodeCount != WCLastNodeCount
      || memcmp (nodes, WCLastNodes, sizeof (nodes[0]) * (size_t) nodeCount)
      != 0)
    {
      WCLastCameraCount = 0;
      for (n = 0; n < nodeCount; n++)
        {
          char path[32];

          snprintf (path, sizeof (path), "/dev/video%d", nodes[n].n);
          if (WCV4L2Probe (path, &WCLastCameras[WCLastCameraCount]) == 0)
            WCLastCameraCount++;
        }
      memcpy (WCLastNodes, nodes, sizeof (nodes));
      WCLastNodeCount = nodeCount;
    }

  for (n = 0; n < WCLastCameraCount && count < max; n++)
    cameras[count++] = WCLastCameras[n];
  return count;
}

static const char *
WCV4L2FormatName (uint32_t pixelformat)
{
  return pixelformat == V4L2_PIX_FMT_MJPEG ? "MJPEG" : "YUYV";
}

/* MJPEG if the camera has it, else YUYV, else none (0). */
static uint32_t
WCV4L2ChooseFormat (int fd)
{
  struct v4l2_fmtdesc desc;
  int haveYUYV = 0;

  memset (&desc, 0, sizeof (desc));
  desc.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
  for (desc.index = 0; WCIoctl (fd, VIDIOC_ENUM_FMT, &desc) == 0;
       desc.index++)
    {
      if (desc.pixelformat == V4L2_PIX_FMT_MJPEG)
        return V4L2_PIX_FMT_MJPEG;
      if (desc.pixelformat == V4L2_PIX_FMT_YUYV)
        haveYUYV = 1;
    }
  return haveYUYV ? V4L2_PIX_FMT_YUYV : 0;
}

static void
WCV4L2Close (WCCapture *capture)
{
  WCV4L2 *v = (WCV4L2 *) capture;
  int type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
  int i;

  if (v->streaming)
    (void) WCIoctl (v->fd, VIDIOC_STREAMOFF, &type);
  for (i = 0; i < v->bufferCount; i++)
    munmap (v->buffers[i].start, v->buffers[i].length);
  if (v->fd >= 0)
    close (v->fd);
  WCFrameFree (&v->frame);
  free (v);
}

/* Says why in error, closes v and returns NULL. */
static WCCapture *
WCV4L2Fail (WCV4L2 *v, const char *what, char *error, size_t errorSize)
{
  snprintf (error, errorSize, "%s: %s", what, strerror (errno));
  WCV4L2Close (&v->capture);
  return NULL;
}

static WCCapture *
WCV4L2Open (const WCCameraInfo *camera, char *error, size_t errorSize)
{
  WCV4L2 *v = calloc (1, sizeof (*v));
  struct v4l2_capability cap;
  struct v4l2_format format;
  struct v4l2_requestbuffers request;
  int type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
  int i;

  if (v == NULL)
    {
      snprintf (error, errorSize, "Out of memory");
      return NULL;
    }
  v->capture.backend = &WCCaptureV4L2Backend;
  v->fd = open (camera->ident, O_RDWR | O_NONBLOCK | O_CLOEXEC);
  if (v->fd < 0)
    return WCV4L2Fail (v, camera->ident, error, errorSize);
  if (WCV4L2Query (v->fd, &cap) != 0)
    return WCV4L2Fail (v, "Not a camera that streams video", error,
                       errorSize);

  v->pixelformat = WCV4L2ChooseFormat (v->fd);
  if (v->pixelformat == 0)
    {
      snprintf (error, errorSize,
                "The camera sends neither MJPEG nor YUYV");
      WCV4L2Close (&v->capture);
      return NULL;
    }
  memset (&format, 0, sizeof (format));
  format.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
  format.fmt.pix.width = WCV4L2Width;
  format.fmt.pix.height = WCV4L2Height;
  format.fmt.pix.pixelformat = v->pixelformat;
  format.fmt.pix.field = V4L2_FIELD_ANY;
  if (WCIoctl (v->fd, VIDIOC_S_FMT, &format) != 0)
    return WCV4L2Fail (v, "Setting the format", error, errorSize);
  /* What the driver chose, which may be another size, or format. */
  if (format.fmt.pix.pixelformat != V4L2_PIX_FMT_MJPEG
      && format.fmt.pix.pixelformat != V4L2_PIX_FMT_YUYV)
    {
      snprintf (error, errorSize,
                "The camera sends neither MJPEG nor YUYV");
      WCV4L2Close (&v->capture);
      return NULL;
    }
  v->pixelformat = format.fmt.pix.pixelformat;
  v->width = (int) format.fmt.pix.width;
  v->height = (int) format.fmt.pix.height;
  v->bytesPerLine = format.fmt.pix.bytesperline;
  snprintf (v->capture.description, sizeof (v->capture.description),
            "%s %d×%d", WCV4L2FormatName (v->pixelformat), v->width,
            v->height);

  memset (&request, 0, sizeof (request));
  request.count = WCV4L2Buffers;
  request.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
  request.memory = V4L2_MEMORY_MMAP;
  if (WCIoctl (v->fd, VIDIOC_REQBUFS, &request) != 0)
    return WCV4L2Fail (v, "Asking for buffers", error, errorSize);
  if (request.count < 2)
    {
      errno = ENOMEM;
      return WCV4L2Fail (v, "Asking for buffers", error, errorSize);
    }
  for (i = 0; i < (int) request.count && i < WCV4L2Buffers; i++)
    {
      struct v4l2_buffer buffer;
      void *start;

      memset (&buffer, 0, sizeof (buffer));
      buffer.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
      buffer.memory = V4L2_MEMORY_MMAP;
      buffer.index = (uint32_t) i;
      if (WCIoctl (v->fd, VIDIOC_QUERYBUF, &buffer) != 0)
        return WCV4L2Fail (v, "Finding a buffer", error, errorSize);
      start = mmap (NULL, buffer.length, PROT_READ | PROT_WRITE, MAP_SHARED,
                    v->fd, (off_t) buffer.m.offset);
      if (start == MAP_FAILED)
        return WCV4L2Fail (v, "Mapping a buffer", error, errorSize);
      v->buffers[i].start = start;
      v->buffers[i].length = buffer.length;
      v->bufferCount = i + 1;
      if (WCIoctl (v->fd, VIDIOC_QBUF, &buffer) != 0)
        return WCV4L2Fail (v, "Queueing a buffer", error, errorSize);
    }
  if (WCIoctl (v->fd, VIDIOC_STREAMON, &type) != 0)
    return WCV4L2Fail (v, "Starting the camera", error, errorSize);
  v->streaming = 1;
  return &v->capture;
}

static int
WCV4L2Read (WCCapture *capture, WCFrame *frame, char *error,
            size_t errorSize)
{
  WCV4L2 *v = (WCV4L2 *) capture;
  struct v4l2_buffer buffer;
  const unsigned char *data;
  int decoded;

  memset (&buffer, 0, sizeof (buffer));
  buffer.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
  buffer.memory = V4L2_MEMORY_MMAP;
  if (WCIoctl (v->fd, VIDIOC_DQBUF, &buffer) != 0)
    {
      if (errno == EAGAIN)
        return 0;
      snprintf (error, errorSize, "The camera stopped: %s",
                strerror (errno));
      return -1;
    }
  if (buffer.index >= (uint32_t) v->bufferCount)
    {
      snprintf (error, errorSize, "The camera sent a buffer it hasn't got");
      return -1;
    }
  data = v->buffers[buffer.index].start;
  if (buffer.bytesused > v->buffers[buffer.index].length)
    buffer.bytesused = (uint32_t) v->buffers[buffer.index].length;
  if (v->pixelformat == V4L2_PIX_FMT_MJPEG)
    decoded = WCImageFromJPEG (data, buffer.bytesused, 1, &v->frame);
  else
    decoded = WCImageFromYUYV (data, buffer.bytesused, v->width, v->height,
                               v->bytesPerLine, &v->frame);
  if (WCIoctl (v->fd, VIDIOC_QBUF, &buffer) != 0)
    {
      snprintf (error, errorSize, "The camera stopped: %s",
                strerror (errno));
      return -1;
    }
  /* A frame that didn't decode (a bad MJPEG, a short one) is skipped. */
  if (decoded != 0)
    return 0;
  *frame = v->frame;
  frame->capacity = 0;
  return 1;
}

const WCCaptureBackend WCCaptureV4L2Backend = {
  WCV4L2List,
  WCV4L2Open,
  WCV4L2Read,
  WCV4L2Close,
};
