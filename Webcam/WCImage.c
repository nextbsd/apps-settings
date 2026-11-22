/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#include "WCImage.h"

#include <errno.h>
#include <fcntl.h>
#include <setjmp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <jpeglib.h>
#include <png.h>

int
WCFrameAlloc (WCFrame *frame, int width, int height)
{
  size_t stride = (size_t) width * 3;
  size_t need = stride * (size_t) height;

  if (width <= 0 || height <= 0)
    return -1;
  if (need > frame->capacity || frame->rgb == NULL)
    {
      unsigned char *rgb = realloc (frame->capacity > 0 ? frame->rgb : NULL,
                                    need);

      if (rgb == NULL)
        return -1;
      frame->rgb = rgb;
      frame->capacity = need;
    }
  frame->width = width;
  frame->height = height;
  frame->stride = stride;
  return 0;
}

void
WCFrameFree (WCFrame *frame)
{
  if (frame->capacity > 0)
    free (frame->rgb);
  memset (frame, 0, sizeof (*frame));
}

int
WCFrameMirror (const WCFrame *from, WCFrame *to)
{
  int x, y;

  if (WCFrameAlloc (to, from->width, from->height) != 0)
    return -1;
  for (y = 0; y < from->height; y++)
    {
      const unsigned char *s = from->rgb + (size_t) y * from->stride;
      unsigned char *d = to->rgb + (size_t) y * to->stride
        + (size_t) (from->width - 1) * 3;

      for (x = 0; x < from->width; x++, s += 3, d -= 3)
        {
          d[0] = s[0];
          d[1] = s[1];
          d[2] = s[2];
        }
    }
  return 0;
}

int
WCFrameShrink (const WCFrame *from, int maxWidth, int maxHeight, WCFrame *to)
{
  int width = from->width, height = from->height;
  int x, y;

  /* Keep the shape. */
  if (width > maxWidth)
    {
      height = (int) ((long) height * maxWidth / width);
      width = maxWidth;
    }
  if (height > maxHeight)
    {
      width = (int) ((long) width * maxHeight / height);
      height = maxHeight;
    }
  if (width < 1)
    width = 1;
  if (height < 1)
    height = 1;
  if (WCFrameAlloc (to, width, height) != 0)
    return -1;

  /* Each pixel is the average of the ones it covers. */
  for (y = 0; y < height; y++)
    {
      int y0 = (int) ((long) y * from->height / height);
      int y1 = (int) ((long) (y + 1) * from->height / height);

      if (y1 <= y0)
        y1 = y0 + 1;
      for (x = 0; x < width; x++)
        {
          int x0 = (int) ((long) x * from->width / width);
          int x1 = (int) ((long) (x + 1) * from->width / width);
          unsigned long sum[3] = { 0, 0, 0 };
          unsigned long n;
          int sx, sy;
          unsigned char *d = to->rgb + (size_t) y * to->stride
            + (size_t) x * 3;

          if (x1 <= x0)
            x1 = x0 + 1;
          for (sy = y0; sy < y1; sy++)
            {
              const unsigned char *s = from->rgb + (size_t) sy * from->stride
                + (size_t) x0 * 3;

              for (sx = x0; sx < x1; sx++, s += 3)
                {
                  sum[0] += s[0];
                  sum[1] += s[1];
                  sum[2] += s[2];
                }
            }
          n = (unsigned long) (x1 - x0) * (unsigned long) (y1 - y0);
          d[0] = (unsigned char) (sum[0] / n);
          d[1] = (unsigned char) (sum[1] / n);
          d[2] = (unsigned char) (sum[2] / n);
        }
    }
  return 0;
}

static unsigned char
WCClamp (int v)
{
  return v < 0 ? 0 : (v > 255 ? 255 : (unsigned char) v);
}

/* ITU-R BT.601, video range, as UVC cameras send it. */
int
WCImageFromYUYV (const unsigned char *yuyv, size_t length, int width,
                 int height, size_t bytesPerLine, WCFrame *frame)
{
  int x, y;

  if (bytesPerLine < (size_t) width * 2)
    bytesPerLine = (size_t) width * 2;
  if (length < bytesPerLine * (size_t) height
      || WCFrameAlloc (frame, width, height) != 0)
    return -1;
  for (y = 0; y < height; y++)
    {
      const unsigned char *s = yuyv + (size_t) y * bytesPerLine;
      unsigned char *d = frame->rgb + (size_t) y * frame->stride;

      for (x = 0; x + 1 < width; x += 2, s += 4)
        {
          int u = s[1] - 128, v = s[3] - 128;
          int r = 409 * v + 128;
          int g = -100 * u - 208 * v + 128;
          int b = 516 * u + 128;
          int i;

          for (i = 0; i < 2; i++)
            {
              int c = 298 * (s[i * 2] - 16);

              *d++ = WCClamp ((c + r) >> 8);
              *d++ = WCClamp ((c + g) >> 8);
              *d++ = WCClamp ((c + b) >> 8);
            }
        }
    }
  return 0;
}

