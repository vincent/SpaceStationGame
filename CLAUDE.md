# CLAUDE.md — Space Station Tycoon

Mobile game (Android first, iOS later) about a castaway restoring an abandoned
space station. Godot **4.7.2** (pinned in `.godot-version`), **GDScript**, 3D
with an orthographic isometric camera and cel shading. Design doc lives in the
claude.ai project ("SpaceStationTycoon.md"); `docs/ROADMAP.md` tracks progress.

## Commands (run from repo root)

| What | Command |
|---|---|
| Run all tests (also imports + fails on script errors) | `tools/test.sh` |
| One test file / tests by name | `tools/test.sh -gselect=test_inventory` · `tools/test.sh -gunit_test_name=merge` |
| Lint | `tools/lint.sh` (needs `pip install "gdtoolkit==4.*"`) |
| Parse/import check only | `tools/import.sh` |
| Screenshot (works headless via xvfb) | `tools/screenshot.sh build/shot.png [--interact=bed] [--inventory] [--debug-panel] [--walls=down] [--time=22] [--delay=5]` |
| Run game / open editor | `tools/run.sh` · `tools/editor.sh` |
| Android debug APK | `tools/export_android.sh` (needs ANDROID_HOME + JDK 17) → `tools/install_android.sh` |

`tools/godot.sh` downloads the pinned Godot into `.godot-bin/` on first use;
set `GODOT=/path/to/godot` to use another binary.

**Before finishing any change:** `tools/lint.sh && tools/test.sh`. For visual
changes also take a screenshot and look at it.

## Architecture

```
src/autoload/   EventBus (signals only), GameClock (time), GameState (needs, inventory, actions, save/load)
src/core/       Pure logic & helpers: Needs, Inventory, ItemDB, ItemData, Palette, Layers, ToonMaterials
src/world/      main.tscn/main.gd (tap → raycast → player order), StationBuilder (ASCII layout → geometry), CutawayController
src/player/     Player (CharacterBody3D + NavigationAgent3D)
src/camera/     IsoCamera (ortho, follow, pinch/wheel zoom), Backdrop (starfield quad)
src/interactables/  Interactable base + Bed, Kitchen, BayWindow (+ .tscn each), InteractionAction
src/ui/         HUD, InteractionMenu, InventoryPanel/Slot, DebugOverlay, UITheme — all built in code
data/items/     One ItemData .tres per item
assets/shaders/ toon (cel shading), outline (inverted hull), starfield
tests/unit, tests/integration   GUT tests (integration boots main.tscn)
```

Rules of thumb:
- **Game rules live in `GameState`** (or pure classes in `src/core`), never in UI
  or scene scripts. Scenes call `GameState.sleep()`, `GameState.perform(cost, minutes, effects)`, etc.
- **Time:** everything that changes over time listens to `GameClock.time_advanced(minutes)`.
  Skipping time = `GameState.spend_time(minutes, activity)`; activities change need rates
  via `GameState.ACTIVITY_RATES`.
- **Cross-system events** go through `EventBus` signals. Don't add state there.
- **Colors** come from `Palette`; materials from `ToonMaterials.get_material()`.
  Physics layers from `Layers` (world=1, player=2, interactable=4, walls=8).
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

**Station layout:** edit `StationBuilder.DEFAULT_LAYOUT` (or the `layout` property
in the inspector, then press "Rebuild"). Legend is in the script header.

**Debug tools:** in debug builds press F3 or tap "DBG" (time speed/skip, needs,
give items, walls mode, save/load). New cheats: `_add_row()` in `debug_overlay.gd`.
Command-line hooks are parsed in `DebugOverlay._run_cli_commands()`.

## Gotchas

- Navigation is baked at runtime after the station is generated, and the map syncs
  asynchronously: `Player.navigation_ready` gates movement; tests must
  `await wait_until(func(): return player.navigation_ready, 5.0)`.
- `NavigationAgent3D` path points sit ~0.25 m above the floor; keep
  `path_desired_distance` > that or the player won't move.
- Sky shaders / Canvas background misbehave with the ortho camera across renderers;
  the starfield is a quad (`Backdrop`) parented to the camera.
- Screenshots use the Compatibility renderer (no GPU in CI/containers); the game
  itself uses the Mobile renderer, so lighting can differ slightly.
- `build/` has a `.gdignore`; never put game assets there.
- Typed-dictionary `.tres` syntax: `Dictionary[StringName, float]({&"food": 15.0})`.
- Input: mouse events are emulated from touch. Tap = move/interact, drag-and-drop
  in inventory, double-tap/right-click = use. Pinch/wheel = zoom.
