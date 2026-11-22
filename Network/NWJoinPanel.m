/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "NWJoinPanel.h"
#import <GNUstepBase/GNUstep.h>

#include <math.h>

#include "NWWiFi.h"

#define NWPanelWidth 460.0
#define NWPanelMargin 20.0
#define NWIconSize 48.0
#define NWLabelWidth 130.0
#define NWFieldX (NWPanelMargin + NWLabelWidth + 8)
#define NWFieldWidth (NWPanelWidth - NWFieldX - NWPanelMargin)
#define NWChooseWidth 80.0
#define NWRowHeight 24.0
#define NWRowGap 8.0
#define NWTop (NWPanelMargin + NWIconSize + 12)

NSString *const NWJoinSSID = @"SSID";
NSString *const NWJoinSecurity = @"Security";
NSString *const NWJoinPassphrase = @"Passphrase";
NSString *const NWJoinEAPMethod = @"EAPMethod";
NSString *const NWJoinTTLSInner = @"TTLSInner";
NSString *const NWJoinUser = @"User";
NSString *const NWJoinPassword = @"Password";
NSString *const NWJoinAnonymousIdentity = @"AnonymousIdentity";
NSString *const NWJoinServerName = @"ServerName";
NSString *const NWJoinCACertificate = @"CACertificate";
NSString *const NWJoinNoVerify = @"NoVerify";
NSString *const NWJoinClientCertificate = @"ClientCertificate";
NSString *const NWJoinPrivateKey = @"PrivateKey";
NSString *const NWJoinKeyPassphrase = @"KeyPassphrase";

/* The rows, in order; -layout shows those the choices need. */
enum
{
  NWRowSSID,
  NWRowSecurity,
  NWRowPassphrase,
  NWRowMethod,
  NWRowInner,
  NWRowUser,
  NWRowPassword,
  NWRowAnonymous,
  NWRowServer,
  NWRowCA,
  NWRowNoVerify,
  NWRowCert,
  NWRowKey,
  NWRowKeyPassphrase,
  NWRowCount
};

/* A view laid out from the top down. */
@interface NWJoinView : NSView
@end

@implementation NWJoinView
- (BOOL)isFlipped
{
  return YES;
}
@end

static NSTextField *
NWLabel (NSRect frame, NSString *text, NSFont *font)
{
  NSTextField *label = AUTORELEASE ([[NSTextField alloc] initWithFrame:frame]);

  [label setStringValue:(text != nil ? text : @"")];
  [label setEditable:NO];
  [label setSelectable:NO];
  [label setBordered:NO];
  [label setBezeled:NO];
  [label setDrawsBackground:NO];
  if (font != nil)
    [label setFont:font];
  return label;
}

static void
NWSetString (NSMutableDictionary *d, NSString *key, NSTextField *field)
{
  NSString *s = [field stringValue];

  if ([s length] > 0)
    [d setObject:s forKey:key];
}

@interface NWJoinPanel (Private)
- (id)initForNetwork:(NSString *)ssid security:(int)security;
- (void)addRow:(NSString *)label views:(NSArray *)views;
- (NSTextField *)field:(Class)class width:(CGFloat)width;
- (NSButton *)chooseButtonFor:(NSTextField *)field;
- (void)layout;
- (NSDictionary *)answer;
- (void)changed:(id)sender;
- (void)choose:(id)sender;
- (void)join:(id)sender;
- (void)cancel:(id)sender;
@end

@implementation NWJoinPanel

+ (NSDictionary *)askForNetwork:(NSString *)ssid
                       security:(int)security
                      forWindow:(NSWindow *)window
{
  NWJoinPanel *join = AUTORELEASE ([[self alloc] initForNetwork:ssid
                                                       security:security]);
  NSPanel *panel = join->panel;
  NSRect over, frame;
  NSDictionary *answer = nil;

  over = window != nil ? [window frame] : [[NSScreen mainScreen] visibleFrame];
  frame = [panel frame];
  frame.origin.x = floor (NSMidX (over) - NSWidth (frame) / 2);
  frame.origin.y = floor (NSMaxY (over) - NSHeight (frame) - 40);
  [panel setFrame:frame display:NO];
  [NSApp activateIgnoringOtherApps:YES];
  if ([NSApp runModalForWindow:panel] == NSOKButton)
    answer = [join answer];
  [panel orderOut:nil];
  [join->passphraseField setStringValue:@""];
  [join->passwordField setStringValue:@""];
  [join->keyPassphraseField setStringValue:@""];
  return answer;
}