/* libjpeg's errors come back here instead of exiting. */
typedef struct
{
  struct jpeg_error_mgr mgr;
  jmp_buf jump;
  char message[JMSG_LENGTH_MAX];
} WCJPEGError;

static void
WCJPEGErrorExit (j_common_ptr cinfo)
{
  WCJPEGError *error = (WCJPEGError *) cinfo->err;

  (*cinfo->err->format_message) (cinfo, error->message);
  longjmp (error->jump, 1);
}

/* Corrupt-data warnings are usual for webcams' MJPEG; say nothing. */
static void
WCJPEGQuiet (j_common_ptr cinfo, int level)
{
}

static int
WCJPEGDecode (struct jpeg_decompress_struct *cinfo, int scale, WCFrame *frame)
{
  JSAMPROW row;

  (void) jpeg_read_header (cinfo, TRUE);
  cinfo->out_color_space = JCS_RGB;
  cinfo->scale_num = 1;
  cinfo->scale_denom = (unsigned int) (scale > 0 ? scale : 1);
  jpeg_start_decompress (cinfo);
  if (cinfo->output_components != 3
      || WCFrameAlloc (frame, (int) cinfo->output_width,
                       (int) cinfo->output_height) != 0)
    {
      jpeg_abort_decompress (cinfo);
      return -1;
    }
  while (cinfo->output_scanline < cinfo->output_height)
    {
      row = frame->rgb + (size_t) cinfo->output_scanline * frame->stride;
      (void) jpeg_read_scanlines (cinfo, &row, 1);
    }
  jpeg_finish_decompress (cinfo);
  return 0;
}

int
WCImageFromJPEG (const unsigned char *jpeg, size_t length, int scale,
                 WCFrame *frame)
{
  struct jpeg_decompress_struct cinfo;
  WCJPEGError error;
  int result;

  if (length < 4 || jpeg[0] != 0xff || jpeg[1] != 0xd8)
    return -1;
  cinfo.err = jpeg_std_error (&error.mgr);
  error.mgr.error_exit = WCJPEGErrorExit;
  error.mgr.emit_message = WCJPEGQuiet;
  if (setjmp (error.jump))
    {
      jpeg_destroy_decompress (&cinfo);
      return -1;
    }
  jpeg_create_decompress (&cinfo);
  jpeg_mem_src (&cinfo, jpeg, (unsigned long) length);
  result = WCJPEGDecode (&cinfo, scale, frame);
  jpeg_destroy_decompress (&cinfo);
  return result;
}

static void
WCJPEGEncode (struct jpeg_compress_struct *cinfo, const WCFrame *frame,
              int quality)
{
  JSAMPROW row;

  cinfo->image_width = (JDIMENSION) frame->width;
  cinfo->image_height = (JDIMENSION) frame->height;
  cinfo->input_components = 3;
  cinfo->in_color_space = JCS_RGB;
  jpeg_set_defaults (cinfo);
  jpeg_set_quality (cinfo, quality, TRUE);
  jpeg_start_compress (cinfo, TRUE);
  while (cinfo->next_scanline < cinfo->image_height)
    {
      row = frame->rgb + (size_t) cinfo->next_scanline * frame->stride;
      (void) jpeg_write_scanlines (cinfo, &row, 1);
    }
  jpeg_finish_compress (cinfo);
}

int
WCImageToJPEG (const WCFrame *frame, int quality, unsigned char **jpeg,
               size_t *length)
{
  struct jpeg_compress_struct cinfo;
  WCJPEGError error;
  unsigned char *buffer = NULL;
  unsigned long size = 0;

  cinfo.err = jpeg_std_error (&error.mgr);
  error.mgr.error_exit = WCJPEGErrorExit;
  if (setjmp (error.jump))
    {
      jpeg_destroy_compress (&cinfo);
      free (buffer);
      return -1;
    }
  jpeg_create_compress (&cinfo);
  jpeg_mem_dest (&cinfo, &buffer, &size);
  WCJPEGEncode (&cinfo, frame, quality);
  jpeg_destroy_compress (&cinfo);
  *jpeg = buffer;
  *length = (size_t) size;
  return 0;
}

/* A new file, never one that's there already. */
static FILE *
WCCreate (const char *path, char *error, size_t errorSize)
{
  int fd = open (path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0644);
  FILE *file;

  if (fd < 0)
    {
      snprintf (error, errorSize, "%s", strerror (errno));
      return NULL;
    }
  file = fdopen (fd, "wb");
  if (file == NULL)
    {
      snprintf (error, errorSize, "%s", strerror (errno));
      close (fd);
      (void) unlink (path);
    }
  return file;
}

