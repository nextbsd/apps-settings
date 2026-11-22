/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * NWJoinPanel: "Join a Wi-Fi network", as macOS's Join Other Network
 * sheet: the network's name, its security (none, WPA/WPA2/WPA3
 * Personal, WPA Enterprise), and what that needs:
 *   - Personal: the passphrase;
 *   - Enterprise (802.1X): the method (PEAP, TTLS with its inner method,
 *     TLS), the user name and password, an anonymous outer identity,
 *     and how to check the server: its name, a CA certificate, or not
 *     at all; for TLS the client certificate and private key.
 * Only the rows the choice needs are shown. A network picked from the
 * scan comes with its name and security filled in.
 *
 * The panel runs modally and hands back what was typed. Network passes
 * it straight to wland (NWWiFi) and forgets it: nothing is kept here.
 */

#import <AppKit/AppKit.h>

/* The panel's security choices. */
enum
{
  NWJoinNone = 0,
  NWJoinPersonal = 1,
  NWJoinEnterprise = 2
};

/* Keys of the answer. Strings unless said; absent when empty. */
extern NSString *const NWJoinSSID;
extern NSString *const NWJoinSecurity;		/* NSNumber, NWJoin* */
extern NSString *const NWJoinPassphrase;
extern NSString *const NWJoinEAPMethod;		/* NSNumber, NWEAP* */
extern NSString *const NWJoinTTLSInner;		/* NSNumber */
extern NSString *const NWJoinUser;
extern NSString *const NWJoinPassword;
extern NSString *const NWJoinAnonymousIdentity;
extern NSString *const NWJoinServerName;
extern NSString *const NWJoinCACertificate;
extern NSString *const NWJoinNoVerify;		/* NSNumber, BOOL */
extern NSString *const NWJoinClientCertificate;
extern NSString *const NWJoinPrivateKey;
extern NSString *const NWJoinKeyPassphrase;

@interface NWJoinPanel : NSObject
{
  NSPanel *panel;
  NSTextField *message;
  NSTextField *ssidField;
  NSPopUpButton *securityPopup;
  NSSecureTextField *passphraseField;
  NSPopUpButton *methodPopup;
  NSPopUpButton *innerPopup;
  NSTextField *userField;
  NSSecureTextField *passwordField;
  NSTextField *anonymousField;
  NSTextField *serverField;
  NSTextField *caField;
  NSButton *noVerifyButton;
  NSTextField *certField;
  NSTextField *keyField;
  NSSecureTextField *keyPassphraseField;
  NSButton *joinButton;
  NSMutableArray *rows;		/* NSArrays of the views on each row */
  BOOL fixedNetwork;		/* the name came from the scan */
}

/* Ask how to join. ssid nil: any network (Join Other Network); else that
   one, with security its NWJoin*. nil when cancelled. */
+ (NSDictionary *)askForNetwork:(NSString *)ssid
                       security:(int)security
                      forWindow:(NSWindow *)window;

@end
