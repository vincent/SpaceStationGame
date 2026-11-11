# Roadmap

Status markers: `[x]` done · `[~]` in progress / partial · `[ ]` todo

> **New direction (2026-11-11):** the station is now a diorama seen from a
> fixed oblique camera and cut open to show its rooms. Detailed plan and
> status: [PLAN_DIORAMA_CUTAWAY.md](PLAN_DIORAMA_CUTAWAY.md). Art conventions:
> [ART_PIPELINE.md](ART_PIPELINE.md).

## Diorama cutaway ("Power-up slice") ✅ in code, needs device + art
- [x] Fixed oblique ortho camera, station/room zoom tiers, pan clamp (CP1)
- [x] Cutaway shader: clip box, back-face section fill, ink edge (CP2)
- [x] Modules on slots, per-module navigation + links, save v2 (CP3)
- [~] Art pipeline: conventions + import script done; first real art imported (capsule + wreck core, `art/station_early/`), other modules still procedural (CP4)
- [x] Power & wear as progression: power-on sequence, power budget, rust (CP5)
- [x] Zoom opens the cut, tap-to-focus, touch mapping (CP6)
- [x] Ambient life, character routines, clock lighting, placeholder audio (CP7)
- [x] Exploded-view upgrade screen (CP8)
- [x] Docking trader ships (CP9)
- [~] Perf & goldens: fps cap, golden-image tests in CI; device profiling open (CP10)
- [ ] Go/no-go on the look (CP0) and touch feel on a real phone

## Checkpoint 0 — Bootstrap ✅
- [x] Godot 4.7 project, Mobile renderer, landscape, GDScript
- [x] Autoloads: EventBus, GameClock, GameState
- [x] Needs (food, energy, morale) with decay & activity rates
- [x] Inventory (stacks, drag/drop move/merge/swap, use) + item data files
- [x] ASCII-layout StationBuilder (walls, floors, lights, furniture), runtime navmesh
- [x] Isometric ortho camera, follow, pinch/wheel zoom (replaced by DioramaCamera)
- [x] Tap-to-move & tap-to-interact, action menus (bed, kitchen, bay window)
- [x] Cel shading + outline shaders, starfield backdrop, wall cutaway (replaced by the diorama cutaway)
- [x] HUD (clock, needs bars, inventory), toasts
- [x] Debug overlay + command-line dev hooks, screenshot tool
- [x] GUT unit + integration tests, gdlint, CI (tests + Android debug APK)

## Checkpoint 1 — Playable day loop
- [ ] Verify on a real Android phone (touch feel, text size, performance)
- [ ] Needs consequences: hunger/exhaustion penalties, passing out, game over/rescue
- [~] Day/night: station lighting dims and warms at night (done); sleep only when tired
- [ ] Autosave (on pause/quit, `NOTIFICATION_APPLICATION_PAUSED`) + Continue on start
- [ ] Main menu / pause menu, settings (volume, walls mode)
- [ ] Interaction feedback: highlight tapped object, walking animation placeholder (idle stretch/breathing exist)

## Checkpoint 2 — Repair & improve
- [~] Equipment states (broken / damaged / working) and a repair action using scrap (modules: derelict → repaired → upgraded; not per object yet)
- [x] Power grid: modules produce/draw power; unpowered rooms are dark
- [~] Unlockable rooms (doors that need repair), exploring the derelict (the wreck is derelict until repaired; doors not locked)
- [ ] Crafting / recipes data (generalise `GameState.perform`)
- [ ] Storage containers (second inventory, transfer UI)

## Checkpoint 3 — Visitors & economy
- [x] Docking port, ships attach to the station
- [~] Traders: buy/sell/exchange goods & services (fixed item swaps)
- [ ] Station development axes: culture, economy, religion

## Tech debt / performance
- [x] Batch walls (one merged hull mesh per module; closed interiors hidden; ~150 draw calls in station view on desktop)
- [~] Real art pipeline: Blender → glTF (Git LFS) using the toon shader (capsule + wreck core imported with a palette texture; hab pod, solar array, trader still procedural)
- [ ] Item icons instead of color swatches
- [ ] iOS export preset (needs a Mac + Apple developer account)
- [ ] Localisation (tr() keys) before text grows
