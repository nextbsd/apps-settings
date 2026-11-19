# apps-settings

NextBSD's settings apps. Each top-level directory is a separate GNUstep
application. For now they install in `~/Applications` with the other desktop
apps, through [nextbsd-gnustep-apps](https://github.com/pkgdemon/nextbsd-gnustep-apps);
they move to `/System/Applications` once they have been tested on their own:

| Directory  | App            | What it sets                                   |
|------------|----------------|------------------------------------------------|
| `Displays/` | Displays.app   | Arrangement, main display, mirroring, "looks like" size, resolution, refresh rate, Night Shift |
| `Bluetooth/` | Bluetooth.app | Bluetooth on or off, paired and nearby devices, connecting, pairing, each headset's audio |
| `Energy/`   | Energy.app     | Display off and computer sleep timers on battery and on the power adapter, wake for network access, the battery's charge and condition, the Dock's battery extra |
| `Sound/`   | Sound.app      | Output and input devices (Bluetooth headsets included), output volume and mute, input volume and a live level meter, the alert sound, Show volume in Dock |
| `DateTime/` | Date & Time.app | Network time and its server, the date and time by hand, the time zone, the Dock clock's format |

Displays talks to NextBSD's WindowServer through its client library
(`libWindowServerClient`, found with `pkg-config WindowServerClient`). With a
WindowServer that lists displays (`WS_SERVER_DISPLAYS`) it shows every
display; with an older one, or built against an older client library, it
shows the one display and its "looks like" sizes, as before.

Bluetooth talks to `bluetoothd` over its MIG interface (`org.nextbsd.bluetooth`)
and follows its `org.nextbsd.bluetooth.*` notifications and `State:/Bluetooth`
keys. It needs no privilege: bluetoothd lets any local user pair.
bluetoothd's MIG client stubs aren't installed for apps, so the build runs
`mig` on a copy of nextbsd-userland's `src/Bluetooth/bluetooth.defs` (in
`Bluetooth/mig`). `gmake -C Bluetooth fake_pairing=yes` builds a test copy
in which a made-up device asks to pair when `BT_FAKE_PAIRING` is set to 1 to
5 (just works, numeric comparison, passkey entry, passkey display, PIN).
Don't install it.

Its **Show Bluetooth in Dock** checkbox turns the Dock's Bluetooth extra on
and off.

Energy reads powerd's Energy Saver settings (`IOPMCopyPMPreferences`) and the
battery (IOPowerSources) through libIOKit as the user, and changes the
settings through the privileged helper, `org.nextbsd.SettingsHelper`
(nextbsd-userland `src/SettingsHelper`), once its lock is open. On a machine
whose root domain says it can't sleep (`IOSleepSupported`), the sleep timers
show but are disabled. "Show battery in Dock" asks the Dock with
`org.nextbsd.Dock.SetExtraHidden`.

