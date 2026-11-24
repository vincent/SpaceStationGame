# CLAUDE.md — Space Station Tycoon

Mobile game (Android first, iOS later) about a castaway restoring an abandoned
space station. Godot **4.7.2** (pinned in `.godot-version`), **GDScript**, 3D
with cel shading. The station is a **diorama**: one object seen from a fixed
oblique orthographic camera, its hull cut open to reveal the rooms
(`docs/PLAN_DIORAMA_CUTAWAY.md`). Design doc lives in the claude.ai project
("SpaceStationTycoon.md"); `docs/ROADMAP.md` tracks progress. Upgrades and
story encounters are data-driven: `docs/CONTENT_PIPELINE.md`.

## Commands (run from repo root)

| What | Command |
|---|---|
| Run all tests (also imports + fails on script errors) | `tools/test.sh` |
| One test file / tests by name | `tools/test.sh -gselect=test_inventory` · `tools/test.sh -gunit_test_name=merge` |
| Lint | `tools/lint.sh` (needs `pip install "gdtoolkit==4.*"`) |
| Parse/import check only | `tools/import.sh` |
| Screenshot (works headless via xvfb) | `tools/screenshot.sh build/shot.png [--resolution=720x1280] [--view=station\|room] [--focus=wreck_core] [--power=all] [--upgrade=all] [--crew=2] [--encounter=intro] [--story=off] [--stock=food:20] [--layout=demo] [--popover=food] [--build-menu] [--explode] [--time=22] [--debug-panel] [--delay=5]` (all hooks: `DebugOverlay._run_cli_commands()`) |
| Perf stress test (huge station + frame-time report) | `tools/stress.sh [modules=80] [seconds=10] [hooks...]` (`--layout=stress --modules=N --perf=S`; layout = `StressLayout`) |
| Golden images (compare / re-record) | `tools/golden.sh` · `tools/golden.sh --update [scene]` (or `/update-goldens`) |
| Run game / open editor | `tools/run.sh` · `tools/editor.sh` |
| Build a kit module (Blender ≥ 4.2) | `tools/art.sh <id> [--render]` → `tools/new_module.py <id>` (or `/new-module`) |
| Android debug APK | `tools/export_android.sh` (needs ANDROID_HOME + JDK 17) → `tools/install_android.sh` |

`tools/godot.sh` downloads the pinned Godot into `.godot-bin/` on first use;
set `GODOT=/path/to/godot` to use another binary.

**Before finishing any change:** `tools/lint.sh && tools/test.sh`. For visual
changes also take a screenshot, look at it, and run `tools/golden.sh`.

## Architecture

```
src/autoload/   EventBus (signals only), GameClock (time), GameState (needs, inventory, stock + wallet, station, story, actions, save/load)
src/core/       Pure logic & helpers: Needs, Inventory, ItemDB/ItemData, StationStock, Production, StationState, StationCrew/CrewMember/CrewSchedule,
                ModuleDB/ModuleDef/UpgradeDef,
                EncounterDef/EncounterDB, StoryState, StoryContext, StoryOutcome, Storyteller,
                DayCycle, Palette, Layers, ToonMaterials, StationGrid (placement/overlaps)
src/world/      main.tscn/main.gd (taps → focus/build/walk/interact), StationBuilder (module interior from ASCII)
src/station/    Station (scene mirror of StationState), Module (hull+interior+lights+parts+slots), Slot, ModulePart,
                HullMesher/MeshKit (procedural watertight hulls), ExplodedView, VisitorDirector, modules/*.tscn
src/rendering/  CutawayController (cut box shader globals), ClockLighting
src/camera/     DioramaCamera (fixed oblique ortho rig, zoom tiers, pan), Backdrop (starfield quad + nebula baked once in a SubViewport)
src/player/     Walker (navmesh walking base), Player (extends Walker), PlayerRoutine (idle auto-routines)
src/crew/       CrewDirector (spawns CrewNPCs from StationCrew, claims spots, hides them in closed modules), CrewNPC
src/interactables/  Interactable base + Bed, Kitchen, BayWindow, SalvagePile, Console, Trader, Planter (+ .tscn each)
src/ambient/    AmbientKit (state-driven props), ExteriorLife (traffic, debris)
src/audio/      SfxSynth (placeholder sounds), AudioDirector
src/ui/         HUD (TopBar = clock + StatusBar + needs + debug button; ModuleSheet = ModulePanel + ObjectPanel (one card per
                object type), bottom sheet in portrait / docked left in landscape; dock; FeedbackLayer = reward pills, ring bursts),
                ProductionPopover, BuildMenu, UpgradeOverlay, EncounterPanel, InventoryPanel/Slot, DebugOverlay,
                UITheme (components, press squash, pulse/flash, bars; icons: assets/ui/icons/*.svg via UITheme.icon();
                fonts: assets/fonts Nunito Sans + Exo 2 via UITheme.font(); costs = `cost_chips`/`cta_button`, one yellow
                primary per surface)
src/tools/      Blender import post-processing (module_import.gd + ModuleImportRules)
data/items/, data/modules/, data/upgrades/, data/encounters/   One .tres per item / module type / upgrade / story beat
assets/shaders/ toon (furniture/characters), toon_cut + cutaway.gdshaderinc (structure), outline, ghost, light_card,
                ambient_fx, starfield + nebula_bake (shared noise.gdshaderinc)
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
- **Costs and rewards go through the wallet:** `GameState.count / has_all / give / pay`.
  Bulk items (`ItemData.bulk`: scrap, water, food) live in `GameState.stock` (StationStock),
  the rest in `inventory`; never call `inventory.add/remove` for costs.
- Saves are JSON (`user://savegame.json`) via each system's `to_dict()/from_dict()`
  (story too: `StoryState`; stock: `StationStock`). v≤3 saves migrate bulk items to the stock.
  Bump `GameState.SAVE_VERSION` when the format changes.

