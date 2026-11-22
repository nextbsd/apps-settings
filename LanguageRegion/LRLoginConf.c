/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * The record is read and written by hand rather than with getcap(3),
 * which only reads: it's the record's lines, joined at their
 * backslashes, split at the colons getcap splits at (a colon is written
 * "\c" inside a value, so every ':' separates). It's written back one
 * capability to a line, as login.conf(5) shows it.
 */

#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <login_cap.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "LRLoginConf.h"

#define LRRecord "me"
#define LRCapMkdb "/usr/bin/cap_mkdb"
#define LRMaxFile (256 * 1024)
#define LRMaxCaps 128

/* The setenv variables this file owns. */
static const char *const LRVariables[] = { "LC_TIME", "LC_NUMERIC",
                                           "LC_MONETARY", NULL };

/* A growing string. */
typedef struct
{
  char *s;
  size_t len, size;
} LRBuf;

static int
LRBufAdd (LRBuf *b, const char *s, size_t n)
{
  if (b->len + n + 1 > b->size)
    {
      size_t size = (b->len + n + 1) * 2;
      char *s2 = realloc (b->s, size);

      if (s2 == NULL)
        return -1;
      b->s = s2;
      b->size = size;
    }
  memcpy (b->s + b->len, s, n);
  b->len += n;
  b->s[b->len] = '\0';
  return 0;
}

static int
LRBufAddString (LRBuf *b, const char *s)
{
  return LRBufAdd (b, s, strlen (s));
}

/* The whole file; NULL with errno ENOENT when there's none. */
static char *
LRReadFile (const char *path)
{
  struct stat st;
  char *buf;
  ssize_t n;
  size_t got = 0;
  int fd;

  if ((fd = open (path, O_RDONLY | O_CLOEXEC)) == -1)
    return NULL;
  if (fstat (fd, &st) == -1 || !S_ISREG (st.st_mode)
      || st.st_size > LRMaxFile)
    {
      close (fd);
      errno = EINVAL;
      return NULL;
    }
  if ((buf = malloc ((size_t) st.st_size + 1)) == NULL)
    {
      close (fd);
      return NULL;
    }
  while (got < (size_t) st.st_size)
    {
      n = read (fd, buf + got, (size_t) st.st_size - got);
      if (n == -1 && errno == EINTR)
        continue;
      if (n <= 0)
        break;
      got += (size_t) n;
    }
  close (fd);
  buf[got] = '\0';
  return buf;
}

/* The end of the line at p, past its newline. */
static const char *
LRLineEnd (const char *p)
{
  const char *nl = strchr (p, '\n');

  return nl != NULL ? nl + 1 : p + strlen (p);
}

/* Does the line [p, end) end in a backslash, continuing its record? */
static int
LRContinues (const char *p, const char *end)
{
  while (end > p && (end[-1] == '\n' || end[-1] == '\r'))
    end--;
  return end > p && end[-1] == '\\';
}

/* Is the line at p the first of record `name`? Its names, separated by
   '|', end at the first ':'. */
static int
LRRecordStarts (const char *p, const char *name)
{
  size_t n = strlen (name);

  if (*p == '#' || *p == ' ' || *p == '\t' || *p == '\n' || *p == '\0')
    return 0;
  while (*p != '\0' && *p != '\n' && *p != ':')
    {
      if (strncmp (p, name, n) == 0 && (p[n] == '|' || p[n] == ':'))
        return 1;
      while (*p != '\0' && *p != '\n' && *p != ':' && *p != '|')
        p++;
      if (*p == '|')
        p++;
    }
  return 0;
}

/* Find record `name` in text: *start and *end bound its lines. 0 if
   there's none. */
static int
LRFindRecord (const char *text, const char *name, const char **start,
              const char **end)
{
  const char *p, *e;

  for (p = text; *p != '\0'; p = LRLineEnd (p))
    if (LRRecordStarts (p, name))
      break;
  if (*p == '\0')
    return 0;
  *start = p;
  for (;;)
    {
      e = LRLineEnd (p);
      if (!LRContinues (p, e) || *e == '\0')
        break;
      p = e;
    }
  *end = e;
  return 1;
}

/* Split the record [start, end) into its fields: the names first, then
   each capability, malloc'd. Returns the count, or -1. */
static int
LRSplitRecord (const char *start, const char *end, char **fields, int max)
{
  LRBuf joined = { NULL, 0, 0 };
  const char *p = start;
  char *f, *colon;
  int n = 0;

  /* Join the lines: drop each backslash-newline and the indentation
     after it. */
  while (p < end)
    {
      const char *e = LRLineEnd (p), *stop = e;

      while (stop > p && (stop[-1] == '\n' || stop[-1] == '\r'))
        stop--;
      if (stop > p && stop[-1] == '\\')
        stop--;
      if (LRBufAdd (&joined, p, (size_t) (stop - p)) != 0)
        {
          free (joined.s);
          return -1;
        }
      p = e;
      while (p < end && (*p == ' ' || *p == '\t'))
        p++;
    }
  if (joined.s == NULL)
    return 0;
  for (f = joined.s; f != NULL && n < max; f = colon)
    {
      colon = strchr (f, ':');
      if (colon != NULL)
        *colon++ = '\0';
      /* Blank fields (the "::" of the layout) aren't capabilities. */
      while (*f == ' ' || *f == '\t')
        f++;
      if (*f == '\0' && n > 0)
        continue;
      if ((fields[n] = strdup (f)) == NULL)
        break;
      n++;
    }
  free (joined.s);
  return n;
}

