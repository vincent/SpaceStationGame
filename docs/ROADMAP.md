# Roadmap

Status markers: `[x]` done · `[~]` in progress / partial · `[ ]` todo

## Checkpoint 0 — Bootstrap ✅
- [x] Godot 4.7 project, Mobile renderer, landscape, GDScript
- [x] Autoloads: EventBus, GameClock, GameState
- [x] Needs (food, energy, morale) with decay & activity rates
- [x] Inventory (stacks, drag/drop move/merge/swap, use) + item data files
- [x] ASCII-layout StationBuilder (walls, floors, lights, furniture), runtime navmesh
- [x] Isometric ortho camera, follow, pinch/wheel zoom
- [x] Tap-to-move & tap-to-interact, action menus (bed, kitchen, bay window)
- [x] Cel shading + outline shaders, starfield backdrop, wall cutaway
- [x] HUD (clock, needs bars, inventory), toasts
- [x] Debug overlay + command-line dev hooks, screenshot tool
- [x] GUT unit + integration tests, gdlint, CI (tests + Android debug APK)

## Checkpoint 1 — Playable day loop
- [ ] Verify on a real Android phone (touch feel, text size, performance)
- [ ] Needs consequences: hunger/exhaustion penalties, passing out, game over/rescue
- [ ] Day/night: station lighting dims at night, sleep only when tired
- [ ] Autosave (on pause/quit, `NOTIFICATION_APPLICATION_PAUSED`) + Continue on start
- [ ] Main menu / pause menu, settings (volume, walls mode)
- [ ] Interaction feedback: highlight tapped object, walking animation placeholder

## Checkpoint 2 — Repair & improve
- [ ] Equipment states (broken / damaged / working) and a repair action using scrap
- [ ] Power grid: capsule power cells power rooms; unpowered rooms are dark
- [ ] Unlockable rooms (doors that need repair), exploring the derelict
- [ ] Crafting / recipes data (generalise `GameState.perform`)
- [ ] Storage containers (second inventory, transfer UI)

## Checkpoint 3 — Visitors & economy
- [ ] Docking port, ships attach to the station
- [ ] Traders: buy/sell/exchange goods & services
- [ ] Station development axes: culture, economy, religion

## Tech debt / performance
- [ ] Batch walls into MultiMesh (≈400 draw calls today; target < 150 on mobile)
- [ ] Real art pipeline: Blender → glTF (Git LFS) using the toon shader
- [ ] Item icons instead of color swatches
- [ ] iOS export preset (needs a Mac + Apple developer account)
- [ ] Localisation (tr() keys) before text grows