- (void)dealloc
{
  RELEASE (panel);
  RELEASE (rows);
  [super dealloc];
}

@end

@implementation NWJoinPanel (Private)

- (id)initForNetwork:(NSString *)ssid security:(int)security
{
  NWJoinView *content;
  NSImageView *icon;

  if ((self = [super init]) == nil)
    return nil;
  rows = [NSMutableArray new];
  fixedNetwork = ssid != nil;
  panel = [[NSPanel alloc]
      initWithContentRect:NSMakeRect (0, 0, NWPanelWidth, 300)
                styleMask:NSTitledWindowMask
                  backing:NSBackingStoreBuffered
                    defer:NO];
  [panel setTitle:@"Join a Wi-Fi Network"];
  [panel setLevel:NSModalPanelWindowLevel];
  [panel setReleasedWhenClosed:NO];
  [panel setHidesOnDeactivate:NO];
  content = AUTORELEASE ([[NWJoinView alloc]
                           initWithFrame:NSMakeRect (0, 0, NWPanelWidth,
                                                     300)]);
  [panel setContentView:content];

  icon = AUTORELEASE ([[NSImageView alloc]
                        initWithFrame:NSMakeRect (NWPanelMargin, NWPanelMargin,
                                                  NWIconSize, NWIconSize)]);
  [icon setImage:[NSApp applicationIconImage]];
  [icon setImageScaling:NSScaleProportionally];
  [icon setEditable:NO];
  [content addSubview:icon];
  message = NWLabel (NSMakeRect (NWPanelMargin + NWIconSize + 16,
                                 NWPanelMargin, NWPanelWidth - NWPanelMargin
                                 - NWIconSize - 16 - NWPanelMargin, 48),
                     fixedNetwork
                       ? [NSString stringWithFormat:@"The Wi-Fi network "
                                   @"\"%@\" needs a %@.", ssid,
                                   security == NWJoinEnterprise
                                     ? @"user name and password"
                                     : @"password"]
                       : @"Type the name of the network to join, and its "
                         @"security.",
                     [NSFont boldSystemFontOfSize:13]);
  [[message cell] setWraps:YES];
  [content addSubview:message];

  ssidField = [self field:[NSTextField class] width:NWFieldWidth];
  if (ssid != nil)
    {
      [ssidField setStringValue:ssid];
      [ssidField setEditable:NO];
      [ssidField setSelectable:YES];
    }
  [self addRow:@"Network Name:" views:[NSArray arrayWithObject:ssidField]];

  securityPopup = AUTORELEASE ([[NSPopUpButton alloc]
                                 initWithFrame:NSMakeRect (0, 0, 240, 24)
                                     pullsDown:NO]);
  [securityPopup addItemWithTitle:@"None"];
  [securityPopup addItemWithTitle:@"WPA/WPA2/WPA3 Personal"];
  [securityPopup addItemWithTitle:@"WPA/WPA2 Enterprise"];
  [securityPopup selectItemAtIndex:security];
  [securityPopup setEnabled:!fixedNetwork];
  [securityPopup setTarget:self];
  [securityPopup setAction:@selector (changed:)];
  [self addRow:@"Security:" views:[NSArray arrayWithObject:securityPopup]];

  passphraseField = (NSSecureTextField *)
    [self field:[NSSecureTextField class] width:NWFieldWidth];
  [self addRow:@"Password:" views:[NSArray arrayWithObject:passphraseField]];

  methodPopup = AUTORELEASE ([[NSPopUpButton alloc]
                               initWithFrame:NSMakeRect (0, 0, 200, 24)
                                   pullsDown:NO]);
  [methodPopup addItemWithTitle:@"PEAP"];
  [[methodPopup lastItem] setTag:NWEAPPEAP];
  [methodPopup addItemWithTitle:@"TTLS"];
  [[methodPopup lastItem] setTag:NWEAPTTLS];
  [methodPopup addItemWithTitle:@"TLS (certificate)"];
  [[methodPopup lastItem] setTag:NWEAPTLS];
  [methodPopup setTarget:self];
  [methodPopup setAction:@selector (changed:)];
  [self addRow:@"Authentication:" views:[NSArray arrayWithObject:methodPopup]];

  innerPopup = AUTORELEASE ([[NSPopUpButton alloc]
                              initWithFrame:NSMakeRect (0, 0, 200, 24)
                                  pullsDown:NO]);
  [innerPopup addItemWithTitle:@"MSCHAPv2"];
  [innerPopup addItemWithTitle:@"PAP"];
  [innerPopup addItemWithTitle:@"CHAP"];
  [self addRow:@"Inner Authentication:"
         views:[NSArray arrayWithObject:innerPopup]];

  userField = [self field:[NSTextField class] width:NWFieldWidth];
  [self addRow:@"User Name:" views:[NSArray arrayWithObject:userField]];
  passwordField = (NSSecureTextField *)
    [self field:[NSSecureTextField class] width:NWFieldWidth];
  [self addRow:@"Password:" views:[NSArray arrayWithObject:passwordField]];
  anonymousField = [self field:[NSTextField class] width:NWFieldWidth];
  [anonymousField setToolTip:@"Sent before the encrypted tunnel starts, "
                             @"instead of the user name. Leave it empty "
                             @"unless the network asks for one."];
  [self addRow:@"Outer Identity:" views:[NSArray arrayWithObject:anonymousField]];
  serverField = [self field:[NSTextField class] width:NWFieldWidth];
  [serverField setToolTip:@"The server's certificate must carry this name, "
                          @"or a name ending in it."];
  [self addRow:@"Server Name:" views:[NSArray arrayWithObject:serverField]];
  caField = [self field:[NSTextField class]
                  width:NWFieldWidth - NWChooseWidth - 8];
  [caField setToolTip:@"A PEM file, or hash://server/sha256/<hex> to pin "
                      @"the server's certificate."];
  [self addRow:@"CA Certificate:"
         views:[NSArray arrayWithObjects:caField,
                        [self chooseButtonFor:caField], nil]];
  noVerifyButton = AUTORELEASE ([[NSButton alloc]
                                  initWithFrame:NSMakeRect (0, 0,
                                                            NWFieldWidth,
                                                            22)]);
  [noVerifyButton setButtonType:NSSwitchButton];
  [noVerifyButton setTitle:@"Don't check the server"];
  [noVerifyButton setTarget:self];
  [noVerifyButton setAction:@selector (changed:)];
  [self addRow:@"" views:[NSArray arrayWithObject:noVerifyButton]];
  certField = [self field:[NSTextField class]
                    width:NWFieldWidth - NWChooseWidth - 8];
  [self addRow:@"Client Certificate:"
         views:[NSArray arrayWithObjects:certField,
                        [self chooseButtonFor:certField], nil]];
  keyField = [self field:[NSTextField class]
                   width:NWFieldWidth - NWChooseWidth - 8];
  [keyField setToolTip:@"PEM or PKCS#12. It must be readable only by "
                       @"you."];
  [self addRow:@"Private Key:"
         views:[NSArray arrayWithObjects:keyField,
                        [self chooseButtonFor:keyField], nil]];
  keyPassphraseField = (NSSecureTextField *)
    [self field:[NSSecureTextField class] width:NWFieldWidth];
  [self addRow:@"Key Password:"
         views:[NSArray arrayWithObject:keyPassphraseField]];

  joinButton = AUTORELEASE ([[NSButton alloc]
                              initWithFrame:NSMakeRect (0, 0, 100, 26)]);
  [joinButton setTitle:@"Join"];
  [joinButton setKeyEquivalent:@"\r"];
  [joinButton setTarget:self];
  [joinButton setAction:@selector (join:)];
  [content addSubview:joinButton];
  {
    NSButton *cancel = AUTORELEASE ([[NSButton alloc]
                                      initWithFrame:NSMakeRect (0, 0, 100,
                                                                26)]);
    [cancel setTitle:@"Cancel"];
    [cancel setKeyEquivalent:@"\e"];
    [cancel setTarget:self];
    [cancel setAction:@selector (cancel:)];
    [cancel setTag:1];
    [content addSubview:cancel];
  }
  [self layout];
  [panel setInitialFirstResponder:fixedNetwork
                                    ? (security == NWJoinEnterprise
                                         ? (NSView *) userField
                                         : (NSView *) passphraseField)
                                    : (NSView *) ssidField];
  return self;
}

