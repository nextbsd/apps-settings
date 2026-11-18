/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "DSDisplay.h"
#import <GNUstepBase/GNUstep.h>

#include <math.h>

NSString *
DSRefreshTitle (unsigned refreshMHz)
{
  if (refreshMHz % 1000 == 0)
    return [NSString stringWithFormat:@"%u Hz", refreshMHz / 1000];
  return [NSString stringWithFormat:@"%.2f Hz", refreshMHz / 1000.0];
}

@implementation DSDisplayMode

+ (DSDisplayMode *)modeWithKind:(unsigned)kind
                          flags:(unsigned)flags
                          width:(unsigned)width
                         height:(unsigned)height
                     refreshMHz:(unsigned)refresh
{
  DSDisplayMode *mode = AUTORELEASE ([[self alloc] init]);

  mode->_kind = kind;
  mode->_flags = flags;
  mode->_width = width;
  mode->_height = height;
  mode->_refreshMHz = refresh;
  return mode;
}

- (unsigned)kind
{
  return _kind;
}

- (unsigned)flags
{
  return _flags;
}

- (unsigned)width
{
  return _width;
}

- (unsigned)height
{
  return _height;
}

- (unsigned)refreshMHz
{
  return _refreshMHz;
}

- (BOOL)isCurrent
{
  return (_flags & DSModeCurrent) != 0;
}

- (BOOL)isDefault
{
  return (_flags & DSModeDefault) != 0;
}

- (BOOL)isInterlaced
{
  return (_flags & DSModeInterlaced) != 0;
}

- (BOOL)hasSizeOf:(DSDisplayMode *)other
{
  return other != nil && _width == [other width] && _height == [other height];
}

- (NSString *)sizeTitle
{
  return [NSString stringWithFormat:@"%u x %u", _width, _height];
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"%u:%ux%u@%u/%x", _kind, _width,
                   _height, _refreshMHz, _flags];
}

@end

@implementation DSDisplay

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
       connector:(NSString *)connector
{
  if ((self = [super init]) == nil)
    return nil;
  _displayID = displayID;
  _flags = flags;
  _frame = frame;
  _scale = scale > 0 ? scale : 1;
  _panelWidth = panelWidth;
  _panelHeight = panelHeight;
  _refreshMHz = refresh;
  _mirrorOf = mirrorOf;
  _revertMS = revertMS;
  _name = [([name length] > 0 ? name : @"Display") copy];
  _edidID = [(edidID != nil ? edidID : @"") copy];
  _connector = [(connector != nil ? connector : @"") copy];
  _modes = [[NSArray alloc] init];
  return self;
}

- (void)dealloc
{
  RELEASE (_name);
  RELEASE (_edidID);
  RELEASE (_connector);
  RELEASE (_modes);
  [super dealloc];
}

- (unsigned)displayID
{
  return _displayID;
}

- (unsigned)flags
{
  return _flags;
}

- (NSRect)frame
{
  return _frame;
}

- (unsigned)scale
{
  return _scale;
}

- (unsigned)panelWidth
{
  return _panelWidth;
}

- (unsigned)panelHeight
{
  return _panelHeight;
}

- (unsigned)refreshMHz
{
  return _refreshMHz;
}

- (unsigned)mirrorOf
{
  return _mirrorOf;
}

- (unsigned)revertMS
{
  return _revertMS;
}

- (NSString *)name
{
  return _name;
}

- (NSString *)edidID
{
  return _edidID;
}

- (NSString *)connector
{
  return _connector;
}

- (BOOL)isMain
{
  return (_flags & DSDisplayMain) != 0;
}

- (BOOL)isBuiltin
{
  return (_flags & DSDisplayBuiltin) != 0;
}

- (BOOL)isMirror
{
  return (_flags & DSDisplayMirror) != 0 && _mirrorOf != 0;
}

- (BOOL)isPending
{
  return (_flags & DSDisplayPending) != 0;
}

- (NSArray *)modes
{
  return _modes;
}

- (void)setModes:(NSArray *)modes
{
  ASSIGNCOPY (_modes, modes != nil ? modes : [NSArray array]);
}

static NSArray *
DSModesOfKind (NSArray *modes, unsigned kind)
{
  NSMutableArray *result = [NSMutableArray array];
  NSEnumerator *e = [modes objectEnumerator];
  DSDisplayMode *mode;

  while ((mode = [e nextObject]) != nil)
    if ([mode kind] == kind)
      [result addObject:mode];
  return result;
}

