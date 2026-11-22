/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * The test pattern: a camera of its own, listed when there's no real
 * one, so the app can be used and tested without a camera. Colour bars,
 * a grey ramp, a ball that moves, and "TEST PATTERN" with the time, 30
 * times a second. The words are in the picture, so photos and videos
 * taken of it can't be taken for a camera's.
 */

#include "WCCapture.h"
#include "WCImage.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define WCPatternWidth 640
#define WCPatternHeight 480
#define WCPatternInterval 33333333L	/* nanoseconds: 30 a second */

typedef struct
{
  WCCapture capture;
  struct timespec start;
  struct timespec last;
  WCFrame frame;
} WCPattern;

/* 75% colour bars: white, yellow, cyan, green, magenta, red, blue. */
static const unsigned char WCBars[7][3] = {
  { 191, 191, 191 }, { 191, 191, 0 }, { 0, 191, 191 }, { 0, 191, 0 },
  { 191, 0, 191 }, { 191, 0, 0 }, { 0, 0, 191 },
};

/* A 5x7 font, for the few characters the label needs: one byte a row,
   bit 4 the leftmost column. */
static const struct
{
  char c;
  unsigned char rows[7];
} WCGlyphs[] = {
  { '0', { 0x0e, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0e } },
  { '1', { 0x04, 0x0c, 0x04, 0x04, 0x04, 0x04, 0x0e } },
  { '2', { 0x0e, 0x11, 0x01, 0x02, 0x04, 0x08, 0x1f } },
  { '3', { 0x1f, 0x02, 0x04, 0x02, 0x01, 0x11, 0x0e } },
  { '4', { 0x02, 0x06, 0x0a, 0x12, 0x1f, 0x02, 0x02 } },
  { '5', { 0x1f, 0x10, 0x1e, 0x01, 0x01, 0x11, 0x0e } },
  { '6', { 0x06, 0x08, 0x10, 0x1e, 0x11, 0x11, 0x0e } },
  { '7', { 0x1f, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08 } },
  { '8', { 0x0e, 0x11, 0x11, 0x0e, 0x11, 0x11, 0x0e } },
  { '9', { 0x0e, 0x11, 0x11, 0x0f, 0x01, 0x02, 0x0c } },
  { ':', { 0x00, 0x0c, 0x0c, 0x00, 0x0c, 0x0c, 0x00 } },
  { 'A', { 0x0e, 0x11, 0x11, 0x1f, 0x11, 0x11, 0x11 } },
  { 'E', { 0x1f, 0x10, 0x10, 0x1e, 0x10, 0x10, 0x1f } },
  { 'N', { 0x11, 0x19, 0x15, 0x13, 0x11, 0x11, 0x11 } },
  { 'P', { 0x1e, 0x11, 0x11, 0x1e, 0x10, 0x10, 0x10 } },
  { 'R', { 0x1e, 0x11, 0x11, 0x1e, 0x14, 0x12, 0x11 } },
  { 'S', { 0x0f, 0x10, 0x10, 0x0e, 0x01, 0x01, 0x1e } },
  { 'T', { 0x1f, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04 } },
};

static void
WCPatternFill (WCFrame *f, int x0, int y0, int x1, int y1,
               const unsigned char rgb[3])
{
  int x, y;

  if (x0 < 0)
    x0 = 0;
  if (y0 < 0)
    y0 = 0;
  if (x1 > f->width)
    x1 = f->width;
  if (y1 > f->height)
    y1 = f->height;
  for (y = y0; y < y1; y++)
    {
      unsigned char *d = f->rgb + (size_t) y * f->stride + (size_t) x0 * 3;

      for (x = x0; x < x1; x++, d += 3)
        memcpy (d, rgb, 3);
    }
}

/* text, size pixels a dot, centred on cx with its top at y. */
static void
WCPatternText (WCFrame *f, const char *text, int cx, int y, int size)
{
  static const unsigned char white[3] = { 255, 255, 255 };
  static const unsigned char black[3] = { 0, 0, 0 };
  int width = (int) strlen (text) * 6 * size - size;
  int x = cx - width / 2;
  const char *p;

  WCPatternFill (f, x - 2 * size, y - 2 * size, x + width + 2 * size,
                 y + 9 * size, black);
  for (p = text; *p != '\0'; p++, x += 6 * size)
    {
      size_t g;
      int row, col;

      for (g = 0; g < sizeof (WCGlyphs) / sizeof (WCGlyphs[0]); g++)
        if (WCGlyphs[g].c == *p)
          break;
      if (g == sizeof (WCGlyphs) / sizeof (WCGlyphs[0]))
        continue;		/* a space */
      for (row = 0; row < 7; row++)
        for (col = 0; col < 5; col++)
          if (WCGlyphs[g].rows[row] & (0x10 >> col))
            WCPatternFill (f, x + col * size, y + row * size,
                           x + (col + 1) * size, y + (row + 1) * size,
                           white);
    }
}

