/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * NWController: Network's app delegate and its one window, laid out as
 * macOS's Network pane (nextbsd/nextbsd#638):
 *   - the computer's name and its local host name ("name.local") at the
 *     top;
 *   - the network services at the left, in service order, each with a
 *     status light: green connected, yellow connected without an
 *     address (or joining), red not connected, grey inactive;
 *   - the chosen service at the right: its status in a sentence; for
 *     Wi-Fi the network it has joined, the networks around (choosing one
 *     joins it, asking for its password), Join Other Network (WPA
 *     Personal or Enterprise), Disconnect, and "Show Wi-Fi status in
 *     Dock"; then three tabs: TCP/IP (IPv4 by DHCP, DHCP with a manual
 *     address, manually or off; IPv6 automatically, manually, link-local
 *     only or off), DNS (servers and search domains), and Hardware (the
 *     interface, its address, and for Wi-Fi the access point);
 *   - the lock, Revert and Apply.
 *
 * As on macOS, changes to services and names wait until Apply, which
 * sends each changed service to SettingsHelper's
 * CommitNetworkPreferences and the names to SetComputerName (right
 * org.nextbsd.settings.network) once the lock is open; Revert forgets
 * them. Joining a Wi-Fi network needs no right: it goes to wland at once
 * (NWWiFi). "Show Wi-Fi status in Dock" asks the Dock, as the other
 * settings apps' "Show X in Dock" checkboxes do (NBDockExtra).
 *
 * Everything is read again every second (NWSystem: SCPreferences and
 * the dynamic store), so a change made with scutil, by DHCP or by
 * another copy of the app shows at once. Opened from the Dock's Wi-Fi
 * extra, as from anywhere, it starts on the Wi-Fi service.
 *
 * Wi-Fi on and off, and the known networks, aren't here yet: wland has
 * no calls for them.
 */

#import <AppKit/AppKit.h>
#import "NBAuthorizationPanel.h"

@class NBDockExtra;

@interface NWController : NSObject <NBLockViewDelegate, NSTextFieldDelegate>
{
  NSWindow *window;
  NBAuthorization *auth;
  NBLockView *lockView;
  NSTimer *timer;
  void *system;			/* NWSystem */

  /* The names. */
  NSTextField *nameField;
  NSTextField *localField;
  NSTextField *localNote;

  /* The services. */
  NSTableView *serviceTable;
  NSData *services;		/* NWService[], as last read */
  NSString *selectedID;		/* the service shown */

  /* The chosen service. */
  NSImageView *statusLight;
  NSTextField *statusLabel;
  NSTextField *statusNote;
  NSView *wifiBox;
  NSPopUpButton *networkPopup;
  NSButton *joinOtherButton;
  NSButton *disconnectButton;
  NSButton *showInDockButton;
  NSTabView *tabView;
  NSPopUpButton *ipv4Popup;
  NSTextField *ipv4Address;
  NSTextField *ipv4Mask;
  NSTextField *ipv4Router;
  NSPopUpButton *ipv6Popup;
  NSTextField *ipv6Address;
  NSTextField *ipv6Prefix;
  NSTextField *ipv6Router;
  NSTextField *dnsField;
  NSTextField *searchField;
  NSTextField *dnsNote;
  NSTextField *hardwareLabel;
  NSButton *applyButton;
  NSButton *revertButton;

  /* Changes waiting for Apply. */
  NSMutableDictionary *pending;	/* service ID -> NBNet* settings */
  NSString *pendingName;	/* nil: unchanged */
  NSString *pendingLocalName;
  BOOL localEdited;		/* typed, not made from the name */

  /* Wi-Fi. */
  NSString *wifiInterface;	/* wland's, or nil */
  NSArray *networks;		/* the last scan's, NSDictionaries */
  BOOL scanning;
  unsigned scanGeneration;
  NSTimeInterval scanStarted;
  NSTimeInterval scanDate;
  NSString *joiningSSID;	/* asked to join; nil when not */
  NSTimeInterval joiningSince;
  NBDockExtra *dockExtra;

  NSString *shownState;		/* what the controls were set from */
  BOOL settingControls;		/* the window, not the user, sets them */
}
@end