/* Closes file, and removes it if it didn't get written whole. */
static int
WCFinish (FILE *file, const char *path, int failed, char *error,
          size_t errorSize)
{
  if (fflush (file) != 0 || ferror (file))
    {
      if (!failed)
        snprintf (error, errorSize, "%s", strerror (errno));
      failed = 1;
    }
  if (fclose (file) != 0 && !failed)
    {
      snprintf (error, errorSize, "%s", strerror (errno));
      failed = 1;
    }
  if (failed)
    (void) unlink (path);
  return failed ? -1 : 0;
}

int
WCImageWritePNG (const WCFrame *frame, const char *path, char *error,
                 size_t errorSize)
{
  png_image image;
  FILE *file = WCCreate (path, error, errorSize);
  int failed = 0;

  if (file == NULL)
    return -1;
  memset (&image, 0, sizeof (image));
  image.version = PNG_IMAGE_VERSION;
  image.width = (png_uint_32) frame->width;
  image.height = (png_uint_32) frame->height;
  image.format = PNG_FORMAT_RGB;
  if (!png_image_write_to_stdio (&image, file, 0, frame->rgb,
                                 (png_int_32) frame->stride, NULL))
    {
      snprintf (error, errorSize, "%s", image.message);
      failed = 1;
    }
  png_image_free (&image);
  return WCFinish (file, path, failed, error, errorSize);
}

int
WCImageWriteJPEG (const WCFrame *frame, int quality, const char *path,
                  char *error, size_t errorSize)
{
  struct jpeg_compress_struct cinfo;
  WCJPEGError jerror;
  FILE *file = WCCreate (path, error, errorSize);

  if (file == NULL)
    return -1;
  cinfo.err = jpeg_std_error (&jerror.mgr);
  jerror.mgr.error_exit = WCJPEGErrorExit;
  if (setjmp (jerror.jump))
    {
      snprintf (error, errorSize, "%s", jerror.message);
      jpeg_destroy_compress (&cinfo);
      return WCFinish (file, path, 1, error, errorSize);
    }
  jpeg_create_compress (&cinfo);
  jpeg_stdio_dest (&cinfo, file);
  WCJPEGEncode (&cinfo, frame, quality);
  jpeg_destroy_compress (&cinfo);
  return WCFinish (file, path, 0, error, errorSize);
}

static int
WCReadPNG (FILE *file, WCFrame *frame)
{
  png_image image;
  int result = -1;

  memset (&image, 0, sizeof (image));
  image.version = PNG_IMAGE_VERSION;
  if (!png_image_begin_read_from_stdio (&image, file))
    return -1;
  image.format = PNG_FORMAT_RGB;
  if (WCFrameAlloc (frame, (int) image.width, (int) image.height) == 0
      && png_image_finish_read (&image, NULL, frame->rgb,
                                (png_int_32) frame->stride, NULL))
    result = 0;
  png_image_free (&image);
  return result;
}

static int
WCReadJPEG (FILE *file, int minWidth, WCFrame *frame)
{
  struct jpeg_decompress_struct cinfo;
  WCJPEGError error;
  int scale = 1, result;

  cinfo.err = jpeg_std_error (&error.mgr);
  error.mgr.error_exit = WCJPEGErrorExit;
  error.mgr.emit_message = WCJPEGQuiet;
  if (setjmp (error.jump))
    {
      jpeg_destroy_decompress (&cinfo);
      return -1;
    }
  jpeg_create_decompress (&cinfo);
  jpeg_stdio_src (&cinfo, file);
  (void) jpeg_read_header (&cinfo, TRUE);
  while (scale < 8 && (int) cinfo.image_width / (scale * 2) >= minWidth)
    scale *= 2;
  /* WCJPEGDecode reads the header again; start over. */
  jpeg_abort_decompress (&cinfo);
  rewind (file);
  jpeg_stdio_src (&cinfo, file);
  result = WCJPEGDecode (&cinfo, scale, frame);
  jpeg_destroy_decompress (&cinfo);
  return result;
}

int
WCImageRead (const char *path, int minWidth, WCFrame *frame)
{
  FILE *file = fopen (path, "rbe");
  unsigned char magic[4];
  int result = -1;

  if (file == NULL)
    return -1;
  if (fread (magic, 1, sizeof (magic), file) == sizeof (magic))
    {
      rewind (file);
      if (magic[0] == 0x89 && magic[1] == 'P' && magic[2] == 'N')
        result = WCReadPNG (file, frame);
      else if (magic[0] == 0xff && magic[1] == 0xd8)
        result = WCReadJPEG (file, minWidth, frame);
    }
  fclose (file);
  return result;
}
