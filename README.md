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
