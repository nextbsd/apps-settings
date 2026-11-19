/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * DSFakeDisplays: made-up displays for trying Displays' window before
 * WindowServer lists real ones. Only in test builds (gmake
 * fake_displays=yes), and only when DS_FAKE_DISPLAYS is set to how many
 * (1 to 3): a built-in HiDPI panel, a 4K monitor to its right and a
 * 1080p one. They behave as WS_SERVER_DISPLAYS describes, including a
 * pending change going back after 15 seconds. Night Shift's settings
 * are kept here too. In ordinary builds +fakeDisplaysWithTarget:
 * returns nil.
 */

#import <Foundation/Foundation.h>

@interface DSFakeDisplays : NSObject
{
  void *_state;
  id _target;			/* not retained */
  SEL _selector;
  NSMutableDictionary *_settings;
  NSTimer *_revertTimer;
}

/* target gets selector whenever the displays change. */
+ (id)fakeDisplaysWithTarget:(id)target selector:(SEL)selector;

- (NSArray *)displays;
- (NSDictionary *)settings;
- (int)configure:(unsigned)op
         display:(unsigned)displayID
               x:(int)x
               y:(int)y
           width:(unsigned)width
          height:(unsigned)height
         refresh:(unsigned)refresh
             arg:(unsigned)arg
           flags:(unsigned)flags;
- (int)setSetting:(NSString *)key value:(NSString *)value;
@end
