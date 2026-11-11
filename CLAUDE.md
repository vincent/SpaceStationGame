# CLAUDE.md — Space Station Tycoon

Mobile game (Android first, iOS later) about a castaway restoring an abandoned
space station. Godot **4.7.2** (pinned in `.godot-version`), **GDScript**, 3D
with cel shading. The station is a **diorama**: one object seen from a fixed
oblique orthographic camera, its hull cut open to reveal the rooms
(`docs/PLAN_DIORAMA_CUTAWAY.md`). Design doc lives in the claude.ai project
("SpaceStationTycoon.md"); `docs/ROADMAP.md` tracks progress.

## Commands (run from repo root)

| What | Command |
|---|---|
| Run all tests (also imports + fails on script errors) | `tools/test.sh` |
| One test file / tests by name | `tools/test.sh -gselect=test_inventory` · `tools/test.sh -gunit_test_name=merge` |
| Lint | `tools/lint.sh` (needs `pip install "gdtoolkit==4.*"`) |
| Parse/import check only | `tools/import.sh` |
| Screenshot (works headless via xvfb) | `tools/screenshot.sh build/shot.png [--view=station\|room] [--focus=wreck_core] [--power=all] [--explode] [--time=22] [--debug-panel] [--delay=5]` (all hooks: `DebugOverlay._run_cli_commands()`) |
| Golden images (compare / re-record) | `tools/golden.sh` · `tools/golden.sh --update [scene]` (or `/update-goldens`) |
| Run game / open editor | `tools/run.sh` · `tools/editor.sh` |
| Android debug APK | `tools/export_android.sh` (needs ANDROID_HOME + JDK 17) → `tools/install_android.sh` |

`tools/godot.sh` downloads the pinned Godot into `.godot-bin/` on first use;
set `GODOT=/path/to/godot` to use another binary.

**Before finishing any change:** `tools/lint.sh && tools/test.sh`. For visual
changes also take a screenshot, look at it, and run `tools/golden.sh`.

## Architecture

```
src/autoload/   EventBus (signals only), GameClock (time), GameState (needs, inventory, station, actions, save/load)
src/core/       Pure logic & helpers: Needs, Inventory, ItemDB/ItemData, StationState, ModuleDB/ModuleDef/UpgradeDef,
                DayCycle, Palette, Layers, ToonMaterials
src/world/      main.tscn/main.gd (taps → focus/build/walk/interact), StationBuilder (module interior from ASCII)
src/station/    Station (scene mirror of StationState), Module (hull+interior+lights+parts+slots), Slot, ModulePart,
                HullMesher/MeshKit (procedural watertight hulls), ExplodedView, VisitorDirector, modules/*.tscn
src/rendering/  CutawayController (cut box shader globals), ClockLighting
src/camera/     DioramaCamera (fixed oblique ortho rig, zoom tiers, pan), Backdrop (starfield quad)
src/player/     Player (CharacterBody3D + NavigationAgent3D), PlayerRoutine (idle auto-routines)
src/interactables/  Interactable base + Bed, Kitchen, BayWindow, SalvagePile, Console, Trader (+ .tscn each)
src/ambient/    AmbientKit (state-driven props), ExteriorLife (traffic, debris)
src/audio/      SfxSynth (placeholder sounds), AudioDirector
src/ui/         HUD, ModulePanel, BuildMenu, UpgradeOverlay, InteractionMenu, InventoryPanel/Slot, DebugOverlay, UITheme
src/tools/      Blender import post-processing (module_import.gd + ModuleImportRules)
data/items/, data/modules/, data/upgrades/   One .tres per item / module type / upgrade
assets/shaders/ toon (furniture/characters), toon_cut + cutaway.gdshaderinc (structure), outline, ghost, light_card,
                ambient_fx, starfield
tests/unit, tests/integration, tests/goldens   GUT tests (integration boots main.tscn) + golden images
```

Rules of thumb:
- **Game rules live in `GameState`** (or pure classes in `src/core`), never in UI
  or scene scripts. Scenes call `GameState.sleep()`, `GameState.perform(cost, minutes, effects)`, etc.
- **Time:** everything that changes over time listens to `GameClock.time_advanced(minutes)`.
  Skipping time = `GameState.spend_time(minutes, activity)`; activities change need rates
  via `GameState.ACTIVITY_RATES`.
- **Cross-system events** go through `EventBus` signals. Don't add state there.
- **Colors** come from `Palette`; materials from `ToonMaterials.get_material()` (never cut:
  furniture, characters, props) or `get_cut_material()` (station structure: hull, parts,
  structural pieces like windows). Physics layers from `Layers` (world=1, player=2,
  interactable=4, walls=8, module_pick=16).
