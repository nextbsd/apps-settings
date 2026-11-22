/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * The part of the V4L2 interface the V4L2 backend uses. NextBSD has no
 * <linux/videodev2.h> yet (webcamd and its header are E44's
 * nextbsd/nextbsd#657); once one is installed, it's used instead and
 * this file's definitions aren't.
 *
 * These follow V4L2's ABI on a 64-bit machine: the structures' layouts
 * (checked by size below) and the ioctl numbers, which on FreeBSD are
 * made with the system's own _IOR/_IOWR, as webcamd's header makes them;
 * webcamd turns them into Linux's.
 */

#ifndef _WC_V4L2_H_
#define _WC_V4L2_H_

#if __has_include(<linux/videodev2.h>)
#include <linux/videodev2.h>
#else

#include <sys/types.h>
#include <sys/ioccom.h>
#include <sys/time.h>
#include <stdint.h>

#define v4l2_fourcc(a, b, c, d) \
  ((uint32_t) (a) | ((uint32_t) (b) << 8) | ((uint32_t) (c) << 16) \
   | ((uint32_t) (d) << 24))

#define V4L2_PIX_FMT_YUYV v4l2_fourcc ('Y', 'U', 'Y', 'V')
#define V4L2_PIX_FMT_MJPEG v4l2_fourcc ('M', 'J', 'P', 'G')

#define V4L2_CAP_VIDEO_CAPTURE 0x00000001
#define V4L2_CAP_STREAMING 0x04000000
#define V4L2_CAP_DEVICE_CAPS 0x80000000

#define V4L2_BUF_TYPE_VIDEO_CAPTURE 1
#define V4L2_MEMORY_MMAP 1
#define V4L2_FIELD_ANY 0

struct v4l2_capability
{
  uint8_t driver[16];
  uint8_t card[32];
  uint8_t bus_info[32];
  uint32_t version;
  uint32_t capabilities;
  uint32_t device_caps;
  uint32_t reserved[3];
};

struct v4l2_fmtdesc
{
  uint32_t index;
  uint32_t type;
  uint32_t flags;
  uint8_t description[32];
  uint32_t pixelformat;
  uint32_t mbus_code;
  uint32_t reserved[3];
};

struct v4l2_pix_format
{
  uint32_t width;
  uint32_t height;
  uint32_t pixelformat;
  uint32_t field;
  uint32_t bytesperline;
  uint32_t sizeimage;
  uint32_t colorspace;
  uint32_t priv;
  uint32_t flags;
  uint32_t ycbcr_enc;
  uint32_t quantization;
  uint32_t xfer_func;
};

struct v4l2_format
{
  uint32_t type;
  union
  {
    struct v4l2_pix_format pix;
    uint8_t raw_data[200];
    void *align;		/* the other members hold pointers */
  } fmt;
};

struct v4l2_requestbuffers
{
  uint32_t count;
  uint32_t type;
  uint32_t memory;
  uint32_t capabilities;
  uint8_t flags;
  uint8_t reserved[3];
};

struct v4l2_timecode
{
  uint32_t type;
  uint32_t flags;
  uint8_t frames;
  uint8_t seconds;
  uint8_t minutes;
  uint8_t hours;
  uint8_t userbits[4];
};

struct v4l2_buffer
{
  uint32_t index;
  uint32_t type;
  uint32_t bytesused;
  uint32_t flags;
  uint32_t field;
  struct timeval timestamp;
  struct v4l2_timecode timecode;
  uint32_t sequence;
  uint32_t memory;
  union
  {
    uint32_t offset;
    unsigned long userptr;
    void *planes;
    int32_t fd;
  } m;
  uint32_t length;
  uint32_t reserved2;
  union
  {
    int32_t request_fd;
    uint32_t reserved;
  };
};

_Static_assert (sizeof (struct v4l2_capability) == 104, "v4l2_capability");
_Static_assert (sizeof (struct v4l2_fmtdesc) == 64, "v4l2_fmtdesc");
_Static_assert (sizeof (struct v4l2_format) == 208, "v4l2_format");
_Static_assert (sizeof (struct v4l2_requestbuffers) == 20,
                "v4l2_requestbuffers");
_Static_assert (sizeof (struct v4l2_buffer) == 88, "v4l2_buffer");

#define VIDIOC_QUERYCAP _IOR ('V', 0, struct v4l2_capability)
#define VIDIOC_ENUM_FMT _IOWR ('V', 2, struct v4l2_fmtdesc)
#define VIDIOC_G_FMT _IOWR ('V', 4, struct v4l2_format)
#define VIDIOC_S_FMT _IOWR ('V', 5, struct v4l2_format)
#define VIDIOC_REQBUFS _IOWR ('V', 8, struct v4l2_requestbuffers)
#define VIDIOC_QUERYBUF _IOWR ('V', 9, struct v4l2_buffer)
#define VIDIOC_QBUF _IOWR ('V', 15, struct v4l2_buffer)
#define VIDIOC_DQBUF _IOWR ('V', 17, struct v4l2_buffer)
#define VIDIOC_STREAMON _IOW ('V', 18, int)
#define VIDIOC_STREAMOFF _IOW ('V', 19, int)

#endif /* __has_include(<linux/videodev2.h>) */

#endif /* _WC_V4L2_H_ */
