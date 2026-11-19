/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "BTPairingPanel.h"
#import <GNUstepBase/GNUstep.h>

#include <math.h>
#include <string.h>

#define BTPanelWidth 460.0
#define BTPanelHeight 190.0
#define BTTextX 84.0
/* As long as `bluetooth pair` follows a pairing. */
#define BTPairTimeout 150.0
#define BTPollInterval 0.25

/* bt_status_t values the panel reports itself (bluetooth_mig_types.h). */
#define BTStatusInternalError 4
#define BTStatusPairingFailed 11
#define BTStatusPairingTimeout 12

static NSTextField *
BTPanelLabel (NSRect frame, NSFont *font)
{
  NSTextField *label = AUTORELEASE ([[NSTextField alloc] initWithFrame:frame]);

  [label setEditable:NO];
  [label setSelectable:NO];
  [label setBordered:NO];
  [label setBezeled:NO];
  [label setDrawsBackground:NO];
  if (font != nil)
    [label setFont:font];
  return label;
}

static BOOL
BTAllDigits (NSString *s)
{
  return [s length] > 0
    && [s rangeOfCharacterFromSet:
            [[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location
       == NSNotFound;
}

@interface BTPairingPanel (Private)
- (void)build;
- (void)showOverWindow:(NSWindow *)window;
- (void)startFollowing;
- (void)tick:(NSTimer *)timer;
- (void)showState:(int)state expires:(int)expires;
- (void)finish;
- (void)pair:(id)sender;
- (void)cancel:(id)sender;
@end

@implementation BTPairingPanel

- (id)initWithClient:(BTClient *)client
            delegate:(id<BTPairingPanelDelegate>)delegate
{
  if ((self = [super init]) == nil)
    return nil;
  _client = client;
  _delegate = delegate;
  return self;
}

- (void)dealloc
{
  [self close];
  RELEASE (_panel);
  [super dealloc];
}

- (BOOL)isVisible
{
  return _timer != nil;
}

- (NSString *)address
{
  return _timer != nil ? _address : nil;
}

- (int)pairWithAddress:(NSString *)address
                  name:(NSString *)name
            overWindow:(NSWindow *)window
{
  int st;

  [self close];
  st = BTClientPair (_client, [address UTF8String], NULL);
  if (st != BTStatusSuccess)
    return st;
  ASSIGN (_address, address);
  ASSIGN (_name, name);
  _incoming = NO;
  [self startFollowing];
  [self showOverWindow:window];
  return BTStatusSuccess;
}

- (void)answerPromptFrom:(NSString *)address
                    name:(NSString *)name
              overWindow:(NSWindow *)window
{
  [self close];
  ASSIGN (_address, address);
  ASSIGN (_name, name);
  _incoming = YES;
  [self startFollowing];
  [self showOverWindow:window];
}

- (void)update
{
  if (_timer != nil)
    [self tick:nil];
}

- (void)close
{
  [_timer invalidate];
  DESTROY (_timer);
  [_spinner stopAnimation:self];
  [_panel orderOut:self];
}

@end

@implementation BTPairingPanel (Private)

- (void)build
{
  NSView *content;
  NSImageView *icon;
  CGFloat textW = BTPanelWidth - BTTextX - 20;

  _panel = [[NSPanel alloc]
      initWithContentRect:NSMakeRect (0, 0, BTPanelWidth, BTPanelHeight)
                styleMask:NSTitledWindowMask
                  backing:NSBackingStoreBuffered
                    defer:NO];
  [_panel setTitle:@"Bluetooth"];
  [_panel setLevel:NSModalPanelWindowLevel];
  [_panel setReleasedWhenClosed:NO];
  [_panel setHidesOnDeactivate:NO];
  content = [_panel contentView];

  icon = AUTORELEASE ([[NSImageView alloc]
                        initWithFrame:NSMakeRect (20, BTPanelHeight - 72, 48, 48)]);
  [icon setImage:[NSApp applicationIconImage]];
  [icon setImageScaling:NSScaleProportionally];
  [icon setEditable:NO];
  [content addSubview:icon];

  _title = BTPanelLabel (NSMakeRect (BTTextX, BTPanelHeight - 42, textW, 22),
                         [NSFont boldSystemFontOfSize:14]);
  [content addSubview:_title];

  _message = BTPanelLabel (NSMakeRect (BTTextX, BTPanelHeight - 82, textW, 36),
                           nil);
  [[_message cell] setWraps:YES];
  [content addSubview:_message];

  _code = BTPanelLabel (NSMakeRect (BTTextX, BTPanelHeight - 120, textW, 32),
                        [NSFont boldSystemFontOfSize:24]);
  [content addSubview:_code];

  _entry = AUTORELEASE ([[NSTextField alloc]
                          initWithFrame:NSMakeRect (BTTextX, BTPanelHeight - 116,
                                                    180, 24)]);
  [_entry setTarget:self];
  [_entry setAction:@selector (pair:)];
  [content addSubview:_entry];

  _expires = BTPanelLabel (NSMakeRect (BTTextX, 52, textW, 16),
                           [NSFont systemFontOfSize:[NSFont smallSystemFontSize]]);
  [content addSubview:_expires];

  _spinner = AUTORELEASE ([[NSProgressIndicator alloc]
                            initWithFrame:NSMakeRect (20, 20, 16, 16)]);
  [_spinner setStyle:NSProgressIndicatorSpinningStyle];
  [_spinner setIndeterminate:YES];
  [_spinner setDisplayedWhenStopped:NO];
  [content addSubview:_spinner];

  _pair = AUTORELEASE ([[NSButton alloc]
                         initWithFrame:NSMakeRect (BTPanelWidth - 20 - 100, 16,
                                                   100, 26)]);
  [_pair setTitle:@"Pair"];
  [_pair setKeyEquivalent:@"\r"];
  [_pair setTarget:self];
  [_pair setAction:@selector (pair:)];
  [content addSubview:_pair];

  _cancel = AUTORELEASE ([[NSButton alloc]
                           initWithFrame:NSMakeRect (BTPanelWidth - 20 - 100 - 12
                                                     - 100, 16, 100, 26)]);
  [_cancel setTitle:@"Cancel"];
  [_cancel setKeyEquivalent:@"\e"];
  [_cancel setTarget:self];
  [_cancel setAction:@selector (cancel:)];
  [content addSubview:_cancel];
}

- (void)showOverWindow:(NSWindow *)window
{
  NSRect over, frame;

  if (_panel == nil)
    [self build];
  [self tick:nil];
  if (_timer == nil)		/* it ended at once */
    return;
  over = window != nil ? [window frame] : [[NSScreen mainScreen] visibleFrame];
  frame = [_panel frame];
  /* Near the top of the window, as a sheet would be. */
  frame.origin.x = floor (NSMidX (over) - NSWidth (frame) / 2);
  frame.origin.y = floor (NSMaxY (over) - NSHeight (frame) - 40);
  [_panel setFrame:frame display:NO];
  [NSApp activateIgnoringOtherApps:YES];
  [_panel makeKeyAndOrderFront:self];
}

- (void)startFollowing
{
  _answered = NO;
  _sawPrompt = NO;
  _shownState = _shownPasskey = -1;
  _started = [NSDate timeIntervalSinceReferenceDate];
  if (_panel == nil)
    [self build];
  [_entry setStringValue:@""];
  ASSIGN (_timer, [NSTimer timerWithTimeInterval:BTPollInterval
                                          target:self
                                        selector:@selector (tick:)
                                        userInfo:nil
                                         repeats:YES]);
  [[NSRunLoop currentRunLoop] addTimer:_timer forMode:NSDefaultRunLoopMode];
  [[NSRunLoop currentRunLoop] addTimer:_timer
                               forMode:NSEventTrackingRunLoopMode];
  [[NSRunLoop currentRunLoop] addTimer:_timer forMode:NSModalPanelRunLoopMode];
}

/* Where the pairing is, as `bluetooth pair` follows it. */
- (void)tick:(NSTimer *)timer
{
  const char *addr = [_address UTF8String];
  int state, method, passkey, expires, result, st;

  if (_timer == nil)
    return;
  st = BTClientPairStatus (_client, addr, &state, &method, &passkey,
                           &expires, &result);
  if (st == BTStatusRPCFailed)
    {
      [self finish];
      [_delegate pairingPanel:self didFailWithName:_name
                       status:BTStatusInternalError];
      return;
    }
  if (state == BTPairSucceeded)
    {
      [self finish];
      [_delegate pairingPanel:self didPairWith:_address];
      return;
    }
  if (state == BTPairFailed || state == BTPairNone)
    {
      [self finish];
      /* A device's own request that went away unanswered: nothing to
         say. */
      if (_incoming && !_answered && state == BTPairNone)
        [_delegate pairingPanelDidCancel:self];
      else
        [_delegate pairingPanel:self didFailWithName:_name
                         status:(state == BTPairNone
                                 ? BTStatusPairingFailed : result)];
      return;
    }
  if ([NSDate timeIntervalSinceReferenceDate] - _started > BTPairTimeout)
    {
      (void) BTClientPairConfirm (_client, addr, 0, 0, NULL);
      [self finish];
      [_delegate pairingPanel:self didFailWithName:_name
                       status:BTStatusPairingTimeout];
      return;
    }
  if (state == BTPairWaiting)
    {
      /* A new prompt (the device asked again) wants a new answer. */
      if (_sawPrompt && (method != _method || passkey != _passkey))
        _answered = NO;
      _sawPrompt = YES;
      _method = method;
      _passkey = passkey;
      /* Nothing to compare, and choosing Pair was the yes. */
      if (method == BTMethodJustWorks && !_incoming && !_answered)
        {
          _answered = YES;
          (void) BTClientPairConfirm (_client, addr, 1, 0, NULL);
        }
    }
  [self showState:state expires:expires];
}

- (void)showState:(int)state expires:(int)expires
{
  NSString *name = [NSString stringWithFormat:@"“%@”", _name];
  BOOL asking = state == BTPairWaiting && !_answered
    && _method != BTMethodPasskeyDisplay;
  BOOL entry = asking && (_method == BTMethodPasskeyEntry
                          || _method == BTMethodPIN);
  BOOL code = state == BTPairWaiting && !_answered
    && (_method == BTMethodNumericComparison
        || _method == BTMethodPasskeyDisplay);
  BOOL waiting = state == BTPairWaiting && !_answered;
  int shown = (_answered ? 1000 : 0) + state * 10 + _method;

  if (waiting && expires > 0)
    [_expires setStringValue:[NSString stringWithFormat:
        @"The request ends in %d %@.", expires,
        expires == 1 ? @"second" : @"seconds"]];
  else
    [_expires setStringValue:@""];

  /* The rest only when it changes, so typing isn't disturbed. */
  if (shown == _shownState && _passkey == _shownPasskey)
    return;
  _shownState = shown;
  _shownPasskey = _passkey;

  [_title setStringValue:[NSString stringWithFormat:@"Pairing with %@", _name]];
  [_pair setTitle:@"Pair"];
  if (!waiting)
    [_message setStringValue:
        state == BTPairPending && !_answered && !_incoming
        ? [NSString stringWithFormat:@"Connecting to %@...", name]
        : [NSString stringWithFormat:@"Pairing with %@...", name]];
  else
    switch (_method)
      {
      case BTMethodNumericComparison:
        [_message setStringValue:[NSString stringWithFormat:
            @"Pair with %@ if it shows this code:", name]];
        break;
      case BTMethodPasskeyEntry:
        [_message setStringValue:[NSString stringWithFormat:
            @"Type the code that %@ shows:", name]];
        break;
      case BTMethodPasskeyDisplay:
        [_message setStringValue:[NSString stringWithFormat:
            @"Type this code on %@, then press Return or Enter on it:",
            name]];
        break;
      case BTMethodPIN:
        [_message setStringValue:[NSString stringWithFormat:
            @"Type the PIN for %@. Headsets often use 0000 or 1234.",
            name]];
        break;
      default:
        [_message setStringValue:[NSString stringWithFormat:
            @"%@ wants to pair with this computer.", name]];
        break;
      }
  [_code setStringValue:code
         ? [NSString stringWithFormat:@"%03d %03d", _passkey / 1000,
                     _passkey % 1000]
         : @""];
  [_code setHidden:!code];
  [_entry setHidden:!entry];
  if (entry)
    {
      [_entry setStringValue:@""];
      [_panel makeFirstResponder:_entry];
    }
  [_pair setHidden:!asking];
  if (asking)
    [_spinner stopAnimation:self];
  else
    [_spinner startAnimation:self];
}

- (void)finish
{
  [self close];
  [_entry setStringValue:@""];
}

- (void)pair:(id)sender
{
  const char *addr = [_address UTF8String];
  NSString *typed = [_entry stringValue];
  int st, passkey = 0;
  const char *pin = NULL;

  if (_timer == nil || _answered || [_pair isHidden])
    return;
  if (_method == BTMethodPasskeyEntry)
    {
      typed = [typed stringByReplacingOccurrencesOfString:@" " withString:@""];
      if (!BTAllDigits (typed) || [typed length] > 6)
        {
          NSBeep ();
          return;
        }
      passkey = [typed intValue];
    }
  else if (_method == BTMethodPIN)
    {
      if ([typed length] < 1 || strlen ([typed UTF8String]) > 16)
        {
          NSBeep ();
          return;
        }
      pin = [typed UTF8String];
    }
  st = BTClientPairConfirm (_client, addr, 1, passkey, pin);
  [_entry setStringValue:@""];
  if (st != BTStatusSuccess && st != BTStatusNoPrompt)
    {
      [self finish];
      [_delegate pairingPanel:self didFailWithName:_name status:st];
      return;
    }
  _answered = YES;
  [self tick:nil];
}

- (void)cancel:(id)sender
{
  /* Say no to the device rather than leave it waiting; with no prompt
     up (still connecting) there's nothing to say no to. */
  (void) BTClientPairConfirm (_client, [_address UTF8String], 0, 0, NULL);
  [self finish];
  [_delegate pairingPanelDidCancel:self];
}

@end
