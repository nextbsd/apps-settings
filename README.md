# apps-settings

NextBSD's settings apps. Each top-level directory is a separate GNUstep
application. For now they install in `~/Applications` with the other desktop
apps, through [nextbsd-gnustep-apps](https://github.com/pkgdemon/nextbsd-gnustep-apps);
they move to `/System/Applications` once they have been tested on their own:

| Directory  | App            | What it sets                                   |
|------------|----------------|------------------------------------------------|
| `Displays/` | Displays.app   | Arrangement, main display, mirroring, "looks like" size, resolution, refresh rate, Night Shift |
| `Bluetooth/` | Bluetooth.app | Bluetooth on or off, paired and nearby devices, connecting, pairing, each headset's audio |

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
