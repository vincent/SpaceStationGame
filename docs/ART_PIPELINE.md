# Art pipeline — Blender → glTF → Godot

How module art is made so it works with the diorama cutaway
([PLAN_DIORAMA_CUTAWAY.md](PLAN_DIORAMA_CUTAWAY.md)). Procedural modules get
their hull from `HullMesher` (built from the interior ASCII) and placeholder
parts from `ModulePart`. Imported art replaces those piece by piece, using the
same conventions. **First imported modules:** `capsule` and `wreck_core`, built
by script in `art/station_early/` (see its `notes.md`).

## Workflow (how `capsule` / `wreck_core` are set up)

1. Blender → `.glb` + palette PNG in `assets/models/<set>/` (the art set's
   script does it: `blender -b --factory-startup --python art/station_early/scripts/make_pass2.py`).
2. In the `.glb.import` file (or Import dock): **Import Script** =
   `res://src/tools/module_import.gd`; palette PNG imported **lossless**.
3. The module scene (`src/station/modules/<id>.tscn`) is an **inherited scene
   of the `.glb`**: root script `module.gd`, `module_id`, `interior_ascii`,
   colours and **`art_palette`** set on the root. Upgrade parts the art doesn't
   model hang on `mount_*` empties exported with the art: the upgrade's
   `.tres` names the mount and a placeholder kind (or a part scene), so the
   module scene needs no hand-placed parts (docs/CONTENT_PIPELINE.md).
4. `tools/test.sh` (`test_module_data` checks slots and upgrade parts), a
   screenshot, then `/update-goldens` on purpose.

## Checklist: add or update a module's art

1. **Fit the layout first.** Write (or read) the module's `interior_ascii` and
   check every room fits: whole 2 m cells, ≥ 2.6 m headroom, 2-cell-wide
   corridors wherever furniture stands, one floor-level doorway per slot
   letter. Change the art (or the layout, plus its tests) before modelling detail.
2. **Place things with the grid formula.** For a layout of `cols × rows` cells,
   cell `(c, r)` is centred at Godot `x = (c − (cols−1)/2) · 2`,
   `z = (r − (rows−1)/2) · 2`, floor `y = 0`. In Blender (Z up): `X = x`,
   `Y = −z`, `Z = y`, relative to the module origin. Wall cells (`#`) are
   2 m in the grid but the art wall is ~0.3 m on the room-side boundary.
3. **Name and mark** per the table below: one `hull`, `slot_X` empties 0.15 m
   outside each doorway (+Z out, at floor level), `light_*` at y ≈ 2.1,
   `part_*` names matching `UpgradeDef.part_node`, `prop_*` clear of furniture
   cells and doorways, optional `cut_box`.
4. **Export** with the module origin at 0 and a flat top level (no root empty:
   Godot puts glTF roots under the imported scene root, and `Module` looks for
   direct children). Copy the `.glb` and palette into `assets/models/<set>/`.
5. **Import:** Import Script = `module_import.gd`, palette lossless, then
   `tools/import.sh` (it must print `Module import: … N nodes converted`).
   After changing `.import` params, delete the matching
   `.godot/imported/<file>-*` files to force a reimport.
6. **Scene:** inherited from the `.glb` (Workflow step 3). Remove procedural
   placeholder parts that the art now provides (same `part_*` name).
7. **Verify:** `tools/lint.sh && tools/test.sh`, screenshots
   (`--view=station`, `--focus=<id>`, `--power=<id> --focus=<id>`), debug panel
   → Back faces (no magenta without a cut), then `/update-goldens` on purpose.

### Troubleshooting

| Symptom | Likely cause |
|---|---|
| A part (or all parts) renders white / unshaded | Mesh kept its glTF material: it must sit under `Parts/` as a `ModulePart` (import script ran?) or under the module root, not deeper. |
| Parts all at the module origin after import | Import ran outside the tree with global transforms; `ModuleImportRules` must reparent with `keep_global_transform = false`. |
| `hull`, slots or lights ignored | Exported under a root empty: they are not direct children of the scene root. |
| "hulls don't overlap" test fails | Hull AABBs overlap (AABB test, not geometry): trim the hull or move the neighbour's art so the boxes clear by > 0.02 m. |
| No navigation path into a room | Furniture body blocks a 1-cell corridor, or a `-col` wall closes a doorway. |
| Floor tiles stick out of the hull | Doorway cells: only hidden when the module has an authored `hull` (`Module.has_art()` sets `StationBuilder.hide_slot_floor`). |
| Bay window floats outside the wall | Wall furniture sits in a 2 m wall cell; `wall_furniture_inset` (set for art modules) pulls it into the thin wall. |
| Whole module gets sliced when focused | Add a `cut_box` around the room(s) that should open. |
| Colours wrong / blurred | Palette not imported lossless, or UVs not at swatch centres. |
| Lamp glows cyan | Material isn't the art material (`emission_from_texture` off). |