- **The station is data first:** `GameState.station` (StationState) owns modules, slots,
  state, wear, power and upgrades; `Station` only mirrors it. Change it through
  `GameState.build_module / repair_module / toggle_power / buy_upgrade`.
- Pure logic classes (`extends RefCounted`) get unit tests; scene behaviour gets an
  integration test in `tests/integration/`.
- Saves are JSON (`user://savegame.json`) via each system's `to_dict()/from_dict()`.
  Bump `GameState.SAVE_VERSION` when the format changes.

## How-tos

**New station object:** create `src/interactables/<name>.gd` extending `Interactable`
and override `get_actions()`; make a `.tscn` (Area3D root on layer 3 with a
`PickShape`, optional `Body` StaticBody3D, meshes; meshes named `Accent*` get
the glowing accent color); map a layout character to it in
`StationBuilder.FURNITURE_SCENES`; put the character in the layout; add a test.

**New item:** add `data/items/<id>.tres` (copy an existing one, `script_class="ItemData"`).
`test_item_db.gd` validates every item automatically.

**New need:** add a constant + default decay in `Needs`, a color in
`HUD.NEED_COLORS`, a message in `HUD.CRITICAL_MESSAGES`.

**Module layout:** edit `interior_ascii` on the module scene's root
(`src/station/modules/*.tscn`) and press "Rebuild" in the inspector. Legend is in
`StationBuilder`'s header; lowercase letters are slot doorways on the hull boundary.

**New module type:** copy a scene in `src/station/modules/` (root = Module, `Parts/part_*`
= ModulePart), add `data/modules/<id>.tres` (scene path, costs, power, `slots` = slot
letter → accepted ids/kinds). `test_module_data.gd` checks scene and data agree.

**New / updated module art (Blender):** follow the checklist and troubleshooting table in
`docs/ART_PIPELINE.md` (layout fit → export → import script → inherited scene → tests,
screenshots, `/update-goldens`). Example set: `art/station_early/` (`notes.md`).

**New upgrade:** add `data/upgrades/<id>.tres` (`module_id`, `part_node` = a `part_*` node
of that module, cost, requires, effects: power_output, power_draw, food/energy/morale_decay).

**Debug tools:** in debug builds press F3 or tap "DBG" (time speed/skip, needs,
give items, cutaway on/off, magenta back faces, repair/power/wear of the focused module,
summon a visitor, camera pitch/yaw/size sliders, save/load). New cheats: `_add_row()` in
`debug_overlay.gd`. Command-line hooks are parsed in `DebugOverlay._run_cli_commands()`.

## Gotchas

- Navigation is baked per module at runtime and modules are joined by NavigationLink3D;
  the map syncs asynchronously: `Player.navigation_ready` gates movement; tests must
  `await wait_until(func(): return player.navigation_ready, 5.0)`. After moving a module
  call `Module.sync_navigation_transform()` (the server copy can go stale otherwise).
- Hull meshes must be **watertight**: the cutaway paints visible back faces as the section
  fill. Debug panel "Back faces" paints them magenta to find holes.
- In headless runs `RenderingServer.global_shader_parameter_get()` returns null; tests read
  `CutawayController.cut_on` / `get_box()` instead.
- Godot doesn't allow assigning varyings in shader helper functions (use `v = cut_world(...)`).
- Golden images render with Mesa's software GL (`LIBGL_ALWAYS_SOFTWARE=1`) so they match CI;
  only update them on purpose (`/update-goldens`).
- `NavigationAgent3D` path points sit ~0.25 m above the floor; keep
  `path_desired_distance` > that or the player won't move.
- Sky shaders / Canvas background misbehave with the ortho camera across renderers;
  the starfield is a quad (`Backdrop`) parented to the camera.
- Screenshots use the Compatibility renderer (no GPU in CI/containers); the game
  itself uses the Mobile renderer, so lighting can differ slightly.
- `build/` has a `.gdignore`; never put game assets there.
- Typed-dictionary `.tres` syntax: `Dictionary[StringName, float]({&"food": 15.0})`.
- Input: mouse events are emulated from touch. Station view: tap module = focus, tap ghost
  slot = build menu, drag = pan. Room view: tap floor = walk, tap object = actions, tap
  another module = focus it. Pinch/wheel = zoom between the tiers. Inventory: drag-and-drop,
  double-tap/right-click = use.
