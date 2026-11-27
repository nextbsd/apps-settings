/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * SSToolbar: the Command+Shift+5 toolbar, a dark rounded bar near the
 * bottom of the screen, as macOS's: close; capture the screen, a
 * window or a selection; record the screen or a selection; Options;
 * and the Capture (or Record) button. While a recording runs it shows
 * close and Stop only.
 */

#import <AppKit/AppKit.h>

typedef enum
{
  SSToolScreen,
  SSToolWindow,
  SSToolSelection,
  SSToolRecordScreen,
  SSToolRecordSelection
} SSTool;

@protocol SSToolbarDelegate
- (void)toolbarClose:(id)toolbar;
- (void)toolbar:(id)toolbar choseTool:(SSTool)tool;
- (void)toolbar:(id)toolbar showOptions:(NSEvent *)event inRect:(NSRect)rect;
- (void)toolbarCapture:(id)toolbar;
@end

@interface SSToolbarView : NSView
{
  id _delegate;
  SSTool _tool;
  BOOL _recording;
  int _pressed;			/* the item under a press, or -1 */
  int _hover;
}
- (id)initWithFrame:(NSRect)frame delegate:(id)delegate;
- (void)setTool:(SSTool)tool;
- (SSTool)tool;
- (void)setRecording:(BOOL)recording;
@end

/* The toolbar's window, centred near the bottom of the main display. */
NSWindow *SSToolbarWindowCreate (id delegate, SSToolbarView **view);
/* Its size for the state it shows. */
NSSize SSToolbarSize (BOOL recording);

/* Whether a tool records, and whether it takes a selection. */
static inline BOOL
SSToolRecords (SSTool tool)
{
  return tool == SSToolRecordScreen || tool == SSToolRecordSelection;
}

static inline BOOL
SSToolSelects (SSTool tool)
{
  return tool == SSToolSelection || tool == SSToolRecordSelection;
}