/* A row: its label, then its views from the field column on. */
- (void)addRow:(NSString *)label views:(NSArray *)views
{
  NSMutableArray *row = [NSMutableArray array];
  NSTextField *title = NWLabel (NSMakeRect (NWPanelMargin, 0, NWLabelWidth,
                                            20), label, nil);
  NSEnumerator *e = [views objectEnumerator];
  NSView *view;

  [title setAlignment:NSRightTextAlignment];
  [row addObject:title];
  [[panel contentView] addSubview:title];
  while ((view = [e nextObject]) != nil)
    {
      [row addObject:view];
      [[panel contentView] addSubview:view];
    }
  [rows addObject:row];
}

- (NSTextField *)field:(Class)class width:(CGFloat)width
{
  NSTextField *field = AUTORELEASE ([[class alloc]
                                      initWithFrame:NSMakeRect (0, 0, width,
                                                                NWRowHeight)]);
  [field setTarget:self];
  [field setAction:@selector (join:)];
  return field;
}

- (NSButton *)chooseButtonFor:(NSTextField *)field
{
  NSButton *b = AUTORELEASE ([[NSButton alloc]
                               initWithFrame:NSMakeRect (0, 0, NWChooseWidth,
                                                         NWRowHeight)]);
  [b setTitle:@"Choose…"];
  [b setTarget:self];
  [b setAction:@selector (choose:)];
  [[b cell] setRepresentedObject:field];
  return b;
}