## How-tos

**New station object:** create `src/interactables/<name>.gd` extending `Interactable`
and override `get_actions()` (`InteractionAction` = `label` + `detail` line, `hint` when disabled; they
show as buttons on the object's HUD card, and the castaway walks there before acting); make a `.tscn` (set
`icon` = a file name in `assets/ui/icons/`) (Area3D root on layer 3 with a
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
letter → accepted ids/kinds, `layout` = copy of the scene's `interior_ascii`; art modules
also `massing` rects + `slot_frames`). `test_module_data.gd` checks scene and data agree.
Placement (orientation = which own slot attaches, overlap check) is `StationGrid`, data only.

**New module (kit art, preferred):** `/new-module <id>`: spec `art/modules/<id>.py` built by
`art/kit/` (`tools/art.sh`), Godot side by `tools/new_module.py`. Briefs: `docs/MODULE_CATALOG.md`.
Slots have sizes (`slot_sizes`, S/M/L = 1/2/3, default `size_class`): a module fits a hatch of
its size or larger.

**New / updated module art (any Blender art, kit or hand-made):** follow the checklist and troubleshooting table in
`docs/ART_PIPELINE.md` (layout fit → export → import script → inherited scene → tests,
screenshots, `/update-goldens`). Examples: `art/modules/wreck_core.py` (weathered), `capsule.py` (own livery).

**New upgrade:** add `data/upgrades/<id>.tres` (`module_id`, `part_node`, cost, requires,
effects from `UpgradeDef.EFFECTS`). The part is either authored (`Parts/<part_node>` in the
scene) or, preferred, spawned on a `mount_<name>` marker of the art (`mount`, `part_kind`
placeholder or `part_scene`). Checklist: `docs/CONTENT_PIPELINE.md`; `test_module_data.gd` validates it.

**New resource / producer:** bulk item `data/items/<id>.tres` (`bulk = true`, `color` for the
status-bar chip); `production` (per game hour, + output / − input) on a module `.tres` or an
upgrade (adds to the module's). Rules in `Production`; checklist in `docs/CONTENT_PIPELINE.md` §4.

**Crew:** data in `GameState.station.crew` (`StationCrew`: bunks = `B` cells of repaired non-capsule
modules, `ModuleDef.jobs`, `staff/unstaff/add`). Needs and meals tick data-side in `CrewSchedule.tick`
(from `GameState._on_time_advanced`); `CrewNPC`s only mirror `member.activity`. Staffing multiplies
production (`StationCrew.staffing`, up to +50%). New job module: set `jobs` on its `.tres` (needs `production`).

**New encounter (story beat):** add `data/encounters/<id>.tres` (`trigger`, `condition` = Godot
expression over `StoryContext`, `lines`, `outcomes`/`choices` = `StoryOutcome` verbs).
Reference + checklist: `docs/CONTENT_PIPELINE.md`; `test_encounter_data.gd` validates it.
Rules stay in `GameState` (`story_event`, `apply_outcome`); new trigger = `GameState.story_event(&"x", subject)`.

**Debug tools:** in debug builds press F3 or tap the bug button of the top bar (time speed/skip, needs,
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
  the starfield is a quad (`Backdrop`) parented to the camera. Its nebula is baked once (tileable,
  fixed seed so goldens stay stable); backdrop colors come from `Palette.SPACE_*` / `NEBULA_*`.
- **Portrait + landscape:** `HUD._fit_content_scale()` swaps the canvas base (1280x720 / 720x1280) so text keeps
  its size; layout code reads `UITheme.is_portrait()` / `HUD.portrait` and re-lays out in `HUD.apply_layout()`.
  The camera frames inside `EventBus.hud_insets_changed` (portrait: between top bar and sheet). Don't anchor new HUD
  controls straight under `layer_root` before it has a size (they drift to their min size): put them in a container.
  Items given with `GameState.give(items, source)` fly from `source` to their chip (`EventBus.reward`); use
  `EventBus.notice.emit(msg, &"success")` for success toasts.
- Screenshots use the Compatibility renderer (no GPU in CI/containers); the game
  itself uses the Mobile renderer, so lighting can differ slightly.
- `build/` has a `.gdignore`; never put game assets there.
- A new game opens the intro encounter; `--freeze` (goldens) and `--story=off` turn
  encounters off. Tests that need a quiet game call `GameState.set_story_enabled(false)`.
- Typed-dictionary `.tres` syntax: `Dictionary[StringName, float]({&"food": 15.0})`.
- Input: mouse events are emulated from touch. Station view: tap module = focus, tap ghost
  slot = build menu, drag = pan. Room view: tap floor = walk, tap object = walk to it +
  flash its HUD card, tap another module = focus it. All module/object actions are HUD buttons.
  Module card: both views; object cards: room view only; build ghosts: station view only
  (`EventBus.room_view_changed`, threshold `main.ROOM_VIEW_T`).
  No pinch/wheel zoom: the "Station"/"Room" button switches views. Inventory: drag-and-drop,
  double-tap/right-click = use.
