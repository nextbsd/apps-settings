# Screenshot

Pictures and recordings of the screen, as macOS's Screenshot
([nextbsd/nextbsd#715](https://github.com/nextbsd/nextbsd/issues/715)).
It installs as `/System/Applications/Screenshot.app`, where WindowServer
trusts it to capture the screen without asking for consent (its
`CaptureTrustedApps` setting, apps-windowserver's "Screen capture").

## The keys

WindowServer takes these before any app, in every app, and hands them to
the Dock, which hands them to Screenshot (starting it if it isn't running):

| Keys | |
|---|---|
| Command+Shift+3, Print Screen | The whole screen, at once |
| Command+Shift+4 | Drag a selection; Space picks a window instead, Escape cancels |
| Command+Shift+5 | The toolbar |
| Control with any of them | Copy the picture instead of saving a file |

## The toolbar

The toolbar sits over the dimmed screen: close, capture the screen, a
window or a selection, record the screen or a selection, **Options** and
the **Capture** (or **Record**) button. A selection is a dashed rectangle
with eight handles and its size in the middle; drag inside it to move it,
or anywhere else to draw a new one. Return takes it, Escape or × closes.
Opening Screenshot.app opens the toolbar.

**Options**: where pictures go (Desktop, the default; Documents;
Clipboard; Other Folder…), a timer (None, 5 or 10 seconds), the
microphone for recordings (None, or each OSS recording device in
`/dev/sndstat`, Bluetooth headsets' `dsp.btN` included), and Show the
Pointer, Show the Thumbnail and Remember the Last Selection. They're the
app's defaults (`org.nextbsd.Screenshot`: `ScreenshotSaveTo`,
`ScreenshotOtherFolder`, `ScreenshotTimer`, `ScreenshotMicrophone`,
`ScreenshotShowPointer`, `ScreenshotShowThumbnail`,
`ScreenshotRememberSelection`).

## After a picture

Pictures are PNG files named `Screenshot 2026-11-27 at 21.04.07.png`. A
thumbnail slides into the bottom right corner for five seconds (longer
while the pointer is over it): drag it into a document or a folder (it
carries the file), click it to open the file, or let it go: the file is
already saved.

## Recordings

Recordings are QuickTime movies, `Screen Recording 2026-11-27 at
21.04.07.mov`, with MPEG-4 video and, with a microphone, AAC sound, made
by the ffmpeg that ships with NextBSD (nextbsd-gnustep-support's own LGPL
encoders and its mov muxer): Screenshot pipes WindowServer's capture
stream into `ffmpeg` at 30 frames a second, repeating the last frame while
the screen doesn't change, so the movie keeps the wall clock's time, and
ffmpeg reads the microphone itself. ffmpeg's messages go to
`~/Library/Logs/Screenshot.log`. They go where pictures go, or to the
Desktop when that is the clipboard.

While it records, the Dock's recording extra shows a red dot, the time
and a stop button: in the menu bar in the Mac style, on the taskbar in the
Windows style, in the Dock in the NeXT style. Stopping saves the movie
and opens it with `-[NSWorkspace openFile:]`, so it opens in Video once
Video is there. Command+Shift+5 while recording shows Stop.

## Asking Screenshot (for other apps)

`SSRequest.h` has the names. They are meant to stay as they are.

**From the command line** (or `NSTask`): run the app's executable. When a
copy is already running, the new one hands it the request and exits at
once, so this works either way:

```sh
/System/Applications/Screenshot.app/Screenshot -Record screen      # the toolbar, ready to record the screen
/System/Applications/Screenshot.app/Screenshot -Record selection   # the toolbar, ready to record a selection
/System/Applications/Screenshot.app/Screenshot -Stop YES           # stop a recording
/System/Applications/Screenshot.app/Screenshot -Shortcut screen    # a picture of the screen (also selection, window, toolbar)
/System/Applications/Screenshot.app/Screenshot -Shortcut screen -Clipboard YES
```

Video's **File › New Screen Recording** runs `Screenshot -Record screen`.
Start it from inside the desktop session (as an app's `NSTask` does), so it
has the session's backend.

**From a GNUstep app**, with Distributed Objects over the user's message
ports: the root proxy of `org.nextbsd.Screenshot`
(`NSMessagePortNameServer`) answers `-performRequest:` (oneway) with a
dictionary of `Action` (`screen`, `selection`, `window`, `toolbar`,
`record-screen`, `record-selection`, `stop`) and, for pictures,
`Clipboard` (a boolean). No proxy means Screenshot isn't running: start it
as above.

**Recording state**: Screenshot posts the distributed notification
`org.nextbsd.Screenshot.RecordingChanged` with `Recording` (boolean),
`Started` (seconds since 1970) and `Path` (the movie) when a recording
starts and stops; `org.nextbsd.Screenshot.RecordingQuery` makes it post it
again, and `org.nextbsd.Screenshot.Stop` stops a recording.

## Running

Screenshot is an agent (`LSUIElement`): it has no Dock item. It quits
after five minutes with nothing to do (`ScreenshotIdleQuitSeconds`, 0 for
never); the next key starts it again.