/* Show the rows the security and method need, top down, and size the
   panel to them. */
- (void)layout
{
  int security = [securityPopup indexOfSelectedItem];
  int method = [[methodPopup selectedItem] tag];
  BOOL enterprise = security == NWJoinEnterprise;
  BOOL tls = method == NWEAPTLS, noVerify = [noVerifyButton state];
  BOOL show[NWRowCount];
  NSView *content = [panel contentView];
  NSRect frame;
  CGFloat y = NWTop, height;
  int i;

  show[NWRowSSID] = YES;
  show[NWRowSecurity] = YES;
  show[NWRowPassphrase] = security == NWJoinPersonal;
  show[NWRowMethod] = enterprise;
  show[NWRowInner] = enterprise && method == NWEAPTTLS;
  show[NWRowUser] = enterprise;
  show[NWRowPassword] = enterprise && !tls;
  show[NWRowAnonymous] = enterprise && !tls;
  show[NWRowServer] = enterprise && !noVerify;
  show[NWRowCA] = enterprise && !noVerify;
  show[NWRowNoVerify] = enterprise;
  show[NWRowCert] = enterprise && tls;
  show[NWRowKey] = enterprise && tls;
  show[NWRowKeyPassphrase] = enterprise && tls;

  for (i = 0; i < NWRowCount; i++)
    {
      NSArray *row = [rows objectAtIndex:i];
      NSUInteger j;
      CGFloat x = NWFieldX;

      for (j = 0; j < [row count]; j++)
        {
          NSView *view = [row objectAtIndex:j];

          [view setHidden:!show[i]];
          if (j == 0)
            [view setFrameOrigin:NSMakePoint (NWPanelMargin, y + 3)];
          else
            {
              [view setFrameOrigin:NSMakePoint (x, y)];
              x += NSWidth ([view frame]) + 8;
            }
        }
      if (show[i])
        y += NWRowHeight + NWRowGap;
    }

  height = y + 12 + 26 + NWPanelMargin;
  [joinButton setFrameOrigin:NSMakePoint (NWPanelWidth - NWPanelMargin - 100,
                                          height - NWPanelMargin - 26)];
  [[content viewWithTag:1]
      setFrameOrigin:NSMakePoint (NWPanelWidth - NWPanelMargin - 208,
                                  height - NWPanelMargin - 26)];
  /* Keep the top where it is. */
  frame = [panel frame];
  frame.origin.y += NSHeight ([content frame]) - height;
  frame.size = [panel frameRectForContentRect:
                        NSMakeRect (0, 0, NWPanelWidth, height)].size;
  [panel setFrame:frame display:YES];
  [content setFrameSize:NSMakeSize (NWPanelWidth, height)];
  [content setNeedsDisplay:YES];
}

