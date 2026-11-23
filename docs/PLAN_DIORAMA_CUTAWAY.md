# Plan — Diorama Cutaway Rendering & Progression

> Status: approved direction (2026-11-11). Replaces the isometric "walls-down" cutaway.
> Implemented 2026-11-11 with procedural placeholder art — see "Implementation notes" at the end.
> Markers: `[x]` done · `[~]` partial / done differently (note says how) · `[ ]` not done.
> Paths below (`res://...`) were suggestions; the real ones are in the implementation notes.

## 0. Goal and principles

Present the station as **one object seen from outside** (a fixed oblique ¾ view, like a technical cutaway illustration), with a section of the hull **sliced away** to reveal a dense, lived-in interior. The station grows like a kit, and progress is read from **silhouette, light and wear**, not only from numbers.

Design rules every checkpoint must respect:

1. **The hull is always visible.** We cut it open; we never hide whole walls.
2. **The camera never rotates freely.** One authored angle means authored composition, baked details and cheap rendering.
3. **Every upgrade changes something visible**: silhouette, light, colour or motion.
4. **Something is always moving.** It's an idle game, so the scene must be pleasant with no input.
5. **Mobile first:** Godot Mobile renderer, Android arm64, landscape, 30 fps idle and 60 fps when interacting.

### What stays from the prototype

| Keep | Change | Remove |
|---|---|---|
| Toon shader, inverted-hull outline | Camera: iso → fixed oblique ortho | "Walls down" system (behind a flag until CP3 is done) |
| `StationBuilder` ASCII (now for module *interiors*) | Station = modules snapped on slots | Free camera rotation, if any |
| Runtime navmesh baking | Navmesh per module + links | |
| Needs system, clock, inventory | Touch mapping (two zoom tiers) | |
| GUT, gdlint, CI, debug panel, screenshot tool | Screenshot tool → golden-image tests | |

---

## CP0 — Spike: validate the look (size S, do first)

Throwaway branch, built on the current prototype. The aim is a go/no-go on the visual direction before refactoring anything.

- [x] Point an orthographic `Camera3D` at the current station at a fixed oblique angle (start at rotation x = −28°, y = 25°).
- [x] Wrap the existing rooms in a rough closed hull (CSG boxes or a quick Blender block-out, watertight, ~0.3 m thick). *(Procedural voxel hull, `HullMesher`, watertight by construction and tested.)*
- [x] Add the cut shader from CP2 (clip box + back-face cap) on the hull only.
- [x] Capture three screenshots with the headless tool: full station, cut open, zoomed on one room. *(`tests/goldens/station_closed.webp`, `cut_open.webp`, `room_view.webp`.)*

**Accept when:** the screenshots read as "an illustrated cutaway of a ship" rather than "a floor plan". **→ Needs your call:** done straight on `main` (no throwaway branch); the go/no-go on the look is still open. Compare them side by side with the reference images and keep the angle values that work best.

---

## CP1 — Camera rig (size S)

`res://src/camera/diorama_camera.gd` (Node3D rig → Camera3D, `projection = ORTHOGONAL`).

- [x] Fixed rotation exported as `@export var pitch_deg`, `yaw_deg`; no rotation input at all.
- [x] Two **zoom tiers** with a continuous pinch between them:
  - **Station view:** `size` fits the station AABB plus a margin; the whole silhouette and the starfield are visible.
  - **Room view:** `size` fits the focused module/room.
- [x] Pan clamped to the station AABB, expanded by a margin, and recomputed when modules are added.
- [x] `focus_on(target: Node3D, tier)`: eased tween of position and size (~0.6 s, ease-in-out).
- [x] Emit `zoom_changed(t: float)`, where t = 0 is station view and t = 1 is room view; CP6 drives the cut from it.
- [x] Starfield backdrop quad parented to the camera, with slight parallax drift and no rotation.
- [x] Debug panel: sliders for pitch, yaw and size so the angle can be tuned on device.

