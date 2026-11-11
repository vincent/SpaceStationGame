# station_early: early-game diorama (capsule docked to the wreck)

Rebuild everything (scene, .blend, renders, glTF, palette, stats) from the repo root:

    blender -b --factory-startup --python art/station_early/scripts/make_pass2.py
    #   -- --no-render | -- --no-export | -- --only=render_roomA.png

`scripts/build_station.py` is the single source of the scene; `station_early.blend`
is its output (edit the script, not the .blend, or the next run overwrites it).
The export step also copies `capsule.glb`, `wreck_core.glb` and `station_palette.png`
into `assets/models/station_early/`, where the game imports them (see
docs/ART_PIPELINE.md, "Workflow"). After a re-export: `tools/test.sh`, a screenshot,
and `/update-goldens` if the change is intended.

## What was built

| Module | Triangles (exported) | Materials | Objects |
|---|---|---|---|
| capsule | 4,126 | M_hull, M_interior, M_emissive | ~20 |
| wreck_core | 12,672 | M_hull, M_interior, M_emissive | ~140 (shared kit meshes) |

The budget is ≤ 15k triangles and ≤ 3 materials per module. `export/stats.json`
lists the heaviest objects. In game, every mesh is drawn with the palette material,
so the Blender materials only matter for the preview renders.

- **capsule**: a 9.8 × 5 m pod (r 2.5). Its two-tone hull has two holes cut through
  its 0.2 m wall: the docking doorway in the nose and the open side hatch.
  Parts: nose collar (docking tube), RCS ring, canopy, hatch door, `part_antenna`
  and `part_thruster` (the engine bell). Those two are the `capsule_antenna` /
  `capsule_thruster` upgrades, so they stay hidden in game until bought.
  Cabin props are on the walls only: screens, light strip, rations shelf,
  first-aid kit.
- **wreck_core**: one watertight `hull` built from a main block, an upper box
  (room C), a cylinder, the Room A wing and solid trim, including the portholes
  of rooms B and C. Room A has doorway holes for slots A, B, C and V. Parts:
  truss, solar panel and a broken panel, two antennas, `part_dish` (the
  `wreck_dish` upgrade), torn plate, two decorative dock rings, work lamp.
- **Room A**: props hug the walls: crate table, crates, toolbox, debris, pipes and a
  cable tray, hanging cables, notes, a vent with a rust streak, floor plates, and the
  neon-yellow extension cable from doorway A to the work lamp.
- **Greeble kit** (`GREEBLE_KIT`, hidden): about 25 items (pipes, vents, panels, tanks,
  crates, cables, hazard strips, rust streaks, paint chips, bolts, porthole rims,
  notes, floor plates, stencils). About 120 linked duplicates are placed.
- **Background**: starfield and crescent planet (parented to the camera), plus
  floating debris. None of it is exported.

## How it fits the game (why the proportions changed after pass 2)

The ASCII layouts are the gameplay truth, so the art follows them:

| Module | `interior_ascii` | Notes |
|---|---|---|
| capsule | `#####` / `aP.B#` / `#..K#` / `#####` | 3 × 2 cells. The bed and kitchen cut the navmesh, so the room needs 2 rows. |
| wreck_core | `######` / `vC..S#` / `b....a` / `##W#c#` | Room A only: 4 × 2 cells. Rooms B and C are closed art. |

- **Grid placement.** One cell is 2 m, the game floor (y = 0) is Blender z 0.3, ASCII
  columns run along +X and rows along −Y. The module origin is the layout centre on
  the floor: wreck (7.2, −3.7, 0.3), capsule (16.8, −5.7, 0.3).
- **Slots.** These are empties 0.15 m outside each doorway, at floor level. Their
  local −Y in Blender becomes +Z in Godot, pointing out of the module:
  - wreck: A (+X, capsule), B and V (−X), C (front)
  - capsule: A (nose)

  The decorative top and side dock rings are not slots: game slots are horizontal
  doorways only.
- **Cut region.** `CUT_BOX` is exported as `cut_box`, so the game opens only Room A
  instead of slicing the whole wreck.
- **Colours.** Flat colours become a 128 px palette texture with 16 colours, and each
  face's UV points at its swatch. `Masks` is exported as COLOR_0 (R = wear,
  G = emissive, B = trim).
- **Walls.** Art walls are 0.3 m thick. The game hides the floor tiles of doorway
  cells and sets the bay window into the wall (`StationBuilder.hide_slot_floor` /
  `wall_furniture_inset`).

## Simplifications / known limits

- The **wear mask R** is per vertex on a coarse hull, and meant to be blended with
  the shader's grunge noise. Visible rust, chipped paint and patches are kit geometry.
- The **hull is made of overlapping closed solids** joined into one mesh. Each is
  watertight; the overlaps read as internal partitions in a section.
- **Toon ramp** (Blender preview): it steps the light's intensity and multiplies by
  its hue. Per-channel steps clipped the amber lamp to white.
- **Outlines** are 0.06 m inverted-hull shells, preview only (the game has its own
  outline pass). The work lamp light has no shadows, with an 11 m cut-off.
- **Modules on slots B/C/V** (e.g. a hab pod) can overlap the wreck's main block
  visually: the procedural modules don't know about the art's massing.
- **No textures besides the palette.** Stencils are low-resolution text meshes.