Date & Time reads the time zone from `/var/db/zoneinfo` (what tzsetup and
the helper record), lists the zones from `/usr/share/zoneinfo`'s
`zone.tab` and `iso3166.tab`, and takes network time to be on while
root's `ntpd` runs (`org.nextbsd.ntpd`), with the server from
`/etc/ntp.conf`. It changes them through the helper's `SetTimeZone`,
`SetDate` and `SetNetworkTime` (right `org.nextbsd.settings.datetime`). The
Clock tab needs no privilege: it writes the Dock clock extra's own
defaults (`DockExtraClock*` in the Dock's domain, `Dock`), key by key,
and posts the distributed notification `org.nextbsd.SettingsChanged`
(userInfo `domain` and `keys`), on which the clock reads them again. The
bundle is `DateTime.app`, since gnustep-make can't name an app with a
space or `&`; it calls itself "Date & Time".

`Frameworks/NBSettings` is what the apps share, compiled into each app that
lists it as a gnustep-make subproject (`xxx_SUBPROJECTS =
../Frameworks/NBSettings`); it becomes the NBSettings framework with
nextbsd/nextbsd#627. For now it holds the helper's client:
`NBAuthorization` (a hold on a right, `org.nextbsd.settings.<area>`, shaped
like Darwin's Authorization Services so an authd can take over the checks),
`NBAuthorizationPanel` (the lock, `NBLockView`, and the name and password
prompt, or "Allow changes?" for an administrator without a password) and
`NBSettingsHelper` (one method per helper operation). Its MIG stubs are made
from a copy of nextbsd-userland's `settingshelper.defs` in
`Frameworks/NBSettings/mig`.

Sound has no daemon to talk to; it reads the devices themselves
(`Sound/SNAudio.c`, which apps-dock's sound extra carries a copy of):

- **Kernel devices** (`pcmN` in `/dev/sndstat`): volume, mute and input
  level through `/dev/mixerN`, as any user. Which one is the output
  (`hw.snd.default_unit`) needs root, so until the settings apps'
  privileged helper exists the list shows the output but can't change it.
- **Bluetooth headsets:** bluetoothd runs a `virtual_oss` for each one
  (`/dev/dsp.btN`, its control device `/dev/dsp.btN.ctl`). The name,
  AVRCP absolute volume and hands-free microphone come from bluetoothd's
  MIG interface (`bt_audio_entry`, `bt_audio_volume`, `bt_hfp_status`,
  `bt_audio_route`), with the same `mig/` copy as Bluetooth/. The volume
  is the headset's own (AVRCP), as on macOS; mute, and the volume of a
  headset without absolute volume (in 6 dB steps), are virtual_oss's.
  Choosing a headset under Input opens its microphone (hands-free), and
  choosing another input closes it.
- **A virtual_oss that doesn't answer** (its headset went away, and the
  mixer waits in `connect(2)` for it to come back) would hang anything that
  opens its devices, uninterruptibly. So every call to one runs in a child
  process with a 400 ms limit, and Sound never waits on one longer.
- **The alert sound** is `NBAlertSound` and `NBAlertVolume` in
  `NSGlobalDomain` (the user's value, else the theme's Info.plist, else
  Tink at 75%). Choosing one plays it. The backend's `NSBeep` doesn't play
  it yet; that's libs-back's side.

## Show X in Dock

The Dock (nextbsd/apps-dock) owns its status extras: Wi-Fi, Bluetooth,
battery, sound, input and the clock. A settings app's **Show X in Dock**
checkbox doesn't keep a setting of its own. It asks the Dock, through
`Shared/NBDockExtra` (built into each app that has such a checkbox):

- The Dock's defaults domain `Dock`, key `DockExtrasHidden`, lists the
  hidden extras' identifiers (`org.nextbsd.dockextra.bluetooth`, `.battery`,
  `.input`, `.wifi`, `.sound`, `.clock`).
- The app posts the distributed notification
  `org.nextbsd.Dock.SetExtraHidden` {`identifier`, `hidden`}. The Dock shows or
  hides the extra at once and answers `org.nextbsd.Dock.ExtrasChanged`
  {`hidden`}, which it also posts when the list changes some other way.
  Every checkbox follows that.
- With no Dock running (no answer within 2 seconds), the app writes
  `DockExtrasHidden` itself; the Dock reads it when it starts.

apps-dock's `DockExtrasSettings.h` has the same names; keep the two in step.
Each extra's menu ends with "Open X Settings…", which opens the app here.

`gmake -C Displays fake_displays=yes` builds a test copy that shows made-up
displays when `DS_FAKE_DISPLAYS` is set to 1, 2 or 3, for trying the window
before WindowServer lists real ones. Don't install it.

The top-level `GNUmakefile` is a gnustep-make aggregate that builds every
app listed in its `SUBPROJECTS`.

## Building

As your normal user, with the GNUstep build environment sourced:

```sh
gmake
gmake install GNUSTEP_INSTALLATION_DOMAIN=USER
```

`DESTDIR=/some/root` stages the install elsewhere. A single app can be
built on its own with `gmake -C <Directory>`.

## License

BSD 2-Clause; see `LICENSE`.