static void
LRCopy (char *dst, const char *src, size_t n, size_t size)
{
  if (n >= size)
    n = size - 1;
  memcpy (dst, src, n);
  dst[n] = '\0';
}

/* setenv's list: "A=1,B=2", a comma inside a value written "\,". Calls
   fn for each "NAME=value" entry. */
static void
LREachVariable (const char *list,
                void (*fn) (const char *entry, size_t len, void *ctx),
                void *ctx)
{
  const char *p = list, *e;

  while (*p != '\0')
    {
      for (e = p; *e != '\0' && *e != ','; e++)
        if (*e == '\\' && e[1] != '\0')
          e++;
      if (e > p)
        fn (p, (size_t) (e - p), ctx);
      p = *e == ',' ? e + 1 : e;
    }
}

/* Which of LRVariables is entry ("LC_TIME=x"), or -1. */
static int
LRVariableIndex (const char *entry, size_t len)
{
  int i;

  for (i = 0; LRVariables[i] != NULL; i++)
    {
      size_t n = strlen (LRVariables[i]);

      if (len > n && strncmp (entry, LRVariables[i], n) == 0
          && entry[n] == '=')
        return i;
    }
  return -1;
}

static void
LRReadVariable (const char *entry, size_t len, void *ctx)
{
  LRLoginLocale *out = ctx;
  char *const fields[] = { out->time, out->numeric, out->monetary };
  int i = LRVariableIndex (entry, len);

  if (i >= 0)
    {
      size_t n = strlen (LRVariables[i]) + 1;
      LRCopy (fields[i], entry + n, len - n, LRLocaleNameMax);
    }
}

int
LRLoginConfRead (const char *path, LRLoginLocale *out)
{
  char *text, *fields[LRMaxCaps];
  const char *start, *end;
  int n, i;

  memset (out, 0, sizeof (*out));
  if ((text = LRReadFile (path)) == NULL)
    return errno == ENOENT ? 0 : -1;
  if (!LRFindRecord (text, LRRecord, &start, &end))
    {
      free (text);
      return 0;
    }
  n = LRSplitRecord (start, end, fields, LRMaxCaps);
  for (i = 1; i < n; i++)
    {
      if (strncmp (fields[i], "lang=", 5) == 0)
        LRCopy (out->lang, fields[i] + 5, strlen (fields[i] + 5),
                sizeof (out->lang));
      else if (strncmp (fields[i], "charset=", 8) == 0)
        LRCopy (out->charset, fields[i] + 8, strlen (fields[i] + 8),
                sizeof (out->charset));
      else if (strncmp (fields[i], "setenv=", 7) == 0)
        LREachVariable (fields[i] + 7, LRReadVariable, out);
    }
  for (i = 0; i < n; i++)
    free (fields[i]);
  free (text);
  return 0;
}

/* Keeps the setenv entries this file doesn't own. */
static void
LRKeepVariable (const char *entry, size_t len, void *ctx)
{
  LRBuf *kept = ctx;

  if (LRVariableIndex (entry, len) >= 0)
    return;
  if (kept->len > 0)
    LRBufAddString (kept, ",");
  LRBufAdd (kept, entry, len);
}

/* Replace path with text (or remove it, for ""), mode 0644 as getcap(3)
   wants a user's file: owned by them and writable by nobody else. */
static int
LRWriteFile (const char *path, const char *text)
{
  char tmp[PATH_MAX];
  size_t len = strlen (text), done = 0;
  ssize_t n;
  int fd;

  if (len == 0)
    return unlink (path) == 0 || errno == ENOENT ? 0 : -1;
  snprintf (tmp, sizeof (tmp), "%s.LanguageRegion", path);
  unlink (tmp);
  if ((fd = open (tmp, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0644)) == -1)
    return -1;
  while (done < len)
    {
      n = write (fd, text + done, len - done);
      if (n == -1 && errno == EINTR)
        continue;
      if (n <= 0)
        break;
      done += (size_t) n;
    }
  if (done != len || fchmod (fd, 0644) == -1 || fsync (fd) == -1)
    {
      int saved = errno;
      close (fd);
      unlink (tmp);
      errno = saved != 0 ? saved : EIO;
      return -1;
    }
  close (fd);
  if (rename (tmp, path) == -1)
    {
      int saved = errno;
      unlink (tmp);
      errno = saved;
      return -1;
    }
  return 0;
}

