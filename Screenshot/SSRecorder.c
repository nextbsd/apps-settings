/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * ffmpeg reads the frames from its standard input:
 *
 *   ffmpeg -f rawvideo -pix_fmt bgra -video_size WxH -framerate 30
 *          -i pipe:0 [-f oss -i /dev/dspN]
 *          -c:v mpeg4 -q:v 3 -pix_fmt yuv420p
 *          [-af aresample=async=1000 -c:a aac -b:a 128k]
 *          -movflags +faststart -f mov FILE
 *
 * WindowServer's XRGB8888 is B, G, R, x in memory: ffmpeg's bgra, with
 * an alpha it ignores (the encoder takes yuv420p).
 */

#include "SSRecorder.h"

#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

extern char **environ;

#define SSFFmpeg "/usr/bin/ffmpeg"
/* After the last frame, how long ffmpeg may take to finish the file. */
#define SSFinishSeconds 60
/* At the end, how far behind the clock the writer may still catch up
   (a machine too slow to encode in real time). */
#define SSCatchUpSeconds 5.0

struct SSRecorder
{
  pid_t pid;
  int pipe;			/* ffmpeg's standard input */
  int microphone;		/* ffmpeg reads one too */
  int width;
  int height;
  size_t frameSize;
  unsigned char *latest;	/* the newest picture (lock) */
  unsigned char *out;		/* the writer's copy */
  int haveFrame;		/* lock */
  int stop;			/* lock */
  int failed;			/* the writer's: a write failed */
  struct timespec start;	/* the first frame */
  double stopAt;		/* seconds: the recording's length */
  pthread_t thread;
  pthread_mutex_t lock;
  pthread_cond_t wake;
};

static double
SSNow (void)
{
  struct timespec ts;

  clock_gettime (CLOCK_MONOTONIC, &ts);
  return ts.tv_sec + ts.tv_nsec / 1e9;
}

static int
SSWriteAll (int fd, const unsigned char *p, size_t n)
{
  while (n > 0)
    {
      ssize_t w = write (fd, p, n);

      if (w < 0)
        {
          if (errno == EINTR)
            continue;
          return -1;
        }
      p += w;
      n -= (size_t) w;
    }
  return 0;
}

/* The writer: frame n at n / fps seconds after the first. */
static void *
SSWriter (void *arg)
{
  SSRecorder *r = arg;
  double start, now, due;
  unsigned long n = 0;
  int stop;

  pthread_mutex_lock (&r->lock);
  while (!r->haveFrame && !r->stop)
    pthread_cond_wait (&r->wake, &r->lock);
  if (!r->haveFrame)
    {
      pthread_mutex_unlock (&r->lock);
      return NULL;
    }
  start = r->start.tv_sec + r->start.tv_nsec / 1e9;
  pthread_mutex_unlock (&r->lock);

  for (;;)
    {
      due = start + (double) n / SSRecorderFPS;
      pthread_mutex_lock (&r->lock);
      for (;;)
        {
          now = SSNow ();
          stop = r->stop;
          if (stop || now >= due)
            break;
          {
            struct timespec until;
            double wait = due - now;

            clock_gettime (CLOCK_REALTIME, &until);
            until.tv_sec += (time_t) wait;
            until.tv_nsec += (long) ((wait - (time_t) wait) * 1e9);
            if (until.tv_nsec >= 1000000000L)
              {
                until.tv_sec++;
                until.tv_nsec -= 1000000000L;
              }
            pthread_cond_timedwait (&r->wake, &r->lock, &until);
          }
        }
      if (stop)
        {
          /* Up to the recording's end, unless that is too far behind. */
          if (due - start > r->stopAt
              || SSNow () - (start + r->stopAt) > SSCatchUpSeconds)
            {
              pthread_mutex_unlock (&r->lock);
              break;
            }
        }
      memcpy (r->out, r->latest, r->frameSize);
      pthread_mutex_unlock (&r->lock);
      if (SSWriteAll (r->pipe, r->out, r->frameSize) < 0)
        {
          r->failed = errno != 0 ? errno : EIO;
          break;
        }
      n++;
    }
  return NULL;
}

static void
SSArg (char **argv, int *argc, const char *s)
{
  argv[(*argc)++] = (char *) s;
}

