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
- [x] Mobile HUD: every action of the focused module on HUD cards (top bar, module card, one card per object type, walk-then-act), no popup menus on 3D objects
- [x] Portrait + landscape: canvas base swaps 1280x720 / 720x1280, two-row top bar, ModuleSheet (bottom sheet PEEK/HALF/FULL in portrait, docked left in landscape), build menu as bottom sheet, exploded-view cards under the model, camera frames inside the HUD's free area, Android back closes the topmost thing
- [x] Feedback: reward pills fly to their chip, ring burst on repair/upgrade/build, success/warning toasts, button press squash, clock roll on time skips (+4 h), condition/staffing bars, next-unit progress strip + "Next unit in / Runs out in" timers
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
- [~] Traders: buy/sell/exchange goods & services (fixed swaps; selling food is the first income loop)
- [x] Station economy (docs/PLAN_STATION_ECONOMY.md): bulk resources in a station stock, module/upgrade production (wreck water → agri bay food, hydroponics tier), status bar + production popover, `produced` trigger, save v4 migration
- [ ] Economy, later: storage caps (silos), wear → efficiency, production-chain overview, agri bay Blender art, conversion modules
- [x] Crew: bunks (`B` cells of repaired habitats) cap the crew, `ModuleDef.jobs` + staffing boost production up to +50%, crew eat station food at meal times (`StationCrew`, `CrewSchedule`, save v6)
- [x] Crew NPCs walk to bunk / job / kitchen / free floor (`CrewDirector`, `CrewNPC`, `Walker` shared with the player); recruit via the `drifter` encounter, trader "Hire a hand", `recruit` outcome; module panel crew row, status-bar crew chip + popover
- [ ] Crew, later: leave when morale stays critical, traits/skills, upgrades that add jobs, crew walking on/off visitor ships, tap a crew member
- [ ] Station development axes: culture, economy, religion

## Modular station (custom layouts)
- [x] Placement data-side: `StationGrid` (orientation via own slot, footprint overlaps), save v5
- [x] Build menu Rotate + footprint preview; ghosts only where something fits
- [x] Walkable procedural connectors: `corridor` (1-1), `junction_t` (1-2), `hub_x` (1-3)
- [x] Hatch sizes S/M/L (`slot_sizes`), smaller fits larger; `adapter_ml` (M→L)
- [x] Blender module kit `art/kit/` + `tools/art.sh` (validators, renders, export) + `tools/new_module.py`
- [x] `/new-module` command + `docs/MODULE_CATALOG.md` (10 modules + connectors)
- [x] Pilot: `hub_node`, `hab_drum` (+ antenna / radiator upgrades)
- [ ] Remaining catalog modules (see docs/MODULE_CATALOG.md), connector art
- [ ] Station-view zoom for large (L) modules; deferred mechanics (heat, gravity, hangar)
- [ ] Move `station_early` onto the kit
- [ ] Loops: join two free slots that meet (needs gap-free placement)

## Content pipeline (docs/CONTENT_PIPELINE.md)
- [x] Upgrade parts on art mounts (`mount_*` + `UpgradeDef.mount`), validation tests, `--upgrade=all`
- [x] Encounters / story beats as data: triggers, conditions, outcomes, choices, schedules, saved story state
- [x] Encounter panel (dialog / radio), debug Story row, `--encounter=<id>`, `--story=off`
- [ ] Part art kit (`part_scene` glTFs) and the capsule wings on a mount
- [ ] Headless story simulation bot; encounters that spawn models
- [ ] Write the real story arc (chapters gated by milestones)

## Tech debt / performance
- [x] Batch walls (one merged hull mesh per module; closed interiors hidden; ~150 draw calls in station view on desktop)
- [~] Real art pipeline: Blender → glTF (Git LFS) using the toon shader (capsule + wreck core imported with a palette texture; hab pod, solar array, trader still procedural)
- [ ] Item icons instead of color swatches
- [ ] iOS export preset (needs a Mac + Apple developer account)
- [ ] Localisation (tr() keys) before text grows
