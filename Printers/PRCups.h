/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * PRCups: Printers' side of libcups (Apple's CUPS 2.3.4, from
 * nextbsd-printing-support), as the user, over IPP to the local cupsd
 * (org.nextbsd.cupsd, which launchd starts on the first connection to
 * /var/run/cupsd):
 *   - the printers: the local queues (cupsEnumDests without the
 *     discovered ones, and without the temporary queues cupsd makes
 *     for them), each with its state and its waiting jobs
 *     (cupsGetJobs2);
 *   - nearby printers: the driverless (IPP Everywhere) printers that
 *     libcups finds through mDNSResponder (DNS-SD) and that have no
 *     queue yet;
 *   - the user's own default printer and options, in ~/.cups/lpoptions
 *     (cupsGetDests2 and cupsSetDests2, as lpoptions(1) does), which
 *     need no privilege;
 *   - what a printer offers for paper size and two-sided printing
 *     (cupsCopyDestInfo).
 * Adding and removing a queue are root's: the controller asks
 * SettingsHelper (CUPSAdmin).
 *
 * A printer is a dictionary with the PR* keys below. libcups keeps its
 * state per thread, so PRCupsNearby may run on another thread.
 */

#import <Foundation/Foundation.h>

/* A printer's keys. */
extern NSString *const PRName;		/* the queue's name */
extern NSString *const PRInfo;		/* its description: the name shown */
extern NSString *const PRLocation;
extern NSString *const PRModel;		/* make and model */
extern NSString *const PRDeviceURI;
extern NSString *const PRState;		/* NSNumber: IPP_PSTATE_* */
extern NSString *const PRReasons;	/* printer-state-reasons, or "none" */
extern NSString *const PRAccepting;	/* NSNumber, BOOL */
extern NSString *const PRDefault;	/* NSNumber, BOOL: the user's default */
extern NSString *const PRMedia;		/* the user's paper size, if set */
extern NSString *const PRSides;		/* the user's two-sided, if set */
extern NSString *const PRJobs;		/* NSArray of jobs, oldest first */

/* A job's keys. */
extern NSString *const PRJobTitle;
extern NSString *const PRJobUser;
extern NSString *const PRJobState;	/* NSNumber: IPP_JSTATE_* */

/* The options Printers sets, IPP's names (CUPS_MEDIA, CUPS_SIDES). */
extern NSString *const PROptionMedia;	/* "media" */
extern NSString *const PROptionSides;	/* "sides" */

/* The local queues, by description. nil: cupsd didn't answer. */
NSArray *PRCupsPrinters (void);

/* Driverless printers nearby without a queue, waiting up to msec for
 * DNS-SD: PRName (a queue name made from the service), PRInfo, PRModel,
 * PRLocation and PRDeviceURI. queues are the printers already set up. */
NSArray *PRCupsNearby (NSArray *queues, int msec);

/* Make printer the user's default (lpoptions -d). */
BOOL PRCupsSetDefault (NSString *printer);

/* Set the user's value of option for printer; nil goes back to the
 * printer's own default (lpoptions -o, -r). */
BOOL PRCupsSetOption (NSString *printer, NSString *option, NSString *value);

/* Forget a removed printer in the user's lpoptions: its options, and the
 * default if it was. */
BOOL PRCupsForget (NSString *printer);

/* What printer offers for option: its values, in the printer's order,
 * and in *byDefault the printer's own default. nil: nothing to offer. */
NSArray *PRCupsChoices (NSString *printer, NSString *option,
                        NSString **byDefault);

/* "US Letter (8.5 × 11 in)" for na_letter_8.5x11in, "Long edge" for
 * two-sided-long-edge: an option value as the window shows it. */
NSString *PRCupsValueName (NSString *option, NSString *value);

/* "Idle", "Printing", "Stopped", with the reasons that matter. */
NSString *PRCupsStateText (NSDictionary *printer);

/* A queue name from a description, as cupsd takes one: no spaces or
 * / \ ? ' " #, at most 127 bytes, and not in taken. */
NSString *PRCupsQueueName (NSString *info, NSArray *taken);

/* A device URI from what was typed in "Address": a URI as it is, or a
 * host name or address as ipp://host/ipp/print. nil: not one. */
NSString *PRCupsURIForAddress (NSString *address);
