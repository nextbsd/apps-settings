/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * An AVI 1.0 file with one MJPEG video stream:
 *
 *   RIFF 'AVI '
 *     LIST 'hdrl'
 *       avih			the main header
 *       LIST 'strl'
 *         strh 'vids' 'MJPG'	the stream's header
 *         strf			its BITMAPINFOHEADER
 *     LIST 'movi'
 *       00dc ...		a JPEG a frame
 *     idx1			where each frame is
 *
 * The header is written first with the counts left at zero and written
 * again at the end. Everything is little-endian. AVI 1.0 sizes are 32
 * bits and readers take them as signed, so a recording stops short of
 * 2 GB (OpenDML's longer files aren't needed for a webcam).
 */

#include "WCRecorder.h"
#include "WCImage.h"

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define WCRecorderQuality 85
#define WCRecorderMaxBytes 2000000000LL

/* Where things are in the header (see above). */
#define WCHeaderSize 224	/* through 'movi' */
#define WCMoviListAt 212	/* 'LIST' of 'movi' */
#define WCMoviAt 220		/* 'movi', which idx1 counts from */

typedef struct
{
  uint32_t offset;		/* from 'movi' */
  uint32_t size;
} WCIndexEntry;

struct WCRecorder
{
  FILE *file;
  char *path;
  int width;
  int height;
  long long bytes;		/* the file's length so far */
  uint32_t frames;
  uint32_t largest;		/* the biggest frame */
  WCIndexEntry *index;
  size_t indexCapacity;
  struct timespec start;
  struct timespec last;
};

static void
WCPut16 (unsigned char *p, uint16_t v)
{
  p[0] = (unsigned char) v;
  p[1] = (unsigned char) (v >> 8);
}

static void
WCPut32 (unsigned char *p, uint32_t v)
{
  p[0] = (unsigned char) v;
  p[1] = (unsigned char) (v >> 8);
  p[2] = (unsigned char) (v >> 16);
  p[3] = (unsigned char) (v >> 24);
}

static uint32_t
WCGet32 (const unsigned char *p)
{
  return (uint32_t) p[0] | ((uint32_t) p[1] << 8) | ((uint32_t) p[2] << 16)
    | ((uint32_t) p[3] << 24);
}

static double
WCSince (const struct timespec *from, const struct timespec *to)
{
  return (double) (to->tv_sec - from->tv_sec)
    + (to->tv_nsec - from->tv_nsec) / 1e9;
}

/* The header, with what's known so far. */
static void
WCRecorderHeader (WCRecorder *r, unsigned char h[WCHeaderSize])
{
  double seconds = WCSince (&r->start, &r->last);
  /* The rate the frames came at, in thousandths of a frame a second;
     30 until there are two to tell. */
  uint32_t rate = r->frames > 1 && seconds > 0.0
    ? (uint32_t) ((r->frames - 1) / seconds * 1000.0 + 0.5) : 30000;
  uint32_t buffer = r->largest + 8;
  uint32_t riff = (uint32_t) (r->bytes - 8);
  uint32_t movi = (uint32_t) (r->bytes - WCMoviListAt - 8);

  if (rate == 0)
    rate = 1;
  memset (h, 0, WCHeaderSize);
  memcpy (h, "RIFF", 4);
  WCPut32 (h + 4, riff);
  memcpy (h + 8, "AVI ", 4);

  memcpy (h + 12, "LIST", 4);
  WCPut32 (h + 16, 192);
  memcpy (h + 20, "hdrl", 4);

  memcpy (h + 24, "avih", 4);
  WCPut32 (h + 28, 56);
  WCPut32 (h + 32, (uint32_t) (1000000000.0 / rate + 0.5));	/* µs */
  WCPut32 (h + 36, (uint32_t) ((double) buffer * rate / 1000.0));
  WCPut32 (h + 40, 0);		/* padding granularity */
  WCPut32 (h + 44, 0x10);	/* AVIF_HASINDEX */
  WCPut32 (h + 48, r->frames);
  WCPut32 (h + 52, 0);		/* initial frames */
  WCPut32 (h + 56, 1);		/* streams */
  WCPut32 (h + 60, buffer);
  WCPut32 (h + 64, (uint32_t) r->width);
  WCPut32 (h + 68, (uint32_t) r->height);

  memcpy (h + 88, "LIST", 4);
  WCPut32 (h + 92, 116);
  memcpy (h + 96, "strl", 4);

  memcpy (h + 100, "strh", 4);
  WCPut32 (h + 104, 56);
  memcpy (h + 108, "vids", 4);
  memcpy (h + 112, "MJPG", 4);
  WCPut32 (h + 116, 0);		/* flags */
  WCPut32 (h + 120, 0);		/* priority, language */
  WCPut32 (h + 124, 0);		/* initial frames */
  WCPut32 (h + 128, 1000);	/* scale: rate / scale = frames a second */
  WCPut32 (h + 132, rate);
  WCPut32 (h + 136, 0);		/* start */
  WCPut32 (h + 140, r->frames);	/* length */
  WCPut32 (h + 144, buffer);
  WCPut32 (h + 148, 0xffffffff);	/* quality: the default */
  WCPut32 (h + 152, 0);		/* sample size: varies */
  WCPut16 (h + 160, (uint16_t) r->width);	/* rcFrame right, bottom */
  WCPut16 (h + 162, (uint16_t) r->height);

  memcpy (h + 164, "strf", 4);
  WCPut32 (h + 168, 40);
  WCPut32 (h + 172, 40);	/* biSize */
  WCPut32 (h + 176, (uint32_t) r->width);
  WCPut32 (h + 180, (uint32_t) r->height);
  WCPut16 (h + 184, 1);		/* planes */
  WCPut16 (h + 186, 24);	/* bits a pixel */
  memcpy (h + 188, "MJPG", 4);
  WCPut32 (h + 192, (uint32_t) (r->width * r->height * 3));

  memcpy (h + WCMoviListAt, "LIST", 4);
  WCPut32 (h + WCMoviListAt + 4, movi);
  memcpy (h + WCMoviAt, "movi", 4);
}