SSRecorder *
SSRecorderStart (const char *path, int width, int height,
                 const char *microphone, const char *log, char *error,
                 size_t errorSize)
{
  SSRecorder *r;
  posix_spawn_file_actions_t actions;
  char size[32], *argv[48];
  int fds[2], logfd = -1, argc = 0, err;
  const char *ffmpeg = access (SSFFmpeg, X_OK) == 0 ? SSFFmpeg : "ffmpeg";

  if (width < 2 || height < 2 || (width & 1) || (height & 1))
    {
      snprintf (error, errorSize, "The area to record is too small");
      return NULL;
    }
  r = calloc (1, sizeof (*r));
  if (r == NULL)
    {
      snprintf (error, errorSize, "Out of memory");
      return NULL;
    }
  r->width = width;
  r->height = height;
  r->frameSize = (size_t) width * height * 4;
  r->latest = calloc (1, r->frameSize);
  r->out = malloc (r->frameSize);
  if (r->latest == NULL || r->out == NULL)
    {
      free (r->latest);
      free (r->out);
      free (r);
      snprintf (error, errorSize, "Out of memory");
      return NULL;
    }
  pthread_mutex_init (&r->lock, NULL);
  pthread_cond_init (&r->wake, NULL);

  /* A write to an ffmpeg that has gone fails with EPIPE, not a
     signal that ends the app. */
  signal (SIGPIPE, SIG_IGN);
  if (pipe2 (fds, O_CLOEXEC) < 0)
    {
      snprintf (error, errorSize, "%s", strerror (errno));
      goto fail;
    }
  if (log != NULL)
    logfd = open (log, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0644);

  snprintf (size, sizeof (size), "%dx%d", width, height);
  SSArg (argv, &argc, "ffmpeg");
  SSArg (argv, &argc, "-hide_banner");
  SSArg (argv, &argc, "-loglevel");
  SSArg (argv, &argc, "warning");
  SSArg (argv, &argc, "-thread_queue_size");
  SSArg (argv, &argc, "64");
  SSArg (argv, &argc, "-f");
  SSArg (argv, &argc, "rawvideo");
  SSArg (argv, &argc, "-pix_fmt");
  SSArg (argv, &argc, "bgra");
  SSArg (argv, &argc, "-video_size");
  SSArg (argv, &argc, size);
  SSArg (argv, &argc, "-framerate");
  SSArg (argv, &argc, "30");
  SSArg (argv, &argc, "-i");
  SSArg (argv, &argc, "pipe:0");
  if (microphone != NULL)
    {
      SSArg (argv, &argc, "-thread_queue_size");
      SSArg (argv, &argc, "1024");
      SSArg (argv, &argc, "-f");
      SSArg (argv, &argc, "oss");
      SSArg (argv, &argc, "-i");
      SSArg (argv, &argc, microphone);
    }
  SSArg (argv, &argc, "-map");
  SSArg (argv, &argc, "0:v");
  if (microphone != NULL)
    {
      SSArg (argv, &argc, "-map");
      SSArg (argv, &argc, "1:a");
    }
  SSArg (argv, &argc, "-c:v");
  SSArg (argv, &argc, "mpeg4");
  SSArg (argv, &argc, "-q:v");
  SSArg (argv, &argc, "3");
  SSArg (argv, &argc, "-pix_fmt");
  SSArg (argv, &argc, "yuv420p");
  if (microphone != NULL)
    {
      /* The microphone's timestamps are the wall clock's as ffmpeg
         reads it: smooth them onto its sample count. */
      SSArg (argv, &argc, "-af");
      SSArg (argv, &argc, "aresample=async=1000");
      SSArg (argv, &argc, "-c:a");
      SSArg (argv, &argc, "aac");
      SSArg (argv, &argc, "-b:a");
      SSArg (argv, &argc, "128k");
    }
  SSArg (argv, &argc, "-movflags");
  SSArg (argv, &argc, "+faststart");
  SSArg (argv, &argc, "-f");
  SSArg (argv, &argc, "mov");
  SSArg (argv, &argc, "-n");		/* never overwrite */
  SSArg (argv, &argc, path);
  argv[argc] = NULL;

  posix_spawn_file_actions_init (&actions);
  posix_spawn_file_actions_adddup2 (&actions, fds[0], 0);
  if (logfd >= 0)
    {
      posix_spawn_file_actions_adddup2 (&actions, logfd, 1);
      posix_spawn_file_actions_adddup2 (&actions, logfd, 2);
    }
  err = ffmpeg[0] == '/'
    ? posix_spawn (&r->pid, ffmpeg, &actions, NULL, argv, environ)
    : posix_spawnp (&r->pid, ffmpeg, &actions, NULL, argv, environ);
  posix_spawn_file_actions_destroy (&actions);
  close (fds[0]);
  if (logfd >= 0)
    close (logfd);
  if (err != 0)
    {
      close (fds[1]);
      snprintf (error, errorSize, "ffmpeg couldn't be started: %s",
                strerror (err));
      goto fail;
    }
  r->pipe = fds[1];
  r->microphone = microphone != NULL;
  if (pthread_create (&r->thread, NULL, SSWriter, r) != 0)
    {
      close (r->pipe);
      waitpid (r->pid, NULL, 0);
      snprintf (error, errorSize, "Out of resources");
      goto fail;
    }
  return r;

fail:
  pthread_mutex_destroy (&r->lock);
  pthread_cond_destroy (&r->wake);
  free (r->latest);
  free (r->out);
  free (r);
  return NULL;
}