## Units and orientation

- 1 unit = 1 m, +Y up. glTF export with "+Y up" ticked.
- One interior cell is 2 × 2 m (`StationBuilder.CELL`). Walls are 2.6 m high
  (`WALL_HEIGHT`); the floor top is at y = 0 and the keel goes down to −0.6.
- Module origin: the centre of its interior layout, on the floor. (The plan
  suggested the main attach slot; slot markers carry the attachment frame
  instead, so the origin doesn't matter to `Station.attach()`.)
- **The ASCII layout is the gameplay truth.** Rooms must enclose whole 2 m
  cells with ≥ 2.6 m headroom (the player is 1.75 m tall); art walls are thin
  (~0.3 m) and sit on the cell boundary. Furniture has collision that cuts the
  navmesh, so corridors need to be 2 cells wide wherever furniture stands.
- Doorways: every slot letter needs a hole in the art hull (~1.6 × 2.4 m) at
  floor level. Slots are horizontal only (a marker's +Z must lie in the XZ
  plane): no roof docking.

## Module kit (new modules)

New modules are built with the **module kit**, not by hand: `art/kit/` (Python, Blender
>= 4.2) + one spec per module, `art/modules/<id>.py`. Procedure: `/new-module <id>`;
briefs: [MODULE_CATALOG.md](MODULE_CATALOG.md).

    tools/art.sh <id> [--render] [--no-export]   # build, validate, export, preview
    tools/new_module.py <id> [--name=..]         # create / sync the Godot side

- `art/kit/core.py`: palette (`PAL`, append-only), mesh builder `MB`, capsule-style
  `rounded_hull` / `rounded_band`, greeble kit (`gk_*`). Copied from the early diorama's
  `build_station.py`, which keeps its own copy for now.
- `art/kit/module.py`: `Module` = one module. The origin is the layout centre on the
  floor (Blender z 0). `piece()` closed solids (merged into one `hull`), `doorway()` (hole
  + size-coloured collar + `slot_X` from the layout letter), `light`, `mount`, `part`,
  `prop`, `greeble`, `pipe`, `cut_box`.
- **Checks** (any failure = non-zero exit): watertight hull, triangle budget, palette
  colours only, every layout letter has a doorway, slot yaw a multiple of 90° and
  outside the footprint, the nav door point (1.15 m inside) on a walkable cell, and
  every walkable cell inside the room (ray parity at its corners: no floor tile or
  bed sticking through a curved wall).
- **Output**: `assets/models/modules/<id>.glb` + the shared `kit_palette.png` (fixed
  swatch order), sidecar `art/modules/export/<id>.json` (layout, slot frames, sizes,
  massing), previews `art/modules/renders/<id>_{closed,cut,top}.png` (not committed),
  `.blend` in `art/modules/build/` (not committed: the spec is the source).
- `new_module.py` creates the `.tres` (placeholder gameplay values), the inherited
  `.tscn` and the `.import` files once; afterwards it only syncs `layout`, `slots`
  (new letters), `slot_sizes`, `slot_frames`, `massing` and `interior_ascii`.

## Station placement (data side)

Modules are placed scene-free by `StationGrid` (`src/core/station_grid.gd`), so the
`.tres` must describe the art's plan:

- `layout`: copy of the scene's `interior_ascii`. Procedural modules get their
  footprint (one rect per non-space cell, HullMesher's thin walls) and slot frames
  from it.
- `massing` (art only): `Array[Rect2]` in local metres (x, z) covering the hull in
  plan. Leave out what floats above module roofs (the wreck's tank and pod).
- `slot_frames` (art only, when the markers differ from the layout):
  slot → `Vector3(x, z, yaw°)`, i.e. each `slot_X` marker's position and facing.

`test_module_data` fails if the frames don't match the scene's slots or a slot lies
inside the footprint. A child attaches by any of its slots (the build menu's
Rotate); `StationGrid.placement_error` refuses overlaps ("Blocked by …").

## Object names (read by `src/tools/module_import.gd`)

Set `res://src/tools/module_import.gd` as the glTF's **Import Script**
(Import dock → Scene → Import Script), then reimport.

| Name | Becomes | Notes |
|---|---|---|
| `hull` | the module hull | Must be **watertight** with **real thickness** (0.2–0.4 m): an outer and an inner shell. Gets the cut material. |
| `slot_A`, `slot_B`… | attachment slot "A", "B"… | An empty. Place it just outside the doorway, **+Z pointing out** of the module. Overrides the ASCII slot letter. |
| `part_<name>` | `ModulePart` (kind CUSTOM) | Moved under `Parts/`. Custom property `explode_dir` = `[x, y, z]` sets the exploded-view direction (default: away from the module centre). The name must match `UpgradeDef.part_node`. |
| `mount_<name>` | upgrade mount (Marker3D) | An empty on the hull surface, **+Z (Blender) = up = surface normal**. Upgrades with `mount = <name>` get their part spawned there (`part_scene` art or a placeholder). Prefer mounts over `part_*` for anything that's an upgrade: no scene edits, parts reusable across modules. See docs/CONTENT_PIPELINE.md. |
| `light_<name>` | light anchor | An empty at ceiling height; the module adds an OmniLight + floor light card there, driven by power. |
| `<name>-col` | collision | Godot's built-in import hint. Walls on layer 4 ("walls"). Usually not needed: the ASCII wall cells already collide, and a `-col` wall would block doorways. |
| `<name>-nav` | navigation source | Hidden; becomes a static collider on layer 1 ("world") so the runtime navmesh bake walks on it. |
| `cut_box` | cut region | A box mesh (hidden in game). When present, the cutaway opens only this box (its X/Z extent and top; the bottom is always floor + 1.15 m) instead of the whole module: e.g. one room of a big wreck. |
| `greebles*` | detail group | A node holding greeble meshes (cut material); hidden in station view like the procedural `Detail`. |
| `prop_<name>` | interior prop | Never cut, drawn only while the module is open (group `interior_prop`). Keep props out of furniture cells and doorways. |

Everything else is treated as structure (cut material).

The walkable interior still comes from the module's ASCII layout (floor
colliders, furniture, spawn); art only has to line up with its cells.

## Vertex colours (masks for `toon_cut.gdshader`)

| Channel | Meaning |
|---|---|
| **R** | wear mask — where rust and grime appear first (edges, low areas, around vents) |
| **G** | emissive mask — running lights, screens; glows only when the module is powered |
| **B** | trim mask — mixes the hull colour towards the module's trim colour (panels, stripes) |

Wear itself is a per-module uniform (`wear`, 0–1, on the module's own material copies) blended with world-space
grunge noise, so one mesh covers derelict → cared-for.

With an `art_palette`, B is effectively off (trim colours are already in the
palette) and the G glow takes the swatch colour instead of the cyan strip
colour (`emission_from_texture`); props glow through `mask_emission` in
`toon.gdshader`.

## Watertight & thick — why it matters

The cutaway discards hull fragments inside a box and paints the **back
faces** seen through the opening as a flat section fill. That only looks
right when every visible back face is the inside of a solid wall:

- no holes, no open edges, no single-sided planes in the hull;
- normals pointing outwards;
- in Godot, debug panel → **Back faces**: magenta anywhere *without* a cut
  means a hole. Report it as an art issue — never patch capping in code.

`tests/unit/test_hull_mesher.gd` shows the check used for procedural hulls
(every directed edge matched by its reverse); the same check can run on
imported meshes.

## Greeble kit

The reference images are ~70 % greebles. Build a shared kit once and reuse
it everywhere: pipes, vents, panels, cable bundles, tanks, crates, antennae.
Each greeble is a closed solid, floating ~1 cm off the hull so faces never
coincide (z-fighting shows up in the section fill otherwise). Small greebles
go in a separate object so they can be hidden in station view.

## Palette

Colours come from `Palette` (`src/core/palette.gd`): yellow, dark blue,
violet, neon pink/cyan, anthracite — plus one hull colour per faction or era
(`HULL_*`). Set a module's hull / trim / cap colours on its root node
(procedural modules and placeholder parts use them).

Imported art carries its flat colours in a **palette texture** (16 px swatches
in a 128 px PNG) and UVs that point each face at its swatch (UVs are constant
per face, so it always samples mip 0 and never bleeds). `Module.art_palette`
+ `ToonMaterials.get_art_material()` draw hull, parts, greebles and props with
it: one texture for every art module.

## Budget per module

- ≤ 15k triangles, ≤ 3 materials (hull, interior, emissive), one atlas.
- ≤ 2–4 real lights (`light_*`); everything else glows through the G mask
  and light cards.
- Station view target: ≤ 150 draw calls, ≤ 250k triangles on screen.