- (NSArray *)looksLikeModes
{
  return DSModesOfKind (_modes, DSModeLooksLike);
}

- (NSArray *)panelModes
{
  return DSModesOfKind (_modes, DSModePanel);
}

static DSDisplayMode *
DSLooksLikeWithFlag (NSArray *modes, unsigned flag)
{
  NSEnumerator *e = [modes objectEnumerator];
  DSDisplayMode *mode;

  while ((mode = [e nextObject]) != nil)
    if ([mode kind] == DSModeLooksLike && ([mode flags] & flag) != 0)
      return mode;
  return nil;
}

- (DSDisplayMode *)currentLooksLike
{
  return DSLooksLikeWithFlag (_modes, DSModeCurrent);
}

- (DSDisplayMode *)defaultLooksLike
{
  return DSLooksLikeWithFlag (_modes, DSModeDefault);
}

- (BOOL)followsDefault
{
  return _followsDefault;
}

- (void)setFollowsDefault:(BOOL)flag
{
  _followsDefault = flag;
}

- (NSString *)stateDescription
{
  /* Not revert_ms, which counts down while a change is pending. */
  return [NSString stringWithFormat:@"%u %x %@ %u %ux%u@%u m%u %@ %@ %@ %d %@",
                   _displayID, _flags, NSStringFromRect (_frame), _scale,
                   _panelWidth, _panelHeight, _refreshMHz, _mirrorOf,
                   _name, _edidID, _connector,
                   (int) _followsDefault, [_modes description]];
}

@end

static BOOL
DSOverlaps (NSRect a, NSRect b)
{
  return NSMinX (a) < NSMaxX (b) && NSMinX (b) < NSMaxX (a)
    && NSMinY (a) < NSMaxY (b) && NSMinY (b) < NSMaxY (a);
}

static CGFloat
DSClamp (CGFloat v, CGFloat lo, CGFloat hi)
{
  return v < lo ? lo : (v > hi ? hi : v);
}

/* Line v (a start, length len) up with [lo, hi) when it's close. */
static CGFloat
DSAlign (CGFloat v, CGFloat len, CGFloat lo, CGFloat hi, CGFloat align)
{
  if (fabs (v - lo) <= align)
    return lo;
  if (fabs (v + len - hi) <= align)
    return hi - len;
  return v;
}

NSPoint
DSSnapOrigin (NSRect rect, NSArray *others, CGFloat align)
{
  NSPoint best = rect.origin;
  CGFloat bestDistance = -1;
  NSUInteger i, j, n = [others count];

  for (i = 0; i < n; i++)
    {
      NSRect o = [[others objectAtIndex:i] rectValue];
      CGFloat w = NSWidth (rect), h = NSHeight (rect);
      /* Sides share at least a point of edge. */
      CGFloat y = DSAlign (DSClamp (NSMinY (rect), NSMinY (o) - h + 1,
                                    NSMaxY (o) - 1), h,
                           NSMinY (o), NSMaxY (o), align);
      CGFloat x = DSAlign (DSClamp (NSMinX (rect), NSMinX (o) - w + 1,
                                    NSMaxX (o) - 1), w,
                           NSMinX (o), NSMaxX (o), align);
      NSPoint candidates[4];
      int k;

      candidates[0] = NSMakePoint (NSMaxX (o), y);	/* right */
      candidates[1] = NSMakePoint (NSMinX (o) - w, y);	/* left */
      candidates[2] = NSMakePoint (x, NSMaxY (o));	/* below */
      candidates[3] = NSMakePoint (x, NSMinY (o) - h);	/* above */
      for (k = 0; k < 4; k++)
        {
          NSRect placed = NSMakeRect (candidates[k].x, candidates[k].y, w, h);
          CGFloat dx = candidates[k].x - NSMinX (rect);
          CGFloat dy = candidates[k].y - NSMinY (rect);
          CGFloat distance = dx * dx + dy * dy;
          BOOL clear = YES;

          for (j = 0; j < n && clear; j++)
            if (DSOverlaps (placed, [[others objectAtIndex:j] rectValue]))
              clear = NO;
          if (clear && (bestDistance < 0 || distance < bestDistance))
            {
              best = candidates[k];
              bestDistance = distance;
            }
        }
    }
  return best;
}
