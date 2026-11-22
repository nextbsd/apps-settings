/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "NWController.h"
#import "NWJoinPanel.h"
#import "NBDockExtra.h"
#import "NBSettingsHelper.h"
#import <GNUstepBase/GNUstep.h>

#include <arpa/inet.h>
#include <netinet/in.h>
#include <string.h>

#include "NWSystem.h"
#include "NWWiFi.h"

/* Layout, in points. */
#define NWMargin 20.0
#define NWWindowWidth 720.0
#define NWNamesHeight 96.0
#define NWListWidth 180.0
#define NWBodyHeight 470.0
#define NWDetailX (NWMargin + NWListWidth + 12)
#define NWDetailWidth (NWWindowWidth - NWDetailX - NWMargin)
#define NWLabelWidth 130.0
#define NWFieldX (NWLabelWidth + 8)
#define NWRowStep 30.0
#define NWRowGap 10.0
#define NWButtonWidth 100.0
#define NWButtonHeight 26.0
#define NWWiFiHeight 100.0
/* The lock and its sentence, beside Revert and Apply. */
#define NWLockWidth (NWWindowWidth - 2 * NWMargin - 2 * NWButtonWidth - 16)

/* A scan older than this is done again while Wi-Fi is shown. */
#define NWRescanAge 30.0
/* wland gives a sweep this long (wlan(8)'s limit). */
#define NWScanTimeout 15.0
/* How long "Joining" shows before the join is taken to have failed. */
#define NWJoinTimeout 30.0
#define NWMaxNetworks 64

static NSString *const NWRight = @"org.nextbsd.settings.network";
static NSString *const NWReason = @"change the network settings";

/* A view laid out from the top down. */
@interface NWFlippedView : NSView
@end

@implementation NWFlippedView
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

static NSTextField *
NWRowLabel (CGFloat y, NSString *text)
{
  NSTextField *label = NWLabel (NSMakeRect (0, y + 3, NWLabelWidth, 20), text,
                                nil);
  [label setAlignment:NSRightTextAlignment];
  return label;
}

static NSFont *
NWSmallFont (void)
{
  return [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
}

static NSString *
NWString (const char *s)
{
  NSString *string = s != NULL ? [NSString stringWithUTF8String:s] : nil;

  return string != nil ? string : @"";
}

/* A list from NWSystem (one entry a line) as an array. */
static NSArray *
NWLines (const char *s)
{
  NSMutableArray *list = [NSMutableArray array];
  NSEnumerator *e = [[NWString (s) componentsSeparatedByString:@"\n"]
                        objectEnumerator];
  NSString *line;

  while ((line = [e nextObject]) != nil)
    if ([line length] > 0)
      [list addObject:line];
  return list;
}

/* What's typed in a list field: entries split by commas or spaces. */
static NSArray *
NWWords (NSString *text)
{
  NSMutableArray *list = [NSMutableArray array];
  NSCharacterSet *split = [NSCharacterSet characterSetWithCharactersInString:
                                            @", \t\n"];
  NSEnumerator *e = [[text componentsSeparatedByCharactersInSet:split]
                        objectEnumerator];
  NSString *word;

  while ((word = [e nextObject]) != nil)
    if ([word length] > 0)
      [list addObject:word];
  return list;
}

static BOOL
NWIsIPv4 (NSString *s)
{
  struct in_addr a;

  return [s length] > 0 && inet_pton (AF_INET, [s UTF8String], &a) == 1;
}

static BOOL
NWIsIPv6 (NSString *s)
{
  struct in6_addr a;

  return [s length] > 0 && inet_pton (AF_INET6, [s UTF8String], &a) == 1;
}

static BOOL
NWIsMask (NSString *s)
{
  struct in_addr a;
  uint32_t m;

  if ([s length] == 0 || inet_pton (AF_INET, [s UTF8String], &a) != 1)
    return NO;
  m = ntohl (a.s_addr);
  return m != 0 && (~m & (~m + 1)) == 0;
}

/* A search domain, as SettingsHelper takes one. */
static BOOL
NWIsDomain (NSString *s)
{
  NSCharacterSet *ok = [NSCharacterSet characterSetWithCharactersInString:
      @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-."];

  return [s length] > 0 && [s length] <= 63
    && [[s stringByTrimmingCharactersInSet:ok] length] == 0
    && ![s hasPrefix:@"."] && ![s hasPrefix:@"-"] && ![s hasSuffix:@"-"]
    && [s rangeOfString:@".."].location == NSNotFound;
}

/* The LocalHostName macOS makes from a computer name: letters and
   digits kept, spaces and the rest as single hyphens, at most 63. */
static NSString *
NWLocalNameFrom (NSString *name)
{
  NSMutableString *local = [NSMutableString string];
  NSUInteger i;
  BOOL hyphen = NO;

  for (i = 0; i < [name length] && [local length] < 63; i++)
    {
      unichar c = [name characterAtIndex:i];

      if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
          || (c >= '0' && c <= '9'))
        {
          if (hyphen && [local length] > 0)
            [local appendString:@"-"];
          hyphen = NO;
          [local appendFormat:@"%C", c];
        }
      else if (c != '\'')
        hyphen = YES;
    }
  return [local length] > 0 ? (NSString *) local : @"NextBSD";
}

static BOOL
NWIsLocalName (NSString *s)
{
  NSCharacterSet *ok = [NSCharacterSet characterSetWithCharactersInString:
      @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-"];

  return [s length] > 0 && [s length] <= 63
    && [[s stringByTrimmingCharactersInSet:ok] length] == 0
    && ![s hasPrefix:@"-"] && ![s hasSuffix:@"-"];
}

/* ---- pictures ---- */

typedef enum
{
  NWGreen,
  NWYellow,
  NWRed,
  NWGrey
} NWLight;

static NSImage *
NWLightImage (NWLight light)
{
  NSImage *image = AUTORELEASE ([[NSImage alloc]
                                  initWithSize:NSMakeSize (14, 14)]);
  NSColor *color;
  NSBezierPath *dot;

  switch (light)
    {
    case NWGreen:
      color = [NSColor colorWithCalibratedRed:0.20 green:0.78 blue:0.30
                                        alpha:1.0];
      break;
    case NWYellow:
      color = [NSColor colorWithCalibratedRed:0.98 green:0.75 blue:0.10
                                        alpha:1.0];
      break;
    case NWRed:
      color = [NSColor colorWithCalibratedRed:0.92 green:0.25 blue:0.22
                                        alpha:1.0];
      break;
    default:
      color = [NSColor colorWithCalibratedWhite:0.62 alpha:1.0];
      break;
    }
  [image lockFocus];
  dot = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect (1.5, 1.5, 11, 11)];
  [color set];
  [dot fill];
  [[color shadowWithLevel:0.35] set];
  [dot setLineWidth:1.0];
  [dot stroke];
  [image unlockFocus];
  return image;
}

/* A network in the list: signal bars (wlan(8)'s steps) and, when it's
   secured, a padlock. */
static NSImage *
NWSignalImage (int rssi, BOOL secured)
{
  NSImage *image = AUTORELEASE ([[NSImage alloc]
                                  initWithSize:NSMakeSize (30, 14)]);
  NSColor *on = [NSColor controlTextColor];
  NSColor *off = [on colorWithAlphaComponent:0.25];
  int bars = rssi >= -60 ? 3 : rssi >= -70 ? 2 : 1;
  NSPoint center = NSMakePoint (8, 1.5);
  int i;

  [image lockFocus];
  for (i = 0; i < 3; i++)
    {
      NSBezierPath *arc = [NSBezierPath bezierPath];

      [arc appendBezierPathWithArcWithCenter:center radius:3.5 + 3.5 * i
                                  startAngle:45.0 endAngle:135.0];
      [arc setLineWidth:1.8];
      [arc setLineCapStyle:NSRoundLineCapStyle];
      [(i < bars ? on : off) set];
      [arc stroke];
    }
  [on set];
  [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect (6.8, 0.3, 2.4, 2.4)]
      fill];
  if (secured)
    {
      NSBezierPath *shackle = [NSBezierPath bezierPath];

      [[NSBezierPath bezierPathWithRect:NSMakeRect (21, 1, 7, 6)] fill];
      [shackle appendBezierPathWithArcWithCenter:NSMakePoint (24.5, 7)
                                          radius:2.3 startAngle:0
                                        endAngle:180];
      [shackle setLineWidth:1.3];
      [shackle stroke];
    }
  [image unlockFocus];
  return image;
}

