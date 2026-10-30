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

## Build

Requires Xcode command line tools, macOS 13+, Apple Silicon.

```sh
./build.sh
open "The Miracle and the Sleeper.app"
```

On the first **Begin** with Shut Down selected, macOS asks to allow controlling System Events — allow it (System Settings › Privacy & Security › Automation).

## Notes

- Apps with unsaved documents can stop the shut down.
- Waking from a full shut down is unreliable on MacBooks; use Sleep together with "Wake me at".