void
SSRecorderFrame (SSRecorder *r, const unsigned char *pixels, int stride,
                 int x, int y)
{
  int row;

  pthread_mutex_lock (&r->lock);
  for (row = 0; row < r->height; row++)
    memcpy (r->latest + (size_t) row * r->width * 4,
            pixels + (size_t) (y + row) * stride + (size_t) x * 4,
            (size_t) r->width * 4);
  if (!r->haveFrame)
    {
      r->haveFrame = 1;
      clock_gettime (CLOCK_MONOTONIC, &r->start);
      pthread_cond_signal (&r->wake);
    }
  pthread_mutex_unlock (&r->lock);
}

double
SSRecorderSeconds (SSRecorder *r)
{
  double seconds = 0.0;

  pthread_mutex_lock (&r->lock);
  if (r->haveFrame)
    seconds = SSNow () - (r->start.tv_sec + r->start.tv_nsec / 1e9);
  pthread_mutex_unlock (&r->lock);
  return seconds;
}

int
SSRecorderFinish (SSRecorder *r, char *error, size_t errorSize)
{
  int status = 0, failed = 0, i;
  pid_t got = 0;

  pthread_mutex_lock (&r->lock);
  r->stopAt = r->haveFrame
    ? SSNow () - (r->start.tv_sec + r->start.tv_nsec / 1e9) : 0.0;
  r->stop = 1;
  pthread_cond_signal (&r->wake);
  pthread_mutex_unlock (&r->lock);
  pthread_join (r->thread, NULL);
  /* End of input: ffmpeg writes the index and moves it to the front.
     A microphone never ends by itself (and -shortest cuts a live one
     short): once ffmpeg has the last frame, SIGINT ends its reading
     and it finishes the file, as it does for q. */
  close (r->pipe);
  if (r->microphone)
    {
      usleep (150000);
      kill (r->pid, SIGINT);
    }
  for (i = 0; i < SSFinishSeconds * 10; i++)
    {
      got = waitpid (r->pid, &status, WNOHANG);
      if (got != 0)
        break;
      usleep (100000);
    }
  if (got == 0)
    {
      /* ffmpeg finishes the file on SIGINT too. */
      kill (r->pid, SIGINT);
      sleep (2);
      if (waitpid (r->pid, &status, WNOHANG) == 0)
        {
          kill (r->pid, SIGKILL);
          waitpid (r->pid, &status, 0);
        }
      snprintf (error, errorSize, "ffmpeg took too long to finish");
      failed = 1;
    }
  /* After the SIGINT above, ffmpeg says "Exiting normally, received
     signal 2" with status 255, the file finished. */
  else if (got < 0 || !WIFEXITED (status)
           || (WEXITSTATUS (status) != 0
               && !(r->microphone && WEXITSTATUS (status) == 255)))
    {
      snprintf (error, errorSize, r->failed != 0
                ? "ffmpeg stopped while recording (see "
                "~/Library/Logs/Screenshot.log)"
                : "ffmpeg couldn't finish the movie (see "
                "~/Library/Logs/Screenshot.log)");
      failed = 1;
    }
  else if (!r->haveFrame)
    {
      snprintf (error, errorSize, "Nothing was recorded");
      failed = 1;
    }
  pthread_mutex_destroy (&r->lock);
  pthread_cond_destroy (&r->wake);
  free (r->latest);
  free (r->out);
  free (r);
  return failed ? -1 : 0;
}

int
SSRecorderMicrophones (char paths[][32], char names[][96], int max)
{
  FILE *f = fopen ("/dev/sndstat", "re");
  char line[512], dev[64];
  int n = 0;

  if (f == NULL)
    return 0;
  /* The kernel's devices, "pcm0: <Realtek ALC269 (Analog)> (play/rec)
     default", then userspace ones (virtual_oss: Bluetooth headsets'
     dsp.btN), "dsp.bt0: <virtual_oss device> (play/rec)". */
  while (n < max && fgets (line, sizeof (line), f) != NULL)
    {
      unsigned unit;
      char *lt, *gt, *caps, *colon;

      lt = strchr (line, '<');
      gt = strrchr (line, '>');
      colon = strchr (line, ':');
      caps = gt != NULL ? strchr (gt, '(') : NULL;
      if (lt == NULL || gt < lt || colon == NULL || colon > lt
          || caps == NULL || strstr (caps, "rec") == NULL)
        continue;
      if (sscanf (line, "pcm%u:", &unit) == 1)
        snprintf (paths[n], 32, "/dev/dsp%u", unit);
      else if (colon - line < (long) sizeof (dev) - 1
               && strncmp (line, "dsp", 3) == 0)
        {
          memcpy (dev, line, (size_t) (colon - line));
          dev[colon - line] = '\0';
          snprintf (paths[n], 32, "/dev/%s", dev);
        }
      else
        continue;
      snprintf (names[n], 96, "%.*s", (int) (gt - lt - 1), lt + 1);
      if (strcmp (names[n], "virtual_oss device") == 0)
        snprintf (names[n], 96, "%s", paths[n] + 5);
      n++;
    }
  fclose (f);
  return n;
}