/* ---- a service's settings, as NBNet* dictionaries ---- */

/* The settings as configured, with only the keys its methods use, so two
   can be compared. */
static NSDictionary *
NWConfigured (const NWService *s)
{
  NSMutableDictionary *d = [NSMutableDictionary dictionary];

  [d setObject:[NSNumber numberWithInt:s->ipv4Method] forKey:NBNetIPv4Method];
  if (s->ipv4Method == NWIPv4Manual || s->ipv4Method == NWIPv4DHCPManualAddress)
    [d setObject:NWString (s->ipv4Address) forKey:NBNetIPv4Address];
  if (s->ipv4Method == NWIPv4Manual)
    {
      [d setObject:NWString (s->ipv4Mask) forKey:NBNetIPv4SubnetMask];
      [d setObject:NWString (s->ipv4Router) forKey:NBNetIPv4Router];
    }
  [d setObject:[NSNumber numberWithInt:s->ipv6Method] forKey:NBNetIPv6Method];
  if (s->ipv6Method == NWIPv6Manual)
    {
      [d setObject:NWString (s->ipv6Address) forKey:NBNetIPv6Address];
      [d setObject:[NSNumber numberWithInt:s->ipv6Prefix]
            forKey:NBNetIPv6PrefixLength];
      [d setObject:NWString (s->ipv6Router) forKey:NBNetIPv6Router];
    }
  [d setObject:NWLines (s->dnsServers) forKey:NBNetDNSServers];
  [d setObject:NWLines (s->searchDomains) forKey:NBNetSearchDomains];
  return d;
}

/* A service's status: its light, a word or two, and a sentence. */
static NWLight
NWStatus (const NWService *s, NSString *joining, NSString **word,
          NSString **sentence)
{
  NSString *name = NWString (s->name);
  NSString *address = NWString (s->addressNow);
  BOOL selfAssigned = [address hasPrefix:@"169.254."];

  if (!s->enabled)
    {
      *word = @"Inactive";
      *sentence = [NSString stringWithFormat:@"%@ is turned off.", name];
      return NWGrey;
    }
  if (s->wifi)
    {
      NSString *ssid = NWString (s->ssid);

      if (joining != nil && !(s->authenticated && [ssid isEqual:joining]))
        {
          *word = @"Joining";
          *sentence = [NSString stringWithFormat:@"%@ is joining \"%@\".",
                                name, joining];
          return NWYellow;
        }
      if (!s->airport || [ssid length] == 0)
        {
          *word = @"Not Connected";
          *sentence = [NSString stringWithFormat:
                         @"%@ is on but isn't connected to a network.", name];
          return NWRed;
        }
      if (!s->authenticated)
        {
          *word = @"Joining";
          *sentence = [NSString stringWithFormat:@"%@ is joining \"%@\".",
                                name, ssid];
          return NWYellow;
        }
      if ([address length] == 0 || selfAssigned)
        {
          *word = selfAssigned ? @"Self-Assigned IP" : @"No IP Address";
          *sentence = [NSString stringWithFormat:
                         @"%@ is connected to \"%@\" but has no address "
                         @"from it yet%@.", name, ssid,
                         selfAssigned ? @" (it gave itself one)" : @""];
          return NWYellow;
        }
      *word = @"Connected";
      *sentence = [NSString stringWithFormat:
                     @"%@ is connected to \"%@\" and has the IP address "
                     @"%@.", name, ssid, address];
      return NWGreen;
    }
  if (s->linkActive == 0)
    {
      *word = @"Cable Unplugged";
      *sentence = [NSString stringWithFormat:
                     @"The cable for %@ isn't plugged in.", name];
      return NWRed;
    }
  if (s->ipv4Method == NWIPv4Off && s->ipv6Method == NWIPv6Off)
    {
      *word = @"Not Configured";
      *sentence = [NSString stringWithFormat:
                     @"%@ has IPv4 and IPv6 turned off.", name];
      return NWRed;
    }
  if ([address length] == 0 || selfAssigned)
    {
      *word = selfAssigned ? @"Self-Assigned IP" : @"No IP Address";
      *sentence = [NSString stringWithFormat:
                     @"%@ is connected but has no address%@.", name,
                     selfAssigned ? @" from DHCP (it gave itself one)"
                                  : @" yet"];
      return NWYellow;
    }
  *word = @"Connected";
  *sentence = [NSString stringWithFormat:
                 @"%@ is connected and has the IP address %@.", name,
                 address];
  return NWGreen;
}

@interface NWController (Private)
- (void)buildMenu;
- (NSView *)namesView;
- (NSView *)detailView;
- (NSView *)tcpipTab:(NSRect)frame;
- (NSView *)dnsTab:(NSRect)frame;
- (NSView *)hardwareTab:(NSRect)frame;
- (NSView *)bottomRow;
- (NSTextField *)field:(NSRect)frame;
- (int)serviceCount;
- (const NWService *)serviceAt:(int)i;
- (const NWService *)selected;
- (NSDictionary *)settingsFor:(const NWService *)s;
- (void)tick:(NSTimer *)t;
- (void)reload;
- (void)updateControls;
- (void)updateNames;
- (void)updateService;
- (void)updateWiFi:(const NWService *)s;
- (void)updateHardware:(const NWService *)s;
- (BOOL)isEditing:(NSTextField *)field;
- (void)setField:(NSTextField *)field to:(NSString *)value
        editable:(BOOL)editable;
- (BOOL)hasChanges;
- (void)capture;
- (void)chooseIPv4:(id)sender;
- (void)chooseIPv6:(id)sender;
- (void)scan;
- (void)pollScan;
- (void)chooseNetwork:(id)sender;
- (void)joinOther:(id)sender;
- (void)join:(NSDictionary *)answer;
- (void)disconnect:(id)sender;
- (void)toggleShowInDock:(id)sender;
- (void)dockExtraChanged:(NBDockExtra *)extra;
- (NSString *)problemIn:(NSDictionary *)settings;
- (int)commit:(id)what;
- (BOOL)apply:(id)what;
- (void)applyChanges:(id)sender;
- (void)revert:(id)sender;
@end

@implementation NWController

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [timer invalidate];
  RELEASE (timer);
  [dockExtra invalidate];
  RELEASE (dockExtra);
  NWSystemClose (system);
  RELEASE (window);
  RELEASE (auth);
  RELEASE (lockView);
  RELEASE (services);
  RELEASE (selectedID);
  RELEASE (pending);
  RELEASE (pendingName);
  RELEASE (pendingLocalName);
  RELEASE (wifiInterface);
  RELEASE (networks);
  RELEASE (joiningSSID);
  RELEASE (shownState);
  [super dealloc];
}

