---
description: Add a new station object the player can use (e.g. "a water recycler that turns 2 water into 3 over 1 h")
---
Add this station object: $ARGUMENTS

Follow "New station object" in CLAUDE.md:
1. `src/interactables/<snake_name>.gd` extending `Interactable`; override `get_actions()`.
   Put rules (costs, effects, durations) in constants and call `GameState` methods
   (`perform`, `spend_time`, ...) rather than changing needs/inventory directly.
   If a new activity is needed, add it to `GameState.ACTIVITY_RATES`.
2. `src/interactables/<snake_name>.tscn`: copy the structure of `kitchen.tscn`
   (Area3D root, PickShape, Body, meshes; `Accent*` meshes glow). Placeholder boxes are fine.
3. Pick an unused layout character, map it in `StationBuilder.FURNITURE_SCENES`, update the
   legend comment, and place it in `DEFAULT_LAYOUT` next to free floor.
4. Tests: actions available/disabled correctly, effects applied (see `test_game_state.gd`);
   update the furniture count in `test_station_builder.gd`.
5. Run `/check` with `--interact=<display name>` and verify the menu in the screenshot.
6. Tick or add the item in `docs/ROADMAP.md`.