/* Build path.db again if there is one; remove it with the file. */
static void
LRUpdateDatabase (const char *path)
{
  char db[PATH_MAX];
  struct stat st;
  pid_t pid;
  int status;

  snprintf (db, sizeof (db), "%s.db", path);
  if (stat (db, &st) != 0)
    return;
  if (stat (path, &st) != 0)
    {
      unlink (db);
      return;
    }
  if ((pid = fork ()) == 0)
    {
      execl (LRCapMkdb, "cap_mkdb", path, (char *) NULL);
      _exit (127);
    }
  if (pid > 0)
    while (waitpid (pid, &status, 0) == -1 && errno == EINTR)
      ;
}

/* Add ":cap:\" (or the record's last ":cap:") to out. */
static int
LRAddCapability (LRBuf *out, const char *cap)
{
  return LRBufAddString (out, "\t:") || LRBufAddString (out, cap)
    || LRBufAddString (out, ":\\\n");
}

int
LRLoginConfWrite (const char *path, const LRLoginLocale *locale)
{
  const char *const values[] = { locale->time, locale->numeric,
                                 locale->monetary };
  char *text, *fields[LRMaxCaps], cap[LRLocaleNameMax + 16];
  const char *start, *end;
  LRBuf out = { NULL, 0, 0 }, record = { NULL, 0, 0 };
  LRBuf vars = { NULL, 0, 0 };
  int n = 0, i, caps = 0, rc;

  if ((text = LRReadFile (path)) == NULL)
    {
      if (errno != ENOENT || (text = strdup ("")) == NULL)
        return -1;
    }
  if (LRFindRecord (text, LRRecord, &start, &end))
    n = LRSplitRecord (start, end, fields, LRMaxCaps);
  else
    start = end = text + strlen (text);
  if (n < 0)
    {
      free (text);
      return -1;
    }

  /* The record: its names, the capabilities this file doesn't own, then
     the ones it does. */
  LRBufAddString (&record, n > 0 ? fields[0] : LRRecord);
  LRBufAddString (&record, ":\\\n");
  for (i = 1; i < n; i++)
    {
      if (strncmp (fields[i], "lang=", 5) == 0
          || strncmp (fields[i], "charset=", 8) == 0)
        continue;
      if (strncmp (fields[i], "setenv=", 7) == 0)
        {
          LREachVariable (fields[i] + 7, LRKeepVariable, &vars);
          continue;
        }
      LRAddCapability (&record, fields[i]);
      caps++;
    }
  if (locale->charset[0] != '\0')
    {
      snprintf (cap, sizeof (cap), "charset=%s", locale->charset);
      LRAddCapability (&record, cap);
      caps++;
    }
  if (locale->lang[0] != '\0')
    {
      snprintf (cap, sizeof (cap), "lang=%s", locale->lang);
      LRAddCapability (&record, cap);
      caps++;
    }
  for (i = 0; LRVariables[i] != NULL; i++)
    if (values[i][0] != '\0')
      {
        if (vars.len > 0)
          LRBufAddString (&vars, ",");
        LRBufAddString (&vars, LRVariables[i]);
        LRBufAddString (&vars, "=");
        LRBufAddString (&vars, values[i]);
      }
  if (vars.len > 0)
    {
      LRBufAddString (&record, "\t:setenv=");
      LRBufAddString (&record, vars.s);
      LRBufAddString (&record, ":\\\n");
      caps++;
    }
  /* The last capability ends the record: no backslash. */
  if (record.len >= 2)
    {
      record.s[record.len - 2] = '\n';
      record.s[--record.len] = '\0';
    }

  LRBufAdd (&out, text, (size_t) (start - text));
  if (caps > 0)
    {
      if (out.len > 0 && out.s[out.len - 1] != '\n')
        LRBufAddString (&out, "\n");
      LRBufAddString (&out, record.s);
    }
  LRBufAddString (&out, end);

  /* Nothing but blank lines left: no file. */
  for (i = 0; out.s != NULL && out.s[i] != '\0'; i++)
    if (out.s[i] != '\n' && out.s[i] != ' ' && out.s[i] != '\t')
      break;
  rc = out.s == NULL ? -1
    : LRWriteFile (path, out.s[i] == '\0' ? "" : out.s);
  if (rc == 0)
    LRUpdateDatabase (path);

  for (i = 0; i < n; i++)
    free (fields[i]);
  free (text);
  free (out.s);
  free (record.s);
  free (vars.s);
  return rc;
}

void
LRLoginConfSystemLang (char *buf, size_t size)
{
  login_cap_t *lc = login_getclassbyname ("default", NULL);
  const char *lang;

  buf[0] = '\0';
  if (lc == NULL)
    return;
  lang = login_getcapstr (lc, "lang", NULL, NULL);
  if (lang != NULL)
    LRCopy (buf, lang, strlen (lang), size);
  login_close (lc);
}
