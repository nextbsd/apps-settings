/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#include <sys/types.h>
#include <sys/sysctl.h>
#include <sys/user.h>

#include <stdlib.h>
#include <string.h>

#include "DTSystem.h"

int
DTNetworkTimeRunning (void)
{
  int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PROC, 0 };
  struct kinfo_proc *procs = NULL;
  size_t len = 0, i, n;
  int found = 0, tries;

  /* The table can grow between the two calls; try a few times. */
  for (tries = 0; tries < 3; tries++)
    {
      if (sysctl (mib, 4, NULL, &len, NULL, 0) != 0)
        return 0;
      len += len / 8;
      free (procs);
      procs = malloc (len);
      if (procs == NULL)
        return 0;
      if (sysctl (mib, 4, procs, &len, NULL, 0) == 0)
        break;
    }
  if (tries == 3)
    {
      free (procs);
      return 0;
    }
  n = len / sizeof (struct kinfo_proc);
  for (i = 0; i < n && !found; i++)
    found = procs[i].ki_uid == 0 && strcmp (procs[i].ki_comm, "ntpd") == 0;
  free (procs);
  return found;
}
