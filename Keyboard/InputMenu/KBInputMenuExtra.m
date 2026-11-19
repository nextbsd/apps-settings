/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * KBInputMenuExtra: the Dock's Input menu (Input.dockextra). Its tile
 * shows the keyboard layout in use by its short name (EN, ΕΛ); a click
 * lists the layouts, with the one in use checked, and switches to the
 * one chosen (WS_MSG_SET_KEYBOARD_LAYOUT); a double-click opens
 * Keyboard. It follows WS_EVENT_KEYBOARD_LAYOUT, so a switch made with
 * the shortcut shows at once, and hides itself when Keyboard's "Show
 * Input menu in Dock" is off.
 *
 * It answers the Dock's extras interface (apps-dock's DockExtra.h)
 * without including it: the Dock asks only that the principal class
 * respond to its methods. Its tile is drawn the Dock extras' way, a
 * dark rounded plate with white text.
 */

#import <AppKit/AppKit.h>
#import <GNUstepBase/GNUstep.h>
#import "KBConnection.h"
#import "KBShared.h"

#include <math.h>

/* The Dock's side (DockExtraHost), the part this extra uses. */
@protocol KBDockExtraHost <NSObject>
- (void)dockExtraNeedsDisplay:(id)extra;
- (void)dockExtraAvailabilityDidChange:(id)extra;
@end

@interface KBInputMenuExtra : NSObject <KBConnectionDelegate>
{
  id<KBDockExtraHost> host;	/* not retained */
  KBConnection *connection;
  NSArray *layouts;		/* {Layout, Variant, Name} */
  int active;
  BOOL shown;			/* Show Input menu in Dock */
}
@end

@interface KBInputMenuExtra (Private)
- (void)reload;
- (void)settingsChanged:(NSNotification *)note;
- (void)chooseLayout:(id)sender;
- (void)openKeyboard:(id)sender;
- (NSDictionary *)activeSource;
@end

@implementation KBInputMenuExtra

- (id)initWithDockHost:(id)aHost
{
  if ((self = [super init]) == nil)
    return nil;
  host = aHost;
  active = -1;
  shown = KBShowsInputMenu ();
  layouts = [NSArray new];
  [[NSDistributedNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector (settingsChanged:)
             name:KBSettingsChangedNotification
           object:nil];
  connection = [[KBConnection alloc] initWithName:@"Input menu"
                                         delegate:self];
  [self reload];
  return self;
}

- (void)dealloc
{
  [self dockExtraWillUnload];
  RELEASE (layouts);
  [super dealloc];
}

- (void)dockExtraWillUnload
{
  [[NSDistributedNotificationCenter defaultCenter] removeObserver:self];
  [connection invalidate];
  DESTROY (connection);
  host = nil;
}

/* Nothing to show without WindowServer, or when turned off. */
- (BOOL)isAvailable
{
  return shown && [connection isConnected] && [layouts count] > 0;
}

- (void)drawInRect:(NSRect)rect
{
  NSDictionary *source = [self activeSource];
  NSString *text = source != nil
    ? KBShortName ([source objectForKey:@"Layout"],
                   [source objectForKey:@"Variant"])
    : @"?";
  CGFloat inset = floor (NSWidth (rect) * 0.08);
  NSRect plate = NSInsetRect (rect, inset, inset);
  CGFloat radius = floor (NSWidth (plate) * 0.2);
  NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:plate
                                                       xRadius:radius
                                                       yRadius:radius];
  CGFloat size = floor (NSHeight (plate) * 0.42);
  NSDictionary *attributes;
  NSSize textSize;

  [[NSColor colorWithCalibratedWhite:0.13 alpha:0.86] set];
  [path fill];
  [[NSColor colorWithCalibratedWhite:1.0 alpha:0.16] set];
  [path setLineWidth:1.0];
  [path stroke];

  /* As large as fits, three letters at most. */
  for (;;)
    {
      attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                   [NSFont boldSystemFontOfSize:size],
                                 NSFontAttributeName,
                                 [NSColor colorWithCalibratedWhite:1.0
                                                             alpha:0.95],
                                 NSForegroundColorAttributeName, nil];
      textSize = [text sizeWithAttributes:attributes];
      if (textSize.width <= NSWidth (plate) * 0.8 || size <= 7)
        break;
      size -= 1;
    }
  [text drawAtPoint:NSMakePoint (floor (NSMidX (plate) - textSize.width / 2),
                                 floor (NSMidY (plate) - textSize.height / 2))
     withAttributes:attributes];
}

