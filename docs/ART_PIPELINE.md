# Art pipeline — Blender → glTF → Godot

How module art is made so it works with the diorama cutaway
([PLAN_DIORAMA_CUTAWAY.md](PLAN_DIORAMA_CUTAWAY.md)). Until real art exists,
every module is procedural: `HullMesher` builds the hull from the module's
interior ASCII, and `ModulePart` builds the placeholder parts. Imported art
replaces those piece by piece, using the same conventions.

## Units and orientation

- 1 unit = 1 m, +Y up. glTF export with "+Y up" ticked.
- One interior cell is 2 × 2 m (`StationBuilder.CELL`). Walls are 2.6 m high
  (`WALL_HEIGHT`); the floor top is at y = 0 and the keel goes down to −0.6.
- Module origin: the centre of its interior layout. (The plan suggested the
  main attach slot; slot markers carry the attachment frame instead, so the
  origin doesn't matter to `Station.attach()`.)

## Object names (read by `src/tools/module_import.gd`)

Set `res://src/tools/module_import.gd` as the glTF's **Import Script**
(Import dock → Scene → Import Script), then reimport.

| Name | Becomes | Notes |
|---|---|---|
| `hull` | the module hull | Must be **watertight** with **real thickness** (0.2–0.4 m): an outer and an inner shell. Gets the cut material. |
| `slot_A`, `slot_B`… | attachment slot "A", "B"… | An empty. Place it just outside the doorway, **+Z pointing out** of the module. Overrides the ASCII slot letter. |
| `part_<name>` | `ModulePart` (kind CUSTOM) | Moved under `Parts/`. Custom property `explode_dir` = `[x, y, z]` sets the exploded-view direction (default: away from the module centre). The name must match `UpgradeDef.part_node`. |
| `light_<name>` | light anchor | An empty at ceiling height; the module adds an OmniLight + floor light card there, driven by power. |
| `<name>-col` | collision | Godot's built-in import hint. Walls on layer 4 ("walls"). |
| `<name>-nav` | navigation source | Hidden; becomes a static collider on layer 1 ("world") so the runtime navmesh bake walks on it. |

The walkable interior still comes from the module's ASCII layout (floor
colliders, furniture, spawn); art only has to line up with its cells.

## Vertex colours (masks for `toon_cut.gdshader`)

| Channel | Meaning |
|---|---|
| **R** | wear mask — where rust and grime appear first (edges, low areas, around vents) |
| **G** | emissive mask — running lights, screens; glows only when the module is powered |
| **B** | trim mask — mixes the hull colour towards the module's trim colour (panels, stripes) |

Wear itself is an instance uniform (`wear`, 0–1) blended with world-space
grunge noise, so one mesh covers derelict → cared-for.

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
(`HULL_*`). Set a module's hull / trim / cap colours on its root node.

## Budget per module

- ≤ 15k triangles, ≤ 3 materials (hull, interior, emissive), one atlas.
- ≤ 2–4 real lights (`light_*`); everything else glows through the G mask
  and light cards.
- Station view target: ≤ 150 draw calls, ≤ 250k triangles on screen.