**Tests (GUT):** AABB fit (station is always fully in frame at t = 0), pan clamp, `focus_on` ends at the expected size and position.

---

## CP2 — Cutaway rendering (size M, core tech)

### 2.1 Cut volume

A world-space **axis-aligned box** (the "cut box"). Hull fragments inside it are discarded. The box usually covers the front quadrant between the camera and the focused room.

- [x] Project Settings → Shader Globals: `cut_min` (vec3), `cut_max` (vec3), `cut_enabled` (bool), `cut_cap_color` (color), `cut_ink_width` (float), `ink_color` (color). *(Plus `debug_backfaces`, `interior_warmth`.)*
- [~] `res://rendering/cutaway_controller.gd` (autoload) computes the box from the focused module plus the camera direction and sets the globals with `RenderingServer.global_shader_parameter_set()`. It also animates open/close. *(`src/rendering/cutaway_controller.gd` is a node in `main.tscn`, not an autoload, so it has a clear owner and is testable. The box slices the focused module horizontally at 1.15 m — a section cut — so it doesn't depend on the camera direction.)*

### 2.2 Shader include

`res://rendering/cutaway.gdshaderinc`, included by the toon shader **and** the outline shader:

> Note: Godot doesn't allow assigning a varying inside a helper function, so the
> real include has `vec3 cut_world(mat4, vec3)` and `vertex()` does
> `v_world_pos = cut_world(MODEL_MATRIX, VERTEX);`. Global uniforms can't take hints.

```glsl
global uniform vec3  cut_min;
global uniform vec3  cut_max;
global uniform bool  cut_enabled;
global uniform vec4  cut_cap_color : source_color;
global uniform float cut_ink_width;
global uniform vec4  ink_color : source_color;

varying vec3 v_world_pos;

// call from vertex()
void cut_vertex(mat4 model, vec3 vertex) {
    v_world_pos = (model * vec4(vertex, 1.0)).xyz;
}

bool cut_inside(vec3 p, float grow) {
    return all(greaterThan(p, cut_min - grow)) && all(lessThan(p, cut_max + grow));
}
```

Toon shader (`render_mode cull_disabled;`), at the top of `fragment()`:

```glsl
if (cut_enabled && cut_inside(v_world_pos, 0.0)) { discard; }

if (!FRONT_FACING) {
    // Back face visible = we are looking into the cut wall thickness -> flat "section" fill
    ALBEDO = cut_cap_color.rgb;
    NORMAL = vec3(0.0, 0.0, 1.0);   // face the camera, lit flat
} else if (cut_enabled && cut_inside(v_world_pos, cut_ink_width)) {
    // Thin band right next to the cut boundary -> ink line along the cut edge
    ALBEDO = ink_color.rgb;
}
```

Outline (inverted hull) shader: include the same file and `discard` when `cut_inside(v_world_pos, 0.0)`, so outlines don't float over the opening.

- [x] Toon shader and outline shader include the file.
- [x] Character, props and interior materials **don't** clip: either a `clip_enabled` per-material uniform, or separate hull and interior materials. Only the hull and structure get cut. *(Separate `toon_cut.gdshader` via `ToonMaterials.get_cut_material()`; the outline has `clip_enabled`.)*
- [x] Cap colour per module through an instance uniform (`instance uniform vec4 cap_tint`), so the cut faces of different modules can differ subtly (cream, grey, rust).
- [ ] *(Not needed so far: back-face capping works on the procedural hulls.)* **Fallback:** if back-face capping looks wrong on some meshes, try stencil-based capping (spatial shader stencil modes, Godot ≥ 4.5) and check it's supported on the Mobile renderer before relying on it.

### 2.3 Mesh requirements (back-face capping only works with these)

- Hull meshes must be **watertight and have real thickness** (an inner and an outer shell). A back face visible anywhere *without* a cut means a hole, which makes it a useful debug signal.
- [x] Debug panel toggle: render back faces in magenta to find holes. *(Also `--backfaces` dev hook.)*

**Tests:** unit-test the box computation (the focused room is never inside the cut box; the camera-to-room segment passes through the box). Golden image of the cut-open test scene (see CP10).

**Accept when:** the cut shows a clean flat section fill with an ink line along the edge, no outline artefacts, the interior is fully readable, and it costs < 1 ms on the target device. **→ Open:** the < 1 ms budget needs a device profile.

---

## CP3 — Module & slot architecture (size L)

The station is a graph of **modules** attached at **slots**. This replaces "one big ASCII station".

### Scenes

```
Station (Node3D)                      res://station/station.gd
 ├─ Module_Capsule (Module)           res://modules/capsule/capsule.tscn
 │   ├─ Hull (MeshInstance3D)         cut + capped
 │   ├─ Interior (Node3D)             built by StationBuilder from the module's ASCII
 │   ├─ Parts (Node3D)                explodable/upgradable parts (CP8)
 │   ├─ Lights (Node3D)               driven by power state (CP5)
 │   ├─ Ambient (Node3D)              particles / loops (CP7)
 │   ├─ NavRegion (NavigationRegion3D)
 │   └─ Slots: Slot_A, Slot_B (Marker3D + Slot.gd)
 └─ Module_Wreck ...
```

- [~] `Module` resource/script: `id`, `display_name`, `state` (`DERELICT`, `REPAIRED`, `UPGRADED_1..n`), `powered: bool`, `wear: float (0–1)`, `slots`, `interior_ascii`. *(Split: `ModuleDef` resource (data/modules) + `StationState` records (pure logic) + `Module` node. State is `DERELICT/REPAIRED/UPGRADED` with the level = installed part count.)*
- [x] `Slot`: transform, `size_class`, `accepts: Array[StringName]`, `occupied_by`. *(Slots come from lowercase letters in the interior ASCII; accepts list from the ModuleDef.)*
- [x] `Station.attach(module_scene, slot)`: snaps the module's own attach slot onto the target slot, updates the camera AABB, rebakes or links navigation, and emits `module_attached`.
- [x] Navigation: one `NavigationRegion3D` per module, with `NavigationLink3D` at slot doorways (or aligned edge connections). Rebake only the affected module.
- [x] `StationBuilder` is narrowed to generating a module's interior from its ASCII.
- [x] Save/load: station = list of `{module_id, slot_path, state, wear, powered, installed_parts}`. *(Save version 2; v1 saves get the story station.)*
- [x] Remove the walls-down system once the capsule and the wreck run fully on the new system.

### First content set (the story start)

1. **Capsule**: your rescue pod (image 2): powered, low wear, the only light source.
2. **Wreck core**: the abandoned station hub, derelict, wear 1.0, unpowered, 2–3 rooms.
3. Two or three empty slots on the wreck, shown as **ghost outlines** (dashed ink, no fill) when the player can afford something.

**Tests:** attach/detach, slot compatibility, AABB update, a navigation path exists from the capsule to every room after an attach, save/load round-trip.

---

## CP4 — Art pipeline (size M, runs in parallel with CP3)

Blender → glTF → Godot conventions, written down in `docs/ART_PIPELINE.md`:

- [~] Scale 1 unit = 1 m; module origin = its main attach slot; +Y up. *(Origin is the layout centre; slot markers carry the attach frame — see ART_PIPELINE.md.)*
- [x] Hull: watertight and thick (0.2–0.4 m). Separate object `hull`. *(Documented; Module uses an authored `hull` instead of the procedural one when present.)*
- [x] Node-name prefixes recognised by an import script (`res://src/tools/module_import.gd`, `EditorScenePostImport`; rules in `ModuleImportRules`, unit-tested):
  - `slot_*` → Marker3D + Slot
  - `part_*` → explodable part (CP8)
  - `light_*` → light anchor (CP5)
  - `-col` → collision, `-nav` → navigation source geometry
- [x] Vertex-colour channel **R = wear mask** (where rust and grime appear), **G = emissive mask** (screens, strips). *(Plus B = trim mask.)*
- [~] **Greeble kit:** pipes, vents, panels, cable bundles, tanks and crates, reused everywhere for density. The references are about 70 % greebles. *(Procedural placeholders only: ribs, light strips, vents, pipes, tanks, antennae. Real kit = art work.)*
- [~] Palette locked to the doc (yellow, dark blue, violet, neon, anthracite) plus one hull colour per faction or era. Store it as a shared `Palette` resource. *(`Palette` stays a script of constants, now with `HULL_*` colours.)*
- [~] Budget per module: ≤ 15k tris, ≤ 3 materials (hull, interior, emissive), one atlas. *(Documented; procedural modules are well under it.)*

---

## CP5 — Light & wear as progression (size M)

### Light ("powering up the station")

- [x] Global darkness: unpowered modules are a near-black silhouette lit only by rim light from the starfield (low ambient plus a cold directional key).
- [x] `module.powered = true` triggers a **power-on sequence** (~2 s): lights flicker on room by room, emissive strips sweep, screens boot. This is the main reward moment, so polish it.
- [x] Lights: emissive materials and fake light cards (additive quads) do most of the work; at most 2–4 real `OmniLight3D` per module. Respect the Mobile renderer's per-mesh light limits.
- [x] Power budget UI: modules draw power, so the player chooses which rooms are lit. This makes light a resource and keeps it visible.

### Wear

- [x] Toon shader uniform `wear` (instance uniform, 0–1), blended with the vertex-colour R mask and triplanar grunge noise to produce rust, darkened panels and stains. *(3D world-space value noise rather than a triplanar texture: same effect, no texture.)*
- [x] Repairs tween `wear` down over ~1.5 s with a sweep effect. Upgrades swap or add `part_*` meshes (clean panels, stripes, decals).
- [x] Never reach 0 wear: keep it "worn but cared for", like the mid-game reference.

**Tests:** state → (powered, wear, visible parts) mapping, and power budget arithmetic. *(Done: `test_station_state.gd`, `test_main_scene.gd`.)*

---

## CP6 — Zoom as reveal + input (size M)

- [x] `CutawayController` listens to `zoom_changed(t)`:
  - t < 0.3: hull closed (`cut_enabled = false` or a zero-size box), as a beauty shot.
  - 0.3–0.7: the cut box grows smoothly from the hull surface inwards (the station "opens").
  - t > 0.7: fully open on the focused module.
- [x] Focus selection: in station view, **tap a module** to `focus_on(module)`; the cut box moves to it.
- [x] Updated touch mapping (update the project doc):
  - Station view: tap module = focus/zoom; tap ghost slot = build menu; drag = pan.
  - Room view: tap floor = move character; tap object = activate; double-tap = use item; pinch out = back to station view.
- [x] Character auto-routines (CP7) continue in both views; the player only interrupts them.

**Accept when:** pinch from full station to room and back feels like opening a model kit, with no pop and no clipping of the character. **→ Open:** "feels like" needs a hands-on check on a phone.

---

## CP7 — Ambient life & clock lighting (size M)

Idle games are watched, so this checkpoint matters as much as the gameplay ones.

- [x] **Ambient kit** (drop-in scenes → built in code by `AmbientKit`): steam vent (GPUParticles3D, with a CPUParticles fallback for low-end devices), blinking LED cluster (shader `TIME`, no nodes), rotating fan, flickering screen, drifting maintenance drone (PathFollow3D), dangling cable sway.
- [x] Each module state enables or disables ambient props: derelict = sparks and drifting debris, repaired = steady hum, upgraded = more screens and drones.
- [x] **Character routines** driven by needs plus the real clock: sleep at night, eat at meal times, work or repair, stargaze at the window when morale is low. Small idle animations (stretch, look out the window).
- [x] **Clock lighting:** global uniform `interior_warmth` (0 = cool work light, 1 = warm night light). Night dims the interior and makes emissives dominant; the station exterior stays constant (it's space).
- [x] Exterior life: occasional distant traffic, passing debris, slow station rotation of the starfield.
- [~] Audio layer (even placeholder): room tone per module, power-on sting, soft UI clicks. *(Synthesised placeholders (`SfxSynth`); one global room tone that follows powered modules rather than one per module.)*

---

## CP8 — Exploded-view upgrade screen (size L, signature feature)

Inspired by the exploded engine in the capsule reference.

- [x] Tap **Upgrade** on a focused module to enter the exploded view: the camera holds, and `part_*` nodes tween outwards along their authored `explode_dir` (custom property from Blender, or local +normal by default) with a stagger.
- [x] Parts show ink leader lines and labels (name, state, cost), like a technical diagram.
- [x] Locked or missing parts are drawn as **ghost parts** (outline only).
- [x] Buying an upgrade: the ghost fills, the part flies in and **snaps** with a small squash, sparks, a sound and `Input.vibrate_handheld(30)`. Then everything reassembles and the power-on or wear sequence plays.
- [x] Data: `UpgradeDef` resource `{id, module_id, part_node, cost, requires, effects}`.

**Tests:** explode/reassemble returns parts exactly to their rest transforms; upgrade prerequisites; effects are applied once.

---

## CP9 — Docking visitors (size M)

- [x] Docking slots (`Slot` with `accepts = [&"visitor"]`).
- [x] Visitor ship scene: approach path, docking clamp animation, its own small cutaway interior (same shader, so it gets cut too), a trader NPC.
- [x] Visitors change the silhouette temporarily, which keeps the scene fresh with no player action.
- [x] Departure after a timer or a trade.

---

## CP10 — Performance, testing & polish (ongoing; hard gate before release)

### Performance budget (target: a mid-range Android from ~2021)

- [x] Idle: `Engine.max_fps = 30`; interacting or camera moving: 60.
- [~] ≤ 150 draw calls in station view, ≤ 250k tris on screen, ≤ 1 ms for the cut and outline passes. *(Desktop Compatibility renderer: ~150 draw calls incl. UI, ~35k tris in station view after hiding closed interiors. Mobile-renderer numbers need a device.)*
- [~] Mesh LOD and visibility ranges: greebles fade out in station view. *(Visibility ranges don't react to ortho zoom, so `CutawayController` hides the Detail greeble mesh below t = 0.25 and every closed module's interior.)*
- [~] Profile on device for each checkpoint; add an FPS and draw-call readout to the debug panel. *(Readout done: FPS, cap, ms, draw calls, tris. No device profiling done yet.)*

### Golden-image tests (the fixed camera makes these reliable)

- [x] Extend the headless screenshot tool: render canonical scenes (station closed, cut open, room view, exploded view, night lighting) and compare with stored goldens using a tolerance threshold. Run in CI. *(`tools/golden.sh`, software GL for stable pixels; CI job `golden`.)*
- [x] Update goldens only with an explicit command (e.g. a `/update-goldens` slash command).

### Polish checklist

- [ ] The silhouette is readable as a black shape at station-view size.
- [x] Every upgrade passes the "visible change" rule. *(Each upgrade reveals a part; `test_module_data.gd` checks every upgrade has one.)*
- [~] Power-on, repair and part-snap moments all have sound, motion and haptics. *(All have sound + motion; haptics only on part-snap.)*
- [x] No frame where the character is clipped by the cut. *(Characters use the non-cut material.)*

---

## Order & dependencies

```
CP0 spike ──► CP1 camera ──► CP2 cutaway ──► CP3 modules ──► CP5 light/wear ──► CP8 exploded view
                                   │              ▲                │
                                   │         CP4 art pipeline      ├──► CP7 ambient life
                                   └──────────► CP6 zoom reveal ◄──┘
                                                                   CP9 docking (after CP3 + CP7)
CP10 runs continuously from CP2 onwards.
```

First playable milestone (**"Power-up slice"**): CP0–CP3 plus the power-on part of CP5 plus CP6 — the capsule docked to a dark wreck, which you zoom into and light up room by room.

## Risks & open questions

- **Back-face capping on non-watertight meshes.** Mitigation: magenta debug view and an import-time check. Fallback: stencil capping.
- **Light count on the Mobile renderer.** Mitigation: emissive materials and fake light cards first, few real lights.
- **Cut box shape.** An AABB is fine while modules are axis-aligned; rotated modules would need an oriented box (pass a world-to-box transform instead). Decide in CP3.
- **Portrait vs landscape:** the doc says landscape. The oblique view suits landscape well; confirm before final composition.
- **Art throughput** is the main bottleneck: a greebles kit plus vertex-colour masks keeps each module cheap. Decide early who makes the modules.

## Notes for Claude Code sessions

- Work one checkpoint at a time; tick the boxes in this file as tasks land.
- Each checkpoint ends with: GUT tests green, gdlint clean, golden images updated if intended, and a device screenshot attached to the PR.
- Never edit hull meshes to "fix" capping artefacts in code. Report them as art issues instead.
## Implementation notes (2026-11-11)

Where things ended up:

| Piece | Path |
|---|---|
| Camera rig | `src/camera/diorama_camera.gd` (+ `backdrop.gd` parallax) |
| Cutaway | `assets/shaders/cutaway.gdshaderinc`, `toon_cut.gdshader`, `outline.gdshader`; `src/rendering/cutaway_controller.gd` |
| Clock lighting | `src/rendering/clock_lighting.gd`, `src/core/day_cycle.gd` |
| Station data & rules | `src/core/station_state.gd`, `module_def.gd`, `upgrade_def.gd`, `module_db.gd`; `data/modules/`, `data/upgrades/`; actions in `GameState` |
| Station scene | `src/station/station.gd`, `module.gd`, `slot.gd`, `module_part.gd`, `hull_mesher.gd`, `mesh_kit.gd`; scenes in `src/station/modules/` |
| Exploded view | `src/station/exploded_view.gd`, `src/ui/upgrade_overlay.gd` |
| Visitors | `src/station/visitor_director.gd`, `src/interactables/trader.*` |
| Ambient life | `src/ambient/ambient_kit.gd`, `exterior_life.gd`; `assets/shaders/ambient_fx.gdshader` |
| Routines | `src/player/player_routine.gd` |
| Audio | `src/audio/sfx_synth.gd`, `audio_director.gd` |
| Art import | `src/tools/module_import.gd`, `module_import_rules.gd`; `docs/ART_PIPELINE.md` |
| Goldens | `tools/golden.sh`, `tools/image_diff.gd`, `tests/goldens/`, `/update-goldens` |

Decisions taken along the way:

- **Section cut instead of a front-quadrant box.** At −28° pitch a quadrant notch leaves most rooms under the roof, so the cut box covers the focused module's whole footprint from 1.15 m above its floor upwards: the roof lifts off and every wall is sliced, like a classic cutaway section.
- **Interiors of closed modules are hidden** (collisions stay). That's most of the draw-call saving in station view.
- **Slot gap 0.15 m per side**, so hull greebles never interpenetrate a neighbour.
- **Visitors are never saved**; they arrive again by themselves.
- After moving a module, its navigation region transform is pushed to the NavigationServer explicitly (otherwise it can stay stale for a module moved in the frame it entered the tree).

Still open (needs a person or a device): CP0 look go/no-go, on-device profiling (cut < 1 ms, draw calls on the Mobile renderer), touch feel of the pinch, real Blender art and greeble kit, real audio.
