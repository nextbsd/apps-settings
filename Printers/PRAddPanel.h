/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * PRAddPanel: the sheet the + button shows. The driverless printers
 * nearby (DNS-SD through mDNSResponder, looked for again every few
 * seconds on another thread while the sheet is up), or a printer by its
 * address: a host name, an IP address, or an ipp://, ipps:// or
 * dnssd:// URI. Then its name and location, and Cancel and Add.
 */

#import <AppKit/AppKit.h>

@class PRAddPanel;

@protocol PRAddPanelDelegate
/* Add pressed: a device URI, the name to show (the queue's description)
   and the location, which may be empty. */
- (void)addPanel:(PRAddPanel *)panel
    didChooseURI:(NSString *)uri
            info:(NSString *)info
        location:(NSString *)location;
@end

@interface PRAddPanel : NSObject
{
  NSPanel *panel;
  NSTableView *nearbyTable;
  NSTextField *searchNote;
  NSTextField *addressField;
  NSTextField *nameField;
  NSTextField *locationField;
  NSButton *addButton;
  NSArray *nearby;		/* PRCupsNearby's printers */
  NSArray *queues;		/* the printers set up, to leave out */
  NSTimer *timer;
  BOOL looking;			/* a search is running */
  BOOL nameTyped;		/* the name is the user's, not the list's */
  BOOL filling;			/* the panel, not the user, sets a field */
  id delegate;			/* not retained */
}

- (id)initWithDelegate:(id<PRAddPanelDelegate>)delegate;

/* Show the sheet over window. queues: the printers already set up. */
- (void)beginSheetForWindow:(NSWindow *)window queues:(NSArray *)queues;

@end
