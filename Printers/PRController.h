/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * PRController: Printers' app delegate and its one window, as macOS's
 * Printers & Scanners (nextbsd/nextbsd#640):
 *   - the printers (the local cupsd's queues) on the left, + and - under
 *     them;
 *   - the selected printer on the right: its status, location, kind,
 *     address and the jobs waiting for it, then its paper size and
 *     two-sided printing;
 *   - the default printer;
 *   - the lock, Defaults and Revert.
 * Adding and removing a printer are root's: they go through
 * SettingsHelper's CUPSAdmin (right org.nextbsd.settings.printers,
 * is-admin, so an administrator's lock is open without a password), on
 * another thread, since adding one asks the printer for what it can do.
 *
 * The default printer, paper size and two-sided are the user's own, in
 * ~/.cups/lpoptions, and need no privilege: the default printer is each
 * user's, as lpoptions -d sets it, and the options are what print
 * dialogs start from. Defaults puts every printer's options back to the
 * printer's own; Revert puts back what the window opened with.
 *
 * The printers are read again every two seconds, so a printer added
 * with lpadmin or a job sent from another app shows at once.
 */

#import <AppKit/AppKit.h>
#import "NBAuthorizationPanel.h"
#import "PRAddPanel.h"

@interface PRController : NSObject <NBLockViewDelegate, PRAddPanelDelegate>
{
  NSWindow *window;
  NBAuthorization *auth;
  NBLockView *lockView;
  NSTimer *timer;
  PRAddPanel *addPanel;

  /* The list. */
  NSTableView *printerTable;
  NSButton *addButton;
  NSButton *removeButton;
  NSTextField *progressNote;	/* "Adding ..." */

  /* The selected printer. */
  NSView *detailView;
  NSTextField *emptyNote;	/* instead of it: no printers, no cupsd */
  NSTextField *nameLabel;
  NSTextField *statusField;
  NSTextField *locationField;
  NSTextField *kindField;
  NSTextField *addressField;
  NSTextField *queueField;
  NSTableView *jobTable;
  NSPopUpButton *mediaPopup;
  NSPopUpButton *sidesPopup;

  NSPopUpButton *defaultPopup;

  /* What's in effect, read every two seconds. */
  NSArray *printers;		/* PRCupsPrinters; nil: cupsd didn't answer */
  NSString *selectedName;	/* the queue selected */
  NSString *shownState;		/* what the controls were set from */
  BOOL selecting;		/* the window, not the user, selects */
  BOOL busy;			/* the helper is adding or removing */

  /* The selected printer's choices, loaded when it's selected. */
  NSString *choicesFor;
  NSArray *mediaValues;
  NSString *mediaDefault;
  NSArray *sidesValues;
  NSString *sidesDefault;

  /* For Revert: as the window opened. */
  NSString *originalDefault;
  NSDictionary *originalOptions;	/* name -> {media, sides} */
}
@end