- (NSDictionary *)answer
{
  NSMutableDictionary *d = [NSMutableDictionary dictionary];
  int security = [securityPopup indexOfSelectedItem];
  int method = [[methodPopup selectedItem] tag];

  NWSetString (d, NWJoinSSID, ssidField);
  [d setObject:[NSNumber numberWithInt:security] forKey:NWJoinSecurity];
  if (security == NWJoinPersonal)
    NWSetString (d, NWJoinPassphrase, passphraseField);
  if (security != NWJoinEnterprise)
    return d;
  [d setObject:[NSNumber numberWithInt:method] forKey:NWJoinEAPMethod];
  [d setObject:[NSNumber numberWithInt:[innerPopup indexOfSelectedItem]]
        forKey:NWJoinTTLSInner];
  NWSetString (d, NWJoinUser, userField);
  if (method != NWEAPTLS)
    {
      NWSetString (d, NWJoinPassword, passwordField);
      NWSetString (d, NWJoinAnonymousIdentity, anonymousField);
    }
  if ([noVerifyButton state] == NSOnState)
    [d setObject:[NSNumber numberWithBool:YES] forKey:NWJoinNoVerify];
  else
    {
      NWSetString (d, NWJoinServerName, serverField);
      NWSetString (d, NWJoinCACertificate, caField);
    }
  if (method == NWEAPTLS)
    {
      NWSetString (d, NWJoinClientCertificate, certField);
      NWSetString (d, NWJoinPrivateKey, keyField);
      NWSetString (d, NWJoinKeyPassphrase, keyPassphraseField);
    }
  return d;
}

- (void)changed:(id)sender
{
  [self layout];
}

- (void)choose:(id)sender
{
  NSOpenPanel *open = [NSOpenPanel openPanel];
  NSTextField *field = [[sender cell] representedObject];

  [open setCanChooseFiles:YES];
  [open setCanChooseDirectories:NO];
  [open setAllowsMultipleSelection:NO];
  if ([open runModalForDirectory:nil file:nil types:nil] == NSOKButton)
    [field setStringValue:[open filename]];
  [panel makeKeyAndOrderFront:nil];
}

/* Join, once what the choice needs is there. */
- (void)join:(id)sender
{
  int security = [securityPopup indexOfSelectedItem];
  int method = [[methodPopup selectedItem] tag];
  NSUInteger length = [[passphraseField stringValue] length];
  NSString *problem = nil;

  if ([[ssidField stringValue] length] == 0)
    problem = @"Type the network's name.";
  else if ([[ssidField stringValue] lengthOfBytesUsingEncoding:
                                      NSUTF8StringEncoding] > 32)
    problem = @"A network's name is at most 32 bytes long.";
  else if (security == NWJoinPersonal && (length < 8 || length > 64))
    problem = @"A Wi-Fi password is 8 to 63 characters long (or 64 "
              @"hexadecimal digits).";
  else if (security == NWJoinEnterprise
           && [[userField stringValue] length] == 0)
    problem = @"Type your user name.";
  else if (security == NWJoinEnterprise && method != NWEAPTLS
           && [[passwordField stringValue] length] == 0)
    problem = @"Type your password.";
  else if (security == NWJoinEnterprise && method == NWEAPTLS
           && [[keyField stringValue] length] == 0)
    problem = @"Choose your private key.";
  else if (security == NWJoinEnterprise && [noVerifyButton state] != NSOnState
           && [[serverField stringValue] length] == 0
           && [[caField stringValue] length] == 0)
    problem = @"Say how to check the network's server: its name or a CA "
              @"certificate. (Or choose not to check it, which lets anyone "
              @"who uses the network's name collect your password.)";
  if (problem != nil)
    {
      [message setStringValue:problem];
      [message setFont:[NSFont systemFontOfSize:12]];
      NSBeep ();
      return;
    }
  [NSApp stopModalWithCode:NSOKButton];
}

- (void)cancel:(id)sender
{
  [NSApp stopModalWithCode:NSCancelButton];
}

@end
