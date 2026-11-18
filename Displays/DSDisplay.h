/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * DSDisplay and DSDisplayMode: what Displays shows, read from
 * WindowServer by DSDisplayConnection. They hold no WindowServer types,
 * so the rest of the app builds against any WindowServerClient.
 *
 * A display comes from WS_MSG_LIST_DISPLAYS (ws_display_info_t) on
 * servers with WS_SERVER_DISPLAYS, or, on older servers, from the
 * Display* settings, which describe the one display there is.
 */

#import <Foundation/Foundation.h>

/* DSDisplay flags, WindowServer's WS_DISPLAY_* values. */
enum {
  DSDisplayMain = 0x0001,	/* the menu bar and the Dock */
  DSDisplayBuiltin = 0x0002,	/* a laptop's own panel */
  DSDisplayMirror = 0x0004,	/* shows another display's part */
  DSDisplayHiDPI = 0x0008,	/* its default size is 2x */
  DSDisplayPending = 0x0010	/* a change goes back unless kept */
};

/* Changes (WindowServer's WS_DISPLAY_SET_*, _KEEP, _REVERT) and their
   flag WS_DISPLAY_CONFIRM: the change goes back by itself after
   DSRevertSeconds unless kept. */
enum {
  DSOpSetLooksLike = 1,
  DSOpSetMode,
  DSOpSetOrigin,
  DSOpSetMain,
  DSOpSetMirror,
  DSOpKeep,
  DSOpRevert
};
#define DSConfirm 0x0001
#define DSRevertSeconds 15

/* DSDisplayMode kinds, WindowServer's WS_DISPLAY_MODE_* values. */
enum {
  DSModeLooksLike = 1,		/* a "looks like" size, in points */
  DSModePanel = 2		/* a mode of the display, in pixels */
};

/* DSDisplayMode flags. */
enum {
  DSModeCurrent = 0x0001,	/* in use */
  DSModeDefault = 0x0002,	/* the display's default size or
				   preferred mode */
  DSModeInterlaced = 0x0004
};

@interface DSDisplayMode : NSObject
{
  unsigned _kind;
  unsigned _flags;
  unsigned _width;
  unsigned _height;
  unsigned _refreshMHz;
}

+ (DSDisplayMode *)modeWithKind:(unsigned)kind
                          flags:(unsigned)flags
                          width:(unsigned)width
                         height:(unsigned)height
                     refreshMHz:(unsigned)refresh;

- (unsigned)kind;
- (unsigned)flags;
- (unsigned)width;
- (unsigned)height;
- (unsigned)refreshMHz;
- (BOOL)isCurrent;
- (BOOL)isDefault;
- (BOOL)isInterlaced;
- (BOOL)hasSizeOf:(DSDisplayMode *)other;

/* "1920 x 1080" */
- (NSString *)sizeTitle;
@end

@interface DSDisplay : NSObject
{
  unsigned _displayID;
  unsigned _flags;
  NSRect _frame;
  unsigned _scale;
  unsigned _panelWidth;
  unsigned _panelHeight;
  unsigned _refreshMHz;
  unsigned _mirrorOf;
  unsigned _revertMS;
  NSString *_name;
  NSString *_edidID;
  NSString *_connector;
  NSArray *_modes;
  BOOL _followsDefault;
}

/* frame: points in the desktop, top-left origin and y down, as
   WindowServer gives it. */
- (id)initWithID:(unsigned)displayID
           flags:(unsigned)flags
           frame:(NSRect)frame
           scale:(unsigned)scale
      panelWidth:(unsigned)panelWidth
     panelHeight:(unsigned)panelHeight
      refreshMHz:(unsigned)refresh
        mirrorOf:(unsigned)mirrorOf
        revertMS:(unsigned)revertMS
            name:(NSString *)name
          edidID:(NSString *)edidID
       connector:(NSString *)connector;

- (unsigned)displayID;
- (unsigned)flags;
- (NSRect)frame;
- (unsigned)scale;
- (unsigned)panelWidth;
- (unsigned)panelHeight;
- (unsigned)refreshMHz;
- (unsigned)mirrorOf;
- (unsigned)revertMS;
- (NSString *)name;
- (NSString *)edidID;
- (NSString *)connector;

- (BOOL)isMain;
- (BOOL)isBuiltin;
- (BOOL)isMirror;
- (BOOL)isPending;

/* Its "looks like" sizes (Larger Text first), then its panel modes
   (largest first). Empty until set. */
- (NSArray *)modes;
- (void)setModes:(NSArray *)modes;
- (NSArray *)looksLikeModes;
- (NSArray *)panelModes;
- (DSDisplayMode *)currentLooksLike;
- (DSDisplayMode *)defaultLooksLike;

/* Whether the size follows the display's default ("Default for
   display") rather than a size the user picked. */
- (BOOL)followsDefault;
- (void)setFollowsDefault:(BOOL)flag;

/* What Displays compares to see whether anything changed. */
- (NSString *)stateDescription;
@end

/* "60 Hz", "59.94 Hz" */
NSString *DSRefreshTitle (unsigned refreshMHz);

/* Where a display of rect (desktop points, top-left origin) goes to
   touch one of others (NSValue rects) without overlapping any: the
   nearest such place, with edges within `align` points of lining up
   lined up. The rect's own origin if there are no others. */
NSPoint DSSnapOrigin (NSRect rect, NSArray *others, CGFloat align);