static void
WCRecorderFree (WCRecorder *r)
{
  if (r->file != NULL)
    fclose (r->file);
  free (r->path);
  free (r->index);
  free (r);
}

WCRecorder *
WCRecorderStart (const char *path, int width, int height, char *error,
                 size_t errorSize)
{
  WCRecorder *r = calloc (1, sizeof (*r));
  unsigned char header[WCHeaderSize];
  int fd;

  if (r == NULL || (r->path = strdup (path)) == NULL)
    {
      free (r);
      snprintf (error, errorSize, "Out of memory");
      return NULL;
    }
  fd = open (path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0644);
  if (fd < 0 || (r->file = fdopen (fd, "wb")) == NULL)
    {
      snprintf (error, errorSize, "%s", strerror (errno));
      if (fd >= 0)
        {
          close (fd);
          (void) unlink (path);
        }
      WCRecorderFree (r);
      return NULL;
    }
  r->width = width;
  r->height = height;
  r->bytes = WCHeaderSize;
  clock_gettime (CLOCK_MONOTONIC, &r->start);
  r->last = r->start;
  WCRecorderHeader (r, header);
  if (fwrite (header, 1, sizeof (header), r->file) != sizeof (header))
    {
      snprintf (error, errorSize, "%s", strerror (errno));
      WCRecorderFree (r);
      (void) unlink (path);
      return NULL;
    }
  return r;
}

int
WCRecorderAdd (WCRecorder *r, const WCFrame *frame, char *error,
               size_t errorSize)
{
  unsigned char *jpeg = NULL;
  size_t length = 0;
  unsigned char chunk[8];
  static const unsigned char pad = 0;
  size_t padded;

  /* A camera doesn't change size while it runs; if it did, the frames
     of another size are left out. */
  if (frame->width != r->width || frame->height != r->height)
    return 0;
  if (WCImageToJPEG (frame, WCRecorderQuality, &jpeg, &length) != 0)
    {
      snprintf (error, errorSize, "A frame couldn't be compressed");
      return -1;
    }
  padded = length + (length & 1);
  if (r->bytes + 8 + (long long) padded
      + 16LL * (r->frames + 1) + 8 > WCRecorderMaxBytes)
    {
      free (jpeg);
      snprintf (error, errorSize, "The recording reached 2 GB, the most "
                "an AVI file holds");
      return -1;
    }
  if (r->frames == r->indexCapacity)
    {
      size_t capacity = r->indexCapacity > 0 ? r->indexCapacity * 2 : 1024;
      WCIndexEntry *index = realloc (r->index, capacity * sizeof (*index));

      if (index == NULL)
        {
          free (jpeg);
          snprintf (error, errorSize, "Out of memory");
          return -1;
        }
      r->index = index;
      r->indexCapacity = capacity;
    }
  memcpy (chunk, "00dc", 4);
  WCPut32 (chunk + 4, (uint32_t) length);
  if (fwrite (chunk, 1, 8, r->file) != 8
      || fwrite (jpeg, 1, length, r->file) != length
      || (padded != length && fwrite (&pad, 1, 1, r->file) != 1))
    {
      free (jpeg);
      snprintf (error, errorSize, "%s", strerror (errno));
      return -1;
    }
  free (jpeg);
  r->index[r->frames].offset = (uint32_t) (r->bytes - WCMoviAt);
  r->index[r->frames].size = (uint32_t) length;
  r->frames++;
  r->bytes += 8 + (long long) padded;
  if (length > r->largest)
    r->largest = (uint32_t) length;
  clock_gettime (CLOCK_MONOTONIC, &r->last);
  return 0;
}

