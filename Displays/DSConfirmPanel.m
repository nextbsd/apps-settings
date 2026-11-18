/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "DSConfirmPanel.h"
#import <GNUstepBase/GNUstep.h>

#include <math.h>

#define DSPanelWidth 420.0
#define DSPanelHeight 132.0

@interface DSConfirmPanel (Private)
- (void)build;
- (void)tick:(NSTimer *)timer;
- (void)showCountdown;
- (void)keep:(id)sender;
- (void)revert:(id)sender;
@end

@implementation DSConfirmPanel

- (id)initWithDelegate:(id<DSConfirmPanelDelegate>)delegate
{
  if ((self = [super init]) == nil)
    return nil;
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

- (void)showOverWindow:(NSWindow *)window seconds:(NSTimeInterval)seconds
{
  if (_panel == nil)
    [self build];
  _deadline = [NSDate timeIntervalSinceReferenceDate] + seconds;
  [self showCountdown];
  if (_timer == nil)
    {
      NSRect over = window != nil ? [window frame]
        : [[NSScreen mainScreen] visibleFrame];
      NSRect frame = [_panel frame];

      /* Near the top of the Displays window, as a sheet would be. */
      frame.origin.x = floor (NSMidX (over) - NSWidth (frame) / 2);
      frame.origin.y = floor (NSMaxY (over) - NSHeight (frame) - 40);
      [_panel setFrame:frame display:NO];
      ASSIGN (_timer, [NSTimer timerWithTimeInterval:0.25
                                              target:self
                                            selector:@selector (tick:)
                                            userInfo:nil
                                             repeats:YES]);
      [[NSRunLoop currentRunLoop] addTimer:_timer forMode:NSDefaultRunLoopMode];
      [[NSRunLoop currentRunLoop] addTimer:_timer
                                   forMode:NSEventTrackingRunLoopMode];
      [[NSRunLoop currentRunLoop] addTimer:_timer
                                   forMode:NSModalPanelRunLoopMode];
    }
  [NSApp activateIgnoringOtherApps:YES];
  [_panel makeKeyAndOrderFront:self];
}

- (void)setSecondsLeft:(NSTimeInterval)seconds
{
  if (_timer == nil)
    return;
  _deadline = [NSDate timeIntervalSinceReferenceDate] + seconds;
  [self showCountdown];
}

- (void)close
{
  [_timer invalidate];
  DESTROY (_timer);
  [_panel orderOut:self];
}

@end

@implementation DSConfirmPanel (Private)

- (void)build
{
  NSView *content;
  NSImageView *icon;
  NSTextField *title;
  NSButton *keep, *revert;

  _panel = [[NSPanel alloc]
      initWithContentRect:NSMakeRect (0, 0, DSPanelWidth, DSPanelHeight)
                styleMask:NSTitledWindowMask
                  backing:NSBackingStoreBuffered
                    defer:NO];
  [_panel setTitle:@"Displays"];
  [_panel setLevel:NSModalPanelWindowLevel];
  [_panel setReleasedWhenClosed:NO];
  [_panel setHidesOnDeactivate:NO];
  content = [_panel contentView];

  icon = AUTORELEASE ([[NSImageView alloc]
                        initWithFrame:NSMakeRect (20, DSPanelHeight - 72, 48, 48)]);
  [icon setImage:[NSApp applicationIconImage]];
  [icon setImageScaling:NSScaleProportionally];
  [icon setEditable:NO];
  [content addSubview:icon];

  title = AUTORELEASE ([[NSTextField alloc]
                         initWithFrame:NSMakeRect (84, DSPanelHeight - 42,
                                                   DSPanelWidth - 104, 22)]);
  [title setStringValue:@"Keep these display settings?"];
  [title setFont:[NSFont boldSystemFontOfSize:14]];
  [title setEditable:NO];
  [title setSelectable:NO];
  [title setBordered:NO];
  [title setBezeled:NO];
  [title setDrawsBackground:NO];
  [content addSubview:title];

  _countdown = AUTORELEASE ([[NSTextField alloc]
                              initWithFrame:NSMakeRect (84, DSPanelHeight - 80,
                                                        DSPanelWidth - 104, 34)]);
  [_countdown setEditable:NO];
  [_countdown setSelectable:NO];
  [_countdown setBordered:NO];
  [_countdown setBezeled:NO];
  [_countdown setDrawsBackground:NO];
  [content addSubview:_countdown];

  keep = AUTORELEASE ([[NSButton alloc]
                        initWithFrame:NSMakeRect (DSPanelWidth - 20 - 120, 16,
                                                  120, 26)]);
  [keep setTitle:@"Keep Changes"];
  [keep setKeyEquivalent:@"\r"];
  [keep setTarget:self];
  [keep setAction:@selector (keep:)];
  [content addSubview:keep];

  revert = AUTORELEASE ([[NSButton alloc]
                          initWithFrame:NSMakeRect (DSPanelWidth - 20 - 120 - 12
                                                    - 100, 16, 100, 26)]);
  [revert setTitle:@"Revert"];
  [revert setKeyEquivalent:@"\e"];
  [revert setTarget:self];
  [revert setAction:@selector (revert:)];
  [content addSubview:revert];

  [_panel setInitialFirstResponder:keep];
}

- (void)showCountdown
{
  NSTimeInterval left = _deadline - [NSDate timeIntervalSinceReferenceDate];
  int seconds = (int) ceil (MAX (0, left));

  [_countdown setStringValue:[NSString stringWithFormat:
      @"If you don't answer, the previous settings come back in %d %@.",
      seconds, seconds == 1 ? @"second" : @"seconds"]];
}

- (void)tick:(NSTimer *)timer
{
  if ([NSDate timeIntervalSinceReferenceDate] >= _deadline)
    {
      [self close];
      [_delegate confirmPanelRevert:self];
      return;
    }
  [self showCountdown];
}

- (void)keep:(id)sender
{
  [self close];
  [_delegate confirmPanelKeep:self];
}

- (void)revert:(id)sender
{
  [self close];
  [_delegate confirmPanelRevert:self];
}

@end