- (void)applicationDidFinishLaunching:(NSNotification *)note
{
  NSImage *icon = [NSImage imageNamed:@"Network.png"];
  NWFlippedView *content;
  NSScrollView *scroll;
  NSTableColumn *column;
  NSBox *line;
  NSView *view;
  CGFloat height, bodyY = NWMargin + NWNamesHeight + NWRowGap;
  char names[4][16];
  int i;

  if (icon != nil)
    [NSApp setApplicationIconImage:icon];
  [self buildMenu];

  auth = RETAIN ([NBAuthorization authorizationWithRight:NWRight]);
  lockView = [[NBLockView alloc]
                initWithFrame:NSMakeRect (0, 0, NWLockWidth, 30)
                authorization:auth
                       reason:NWReason];
  [lockView setDelegate:self];
  system = NWSystemOpen ();
  pending = [NSMutableDictionary new];
  networks = [NSArray new];
  if (NWWiFiInterfaces (names, 4) > 0)
    wifiInterface = [[NSString alloc] initWithUTF8String:names[0]];
  dockExtra = [[NBDockExtra alloc] initWithIdentifier:NBDockExtraWiFi
                                           bundleName:@"WiFi"];
  [dockExtra setTarget:self action:@selector (dockExtraChanged:)];

  height = bodyY + NWBodyHeight + NWRowGap + 30 + NWMargin;
  window = [[NSWindow alloc]
      initWithContentRect:NSMakeRect (200, 200, NWWindowWidth, height)
                styleMask:NSTitledWindowMask | NSClosableWindowMask
                          | NSMiniaturizableWindowMask
                  backing:NSBackingStoreBuffered
                    defer:NO];
  [window setTitle:@"Network"];
  [window setReleasedWhenClosed:NO];
  [window setFrameAutosaveName:@"Network"];
  [window setDelegate:self];

  content = AUTORELEASE ([[NWFlippedView alloc]
                           initWithFrame:NSMakeRect (0, 0, NWWindowWidth,
                                                     height)]);
  view = [self namesView];
  [view setFrameOrigin:NSMakePoint (NWMargin, NWMargin)];
  [content addSubview:view];
  line = AUTORELEASE ([[NSBox alloc]
                        initWithFrame:NSMakeRect (NWMargin, bodyY - 6,
                                                  NWWindowWidth
                                                  - 2 * NWMargin, 1)]);
  [line setBoxType:NSBoxSeparator];
  [content addSubview:line];

  scroll = AUTORELEASE ([[NSScrollView alloc]
                          initWithFrame:NSMakeRect (NWMargin, bodyY + 4,
                                                    NWListWidth,
                                                    NWBodyHeight - 4)]);
  [scroll setBorderType:NSBezelBorder];
  serviceTable = AUTORELEASE ([[NSTableView alloc]
                                initWithFrame:[[scroll contentView] bounds]]);
  column = AUTORELEASE ([[NSTableColumn alloc] initWithIdentifier:@"light"]);
  [column setWidth:20];
  [column setEditable:NO];
  [column setDataCell:AUTORELEASE ([[NSImageCell alloc] init])];
  [serviceTable addTableColumn:column];
  column = AUTORELEASE ([[NSTableColumn alloc] initWithIdentifier:@"name"]);
  [column setWidth:NWListWidth - 26];
  [column setEditable:NO];
  [[column dataCell] setWraps:YES];
  [serviceTable addTableColumn:column];
  [serviceTable setHeaderView:nil];
  [serviceTable setCornerView:nil];
  [serviceTable setRowHeight:34];
  [serviceTable setAllowsEmptySelection:NO];
  [serviceTable setAllowsMultipleSelection:NO];
  [serviceTable setDataSource:self];
  [serviceTable setDelegate:self];
  [scroll setDocumentView:serviceTable];
  [content addSubview:scroll];

  view = [self detailView];
  [view setFrameOrigin:NSMakePoint (NWDetailX, bodyY)];
  [content addSubview:view];

  view = [self bottomRow];
  [view setFrameOrigin:NSMakePoint (NWMargin,
                                    bodyY + NWBodyHeight + NWRowGap)];
  [content addSubview:view];
  [window setContentView:content];

  [self reload];
  /* Start on Wi-Fi, as macOS's Wi-Fi menu opens the pane; else on the
     service in use; else the first. */
  for (i = 0; i < [self serviceCount] && selectedID == nil; i++)
    if ([self serviceAt:i]->wifi)
      ASSIGN (selectedID, NWString ([self serviceAt:i]->serviceID));
  for (i = 0; i < [self serviceCount] && selectedID == nil; i++)
    if ([self serviceAt:i]->primary)
      ASSIGN (selectedID, NWString ([self serviceAt:i]->serviceID));
  if (selectedID == nil && [self serviceCount] > 0)
    ASSIGN (selectedID, NWString ([self serviceAt:0]->serviceID));
  DESTROY (shownState);
  [self reload];
  [self dockExtraChanged:dockExtra];
  [window makeKeyAndOrderFront:self];
  [self scan];

  ASSIGN (timer, [NSTimer scheduledTimerWithTimeInterval:1.0
                                                  target:self
                                                selector:@selector (tick:)
                                                userInfo:nil
                                                 repeats:YES]);
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app
{
  return YES;
}

/* Network has no documents; a file it's asked to open just brings the
   window forward. */
- (BOOL)application:(NSApplication *)app openFile:(NSString *)filename
{
  [window makeKeyAndOrderFront:self];
  return YES;
}

/* Changes not applied: apply them, or not, as macOS asks. */
- (BOOL)windowShouldClose:(id)sender
{
  NSInteger answer;

  if (![self hasChanges])
    return YES;
  answer = NSRunAlertPanel (@"Network", @"You have changed the network "
                            @"settings. Apply the changes?", @"Apply",
                            @"Cancel", @"Don't Apply");
  if (answer == NSAlertDefaultReturn)
    {
      [self applyChanges:nil];
      return ![self hasChanges];
    }
  return answer == NSAlertOtherReturn;
}

- (void)lockViewDidChange:(NBLockView *)view
{
  DESTROY (shownState);
  [self reload];
}

/* ---- the service list ---- */

- (NSInteger)numberOfRowsInTableView:(NSTableView *)table
{
  return [self serviceCount];
}

- (id)tableView:(NSTableView *)table
    objectValueForTableColumn:(NSTableColumn *)column
                          row:(NSInteger)row
{
  const NWService *s = [self serviceAt:row];
  NSString *word, *sentence;
  NWLight light;
  NSMutableAttributedString *text;
  NSDictionary *small;

  if (s == NULL)
    return nil;
  light = NWStatus (s, [NWString (s->serviceID) isEqual:selectedID]
                         ? joiningSSID : nil, &word, &sentence);
  if ([[column identifier] isEqual:@"light"])
    return NWLightImage (light);
  small = [NSDictionary dictionaryWithObject:NWSmallFont ()
                                      forKey:NSFontAttributeName];
  text = AUTORELEASE ([[NSMutableAttributedString alloc]
                        initWithString:[NWString (s->name)
                                         stringByAppendingString:@"\n"]
                            attributes:[NSDictionary dictionaryWithObject:
                                          [NSFont boldSystemFontOfSize:0]
                                          forKey:NSFontAttributeName]]);
  [text appendAttributedString:
          AUTORELEASE ([[NSAttributedString alloc] initWithString:word
                                                       attributes:small])];
  return text;
}

- (void)tableViewSelectionDidChange:(NSNotification *)note
{
  NSInteger row = [serviceTable selectedRow];
  const NWService *s = [self serviceAt:row];

  if (settingControls || s == NULL)
    return;
  ASSIGN (selectedID, NWString (s->serviceID));
  [window makeFirstResponder:nil];
  DESTROY (shownState);
  [self reload];
  if (s->wifi)
    [self scan];
}

/* Typing in a field is a change, kept until Apply. */
- (void)controlTextDidChange:(NSNotification *)note
{
  id field = [note object];
  NWNames names;

  if (settingControls)
    return;
  memset (&names, 0, sizeof (names));
  NWSystemReadNames (system, &names);
  if (field == nameField)
    {
      ASSIGN (pendingName, [nameField stringValue]);
      if (!localEdited)
        {
          ASSIGN (pendingLocalName, NWLocalNameFrom (pendingName));
          [localField setStringValue:pendingLocalName];
        }
    }
  else if (field == localField)
    {
      localEdited = YES;
      ASSIGN (pendingLocalName, [localField stringValue]);
    }
  else
    [self capture];
  /* Typed back as they were: no change. */
  if ([pendingName isEqual:NWString (names.computerName)])
    DESTROY (pendingName);
  if ([pendingLocalName isEqual:NWString (names.localHostName)])
    DESTROY (pendingLocalName);
  DESTROY (shownState);
  [self reload];
}

@end

@implementation NWController (Private)

- (void)buildMenu
{
  NSMenu *menu = AUTORELEASE ([[NSMenu alloc] initWithTitle:@"Network"]);
  NSMenu *edit = AUTORELEASE ([[NSMenu alloc] initWithTitle:@"Edit"]);
  NSMenu *windows = AUTORELEASE ([[NSMenu alloc] initWithTitle:@"Window"]);
  id<NSMenuItem> item;

  [menu addItemWithTitle:@"About Network"
                  action:@selector (orderFrontStandardAboutPanel:)
           keyEquivalent:@""];
  /* The fields take typing, so cut, copy and paste. */
  item = [menu addItemWithTitle:@"Edit" action:NULL keyEquivalent:@""];
  [edit addItemWithTitle:@"Cut" action:@selector (cut:) keyEquivalent:@"x"];
  [edit addItemWithTitle:@"Copy" action:@selector (copy:) keyEquivalent:@"c"];
  [edit addItemWithTitle:@"Paste" action:@selector (paste:)
           keyEquivalent:@"v"];
  [edit addItemWithTitle:@"Select All" action:@selector (selectAll:)
           keyEquivalent:@"a"];
  [menu setSubmenu:edit forItem:item];
  item = [menu addItemWithTitle:@"Window" action:NULL keyEquivalent:@""];
  [windows addItemWithTitle:@"Minimize"
                     action:@selector (performMiniaturize:)
              keyEquivalent:@"m"];
  [windows addItemWithTitle:@"Close"
                     action:@selector (performClose:)
              keyEquivalent:@"w"];
  [menu setSubmenu:windows forItem:item];
  [NSApp setWindowsMenu:windows];
  [menu addItemWithTitle:@"Hide" action:@selector (hide:) keyEquivalent:@"h"];
  [menu addItemWithTitle:@"Quit" action:@selector (terminate:) keyEquivalent:@"q"];
  [NSApp setMainMenu:menu];
}

- (NSTextField *)field:(NSRect)frame
{
  NSTextField *field = AUTORELEASE ([[NSTextField alloc] initWithFrame:frame]);

  [field setDelegate:self];
  return field;
}

/* The computer's name and its local host name. */
- (NSView *)namesView
{
  CGFloat width = NWWindowWidth - 2 * NWMargin, y = 0;
  NWFlippedView *view = AUTORELEASE ([[NWFlippedView alloc]
                                       initWithFrame:NSMakeRect (0, 0, width,
                                                                 NWNamesHeight)]);

  [view addSubview:NWRowLabel (y, @"Computer Name:")];
  nameField = [self field:NSMakeRect (NWFieldX, y, 300, 24)];
  [view addSubview:nameField];
  y += NWRowStep;
  [view addSubview:NWRowLabel (y, @"Local Hostname:")];
  localField = [self field:NSMakeRect (NWFieldX, y, 220, 24)];
  [view addSubview:localField];
  [view addSubview:NWLabel (NSMakeRect (NWFieldX + 224, y + 3, 60, 20),
                            @".local", nil)];
  y += NWRowStep;
  localNote = NWLabel (NSMakeRect (NWFieldX, y, width - NWFieldX, 32), nil,
                       NWSmallFont ());
  [[localNote cell] setWraps:YES];
  [view addSubview:localNote];
  return view;
}

/* The chosen service: its status, Wi-Fi, and the tabs. */
- (NSView *)detailView
{
  NWFlippedView *view = AUTORELEASE ([[NWFlippedView alloc]
                                       initWithFrame:NSMakeRect (0, 0,
                                                                 NWDetailWidth,
                                                                 NWBodyHeight)]);
  CGFloat width = NWDetailWidth, y = 4;
  NSTabViewItem *item;
  NSRect inner;

  [view addSubview:NWRowLabel (y, @"Status:")];
  statusLight = AUTORELEASE ([[NSImageView alloc]
                               initWithFrame:NSMakeRect (NWFieldX, y + 4, 14,
                                                         14)]);
  [statusLight setEditable:NO];
  [view addSubview:statusLight];
  statusLabel = NWLabel (NSMakeRect (NWFieldX + 20, y + 3, 220, 20), nil,
                         [NSFont boldSystemFontOfSize:13]);
  [view addSubview:statusLabel];
  y += 26;
  statusNote = NWLabel (NSMakeRect (NWFieldX, y, width - NWFieldX, 34), nil,
                        NWSmallFont ());
  [[statusNote cell] setWraps:YES];
  [view addSubview:statusNote];
  y += 38;

  /* Wi-Fi: shown only for a Wi-Fi service. */
  wifiBox = AUTORELEASE ([[NWFlippedView alloc]
                           initWithFrame:NSMakeRect (0, y, width,
                                                     NWWiFiHeight)]);
  [wifiBox addSubview:NWRowLabel (0, @"Network Name:")];
  networkPopup = AUTORELEASE ([[NSPopUpButton alloc]
                                initWithFrame:NSMakeRect (NWFieldX, 0, 260, 24)
                                    pullsDown:NO]);
  [networkPopup setTarget:self];
  [networkPopup setAction:@selector (chooseNetwork:)];
  [wifiBox addSubview:networkPopup];
  joinOtherButton = AUTORELEASE ([[NSButton alloc]
                                   initWithFrame:NSMakeRect (NWFieldX,
                                                             NWRowStep, 170,
                                                             NWButtonHeight)]);
  [joinOtherButton setTitle:@"Join Other Network…"];
  [joinOtherButton setTarget:self];
  [joinOtherButton setAction:@selector (joinOther:)];
  [wifiBox addSubview:joinOtherButton];
  disconnectButton = AUTORELEASE ([[NSButton alloc]
                                    initWithFrame:NSMakeRect (NWFieldX + 178,
                                                              NWRowStep, 110,
                                                              NWButtonHeight)]);
  [disconnectButton setTitle:@"Disconnect"];
  [disconnectButton setToolTip:@"Leave the network. Wi-Fi doesn't join it "
                               @"again by itself until you choose it."];
  [disconnectButton setTarget:self];
  [disconnectButton setAction:@selector (disconnect:)];
  [wifiBox addSubview:disconnectButton];
  showInDockButton = AUTORELEASE ([[NSButton alloc]
                                    initWithFrame:NSMakeRect (NWFieldX,
                                                              2 * NWRowStep + 4,
                                                              300, 22)]);
  [showInDockButton setButtonType:NSSwitchButton];
  [showInDockButton setTitle:@"Show Wi-Fi status in Dock"];
  [showInDockButton setTarget:self];
  [showInDockButton setAction:@selector (toggleShowInDock:)];
  [wifiBox addSubview:showInDockButton];
  [view addSubview:wifiBox];

  /* -updateService moves it up when there's no Wi-Fi. */
  tabView = AUTORELEASE ([[NSTabView alloc]
                           initWithFrame:NSMakeRect (0, y + NWWiFiHeight,
                                                     width,
                                                     NWBodyHeight - y
                                                     - NWWiFiHeight)]);
  [view addSubview:tabView];
  inner = [tabView contentRect];
  inner.origin = NSZeroPoint;
  item = AUTORELEASE ([[NSTabViewItem alloc] initWithIdentifier:@"tcpip"]);
  [item setLabel:@"TCP/IP"];
  [item setView:[self tcpipTab:inner]];
  [tabView addTabViewItem:item];
  item = AUTORELEASE ([[NSTabViewItem alloc] initWithIdentifier:@"dns"]);
  [item setLabel:@"DNS"];
  [item setView:[self dnsTab:inner]];
  [tabView addTabViewItem:item];
  item = AUTORELEASE ([[NSTabViewItem alloc] initWithIdentifier:@"hardware"]);
  [item setLabel:@"Hardware"];
  [item setView:[self hardwareTab:inner]];
  [tabView addTabViewItem:item];
  return view;
}

- (NSView *)tcpipTab:(NSRect)frame
{
  NWFlippedView *view = AUTORELEASE ([[NWFlippedView alloc]
                                       initWithFrame:frame]);
  CGFloat y = 12;

  [view addSubview:NWRowLabel (y, @"Configure IPv4:")];
  ipv4Popup = AUTORELEASE ([[NSPopUpButton alloc]
                             initWithFrame:NSMakeRect (NWFieldX, y, 250, 24)
                                 pullsDown:NO]);
  [ipv4Popup addItemWithTitle:@"Using DHCP"];
  [ipv4Popup addItemWithTitle:@"Using DHCP with manual address"];
  [ipv4Popup addItemWithTitle:@"Manually"];
  [ipv4Popup addItemWithTitle:@"Off"];
  [ipv4Popup setTarget:self];
  [ipv4Popup setAction:@selector (chooseIPv4:)];
  [view addSubview:ipv4Popup];
  y += NWRowStep;
  [view addSubview:NWRowLabel (y, @"IPv4 Address:")];
  ipv4Address = [self field:NSMakeRect (NWFieldX, y, 160, 24)];
  [view addSubview:ipv4Address];
  y += NWRowStep;
  [view addSubview:NWRowLabel (y, @"Subnet Mask:")];
  ipv4Mask = [self field:NSMakeRect (NWFieldX, y, 160, 24)];
  [view addSubview:ipv4Mask];
  y += NWRowStep;
  [view addSubview:NWRowLabel (y, @"Router:")];
  ipv4Router = [self field:NSMakeRect (NWFieldX, y, 160, 24)];
  [view addSubview:ipv4Router];
  y += NWRowStep + NWRowGap;

  [view addSubview:NWRowLabel (y, @"Configure IPv6:")];
  ipv6Popup = AUTORELEASE ([[NSPopUpButton alloc]
                             initWithFrame:NSMakeRect (NWFieldX, y, 250, 24)
                                 pullsDown:NO]);
  [ipv6Popup addItemWithTitle:@"Automatically"];
  [ipv6Popup addItemWithTitle:@"Manually"];
  [ipv6Popup addItemWithTitle:@"Link-local only"];
  [ipv6Popup addItemWithTitle:@"Off"];
  [ipv6Popup setTarget:self];
  [ipv6Popup setAction:@selector (chooseIPv6:)];
  [view addSubview:ipv6Popup];
  y += NWRowStep;
  [view addSubview:NWRowLabel (y, @"IPv6 Address:")];
  ipv6Address = [self field:NSMakeRect (NWFieldX, y, 290, 24)];
  [view addSubview:ipv6Address];
  y += NWRowStep;
  [view addSubview:NWRowLabel (y, @"Prefix Length:")];
  ipv6Prefix = [self field:NSMakeRect (NWFieldX, y, 60, 24)];
  [view addSubview:ipv6Prefix];
  y += NWRowStep;
  [view addSubview:NWRowLabel (y, @"Router:")];
  ipv6Router = [self field:NSMakeRect (NWFieldX, y, 290, 24)];
  [view addSubview:ipv6Router];
  return view;
}

- (NSView *)dnsTab:(NSRect)frame
{
  NWFlippedView *view = AUTORELEASE ([[NWFlippedView alloc]
                                       initWithFrame:frame]);
  CGFloat width = NSWidth (frame) - NWFieldX - NWMargin, y = 12;

  [view addSubview:NWRowLabel (y, @"DNS Servers:")];
  dnsField = [self field:NSMakeRect (NWFieldX, y, width, 24)];
  [view addSubview:dnsField];
  y += NWRowStep;
  [view addSubview:NWRowLabel (y, @"Search Domains:")];
  searchField = [self field:NSMakeRect (NWFieldX, y, width, 24)];
  [view addSubview:searchField];
  y += NWRowStep + 4;
  dnsNote = NWLabel (NSMakeRect (NWFieldX, y, width, 110), nil,
                     NWSmallFont ());
  [[dnsNote cell] setWraps:YES];
  [view addSubview:dnsNote];
  return view;
}

- (NSView *)hardwareTab:(NSRect)frame
{
  NWFlippedView *view = AUTORELEASE ([[NWFlippedView alloc]
                                       initWithFrame:frame]);

  hardwareLabel = NWLabel (NSMakeRect (NWMargin, 12,
                                       NSWidth (frame) - 2 * NWMargin,
                                       NSHeight (frame) - 24), nil, nil);
  [[hardwareLabel cell] setWraps:YES];
  [hardwareLabel setSelectable:YES];
  [view addSubview:hardwareLabel];
  return view;
}

/* The lock at the left, Revert and Apply at the right. */
- (NSView *)bottomRow
{
  CGFloat width = NWWindowWidth - 2 * NWMargin;
  NWFlippedView *row = AUTORELEASE ([[NWFlippedView alloc]
                                      initWithFrame:NSMakeRect (0, 0, width,
                                                                30)]);

  [lockView setFrameOrigin:NSMakePoint (0, 0)];
  [row addSubview:lockView];

  applyButton = AUTORELEASE ([[NSButton alloc]
                               initWithFrame:NSMakeRect (width - NWButtonWidth,
                                                         2, NWButtonWidth,
                                                         NWButtonHeight)]);
  [applyButton setTitle:@"Apply"];
  [applyButton setTarget:self];
  [applyButton setAction:@selector (applyChanges:)];
  [row addSubview:applyButton];

  revertButton = AUTORELEASE ([[NSButton alloc]
                                initWithFrame:NSMakeRect (width
                                                          - 2 * NWButtonWidth
                                                          - 8, 2,
                                                          NWButtonWidth,
                                                          NWButtonHeight)]);
  [revertButton setTitle:@"Revert"];
  [revertButton setTarget:self];
  [revertButton setAction:@selector (revert:)];
  [row addSubview:revertButton];
  return row;
}

/* ---- the services as read ---- */

- (int)serviceCount
{
  return (int) ([services length] / sizeof (NWService));
}

- (const NWService *)serviceAt:(int)i
{
  if (i < 0 || i >= [self serviceCount])
    return NULL;
  return (const NWService *) [services bytes] + i;
}

- (const NWService *)selected
{
  int i;

  for (i = 0; i < [self serviceCount]; i++)
    if ([NWString ([self serviceAt:i]->serviceID) isEqual:selectedID])
      return [self serviceAt:i];
  return NULL;
}

/* What the controls show: the change waiting, else what's configured. */
- (NSDictionary *)settingsFor:(const NWService *)s
{
  NSDictionary *d = [pending objectForKey:NWString (s->serviceID)];

  return d != nil ? d : NWConfigured (s);
}

/* ---- following the system ---- */

/* Every second: the lock's time, a scan's progress, and anything changed
   elsewhere. */
- (void)tick:(NSTimer *)t
{
  const NWService *s;

  [lockView update];
  [self pollScan];
  s = [self selected];
  if (s != NULL && s->wifi && !scanning
      && [NSDate timeIntervalSinceReferenceDate] - scanDate > NWRescanAge)
    [self scan];
  [self reload];
}

/* Read everything again, and set the controls if anything shown
   changed. */
- (void)reload
{
  NWService list[NWMaxServices];
  NWNames names;
  NSData *read;
  NSString *state;
  const NWService *s;
  int n = NWSystemReadServices (system, list, NWMaxServices);

  memset (&names, 0, sizeof (names));
  NWSystemReadNames (system, &names);
  read = [NSData dataWithBytes:list length:n * sizeof (NWService)];
  ASSIGN (services, read);

  /* A join is over once the network is joined, or after a while. */
  s = [self selected];
  if (joiningSSID != nil
      && ((s != NULL && s->authenticated
           && [NWString (s->ssid) isEqual:joiningSSID])
          || [NSDate timeIntervalSinceReferenceDate] - joiningSince
             > NWJoinTimeout))
    DESTROY (joiningSSID);

  state = [NSString stringWithFormat:@"%@ %s %s %@ %@ %@ %@ %@ %d %d %d %@",
                    read, names.computerName, names.localHostName, selectedID,
                    pending, pendingName, pendingLocalName, networks,
                    (int) scanning, (int) [lockView isUnlocked], [auth status],
                    joiningSSID];
  if ([state isEqual:shownState])
    return;
  ASSIGN (shownState, state);
  [self updateControls];
}

- (void)updateControls
{
  BOOL changes = [self hasChanges];
  NSInteger row = -1;
  int i;

  settingControls = YES;
  [serviceTable reloadData];
  for (i = 0; i < [self serviceCount]; i++)
    if ([NWString ([self serviceAt:i]->serviceID) isEqual:selectedID])
      row = i;
  if (row >= 0 && row != [serviceTable selectedRow])
    [serviceTable selectRow:row byExtendingSelection:NO];
  [self updateNames];
  [self updateService];
  [applyButton setEnabled:changes];
  [revertButton setEnabled:changes];
  settingControls = NO;
}

- (void)updateNames
{
  NWNames names;
  BOOL unlocked = [lockView isUnlocked];
  NSString *local;

  memset (&names, 0, sizeof (names));
  NWSystemReadNames (system, &names);
  if (![self isEditing:nameField])
    [nameField setStringValue:pendingName != nil ? pendingName
                                : NWString (names.computerName)];
  if (![self isEditing:localField])
    [localField setStringValue:pendingLocalName != nil ? pendingLocalName
                                 : NWString (names.localHostName)];
  [nameField setEnabled:unlocked];
  [localField setEnabled:unlocked];
  local = pendingLocalName != nil ? pendingLocalName
                                  : NWString (names.localHostName);
  [localNote setStringValue:
      [local length] > 0
        ? [NSString stringWithFormat:@"Computers on your local network can "
                    @"reach this computer at %@.local.", local]
        : @"This computer has no local host name yet."];
}

- (void)updateService
{
  const NWService *s = [self selected];
  NSDictionary *d;
  NSString *word = @"", *sentence = @"";
  BOOL unlocked = [lockView isUnlocked];
  int m4, m6;
  NSRect frame;
  NSArray *dns, *search;
  NSMutableString *note;

  if (s == NULL)
    {
      [statusLight setImage:nil];
      [statusLabel setStringValue:@""];
      [statusNote setStringValue:[self serviceCount] == 0
                    ? @"There are no network services. They're made when a "
                      @"network interface appears."
                    : @""];
      [wifiBox setHidden:YES];
      [tabView setHidden:YES];
      return;
    }
  [tabView setHidden:NO];
  [statusLight setImage:NWLightImage (NWStatus (s, joiningSSID, &word,
                                                &sentence))];
  [statusLabel setStringValue:word];
  [statusNote setStringValue:sentence];

  /* Wi-Fi's controls, and the tabs beneath them. */
  [wifiBox setHidden:!s->wifi];
  frame = [tabView frame];
  frame.origin.y = NSMinY ([wifiBox frame]) + (s->wifi ? NWWiFiHeight : 0);
  frame.size.height = NWBodyHeight - NSMinY (frame);
  if (!NSEqualRects (frame, [tabView frame]))
    {
      [tabView setFrame:frame];
      [[tabView superview] setNeedsDisplay:YES];
    }
  if (s->wifi)
    [self updateWiFi:s];

  /* TCP/IP: the address fields can be typed in when the method takes
     them; otherwise they show what the service has now. */
  d = [self settingsFor:s];
  m4 = [[d objectForKey:NBNetIPv4Method] intValue];
  m6 = [[d objectForKey:NBNetIPv6Method] intValue];
  while ([ipv4Popup numberOfItems] > 4)
    [ipv4Popup removeItemAtIndex:4];
  if (m4 == NWIPv4Other)
    [ipv4Popup addItemWithTitle:@"Other (set with scutil)"];
  [ipv4Popup selectItemAtIndex:m4];
  [ipv4Popup setEnabled:unlocked];
  [self setField:ipv4Address
              to:(m4 == NWIPv4Manual || m4 == NWIPv4DHCPManualAddress)
                   ? [d objectForKey:NBNetIPv4Address]
                   : (m4 == NWIPv4Off ? @"" : NWString (s->addressNow))
        editable:unlocked && (m4 == NWIPv4Manual
                              || m4 == NWIPv4DHCPManualAddress)];
  [self setField:ipv4Mask
              to:m4 == NWIPv4Manual ? [d objectForKey:NBNetIPv4SubnetMask]
                   : (m4 == NWIPv4Off ? @"" : NWString (s->maskNow))
        editable:unlocked && m4 == NWIPv4Manual];
  [self setField:ipv4Router
              to:m4 == NWIPv4Manual ? [d objectForKey:NBNetIPv4Router]
                   : (m4 == NWIPv4Off ? @"" : NWString (s->routerNow))
        editable:unlocked && m4 == NWIPv4Manual];

  while ([ipv6Popup numberOfItems] > 4)
    [ipv6Popup removeItemAtIndex:4];
  if (m6 == NWIPv6Other)
    [ipv6Popup addItemWithTitle:@"Other (set with scutil)"];
  [ipv6Popup selectItemAtIndex:m6];
  [ipv6Popup setEnabled:unlocked];
  {
    NSArray *now = NWLines (s->ipv6Now);
    NSString *first = [now count] > 0 ? [now objectAtIndex:0] : @"";

    [self setField:ipv6Address
                to:m6 == NWIPv6Manual ? [d objectForKey:NBNetIPv6Address]
                     : (m6 == NWIPv6Off ? @"" : first)
          editable:unlocked && m6 == NWIPv6Manual];
    [self setField:ipv6Prefix
                to:m6 == NWIPv6Manual
                     ? [[d objectForKey:NBNetIPv6PrefixLength] stringValue]
                     : @""
          editable:unlocked && m6 == NWIPv6Manual];
    [self setField:ipv6Router
                to:m6 == NWIPv6Manual ? [d objectForKey:NBNetIPv6Router]
                     : (m6 == NWIPv6Off ? @"" : NWString (s->ipv6RouterNow))
          editable:unlocked && m6 == NWIPv6Manual];
  }

  /* DNS: what's set, and beneath it what's in use. */
  dns = [d objectForKey:NBNetDNSServers];
  search = [d objectForKey:NBNetSearchDomains];
  [self setField:dnsField to:[dns componentsJoinedByString:@", "]
        editable:unlocked];
  [self setField:searchField to:[search componentsJoinedByString:@", "]
        editable:unlocked];
  note = [NSMutableString string];
  [note appendFormat:@"In use: %@",
        s->dnsServersNow[0] != '\0'
          ? [NWLines (s->dnsServersNow) componentsJoinedByString:@", "]
          : @"no DNS servers"];
  if (s->searchDomainsNow[0] != '\0')
    [note appendFormat:@"; searching %@",
          [NWLines (s->searchDomainsNow) componentsJoinedByString:@", "]];
  [note appendString:@".\n\n"];
  [note appendString:@"Leave a field empty to use what DHCP gives. "
                     @"Separate several with commas or spaces."];
  [dnsNote setStringValue:note];

  [self updateHardware:s];
}

/* The network popup, Join Other Network, Disconnect and the Dock's
   checkbox. */
- (void)updateWiFi:(const NWService *)s
{
  NSString *current = s->airport && s->ssid[0] != '\0'
                        ? NWString (s->ssid) : nil;
  NSEnumerator *e;
  NSDictionary *net;
  id<NSMenuItem> item;
  BOOL listed = NO;

  [networkPopup removeAllItems];
  if (joiningSSID != nil)
    current = joiningSSID;
  [networkPopup addItemWithTitle:current != nil ? current
                                   : @"No network selected"];
  [[networkPopup lastItem] setEnabled:NO];
  e = [networks objectEnumerator];
  while ((net = [e nextObject]) != nil)
    {
      NSString *ssid = [net objectForKey:@"ssid"];

      if ([ssid isEqual:current])
        {
          /* The joined network heads the list, with its signal. */
          item = [networkPopup itemAtIndex:0];
          [item setImage:NWSignalImage ([[net objectForKey:@"rssi"] intValue],
                                        [[net objectForKey:@"security"]
                                          intValue] != NWWiFiOpen)];
          continue;
        }
      listed = YES;
      /* A title the popup hasn't got yet: addItemWithTitle: would move
         an existing one. */
      item = [[networkPopup menu] addItemWithTitle:ssid
                                            action:NULL
                                     keyEquivalent:@""];
      [item setImage:NWSignalImage ([[net objectForKey:@"rssi"] intValue],
                                    [[net objectForKey:@"security"] intValue]
                                      != NWWiFiOpen)];
      [item setRepresentedObject:net];
    }
  /* No separators: a popup shows one as an empty row. */
  if (!listed)
    {
      [networkPopup addItemWithTitle:scanning ? @"Looking for networks…"
                                              : @"No other networks found"];
      [[networkPopup lastItem] setEnabled:NO];
    }
  [networkPopup selectItemAtIndex:0];
  [networkPopup setEnabled:wifiInterface != nil];
  [joinOtherButton setEnabled:wifiInterface != nil];
  [disconnectButton setEnabled:wifiInterface != nil && current != nil];
}

- (void)updateHardware:(const NWService *)s
{
  NSMutableString *text = [NSMutableString string];

  [text appendFormat:@"Interface: %@\n", s->device[0] != '\0'
                       ? NWString (s->device) : @"none"];
  [text appendFormat:@"Type: %@\n", s->wifi ? @"Wi-Fi (IEEE 802.11)"
                                            : @"Ethernet"];
  [text appendFormat:@"Hardware address: %@\n",
        s->hardwareAddress[0] != '\0' ? NWString (s->hardwareAddress)
                                      : @"unknown"];
  [text appendFormat:@"Service ID: %@\n", NWString (s->serviceID)];
  if (s->wifi && s->airport && s->ssid[0] != '\0')
    {
      NSEnumerator *e = [networks objectEnumerator];
      NSDictionary *net, *seen = nil;
      int rssi = s->rssi, channel = s->channel;

      /* The scan's figures are fresher than wland's entry, which keeps
         those of the moment it joined. */
      while ((net = [e nextObject]) != nil && seen == nil)
        if ([[net objectForKey:@"ssid"] isEqual:NWString (s->ssid)])
          seen = net;
      if (seen != nil)
        {
          rssi = [[seen objectForKey:@"rssi"] intValue];
          channel = [[seen objectForKey:@"channel"] intValue];
        }
      [text appendString:@"\n"];
      [text appendFormat:@"Network: %@\n", NWString (s->ssid)];
      [text appendFormat:@"Access point (BSSID): %@\n", NWString (s->bssid)];
      if (channel > 0)
        [text appendFormat:@"Channel: %d\n", channel];
      [text appendFormat:@"Signal: %d dBm\n", rssi];
      [text appendFormat:@"Security: %@\n", NWString (s->security)];
    }
  [hardwareLabel setStringValue:text];
}

- (BOOL)isEditing:(NSTextField *)field
{
  id responder = [window firstResponder];

  return [responder isKindOfClass:[NSText class]]
    && [(NSText *) responder delegate] == (id) field;
}

/* Set a field unless it's being typed in. */
- (void)setField:(NSTextField *)field to:(NSString *)value
        editable:(BOOL)editable
{
  if (![self isEditing:field])
    [field setStringValue:value != nil ? value : @""];
  [field setEnabled:editable];
  [field setEditable:editable];
}

/* ---- changes ---- */

- (BOOL)hasChanges
{
  return [pending count] > 0 || pendingName != nil || pendingLocalName != nil;
}

/* The controls' settings for the chosen service, kept as a change if
   they differ from what's configured. */
- (void)capture
{
  const NWService *s = [self selected];
  NSMutableDictionary *d = [NSMutableDictionary dictionary];
  int m4 = [ipv4Popup indexOfSelectedItem];
  int m6 = [ipv6Popup indexOfSelectedItem];
  NSString *serviceID;

  if (s == NULL)
    return;
  serviceID = NWString (s->serviceID);
  [d setObject:[NSNumber numberWithInt:m4] forKey:NBNetIPv4Method];
  if (m4 == NWIPv4Manual || m4 == NWIPv4DHCPManualAddress)
    [d setObject:[ipv4Address stringValue] forKey:NBNetIPv4Address];
  if (m4 == NWIPv4Manual)
    {
      [d setObject:[ipv4Mask stringValue] forKey:NBNetIPv4SubnetMask];
      [d setObject:[ipv4Router stringValue] forKey:NBNetIPv4Router];
    }
  [d setObject:[NSNumber numberWithInt:m6] forKey:NBNetIPv6Method];
  if (m6 == NWIPv6Manual)
    {
      [d setObject:[ipv6Address stringValue] forKey:NBNetIPv6Address];
      [d setObject:[NSNumber numberWithInt:[ipv6Prefix intValue]]
            forKey:NBNetIPv6PrefixLength];
      [d setObject:[ipv6Router stringValue] forKey:NBNetIPv6Router];
    }
  [d setObject:NWWords ([dnsField stringValue]) forKey:NBNetDNSServers];
  [d setObject:NWWords ([searchField stringValue]) forKey:NBNetSearchDomains];
  if ([d isEqual:NWConfigured (s)])
    [pending removeObjectForKey:serviceID];
  else
    [pending setObject:d forKey:serviceID];
}

/* A method that takes addresses starts from the ones in use, as on
   macOS. */
- (void)chooseIPv4:(id)sender
{
  const NWService *s = [self selected];
  int m4 = [ipv4Popup indexOfSelectedItem];
  NSString *now;

  if (s == NULL || settingControls)
    return;
  now = NWString (s->addressNow);
  if ([now hasPrefix:@"169.254."])
    now = @"";
  if ((m4 == NWIPv4Manual || m4 == NWIPv4DHCPManualAddress)
      && [[ipv4Address stringValue] length] == 0)
    [ipv4Address setStringValue:now];
  if (m4 == NWIPv4Manual && [[ipv4Mask stringValue] length] == 0)
    [ipv4Mask setStringValue:NWString (s->maskNow)];
  if (m4 == NWIPv4Manual && [[ipv4Router stringValue] length] == 0)
    [ipv4Router setStringValue:NWString (s->routerNow)];
  [self capture];
  DESTROY (shownState);
  [self reload];
}

- (void)chooseIPv6:(id)sender
{
  const NWService *s = [self selected];
  int m6 = [ipv6Popup indexOfSelectedItem];

  if (s == NULL || settingControls)
    return;
  if (m6 == NWIPv6Manual)
    {
      /* A link-local address can't be set by hand. */
      if ([[ipv6Address stringValue] hasPrefix:@"fe80:"])
        [ipv6Address setStringValue:@""];
      if ([[ipv6Prefix stringValue] length] == 0)
        [ipv6Prefix setStringValue:@"64"];
    }
  [self capture];
  DESTROY (shownState);
  [self reload];
}

/* ---- Wi-Fi ---- */

- (void)scan
{
  unsigned generation;
  int status;

  if (wifiInterface == nil || scanning)
    return;
  status = NWWiFiScan ([wifiInterface UTF8String], &generation);
  if (status != 0)
    return;
  scanning = YES;
  scanGeneration = generation;
  scanStarted = [NSDate timeIntervalSinceReferenceDate];
}

/* A scan finished (or ran out of time): read the networks. */
- (void)pollScan
{
  NWNetwork found[NWMaxNetworks];
  NSMutableArray *list;
  int failed = 0, done, n, i;

  if (!scanning)
    return;
  done = NWWiFiScanFinished ([wifiInterface UTF8String], scanGeneration,
                             &failed);
  if (done == 0
      && [NSDate timeIntervalSinceReferenceDate] - scanStarted
         < NWScanTimeout)
    return;
  scanning = NO;
  scanDate = [NSDate timeIntervalSinceReferenceDate];
  n = NWWiFiScanResults ([wifiInterface UTF8String], found, NWMaxNetworks);
  list = [NSMutableArray array];
  for (i = 0; i < n; i++)
    {
      NSString *ssid = [NSString stringWithUTF8String:found[i].ssid];

      if (ssid == nil)
        continue;		/* not UTF-8 */
      [list addObject:
              [NSDictionary dictionaryWithObjectsAndKeys:
                              ssid, @"ssid",
                              [NSNumber numberWithInt:found[i].rssi], @"rssi",
                              [NSNumber numberWithInt:found[i].channel],
                              @"channel",
                              [NSNumber numberWithInt:found[i].security],
                              @"security", nil]];
    }
  ASSIGN (networks, list);
}

/* A network from the list: join it, asking for what it needs. */
- (void)chooseNetwork:(id)sender
{
  NSDictionary *net = [[networkPopup selectedItem] representedObject];
  NSDictionary *answer;
  int security;

  if (net == nil || settingControls)
    return;
  security = [[net objectForKey:@"security"] intValue];
  if (security == NWWiFiOpen)
    answer = [NSDictionary dictionaryWithObjectsAndKeys:
                             [net objectForKey:@"ssid"], NWJoinSSID,
                             [NSNumber numberWithInt:NWJoinNone],
                             NWJoinSecurity, nil];
  else
    answer = [NWJoinPanel askForNetwork:[net objectForKey:@"ssid"]
                               security:security == NWWiFiEnterprise
                                          ? NWJoinEnterprise : NWJoinPersonal
                              forWindow:window];
  [networkPopup selectItemAtIndex:0];
  if (answer != nil)
    [self join:answer];
}

- (void)joinOther:(id)sender
{
  NSDictionary *answer = [NWJoinPanel askForNetwork:nil
                                           security:NWJoinPersonal
                                          forWindow:window];

  if (answer != nil)
    [self join:answer];
}

- (void)join:(NSDictionary *)answer
{
  NSString *ssid = [answer objectForKey:NWJoinSSID];
  const char *interface = [wifiInterface UTF8String];
  int status;

  if (wifiInterface == nil || ssid == nil)
    return;
  if ([[answer objectForKey:NWJoinSecurity] intValue] == NWJoinEnterprise)
    {
      NWEAPSettings eap;

      memset (&eap, 0, sizeof (eap));
      eap.method = [[answer objectForKey:NWJoinEAPMethod] intValue];
      eap.ttlsInner = [[answer objectForKey:NWJoinTTLSInner] intValue];
      eap.identity = [[answer objectForKey:NWJoinUser] UTF8String];
      eap.anonymousIdentity = [[answer objectForKey:NWJoinAnonymousIdentity]
                                UTF8String];
      eap.password = [[answer objectForKey:NWJoinPassword] UTF8String];
      eap.caCertificate = [[answer objectForKey:NWJoinCACertificate]
                            UTF8String];
      eap.serverName = [[answer objectForKey:NWJoinServerName] UTF8String];
      eap.clientCertificate = [[answer objectForKey:NWJoinClientCertificate]
                                UTF8String];
      eap.privateKey = [[answer objectForKey:NWJoinPrivateKey] UTF8String];
      eap.keyPassphrase = [[answer objectForKey:NWJoinKeyPassphrase]
                            UTF8String];
      eap.noVerifyServer = [[answer objectForKey:NWJoinNoVerify] boolValue];
      status = NWWiFiConnectEAP (interface, [ssid UTF8String], &eap);
    }
  else
    {
      NSString *passphrase = [answer objectForKey:NWJoinPassphrase];

      status = NWWiFiConnect (interface, [ssid UTF8String],
                              passphrase != nil ? [passphrase UTF8String]
                                                : "");
    }
  if (status != 0)
    {
      NSRunAlertPanel (@"Network", @"Couldn't join \"%@\": %s", @"OK", nil,
                       nil, ssid, NWWiFiMessage (status));
      return;
    }
  ASSIGN (joiningSSID, ssid);
  joiningSince = [NSDate timeIntervalSinceReferenceDate];
  DESTROY (shownState);
  [self reload];
}

- (void)disconnect:(id)sender
{
  int status;

  if (wifiInterface == nil)
    return;
  DESTROY (joiningSSID);
  status = NWWiFiDisconnect ([wifiInterface UTF8String]);
  if (status != 0)
    NSRunAlertPanel (@"Network", @"%s", @"OK", nil, nil,
                     NWWiFiMessage (status));
  DESTROY (shownState);
  [self reload];
}

- (void)toggleShowInDock:(id)sender
{
  [dockExtra setShown:[showInDockButton state] == NSOnState];
}

/* The Dock answered, or its extras changed some other way. */
- (void)dockExtraChanged:(NBDockExtra *)extra
{
  BOOL installed = [dockExtra isInstalled];

  [showInDockButton setState:installed && [dockExtra isShown]
                    ? NSOnState : NSOffState];
  [showInDockButton setEnabled:installed];
  [showInDockButton setToolTip:installed ? nil
                    : @"The Dock's Wi-Fi extra isn't installed."];
}

/* ---- Apply and Revert ---- */

/* What's wrong with a service's settings, in a sentence, or nil. */
- (NSString *)problemIn:(NSDictionary *)d
{
  int m4 = [[d objectForKey:NBNetIPv4Method] intValue];
  int m6 = [[d objectForKey:NBNetIPv6Method] intValue];
  NSString *router;
  NSEnumerator *e;
  NSString *entry;
  int prefix;

  if (m4 == NWIPv4Other || m6 == NWIPv6Other)
    return @"Choose how to configure IPv4 and IPv6.";
  if ((m4 == NWIPv4Manual || m4 == NWIPv4DHCPManualAddress)
      && !NWIsIPv4 ([d objectForKey:NBNetIPv4Address]))
    return @"Type an IPv4 address, such as 192.168.1.20.";
  if (m4 == NWIPv4Manual && !NWIsMask ([d objectForKey:NBNetIPv4SubnetMask]))
    return @"Type a subnet mask, such as 255.255.255.0.";
  router = [d objectForKey:NBNetIPv4Router];
  if (m4 == NWIPv4Manual && [router length] > 0 && !NWIsIPv4 (router))
    return @"The router must be an IPv4 address.";
  if (m6 == NWIPv6Manual)
    {
      NSString *address = [d objectForKey:NBNetIPv6Address];

      prefix = [[d objectForKey:NBNetIPv6PrefixLength] intValue];
      if (!NWIsIPv6 (address) || [address hasPrefix:@"fe80:"])
        return @"Type an IPv6 address that isn't link-local "
               @"(not fe80::...).";
      if (prefix < 1 || prefix > 128)
        return @"The prefix length is a number from 1 to 128.";
      router = [d objectForKey:NBNetIPv6Router];
      if ([router length] > 0 && !NWIsIPv6 (router))
        return @"The IPv6 router must be an IPv6 address.";
    }
  if ([[d objectForKey:NBNetDNSServers] count] > 8
      || [[d objectForKey:NBNetSearchDomains] count] > 8)
    return @"Give at most eight DNS servers and eight search domains.";
  e = [[d objectForKey:NBNetDNSServers] objectEnumerator];
  while ((entry = [e nextObject]) != nil)
    if (!NWIsIPv4 (entry) && !NWIsIPv6 (entry))
      return [NSString stringWithFormat:@"\"%@\" isn't a DNS server's "
                       @"address.", entry];
  e = [[d objectForKey:NBNetSearchDomains] objectEnumerator];
  while ((entry = [e nextObject]) != nil)
    if (!NWIsDomain (entry))
      return [NSString stringWithFormat:@"\"%@\" isn't a domain name.",
                       entry];
  return nil;
}

/* One change through the helper: a service ID (its settings pending), or
   the names (nil). */
- (int)commit:(id)what
{
  NWNames names;

  if (what != nil)
    return [NBSettingsHelper commitNetworkService:what
                                         settings:[pending objectForKey:what]
                                    authorization:auth];
  memset (&names, 0, sizeof (names));
  NWSystemReadNames (system, &names);
  return [NBSettingsHelper
            setComputerName:pendingName != nil ? pendingName
                              : NWString (names.computerName)
              localHostName:pendingLocalName != nil ? pendingLocalName
                              : NWString (names.localHostName)
              authorization:auth];
}

/* Through the helper, unlocking first if the lock was open but the
   right ran out. */
- (BOOL)apply:(id)what
{
  int status = [self commit:what];

  if (status == NBAuthorizationNeeded)
    {
      /* The helper no longer holds the right (it ran out, or the helper
         was restarted): close the lock, then ask. */
      [auth refresh];
      [lockView update];
      if ([lockView unlock])
        status = [self commit:what];
      else
        return NO;		/* cancelled: nothing to say */
    }
  if (status != NBAuthorizationOK)
    NSRunAlertPanel (@"Network", @"%@", @"OK", nil, nil,
                     status == NBAuthorizationInvalid
                       ? @"The settings weren't accepted."
                       : [NBAuthorization messageForStatus:status]);
  return status == NBAuthorizationOK;
}

- (void)applyChanges:(id)sender
{
  NSEnumerator *e;
  NSString *serviceID, *problem = nil;

  [self capture];
  e = [[pending allKeys] objectEnumerator];
  while (problem == nil && (serviceID = [e nextObject]) != nil)
    problem = [self problemIn:[pending objectForKey:serviceID]];
  if (problem == nil && (pendingName != nil || pendingLocalName != nil))
    {
      if (pendingName != nil && [[pendingName stringByTrimmingCharactersInSet:
                                   [NSCharacterSet whitespaceCharacterSet]]
                                  length] == 0)
        problem = @"Type a name for the computer.";
      else if (pendingLocalName != nil && !NWIsLocalName (pendingLocalName))
        problem = @"The local host name can have letters, digits and "
                  @"hyphens (not at either end), at most 63.";
    }
  if (problem != nil)
    {
      NSRunAlertPanel (@"Network", @"%@", @"OK", nil, nil, problem);
      return;
    }
  if (![lockView isUnlocked] && ![lockView unlock])
    return;

  e = [[pending allKeys] objectEnumerator];
  while ((serviceID = [e nextObject]) != nil)
    {
      if (![self apply:serviceID])
        break;
      [pending removeObjectForKey:serviceID];
    }
  if ([pending count] == 0 && (pendingName != nil || pendingLocalName != nil)
      && [self apply:nil])
    {
      DESTROY (pendingName);
      DESTROY (pendingLocalName);
      localEdited = NO;
    }
  [window makeFirstResponder:nil];
  DESTROY (shownState);
  [self reload];
}

/* Forget the changes not applied. */
- (void)revert:(id)sender
{
  [pending removeAllObjects];
  DESTROY (pendingName);
  DESTROY (pendingLocalName);
  localEdited = NO;
  [window makeFirstResponder:nil];
  DESTROY (shownState);
  [self reload];
}

@end
