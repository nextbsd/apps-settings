/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "DSController.h"
#import <GNUstepBase/GNUstep.h>

#include <errno.h>
#include <string.h>

/* The value of DisplayLooksLike that follows WindowServer's default. */
static NSString *const DSDefault = @"Default";

/* Layout, in points. */
#define DSMargin 24.0
#define DSIconSize 64.0
#define DSButtonWidth 112.0
#define DSButtonHeight 28.0
#define DSButtonGap 8.0
#define DSMinWidth 480.0

static NSTextField *
DSLabel (NSRect frame, NSString *text, NSFont *font)
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

/* "3840x2160" -> "3840 x 2160", as macOS writes sizes. */
static NSString *
DSSizeTitle (NSString *size)
{
  NSArray *parts = [size componentsSeparatedByString:@"x"];

  if ([parts count] != 2)
    return size;
  return [NSString stringWithFormat:@"%@ x %@", [parts objectAtIndex:0],
                   [parts objectAtIndex:1]];
}

/* DisplayCurrent "1920x1080@2" -> its size and scale. */
static NSString *
DSCurrentSize (NSString *current, int *scale)
{
  NSRange at = [current rangeOfString:@"@"];

  if (at.location == NSNotFound)
    {
      if (scale != NULL)
        *scale = 1;
      return current;
    }
  if (scale != NULL)
    *scale = [[current substringFromIndex:NSMaxRange (at)] intValue];
  return [current substringToIndex:at.location];
}

static NSArray *
DSParseModes (NSString *list)
{
  NSMutableArray *result = [NSMutableArray array];
  NSEnumerator *e = [[list componentsSeparatedByString:@","] objectEnumerator];
  NSString *mode;

  while ((mode = [e nextObject]) != nil)
    {
      mode = [mode stringByTrimmingCharactersInSet:
                     [NSCharacterSet whitespaceCharacterSet]];
      if ([mode length] > 0 && [[mode componentsSeparatedByString:@"x"] count] == 2)
        [result addObject:mode];
    }
  return result;
}

@interface DSController (Private)
- (void)buildMenu;
- (void)reload;
- (void)rebuildContent;
- (void)chooseSize:(id)sender;
- (void)chooseDefault:(id)sender;
- (void)apply:(NSString *)value;
- (void)settle;
- (void)screenParametersChanged:(NSNotification *)note;
@end

@implementation DSController

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [connection invalidate];
  RELEASE (connection);
  RELEASE (window);
  RELEASE (settings);
  RELEASE (modes);
  RELEASE (pending);
  [super dealloc];
}

