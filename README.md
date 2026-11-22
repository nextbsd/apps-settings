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
| `Trackpad/` | Trackpad.app   | Tap to click, tap and drag, three-finger drag, secondary click, tracking speed, natural and momentum scrolling, scroll speed |
| `Mouse/`    | Mouse.app      | Tracking speed, pointer acceleration, primary button, double-click speed, natural scrolling, scroll speed |
| `UsersLogin/` | Users & Login.app | The local accounts (add, delete, passwords, administrators), automatic login, the login window's list or name and password fields, its Restart and Shut Down buttons |
| `Printers/` | Printers.app   | The printers with their status and waiting jobs, adding nearby driverless printers or one by address, removing them, the default printer, paper size and two-sided printing |
| `Network/`  | Network.app    | The network services and their status, IPv4, IPv6, DNS servers and search domains, the hardware address, Wi-Fi networks and joining them (WPA Personal and Enterprise), the computer's name, the Dock's Wi-Fi extra |

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
(userInfo `domain` and `keys`), on which the clock reads them again. It's
built as `DateTime.app`, since gnustep-make can't name an app with a
space or `&`, and installed as `Date & Time.app`.

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

Users & Login lists the local accounts from the directory's own files,
`/Local/Library/DirectoryServices/Users.plist` and `Groups.plist` (group
`admin`'s members are the administrators), and reads them again whenever
they change, so an account made with `adduser` shows at once. It changes
them through the helper's `CreateUser`, `DeleteUser`, `SetPassword` and
`SetAdmin` (right `org.nextbsd.settings.users`), which follow `adduser`'s,
`rmuser`'s and `passwd`'s rules through libds. The helper won't delete the
account logged in at the screen or the last administrator. With the lock
closed you can still change your own password: you give your old one, which
proves `org.nextbsd.settings.users.own-password` for that one change. On a
machine joined to a directory server the list is read-only, since the
accounts are the server's.

Its Login Options are keys of
`/Local/Library/Preferences/org.nextbsd.loginwindow.plist`, with the names
macOS's loginwindow uses, written by `SetAutoLogin` and
`SetLoginWindowOptions`: `autoLoginUser` (absent: autologin-user's own rule,
the only account, `admin`, without a password; empty: off), `SHOWFULLNAME`,
`RestartDisabled` and `ShutDownDisabled`. Only an account without a password
can log in automatically; it never stands in for one. They apply at the next
login window, once autologin-user and loginwindow read them. It's built as
`UsersLogin.app` and installed as `Users & Login.app`, as Date & Time is.

Printers talks to the local cupsd (`org.nextbsd.cupsd`, from
nextbsd-printing-support) through libcups, as the user: the queues and
their jobs (`cupsEnumDests`, `cupsGetJobs2`), the driverless (IPP
Everywhere) printers nearby that libcups finds through mDNSResponder, and
what a printer offers for paper size and two-sided printing
(`cupsCopyDestInfo`). The default printer, paper size and two-sided are
the user's own, in `~/.cups/lpoptions` (`cupsSetDests2`, as `lpoptions`
does), and need no privilege. Adding and removing a printer go through
the helper's `CUPSAdmin` (right `org.nextbsd.settings.printers`,
`is-admin`), which runs `lpadmin -m everywhere` as root; only driverless
printers can be added until nextbsd-printing-support has filters and
drivers. Printing is optional, so Printers.app is meant to ship with that
package rather than the desktop's core.

Network reads the network services as the user from configd: their
settings from SCPreferences (`preferences.plist`) and what they have now
from the dynamic store (`State:/Network/...`), with the names hostnamed
publishes. As on macOS, changes wait for Apply, which sends each changed
service to the helper's `CommitNetworkPreferences` (its IPv4, IPv6 and
DNS settings, which the helper writes, commits and applies, so ipconfigd
configures the service again) and the names to `SetComputerName` (right
`org.nextbsd.settings.network`). Wi-Fi needs no privilege: Network scans
and joins through wland's MIG interface (`org.nextbsd.wlan`), with the
build making the client stubs from a copy of nextbsd-userland's
`src/WLAN/wlan.defs` (in `Network/mig`), and reads the joined network
from wland's `State:/Network/Interface/<if>/AirPort` entry, as the Dock's
Wi-Fi extra does. Turning Wi-Fi on and off, and the known networks, wait
for wland calls that don't exist yet. Its **Show Wi-Fi status in Dock**
checkbox turns the Dock's Wi-Fi extra on and off, and the extra's "Open
Network Settings…" opens it on the Wi-Fi service.

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

Trackpad and Mouse change WindowServer's settings while it runs
(`WS_SERVER_SETTINGS`) and save them in the user's
`org.nextbsd.WindowServer` defaults, which the session sends again at
login (`wsctl settings reload`). Natural scrolling and scroll speed are
one key each, so the two apps share them. Each app says so when
WindowServer's device list (`wsctl devices`) has no trackpad or mouse.
Mouse's double-click speed is GNUstep's `GSDoubleClickTime` in
`NSGlobalDomain`.

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
