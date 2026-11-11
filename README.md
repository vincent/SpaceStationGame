# Space Station Tycoon

A mobile game about managing and improving an abandoned space station.
Built with Godot 4.7 (GDScript), Android first.

![screenshot](docs/screenshot.png)

## Quick start

```bash
tools/editor.sh      # open in the pinned Godot editor (downloads it on first run)
tools/run.sh         # play on desktop (click = tap, wheel = zoom, F3 = debug panel)
tools/test.sh        # run all tests headless
```

Already have Godot 4.7.x installed? Open `project.godot` from the Godot
project manager, or `export GODOT=/path/to/godot` so the scripts use it.

## On your Android phone

1. Install Android Studio (or just the command-line SDK) and a JDK 17;
   set `ANDROID_HOME`.
2. `tools/export_android.sh` → `build/android/SpaceStationTycoon-debug.apk`
3. Enable USB debugging on the phone, plug it in, `tools/install_android.sh`.

Or skip all that: every push to `main` builds a debug APK in GitHub Actions
(Actions tab → latest run → **SpaceStationTycoon-debug-apk** artifact).
For one-click deploys from the editor, enable *Remote Debug → Deploy with Remote Debug*
and press the Android button in the top-right.

## Controls

| Action | Touch | Desktop |
|---|---|---|
| Zoom between station view and room view | pinch | mouse wheel |
| Focus a module (zooms in, cuts it open) | tap it | click |
| Build on a free slot (dashed outline) | tap it in station view | click |
| Pan | drag | drag |
| Walk | tap the floor (room view) | left click |
| Use an object | tap it, then pick an action | click |
| Repair / power / upgrade a module | panel bottom-left (room view) | click |
| Inventory: move / use | drag / double-tap | drag / double-click or right-click |
| Debug panel (debug builds) | "DBG" button | F3 |

## Project layout & conventions

See [CLAUDE.md](CLAUDE.md) (it's written for both humans and Claude) and the
[roadmap](docs/ROADMAP.md).
