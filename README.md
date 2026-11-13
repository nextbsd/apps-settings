# apps-settings

NextBSD's settings apps. Each top-level directory is a separate GNUstep
application, installed in `/System/Applications`:

| Directory  | App            | What it sets                                   |
|------------|----------------|------------------------------------------------|
| `Displays/` | Displays.app   | The display's "looks like" size (HiDPI scaling) |

Displays talks to NextBSD's WindowServer through its client library
(`libWindowServerClient`, found with `pkg-config WindowServerClient`).

The top-level `GNUmakefile` is a gnustep-make aggregate that builds every
app listed in its `SUBPROJECTS`.

## Building

With the GNUstep build environment sourced:

```sh
gmake
gmake install GNUSTEP_INSTALLATION_DOMAIN=SYSTEM
```

`DESTDIR=/some/root` stages the install elsewhere. A single app can be
built on its own with `gmake -C <Directory>`.

## License

BSD 2-Clause; see `LICENSE`.
