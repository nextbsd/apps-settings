/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * SNController: Sound's app delegate and its one window, as macOS's
 * Sound settings:
 *   - Sound Effects: the alert sound and its volume, NSGlobalDomain's
 *     NBAlertSound and NBAlertVolume, which the backend's NSBeep is to
 *     play (the theme's Info.plist can set the defaults). Choosing one
 *     plays it;
 *   - Output: the devices sound can play to, kernel devices and
 *     Bluetooth headsets by name, with the one playing now selected;
 *   - Input: the devices that can record, a headset's microphone
 *     included, the input volume and a live level meter. Choosing a
 *     headset opens its microphone, as on macOS;
 *   - under the tabs, the output volume, Mute, and Show volume in Dock
 *     (the Dock's sound extra).
 * The device work is SNAudio's. A change applies at once; there's no
 * Apply button. Everything follows bluetoothd's notifications and reads
 * the mixers again every second (OSS posts no changes), so a change made
 * elsewhere (the Dock, mixer(8), the headset's own buttons) shows at once.
 *
 * Choosing which kernel device is the output (hw.snd.default_unit) needs
 * root, through the settings apps' privileged helper, which doesn't exist
 * yet: until then the list shows the output but can't change it.
 */

#import <AppKit/AppKit.h>
#import "SNAudio.h"
#import "SNDockExtra.h"
#import "SNLevelView.h"

@interface SNController : NSObject
{
  NSWindow *window;
  SNAudio *audio;
  int wakeFDs[2];
  NSFileHandle *wakeHandle;
  NSTimer *poll;
  NSTimer *meterTimer;
  SNDockExtra *dockExtra;
  NSSound *playing;

  /* What SNAudio said last. */
  SNAudioDevice devices[SNAudioMaxDevices];
  int deviceCount;
  NSArray *outputs;		/* NSNumber indexes into devices */
  NSArray *inputs;
  NSString *shownDevices;	/* what the lists show, to reload on change */
  NSString *meterDevice;	/* the ident the meter is open on */
  SNAudioMeter *meter;
  int outputVolume;
  BOOL outputMuted;
  BOOL outputStalled;		/* its virtual_oss isn't answering */
  BOOL reloading;		/* selection changes are ours, not the user's */
  NSArray *alertSounds;		/* names */
  NSDictionary *alertPaths;	/* name -> file */

  /* The window's controls; the window retains them. */
  NSTabView *tabs;
  NSTableView *alertTable;
  NSSlider *alertSlider;
  NSTextField *effectsNote;
  NSTableView *outputTable;
  NSTextField *outputDetail;
  NSTextField *outputNote;
  NSTableView *inputTable;
  NSTextField *inputDetail;
  NSTextField *inputVolumeLabel;
  NSSlider *inputSlider;
  SNLevelView *levelView;
  NSTextField *inputNote;
  NSSlider *volumeSlider;
  NSButton *muteSwitch;
  NSButton *dockSwitch;
}
@end
