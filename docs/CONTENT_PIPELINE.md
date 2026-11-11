# Content pipeline — upgrades & encounters

How upgrades (and the parts they put on the station's models) and
encounters (story beats) are authored as data, validated by tests and
debugged. Part 1 is the plan and what's done; parts 2 and 3 are the
developer guide.

Principles (both systems):

- **Content is data.** One `.tres` per upgrade / encounter; no code change to add one.
- **One source of truth per fact.** Gameplay numbers live in the `.tres`; positions live in the art (mounts); nothing is restated by hand in a scene.
- **Validators in tests.** Every file is checked on `tools/test.sh` (unknown ids, bad expressions, missing mounts...), so a typo fails CI instead of the game.
- **Debug and command-line hooks** to reach any state fast (`--upgrade=all`, `--encounter=<id>`).
- **Rules stay in `GameState`.** Encounter outcomes call the same methods as the rest of the game.

## 1. Plan & status

| Phase | What | Status |
|---|---|---|
| U1 | `mount_<name>` empties in the art → `Marker3D` on import (`ModuleImportRules`) | done |
| U2 | `UpgradeDef.mount` + placeholder (`part_kind`/`part_length`/`part_mirror`) or `part_scene`: `Module` spawns the part on the mount | done |
| U3 | Wreck reactor / radiator moved from hand-placed scene nodes to roof mounts | done |
| U4 | Validation: `UpgradeDef.validate()` (known effects, items, part names), `requires` same-module & acyclic, one part per upgrade, part sits on its mount | done (`test_module_data`) |
| U5 | `--upgrade=all` hook (fully upgraded station for screenshots) | done |
| U6 | `UpgradeDef.sets_flags`: installing sets story flags; `upgraded` encounter trigger | done |
| U7 | Part art kit: `art/parts/` Blender script exporting one `.glb` per part (shared palette), plugged in via `part_scene` | todo |
| U8 | Move the capsule's solar wings to a mount (needs a mount empty matching its current rotation) | todo |
| U9 | Tiers: `replaces = <upgrade>` (mk2 swaps the mk1 part), interior `layout_patch` (an upgrade swaps a layout cell, e.g. salvage pile → recycler) | idea |
| U10 | Balancing sheet: CSV ↔ `.tres` sync script once there are ~50 upgrades | idea |
| E1 | `EncounterDef` / `EncounterDB` (`data/encounters/*.tres`) | done |
| E2 | `StoryState` (flags, counters, seen, schedule) saved with the game (`SAVE_VERSION` 3) | done |
| E3 | `StoryContext`: conditions as Godot `Expression`s over read-only queries | done |
| E4 | `Storyteller`: once / cooldown / condition / chance / priority / weight | done |
| E5 | `GameState`: triggers wired (start, hour, day, repaired, powered, upgraded, built, visitor, traded, interacted, scheduled), outcomes, queue, save/load | done |
| E6 | `EncounterPanel` in the HUD (dialog & radio channels), toast channel | done |
| E7 | Debug panel "Story" row, `--encounter=<id>`, `--story=off` (implied by `--freeze`, so goldens stay quiet) | done |
| E8 | Validation (`test_encounter_data`) + beat-chain tests (`test_storyline`) | done |
| E9 | Starter content: intro, wreck lights, dish signal → Kestrel trader, debris, long night, first salvage, first trade | done |
| E10 | Headless "bot" simulation: fast-forward N days with scripted play and assert every main beat is reachable | todo |
| E11 | Encounters that spawn models (a specific visitor ship, drifting pods via `ExteriorLife`) | todo |
| E12 | Localisation keys for lines (with the game-wide `tr()` pass) | todo |
| E13 | If writing grows: Ink / Yarn for dialogue text, keeping these triggers and conditions | idea |

## 2. Upgrades

An upgrade is `data/upgrades/<id>.tres` (`UpgradeDef`). Buying it in the
exploded view reveals its part and applies its effects.

### Where the part comes from

1. **Authored part:** a node `Parts/<part_node>` already in the module
   scene (a Blender `part_*` object, like the wreck's `part_dish`, or a
   hand-placed `ModulePart`). Use this when the part is modelled with
   the module.
2. **Mounted part (preferred):** `mount = &"roof_a"`. `Module` spawns a
   `ModulePart` named `part_node` on the scene's `mount_roof_a` marker:
   - `part_scene` set → the scene is instanced (art, palette material);
   - else the procedural placeholder `part_kind` (`ModulePart.Kind`:
     1 solar wing, 2 antenna, 3 thruster, 4 reactor, 5 radiator, 6 dish,
     7 garden, 8 panel array, 9 clamp), sized by `part_length`,
     mirrored with `part_mirror`.
   - Exploded-view direction: `explode_dir`, default the mount's up axis.

A mount is an empty named `mount_<name>` in the module's Blender script
(`art/station_early/scripts/build_station.py`, see `mount_roof_a`).
Its **+Z (Blender) is the surface normal** (+Y in Godot); parts grow
along it. For procedural modules, add a `Marker3D` named `mount_<name>`
to the `.tscn` by hand.

### Add an upgrade (checklist)

1. Copy a file in `data/upgrades/` (e.g. `wreck_reactor.tres`) and set:
   `id`, `module_id`, `display_name`, `description`, `part_node`
   (`part_<something>`, unique on that module), `cost`, `minutes`,
   `requires` (same module), `effects` (keys in `UpgradeDef.EFFECTS`),
   optional `sets_flags`.
2. Part: `mount` + `part_kind` (placeholder) or `part_scene`; or an
   authored `part_*` in the art.
3. New mount? Add the empty in the Blender script, re-run it
   (`ART_PIPELINE.md`), `tools/import.sh`.
4. `tools/test.sh` (`test_module_data` validates it), then look at it:
   `tools/screenshot.sh build/up.png --freeze --power=all --upgrade=<id> --focus=<module> --view=station`
   (`--upgrade=all` for everything).
5. New effect kind? Add it to `UpgradeDef.EFFECTS` and read it with
   `StationState.effect_total()` / `_effect_sum()` where the rule lives.

## 3. Encounters

An encounter is `data/encounters/<id>.tres` (`EncounterDef`): a small
story beat. The game raises **triggers**; for each one the `Storyteller`
keeps the encounters listening to it that are available (not a `once`
already seen, not in cooldown, `condition` true, `chance` roll), takes
the highest `priority` and breaks ties by `weight`. `GameState` then
starts it: marks it seen, applies its `outcomes`, and shows it.

### Fields

| Field | Meaning |
|---|---|
| `id` | unique, = file name |
| `trigger` | `start`, `hour`, `day`, `repaired`, `powered`, `upgraded`, `built`, `visitor`, `traded`, `interacted`, `scheduled` (see `EncounterDef.TRIGGERS` for the `subject` of each) |
| `condition` | Godot expression, empty = always (below) |
| `priority`, `weight`, `chance` | selection (see above). `chance` < 1 for random flavour |
| `once`, `cooldown_hours` | repeatability |
| `channel` | `dialog` (panel), `radio` (panel with a transmission header), `toast` (lines flash, no choices, never blocks) |
| `title`, `lines` | text |
| `outcomes` | applied when it starts |
| `choices` | `[{"text": ..., "outcomes": PackedStringArray(...), "condition": "..."}]`; a choice whose condition is false is greyed out. None = "Continue" |

Only one dialog/radio encounter is on screen at a time; others started
meanwhile queue up (their outcomes already applied). The open one and the
queue are saved.

### Conditions

Evaluated by `StoryContext` (read-only; add functions there, never ones
that change the game). `and`, `or`, `not`, comparisons work. Input
variable `subject` (string) = what the trigger was about.

```
flag("met_signal")  count("trades")  seen("intro")  hours_since("intro")
item("scrap_metal")  has_item("scrap_metal", 5)
has_module("hab_pod")  repaired("wreck_core")  powered("wreck_core")  has_upgrade("wreck_dish")
power()  need("morale")  day()  hour()  chance(0.3)
```

Example: `subject == "wreck_dish" and not flag("ignored_signal")`.

### Outcomes

One per line, verbs in `StoryOutcome` (validated against the item, module
and encounter databases):

```
give <item> <n>         take <item> <n>        need <need> <delta>
flag <name>             unflag <name>          count <name> <delta>
schedule <encounter> <hours>                   toast <text...>
visitor                 wear <module> <delta>
```

`schedule` + `trigger = scheduled` makes chains: a beat answered now
fires another one later (its condition is checked then). New verbs: add
them to `StoryOutcome.VERBS` and to `GameState.apply_outcome()`.

### Add an encounter (checklist)

1. Copy a file in `data/encounters/` (`first_signal.tres` has choices,
   `drifting_debris.tres` is a random repeatable toast). Strings in `.tres`
   escape quotes: `condition = "subject == \"wreck_dish\""`.
2. `tools/test.sh`: `test_encounter_data` checks fields, conditions,
   outcomes and that every `scheduled` encounter is scheduled somewhere.
   Main story chains deserve a test in `test_storyline.gd`.
3. Try it: debug panel → Story → pick → Fire, or
   `tools/screenshot.sh build/enc.png --story=off --encounter=<id>`.

### New trigger

Raise it with `GameState.story_event(&"name", subject)` from where the
event happens (prefer a `GameState` method or a signal it already
listens to), and document it in `EncounterDef.TRIGGERS`.

### Code map

| File | Role |
|---|---|
| `src/core/encounter_def.gd`, `encounter_db.gd` | data + registry |
| `src/core/story_state.gd` | flags, counters, seen, schedule (saved) |
| `src/core/story_context.gd` | condition functions |
| `src/core/story_outcome.gd` | outcome verbs (parse, validate) |
| `src/core/storyteller.gd` | selection rules |
| `src/autoload/game_state.gd` | triggers, `story_event`, `fire_encounter`, `resolve_encounter`, `apply_outcome`, save/load |
| `src/ui/encounter_panel.gd` | dialog/radio UI |
| `tests/unit/test_story.gd`, `test_encounter_data.gd`, `test_storyline.gd` | tests |
