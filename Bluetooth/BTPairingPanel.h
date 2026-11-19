/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * BTPairingPanel: pairing with one device, shown over the Bluetooth
 * window as a sheet would be. It follows the pairing the way
 * `bluetooth pair` does (bt_pair_status, four times a second) and asks
 * what bluetoothd's prompt asks:
 *   - just works: nothing to ask when we started it (choosing Pair was
 *     the yes, as for the CLI); "Pair with ...?" when the device did;
 *   - numeric comparison: does the device show this code?
 *   - passkey entry: type the code the device shows;
 *   - passkey display: type this code on the device;
 *   - legacy PIN: type the PIN.
 * The answer goes back with bt_pair_confirm; Cancel or Escape says no.
 * It also answers a prompt a device started on its own
 * (State:/Bluetooth/Pairing/<addr>), while the Mac is discoverable.
 */

#import <AppKit/AppKit.h>
#import "BTClient.h"

@class BTPairingPanel;

@protocol BTPairingPanelDelegate
/* It ended: paired, failed (with a bt_status_t), or the user cancelled. */
- (void)pairingPanel:(BTPairingPanel *)panel
         didPairWith:(NSString *)address;
- (void)pairingPanel:(BTPairingPanel *)panel
     didFailWithName:(NSString *)name
              status:(int)status;
- (void)pairingPanelDidCancel:(BTPairingPanel *)panel;
@end

@interface BTPairingPanel : NSObject
{
  BTClient *_client;		/* not owned */
  id _delegate;			/* not retained */
  NSPanel *_panel;
  NSTextField *_title;
  NSTextField *_message;
  NSTextField *_code;
  NSTextField *_entry;
  NSTextField *_expires;
  NSProgressIndicator *_spinner;
  NSButton *_pair;
  NSButton *_cancel;
  NSTimer *_timer;
  NSString *_address;
  NSString *_name;
  BOOL _incoming;		/* the device asked, not us */
  BOOL _answered;
  BOOL _sawPrompt;
  NSTimeInterval _started;
  int _shownState;
  int _shownPasskey;
  int _method;
  int _passkey;
}

- (id)initWithClient:(BTClient *)client
            delegate:(id<BTPairingPanelDelegate>)delegate;

/* Start pairing; 0 when it started (the panel shows), else the
   bt_status_t it was refused with. */
- (int)pairWithAddress:(NSString *)address
                  name:(NSString *)name
            overWindow:(NSWindow *)window;

/* Answer the prompt a device started. */
- (void)answerPromptFrom:(NSString *)address
                    name:(NSString *)name
              overWindow:(NSWindow *)window;

- (BOOL)isVisible;
/* The device it's pairing with, or nil. */
- (NSString *)address;
/* Follow the pairing now (a notification came). */
- (void)update;
/* Close without answering. */
- (void)close;

@end