- (void)applicationDidFinishLaunching:(NSNotification *)note
{
  NSImage *icon = [NSImage imageNamed:@"Displays.png"];

  if (icon != nil)
    [NSApp setApplicationIconImage:icon];
  [self buildMenu];
  window = [[NSWindow alloc]
      initWithContentRect:NSMakeRect (200, 200, DSMinWidth, 300)
                styleMask:NSTitledWindowMask | NSClosableWindowMask
                          | NSMiniaturizableWindowMask
                  backing:NSBackingStoreBuffered
                    defer:NO];
  [window setTitle:@"Displays"];
  [window setReleasedWhenClosed:NO];
  [window setFrameAutosaveName:@"Displays"];

  [[NSNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector (screenParametersChanged:)
             name:NSApplicationDidChangeScreenParametersNotification
           object:nil];

  connection = [[DSDisplayConnection alloc] initWithDelegate:self];
  [self reload];
  [window makeKeyAndOrderFront:self];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app
{
  return YES;
}

- (void)applicationWillTerminate:(NSNotification *)note
{
  [connection invalidate];
}

- (void)displayConnectionDidChange:(DSDisplayConnection *)c
{
  [self reload];
}

@end

@implementation DSController (Private)

- (void)buildMenu
{
  NSMenu *menu = AUTORELEASE ([[NSMenu alloc] initWithTitle:@"Displays"]);
  NSMenu *windows = AUTORELEASE ([[NSMenu alloc] initWithTitle:@"Window"]);
  id<NSMenuItem> item;

  [menu addItemWithTitle:@"About Displays"
                  action:@selector (orderFrontStandardAboutPanel:)
           keyEquivalent:@""];
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

- (void)screenParametersChanged:(NSNotification *)note
{
  [self reload];
}

/* Read the display's entries again and show them. */
- (void)reload
{
  ASSIGN (settings, [connection displaySettings]);
  ASSIGN (modes, DSParseModes ([settings objectForKey:@"DisplayModes"]));
  /* The choice just made shows once WindowServer reports it. */
  if (pending != nil
      && [pending isEqual:[settings objectForKey:@"DisplayLooksLike"]])
    DESTROY (pending);
  [self rebuildContent];
}

- (void)rebuildContent
{
  NSString *name = [settings objectForKey:@"DisplayName"];
  NSString *panel = [settings objectForKey:@"DisplayPanel"];
  NSString *current = [settings objectForKey:@"DisplayCurrent"];
  NSString *defaultSize = [settings objectForKey:@"DisplayDefault"];
  NSString *looksLike = [settings objectForKey:@"DisplayLooksLike"];
  NSUInteger count = [modes count];
  NSFont *small = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
  NSFont *bold = [NSFont boldSystemFontOfSize:0];
  NSString *currentSize;
  NSString *note = nil;
  CGFloat rowWidth, width, height, top, y;
  NSView *content;
  NSRect frame;
  NSUInteger i;
  int scale = 1;

  if (pending != nil)
    looksLike = pending;
  currentSize = DSCurrentSize (current, &scale);

  rowWidth = count * DSButtonWidth + (count > 0 ? (count - 1) * DSButtonGap : 0);
  width = MAX (DSMinWidth, rowWidth + 2 * DSMargin);
  if (![connection isConnected])
    note = @"WindowServer isn't running. Displays will connect when it starts.";
  else if ([settings objectForKey:@"DisplayPanel"] == nil)
    note = @"This WindowServer has no display settings.";
  else if (count <= 1)
    note = @"This display offers no other sizes.";

  /* Header, then either the choices or the note. */
  height = DSMargin + DSIconSize + 20;
  if (count > 1)
    height += 24 + 32 + 16 + DSButtonHeight + 18 + 18;
  if (note != nil)
    height += 36;
  height += DSMargin - 8;

  content = AUTORELEASE ([[NSView alloc]
                           initWithFrame:NSMakeRect (0, 0, width, height)]);
  top = height - DSMargin;

  /* The display: its icon, name, panel and current size. */
  NSImageView *iconView = AUTORELEASE ([[NSImageView alloc]
      initWithFrame:NSMakeRect (DSMargin, top - DSIconSize, DSIconSize, DSIconSize)]);
  [iconView setImage:[NSApp applicationIconImage]];
  [iconView setImageScaling:NSScaleProportionally];
  [iconView setEditable:NO];
  [content addSubview:iconView];

  CGFloat textX = DSMargin + DSIconSize + 16;
  CGFloat textW = width - textX - DSMargin;
  [content addSubview:DSLabel (NSMakeRect (textX, top - 22, textW, 22),
                               [name length] > 0 ? name : @"Display",
                               [NSFont boldSystemFontOfSize:16])];
  if (panel != nil)
    [content addSubview:DSLabel (NSMakeRect (textX, top - 42, textW, 18),
                                 [NSString stringWithFormat:@"%@ pixels",
                                           DSSizeTitle (panel)], nil)];
  if ([currentSize length] > 0)
    {
      NSString *text = scale > 1
        ? [NSString stringWithFormat:@"Looks like %@ (HiDPI, %dx)",
                    DSSizeTitle (currentSize), scale]
        : [NSString stringWithFormat:@"Looks like %@", DSSizeTitle (currentSize)];
      [content addSubview:DSLabel (NSMakeRect (textX, top - 62, textW, 18),
                                   text, small)];
    }
  y = top - DSIconSize - 20;

  if (count > 1)
    {
      NSBox *line = AUTORELEASE ([[NSBox alloc]
          initWithFrame:NSMakeRect (DSMargin, y, width - 2 * DSMargin, 1)]);
      [line setBoxType:NSBoxSeparator];
      [line setTitlePosition:NSNoTitle];
      [content addSubview:line];
      y -= 24;

      [content addSubview:DSLabel (NSMakeRect (DSMargin, y, 200, 20),
                                   @"Looks like:", bold)];
      y -= 32;

      /* Default for display, naming the size it is. */
      NSButton *defaultButton = AUTORELEASE ([[NSButton alloc]
          initWithFrame:NSMakeRect (DSMargin, y, 320, 22)]);
      [defaultButton setButtonType:NSSwitchButton];
      [defaultButton setTitle:defaultSize != nil
          ? [NSString stringWithFormat:@"Default for display (%@)",
                      DSSizeTitle (defaultSize)]
          : @"Default for display"];
      [defaultButton setState:[looksLike isEqual:DSDefault]
                                ? NSOnState : NSOffState];
      [defaultButton setTarget:self];
      [defaultButton setAction:@selector (chooseDefault:)];
      [content addSubview:defaultButton];
      y -= 16 + DSButtonHeight;

      /* One button per size, Larger Text to More Space. With the
         default chosen, the size it is shows selected too, as the
         size in effect. */
      CGFloat x0 = floor ((width - rowWidth) / 2);
      NSString *selected = [looksLike isEqual:DSDefault] || looksLike == nil
        ? (defaultSize != nil ? defaultSize : currentSize) : looksLike;
      for (i = 0; i < count; i++)
        {
          NSString *mode = [modes objectAtIndex:i];
          CGFloat x = x0 + i * (DSButtonWidth + DSButtonGap);
          NSButton *button = AUTORELEASE ([[NSButton alloc]
              initWithFrame:NSMakeRect (x, y, DSButtonWidth, DSButtonHeight)]);
          [button setButtonType:NSPushOnPushOffButton];
          [button setTitle:DSSizeTitle (mode)];
          [button setTag:(NSInteger) i];
          [button setState:[mode isEqual:selected] ? NSOnState : NSOffState];
          [button setTarget:self];
          [button setAction:@selector (chooseSize:)];
          [content addSubview:button];

          if ([mode isEqual:defaultSize])
            {
              NSTextField *mark = DSLabel (
                  NSMakeRect (x, y - 18, DSButtonWidth, 16), @"Default", small);
              [mark setAlignment:NSCenterTextAlignment];
              [content addSubview:mark];
            }
        }
      y -= 18 + 18;
      NSTextField *larger = DSLabel (NSMakeRect (x0, y, 140, 16),
                                     @"Larger Text", small);
      NSTextField *more = DSLabel (
          NSMakeRect (x0 + rowWidth - 140, y, 140, 16), @"More Space", small);
      [more setAlignment:NSRightTextAlignment];
      [content addSubview:larger];
      [content addSubview:more];
    }

  if (note != nil)
    {
      y -= 30;
      [content addSubview:DSLabel (NSMakeRect (DSMargin, y, width - 2 * DSMargin, 20),
                                   note, nil)];
    }

  /* Keep the window's top left where it is. */
  frame = [window frame];
  NSRect newFrame = [window frameRectForContentRect:
                              NSMakeRect (0, 0, width, height)];
  newFrame.origin.x = frame.origin.x;
  newFrame.origin.y = NSMaxY (frame) - newFrame.size.height;
  [window setContentView:content];
  [window setFrame:newFrame display:YES];
}

- (void)chooseSize:(id)sender
{
  NSInteger i = [sender tag];

  if (i >= 0 && (NSUInteger) i < [modes count])
    [self apply:[modes objectAtIndex:i]];
}

- (void)chooseDefault:(id)sender
{
  if ([sender state] == NSOnState)
    [self apply:DSDefault];
  else
    {
      /* Unticking keeps the size in effect, now as the user's choice. */
      NSString *size = DSCurrentSize ([settings objectForKey:@"DisplayCurrent"], NULL);
      [self apply:([modes containsObject:size] ? size : DSDefault)];
    }
}

- (void)apply:(NSString *)value
{
  int e;

  if (value == nil)
    return;
  e = [connection setLooksLike:value];
  if (e != 0)
    {
      NSString *why = e == EPERM
        ? @"Only the user logged in at the display can change its size."
        : [NSString stringWithFormat:@"WindowServer didn't accept the size (%s).",
                    strerror (e)];
      NSRunAlertPanel (@"Displays", @"%@", @"OK", nil, nil, why);
      [self reload];
      return;
    }
  /* Show the choice now; WindowServer's screen change follows. */
  ASSIGN (pending, value);
  [self rebuildContent];
  [NSObject cancelPreviousPerformRequestsWithTarget:self
                                           selector:@selector (settle)
                                             object:nil];
  [self performSelector:@selector (settle) withObject:nil afterDelay:1.0];
}

/* A second after a choice: show what WindowServer has, whether or not
   its screen change came. */
- (void)settle
{
  DESTROY (pending);
  [self reload];
}

@end