double
WCRecorderSeconds (WCRecorder *r)
{
  struct timespec now;

  clock_gettime (CLOCK_MONOTONIC, &now);
  return WCSince (&r->start, &now);
}

long long
WCRecorderBytes (WCRecorder *r)
{
  return r->bytes;
}

int
WCRecorderFinish (WCRecorder *r, char *error, size_t errorSize)
{
  unsigned char header[WCHeaderSize];
  unsigned char entry[16];
  uint32_t i;
  int failed = 0;

  /* The index ends the movi list, which the header then counts. */
  memcpy (entry, "idx1", 4);
  WCPut32 (entry + 4, r->frames * 16);
  failed = fwrite (entry, 1, 8, r->file) != 8;
  for (i = 0; i < r->frames && !failed; i++)
    {
      memcpy (entry, "00dc", 4);
      WCPut32 (entry + 4, 0x10);	/* AVIIF_KEYFRAME: all of them */
      WCPut32 (entry + 8, r->index[i].offset);
      WCPut32 (entry + 12, r->index[i].size);
      failed = fwrite (entry, 1, 16, r->file) != 16;
    }
  if (!failed)
    {
      long long movieEnd = r->bytes;

      r->bytes += 8 + 16LL * r->frames;
      WCRecorderHeader (r, header);
      /* movi ends where idx1 begins. */
      WCPut32 (header + WCMoviListAt + 4,
               (uint32_t) (movieEnd - WCMoviListAt - 8));
      failed = fseeko (r->file, 0, SEEK_SET) != 0
        || fwrite (header, 1, sizeof (header), r->file) != sizeof (header);
    }
  if (fflush (r->file) != 0)
    failed = 1;
  if (failed)
    snprintf (error, errorSize, "%s", strerror (errno));
  if (fclose (r->file) != 0 && !failed)
    {
      snprintf (error, errorSize, "%s", strerror (errno));
      failed = 1;
    }
  r->file = NULL;
  /* Nothing recorded is no recording. */
  if (!failed && r->frames == 0)
    (void) unlink (r->path);
  WCRecorderFree (r);
  return failed ? -1 : 0;
}

int
WCRecorderReadFirstFrame (const char *path, int scale, WCFrame *frame)
{
  FILE *file = fopen (path, "rbe");
  unsigned char head[WCHeaderSize + 8];
  unsigned char *jpeg;
  uint32_t length;
  int result;

  if (file == NULL)
    return -1;
  if (fread (head, 1, sizeof (head), file) != sizeof (head)
      || memcmp (head, "RIFF", 4) != 0 || memcmp (head + 8, "AVI ", 4) != 0
      || memcmp (head + WCMoviAt, "movi", 4) != 0
      || memcmp (head + WCHeaderSize, "00dc", 4) != 0)
    {
      /* Not laid out as this file writes them. */
      fclose (file);
      return -1;
    }
  length = WCGet32 (head + WCHeaderSize + 4);
  if (length == 0 || length > 64 * 1024 * 1024
      || (jpeg = malloc (length)) == NULL)
    {
      fclose (file);
      return -1;
    }
  result = fread (jpeg, 1, length, file) == length
    ? WCImageFromJPEG (jpeg, length, scale, frame) : -1;
  free (jpeg);
  fclose (file);
  return result;
}
