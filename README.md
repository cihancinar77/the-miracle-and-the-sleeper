# The Miracle and the Sleeper

A tiny native macOS menu bar sleep timer. Fall asleep to YouTube — when the countdown ends, your Mac shuts down (or sleeps), and can optionally wake again in the morning.

Themed after Dream Theater's *Images and Words*.

## Features

- Countdown in the menu bar
- Presets (15–120 min) or any custom duration
- Shut Down or Sleep when the timer ends
- +5 / +15 min while running, Cancel any time
- Optional "Wake me at" — schedules a morning wake via `pmset` (asks for your admin password)
- If the Mac fell asleep on its own and wakes after the deadline, the timer is dropped instead of shutting down

## Download

Grab `The-Miracle-and-the-Sleeper.zip` from the [latest release](https://github.com/cihancinar77/the-miracle-and-the-sleeper/releases/latest), unzip, and drag the app to Applications. Requires macOS 13+ (Apple Silicon or Intel).

The app isn't notarized, so macOS blocks it on first launch. Either:

- Try to open it once, then go to System Settings › Privacy & Security and click **Open Anyway**, or
- Run `xattr -dr com.apple.quarantine "/Applications/The Miracle and the Sleeper.app"`

It lives in the menu bar (moon icon) — there's no Dock icon.

## Build

Requires Xcode command line tools and macOS 13+.

```sh
./build.sh
open "The Miracle and the Sleeper.app"
```

On the first **Begin** with Shut Down selected, macOS asks to allow controlling System Events — allow it (System Settings › Privacy & Security › Automation).

## Notes

- Apps with unsaved documents can stop the shut down.
- Waking from a full shut down is unreliable on MacBooks; use Sleep together with "Wake me at".