- (NSString *)toolTip
{
  NSDictionary *source = [self activeSource];

  if (source == nil)
    return @"Input";
  return [NSString stringWithFormat:@"Input: %@",
                   [source objectForKey:@"Name"]];
}

- (NSMenu *)menuForEvent:(NSEvent *)event
{
  NSMenu *menu = AUTORELEASE ([[NSMenu alloc] initWithTitle:@"Input"]);
  NSUInteger i;

  [self reload];
  for (i = 0; i < [layouts count]; i++)
    {
      NSDictionary *source = [layouts objectAtIndex:i];
      NSString *name = [source objectForKey:@"Name"];
      id<NSMenuItem> item;

      if ([name length] == 0)
        name = [source objectForKey:@"Layout"];
      item = [menu addItemWithTitle:
                     [NSString stringWithFormat:@"%@  (%@)", name,
                               KBShortName ([source objectForKey:@"Layout"],
                                            [source objectForKey:@"Variant"])]
                             action:@selector (chooseLayout:)
                      keyEquivalent:@""];
      [item setTarget:self];
      [item setTag:(NSInteger) i];
      [item setState:((int) i == active ? NSOnState : NSOffState)];
    }
  if ([layouts count] > 0)
    [menu addItem:[NSMenuItem separatorItem]];
  [[menu addItemWithTitle:@"Keyboard Settings..."
                   action:@selector (openKeyboard:)
            keyEquivalent:@""] setTarget:self];
  return menu;
}

- (void)dockExtraOpen:(id)sender
{
  [self openKeyboard:sender];
}

/* ---- WindowServer ---- */

- (void)connectionDidChange:(KBConnection *)c
{
  [self reload];
}

- (void)connectionLayoutDidChange:(KBConnection *)c
{
  [self reload];
}

@end

@implementation KBInputMenuExtra (Private)

- (void)reload
{
  BOOL wasAvailable = [self isAvailable];
  int index = -1;

  ASSIGN (layouts, [connection layoutsWithActiveIndex:&index]);
  active = index;
  if ([self isAvailable] != wasAvailable)
    [host dockExtraAvailabilityDidChange:self];
  [host dockExtraNeedsDisplay:self];
}

/* Keyboard changed a setting: "Show Input menu in Dock" may be. */
- (void)settingsChanged:(NSNotification *)note
{
  BOOL wasAvailable = [self isAvailable];

  if (![[[note userInfo] objectForKey:@"domain"] isEqual:KBKeyboardDomain])
    return;
  shown = KBShowsInputMenu ();
  if ([self isAvailable] != wasAvailable)
    [host dockExtraAvailabilityDidChange:self];
}

- (void)chooseLayout:(id)sender
{
  NSInteger index = [sender tag];

  if (index < 0 || (NSUInteger) index >= [layouts count])
    return;
  if ([connection setActiveLayout:(unsigned) index] != 0)
    NSBeep ();
  [self reload];
}

- (void)openKeyboard:(id)sender
{
  if (![[NSWorkspace sharedWorkspace] launchApplication:@"Keyboard"])
    NSBeep ();
}

- (NSDictionary *)activeSource
{
  if (active < 0 || (NSUInteger) active >= [layouts count])
    return nil;
  return [layouts objectAtIndex:active];
}

@end
