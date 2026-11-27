/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * How other programs ask Screenshot for something (README.md, "Asking
 * Screenshot"). Keep these names stable: the Dock (apps-dock, the
 * screenshot keys and the recording extra) and Video (apps-video, File
 * > New Screen Recording) use them.
 *
 * 1. Run the app with an argument; a copy already running takes the
 *    request and the new one exits:
 *
 *      Screenshot -Record screen      the toolbar, ready to record the
 *                                     screen
 *      Screenshot -Record selection   the toolbar, ready to record a
 *                                     selection
 *      Screenshot -Shortcut screen    a picture of the screen, at once
 *      Screenshot -Shortcut selection drag a selection (Space: a window)
 *      Screenshot -Shortcut window    pick a window
 *      Screenshot -Shortcut toolbar   the toolbar, as last used
 *      Screenshot -Clipboard YES      with -Shortcut: copy, don't save
 *      Screenshot -Stop YES           stop recording
 *
 *    With no argument it opens the toolbar.
 *
 * 2. Or, from a GNUstep app, Distributed Objects over message ports
 *    (the user's own; NSMessagePortNameServer): the root proxy of
 *    SSConnectionName takes -performRequest: with a dictionary of
 *    SSActionKey (one of the SSAction* values) and, for pictures,
 *    SSClipboardKey. When nothing is registered under that name,
 *    Screenshot isn't running: start it as in 1.
 *
 * While it records, Screenshot posts the distributed notification
 * SSRecordingNotification ({Recording = YES; Started = seconds since
 * 1970; Path = the movie}) and again with Recording = NO when it stops;
 * SSRecordingQueryNotification makes it post its state again.
 * SSStopNotification (no userInfo) stops a recording.
 */

#ifndef _SS_REQUEST_H_
#define _SS_REQUEST_H_

#import <Foundation/Foundation.h>

#define SSConnectionName @"org.nextbsd.Screenshot"

#define SSActionKey @"Action"
#define SSClipboardKey @"Clipboard"

#define SSActionScreen @"screen"
#define SSActionSelection @"selection"
#define SSActionWindow @"window"
#define SSActionToolbar @"toolbar"
#define SSActionRecordScreen @"record-screen"
#define SSActionRecordSelection @"record-selection"
#define SSActionStop @"stop"

#define SSRecordingNotification @"org.nextbsd.Screenshot.RecordingChanged"
#define SSRecordingQueryNotification @"org.nextbsd.Screenshot.RecordingQuery"
#define SSStopNotification @"org.nextbsd.Screenshot.Stop"

@protocol SSScreenshotServer
- (oneway void)performRequest:(bycopy NSDictionary *)request;
@end

/* The request a command line asks for (1. above), or nil for none. */
static inline NSDictionary *
SSRequestFromArguments (NSArray *args)
{
  NSString *action = nil;
  BOOL clipboard = NO;
  NSUInteger i, n = [args count];

  for (i = 1; i < n; i++)
    {
      NSString *arg = [args objectAtIndex:i];
      NSString *value = i + 1 < n ? [args objectAtIndex:i + 1] : nil;

      if ([arg isEqualToString:@"-Record"] && value != nil)
        {
          action = [value isEqualToString:@"selection"]
            ? SSActionRecordSelection : SSActionRecordScreen;
          i++;
        }
      else if ([arg isEqualToString:@"-Shortcut"] && value != nil)
        {
          if ([value isEqualToString:SSActionScreen]
              || [value isEqualToString:SSActionSelection]
              || [value isEqualToString:SSActionWindow]
              || [value isEqualToString:SSActionToolbar])
            action = value;
          i++;
        }
      else if ([arg isEqualToString:@"-Clipboard"] && value != nil)
        {
          clipboard = [value boolValue];
          i++;
        }
      else if ([arg isEqualToString:@"-Stop"] && value != nil)
        {
          if ([value boolValue])
            action = SSActionStop;
          i++;
        }
    }
  if (action == nil)
    return nil;
  return [NSDictionary dictionaryWithObjectsAndKeys:
                         action, SSActionKey,
                       [NSNumber numberWithBool:clipboard], SSClipboardKey,
                       nil];
}

#endif /* _SS_REQUEST_H_ */