static void
WCPatternDraw (WCPattern *p, double seconds)
{
  WCFrame *f = &p->frame;
  int barsBottom = f->height * 2 / 3;
  int i, x, y, bx, by, r = f->height / 12;
  double t;
  char clock[16];
  time_t now = time (NULL);
  struct tm tm;

  for (i = 0; i < 7; i++)
    WCPatternFill (f, f->width * i / 7, 0, f->width * (i + 1) / 7,
                   barsBottom, WCBars[i]);
  for (x = 0; x < f->width; x++)
    {
      unsigned char grey = (unsigned char) (x * 255 / (f->width - 1));
      unsigned char rgb[3] = { grey, grey, grey };

      WCPatternFill (f, x, barsBottom, x + 1, f->height, rgb);
    }

  /* The ball goes to and fro across the bars, so a frozen picture
     shows. */
  t = seconds / 4.0;
  t -= (double) (long) t;
  bx = r + (int) ((t < 0.5 ? t * 2 : 2 - t * 2) * (f->width - 2 * r));
  by = barsBottom / 2;
  for (y = by - r; y <= by + r; y++)
    for (x = bx - r; x <= bx + r; x++)
      if ((x - bx) * (x - bx) + (y - by) * (y - by) <= r * r)
        {
          static const unsigned char orange[3] = { 255, 149, 0 };

          WCPatternFill (f, x, y, x + 1, y + 1, orange);
        }

  localtime_r (&now, &tm);
  strftime (clock, sizeof (clock), "%H:%M:%S", &tm);
  WCPatternText (f, "TEST PATTERN", f->width / 2, barsBottom + 16, 4);
  WCPatternText (f, clock, f->width / 2, barsBottom + 16 + 48, 4);
}

static int
WCPatternList (WCCameraInfo *cameras, int max)
{
  if (max < 1)
    return 0;
  memset (&cameras[0], 0, sizeof (cameras[0]));
  cameras[0].backend = WCCameraTestPattern;
  snprintf (cameras[0].ident, sizeof (cameras[0].ident), "testpattern");
  snprintf (cameras[0].name, sizeof (cameras[0].name), "Test Pattern");
  cameras[0].mirror = 0;	/* its words would read backwards */
  return 1;
}

static WCCapture *
WCPatternOpen (const WCCameraInfo *camera, char *error, size_t errorSize)
{
  WCPattern *p = calloc (1, sizeof (*p));

  if (p == NULL || WCFrameAlloc (&p->frame, WCPatternWidth,
                                 WCPatternHeight) != 0)
    {
      free (p);
      snprintf (error, errorSize, "Out of memory");
      return NULL;
    }
  p->capture.backend = &WCCaptureTestPatternBackend;
  snprintf (p->capture.description, sizeof (p->capture.description),
            "Test pattern %d×%d", WCPatternWidth, WCPatternHeight);
  clock_gettime (CLOCK_MONOTONIC, &p->start);
  p->last.tv_sec = p->start.tv_sec - 1;
  p->last.tv_nsec = p->start.tv_nsec;
  return &p->capture;
}

static int
WCPatternRead (WCCapture *capture, WCFrame *frame, char *error,
               size_t errorSize)
{
  WCPattern *p = (WCPattern *) capture;
  struct timespec now;
  long since;

  clock_gettime (CLOCK_MONOTONIC, &now);
  since = (now.tv_sec - p->last.tv_sec) * 1000000000L
    + (now.tv_nsec - p->last.tv_nsec);
  if (since < WCPatternInterval)
    return 0;
  p->last = now;
  WCPatternDraw (p, (double) (now.tv_sec - p->start.tv_sec)
                 + (now.tv_nsec - p->start.tv_nsec) / 1e9);
  *frame = p->frame;
  frame->capacity = 0;
  return 1;
}

static void
WCPatternClose (WCCapture *capture)
{
  WCPattern *p = (WCPattern *) capture;

  WCFrameFree (&p->frame);
  free (p);
}

const WCCaptureBackend WCCaptureTestPatternBackend = {
  WCPatternList,
  WCPatternOpen,
  WCPatternRead,
  WCPatternClose,
};
