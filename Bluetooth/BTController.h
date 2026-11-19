/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * BTController: Bluetooth's app delegate and its one window, as macOS's
 * Bluetooth settings:
 *   - Bluetooth on or off, and the controller's name. While the window
 *     is open the computer is discoverable (a timed discoverable that
 *     bluetoothd ends by itself, so a persisted setting is never
 *     touched); and Show Bluetooth in Dock, the Dock's Bluetooth
 *     extra (NBDockExtra);
 *   - My Devices: the paired devices, what each is and whether it's
 *     connected, with Connect, Disconnect and Remove; Connect
 *     automatically; and for a headset whether it plays audio and
 *     whether it's used as stereo headphones or as a headset with its
 *     microphone;
 *   - Nearby Devices: what a scan finds, and Pair, which opens the
 *     pairing panel (BTPairingPanel).
 * A click applies at once; there's no Apply button. Everything follows
 * bluetoothd's notifications and State:/Bluetooth, so changes made
 * elsewhere (bluetooth(8), a device connecting) show at once.
 */

#import <AppKit/AppKit.h>
#import "BTClient.h"
#import "BTPairingPanel.h"
#import "NBDockExtra.h"

@interface BTController : NSObject <BTPairingPanelDelegate>
{
  NSWindow *window;
  BTClient *client;
  int wakeFDs[2];
  NSFileHandle *wakeHandle;
  NSTimer *heartbeat;
  BTPairingPanel *pairingPanel;

  /* What bluetoothd said last. */
  BOOL reachable;
  BOOL haveAdapter;
  BOOL powered;
  BOOL scanning;
  BTClientStatus status;
  BTClientAdapter adapter;
  NSArray *pairedDevices;	/* BTDevice */
  NSArray *nearbyDevices;	/* BTDevice, not paired */
  NSString *shownPaired;
  NSString *shownNearby;
  BOOL wasPowered;
  NSTimeInterval discoverableArmed;	/* when, 0 if not by us */
  NSMutableSet *dismissedPrompts;	/* addresses */

  /* The window's controls; the window retains them. */
  NSTextField *powerTitle;
  NSTextField *powerDetail;
  NSButton *powerButton;
  NSButton *dockSwitch;		/* Show Bluetooth in Dock */
  NBDockExtra *dockExtra;
  NSTableView *pairedTable;
  NSTextField *deviceDetail;
  NSButton *connectButton;
  NSButton *disconnectButton;
  NSButton *removeButton;
  NSButton *autoconnectSwitch;
  NSButton *audioSwitch;
  NSTextField *routeLabel;
  NSPopUpButton *routePopup;
  NSTableView *nearbyTable;
  NSProgressIndicator *searchSpinner;
  NSTextField *searchStatus;
  NSButton *searchButton;
  NSButton *pairButton;
}
@end
