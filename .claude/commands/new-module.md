---
description: Build a station module with the Blender module kit (e.g. "cupola", or a row id of docs/MODULE_CATALOG.md)
---
Build this station module: $ARGUMENTS

Source of truth: `art/modules/<id>.py` (spec) + `art/kit/` (kit). Never hand-edit the .glb,
the generated .blend or the synced .tres fields (layout, slot_frames, massing, slot_sizes).
Reference: docs/ART_PIPELINE.md ("Module kit"), docs/MODULE_CATALOG.md (the brief for each module).

1. **Brief.** Read the module's row in `docs/MODULE_CATALOG.md`: attach slot, offered slots
   (size S/M/L = 1/2/3; P = pressurised hatch, D = visitor dock), mounts (T slots are
   upgrade mounts, not slots), role, look. Station is a flat deck: horizontal slots only.
2. **Layout first.** Write `LAYOUT` (StationBuilder legend): whole 2 m cells, doorway letters
   on the outer ring, 2-cell-wide corridors next to furniture (B, K, C, S, T, G block the
   navmesh), at most one interior room (the cutaway opens one `cut_box`). Non-walkable
   modules (truss, reactor, pylon arms): a tiny maintenance room or none (then no cut_box).
3. **Spec.** `art/modules/<id>.py` with `ID`, `LAYOUT`, optional `SIZES` ({"A": 3} for an L
   hatch), `BUDGET`, `SEED`, and `build(m)`. Copy `greenhouse.py` (tube) / `hub_oct.py` (polygon):
   `m.piece()` closed solids (`thick=` for shells with an interior; `massing=False` for bits
   above the roofs or tiny trims), `m.doorway(letter, pieces, face=)`, `m.light`, `m.mount`,
   `m.cut_box`, `m.greeble` / `m.pipe` (kit names in `core.build_kit`), `m.prop`, `m.part`.
   Colours: only `core.PAL` names (append new ones at the END of PAL, never reorder).
   Floor corners of rounded sections must be tight (radius ~0.45) or floor cells stick out.
4. **Build & look.** `tools/art.sh <id> --render`, then Read
   `art/modules/renders/<id>_closed.png`, `_cut.png`, `_top.png`. Fix every `KIT ERROR`
   (watertight hull, budget, slot facing / outside the footprint, door points on walkable
   cells, layout cells inside the room). Iterate until it reads well at station scale.
   The Blender MCP (`look`) can help tune proportions live; copy the result back into the spec.
5. **Godot side.** `tools/new_module.py <id> --name="..." --description="..."` (creates the
   .tres / inherited .tscn / .import files, or syncs layout & slot data). Then set gameplay
   values by hand in `data/modules/<id>.tres`: `build_cost`, `power_*`, `production`,
   `slots` accepts (`"module"`, `"visitor"` for D slots), `size_class` (the module's default
   hatch size). One `data/upgrades/<id>_<mount>.tres` per mount (`mount`, `part_kind`
   placeholder, effects from `UpgradeDef.EFFECTS`).
6. **Verify.** `tools/import.sh`, `tools/lint.sh && tools/test.sh` (test_module_data checks
   slots/layout/footprint against the scene), screenshots:
   `tools/screenshot.sh build/m.png --build=<id> --focus=<id> --power=all --story=off` and
   `--view=station --layout=demo`. Look at them. `tools/golden.sh`; `/update-goldens` only if a
   golden scene changed on purpose.
7. Tick the module in `docs/MODULE_CATALOG.md` and `docs/ROADMAP.md`; note triangles and any
   deviation from the brief.
