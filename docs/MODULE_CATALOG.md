# Module catalog

The station modules the player builds, and the brief for making each one with the
Blender module kit (`/new-module <id>`, docs/ART_PIPELINE.md "Module kit").

**Slot codes.** Size **S / M / L** (`slot_sizes` 1 / 2 / 3; M = the standard 1.6 × 2.4 m
doorway). Type **P** = pressurised hatch (walkable, takes modules), **D** = dock (takes
visitor ships), **T** = truss point: an **upgrade mount** (`mount_*`), not a slot.
A module fits a slot of its own hatch size or larger (a collar covers the gap); the
**Docking adapter** steps M up to L. The station is a flat deck: slots are horizontal,
top / bottom faces are mounts. Every module also has its own attach slot (listed first);
the player can rotate a module to attach by another of its P slots.

Hatch collars are colour-coded on the art: S cyan, M yellow, L violet.

## Connectors

| id | Module | Attach | Offers | Status |
|---|---|---|---|---|
| `corridor` | Corridor | M-P | 1 M-P | procedural (art: todo) |
| `adapter_ml` | Docking adapter | M-P | 1 L-P | procedural (art: todo) |
| `hub_node` | Hub node | M-P | 3 M-P | ✅ kit art, 2.8k tris |
| `junction_t`, `hub_x` | T-junction, cross hub | M-P | 2 / 3 M-P | procedural, cheap early versions |

## Modules

| # | id | Module (inspiration) | Size | Attach | Offers (slots) | Mounts (upgrades) | Role | Look | Status |
|---|---|---|---|---|---|---|---|---|---|
| 1 | `hub_node` | Hub Node (ISS Unity/Harmony) | 6.6 × 4.6 m | M-P | 3 M-P (end + 2 radial ports) | top face | Junction, storage racks | Short stubby node, a hatch on every side, cable bundles and handrails | ✅ |
| 2 | `hab_drum` | Habitat Drum (Skylab, TransHab) | 10.6 × 8.6 m | M-P | 1 M-P (far end) | antenna, radiator | Habitat: bunks, galley, hygiene | Fat inflated drum, quilted fabric skin, band of portholes | ✅ (looks boxy: rounder top?) |
| 3 | `cupola` | Observation Cupola (ISS Cupola, B5) | Ø3 × 1.5 m | S-P | none | shutters | Morale (stargazing) | Faceted dome, seven windows, shutters open when powered | todo |
| 4 | `solar_truss` | Solar Truss (ISS ITS + wings) | 30 m truss, 35 m wings | M-P | none | 2 wing pairs, 2 radiators, arm rail | Power (early-mid) | Square lattice girder, gold and blue wings tracking the sun | todo |
| 5 | `reactor_spine` | Reactor Spine (Discovery One) | 40 m boom, Ø6 m reactor | L-P | none | 4 radiator fins, 1 small | Power (late: output, heat, risk) | Thin boom, reactor bulb far away behind a shadow shield, red-glowing fins | todo |
| 6 | `biodome` | Biodome (Valley Forge, O'Neill farms) | Ø20 m dome on 6 m base | L-P | 1 S-P (airlock) | water tank, sun mirror | Food, oxygen, morale | Geodesic glass dome, hex frame, green inside, violet grow lights at night | todo |
| 7 | `hangar` | Construction Hangar (Tycho Station) | Ø35 m frame + 8 m booth | L-P | 1 L-D (ship cradle), 2 M-P (shops) | 2 gantry crane rails | Builds modules, repairs visitor ships | Skeletal girder sphere, gantry cranes, sparks, lit control booth | todo (budget > 15k?) |
| 8 | `pylons` | Docking Pylons (DS9) | Ø6 m hub, 25 m arms | M-P | 2 M-D, 1 L-D (pylon tips) | nav beacon | Trade and visitors | Three thin curved arms, blinking approach lights | todo |
| 9 | `promenade` | Promenade (DS9, B5 Zocalo) | Ø12 × 25 m | L-P | 1 L-P, 2 M-P | | Economy and culture: stalls, bar, shrine | Wide drum, long panoramic window band, neon shop signs | todo |
| 10 | `gravity_ring` | Gravity Ring (Space Station V, Stanford torus) | Ø70 m ring, 4 spokes | L-P (hub) | 1 L-P (axis) | 2 on the hub | Late habitat: gravity, health & morale | Slowly turning wheel on spokes, lit windows round the rim | todo (budget > 15k?) |

### Canopy style (experiment, branch `module-style-canopy`)

Glass-roofed modules from the mockups (`~/Downloads/images`, numbers below): ivory walls up
to 1.15 m (= the cut height), a glass canopy on a white strut frame (`frame`: never cut,
always visible), gold stripe, navy accents, octagonal ports and amber portholes. The
cutaway removes the glass; walls and frame stay. Kit: `Module.canopy_tube` (faceted tube),
`canopy_polygon` (any plan polygon, roof chamfer or dome rings), `port`, `portholes` /
`porthole_at`. Furniture blocks stand on interior `#` cells (blocked, no floor tile) with a
deck plate prop. Gameplay values copy the nearest existing role; their own mechanics
(storage, workshop, lab, mess, plaza) are not designed yet.

Station view of the whole set: `tools/screenshot.sh build/c.png --layout=demo --build=hub_oct,greenhouse,dorm,hub_dome,storage,workshop,lab,cargo,commons,mess,refinery,briefing,plaza,power_deck --view=station --focus=hub_oct --power=all --story=off`

| id | Module (mockup) | Shell | Size (m) | Attach | Offers | Mount | Role (data) | Tris |
|---|---|---|---|---|---|---|---|---|
| `greenhouse` | Greenhouse (489) | tube | 18 × 8.6 | M-P | 1 M-P | lamp_rack | food +0.15 / water −0.15, 2 jobs | 1.6k |
| `dorm` | Dormitory (491) | tube | 18 × 8.6 | M-P | 1 M-P | antenna | 6 bunks (crew beds), console | 2.8k |
| `cargo` | Cargo hold (502) | tube, dead end | 18 × 8.6 | M-P | — | crane | decorative storage | 2.8k |
| `storage` | Storage module (494–496 tubes) | tube | 18 × 8.6 | M-P | 1 M-P | crane | decorative storage | 1.7k |
| `workshop` | Workshop (497) | tube | 18 × 8.6 | M-P | 1 M-P | crane | benches, console | 2.4k |
| `lab` | Lab (498) | tube | 18 × 8.6 | M-P | 1 M-P | dish | holo table, analysers, console | 1.9k |
| `commons` | Commons (490) | tube + opaque dome | 18 × 8.6 | M-P | 1 M-P | lantern | lounge | 2.0k |
| `power_deck` | Power deck (493) | low opaque tube, wings | 18 × 8.6 (+ wings) | M-P | — | wing | power +4.0, console | 1.8k |
| `hub_oct` | Octagon hub (492) | octagon | 9.2 × 9.2 | M-P | 3 M-P | beacon | junction, console | 2.4k |
| `hub_dome` | Dome hub (494–496 core) | octagon + glass dome | 9.2 × 9.2 | M-P | 2 M-P | lantern | junction, console | 2.5k |
| `briefing` | Briefing room (500) | square, pyramid roof | 8.6 × 8.6 | M-P | 2 M-P | mast | seat rows, console | 1.8k |
| `refinery` | Refinery (501) | hexagon | 9.2 × 10.6 | M-P | 1 M-P | chimney | water +0.2, 1 job, console | 1.3k |
| `mess` | Mess hall (499) | wedge (cut triangle) | 10.6 × 10.6 | M-P | 2 M-P | vent | galley (K), tables | 1.9k |
| `plaza` | Plaza (504) | five-armed star | 16.5 × 17.4 | M-P | — | spire | pool, servers, bar | 2.2k |

Deviations from the mockups: ports only on flats facing ±X / ±Y (the triangle and hexagon get
two or three of them, not one per side); the plaza's arms meet at sharp inner corners; the
tall octagonal columns of the mockups are neighbours, not modelled.

Early, cheaper procedural modules stay: `hab_pod`, `agri_bay`, `solar_array`.

## Deferred mechanics

Roles above only use what exists (power, production, upgrade effects). Still to design:
reactor heat and risk, the hangar building modules and repairing ships, gravity bonuses,
the cupola's stargazing action, oxygen. Large modules (hangar, ring) will need the
station-view zoom tiers retuned and probably a bigger triangle budget.

## Making them (order)

Pilot done: Hub node, Habitat drum. Next: Corridor + Docking adapter art, Solar truss
(first non-walkable module), Cupola, Biodome, Pylons, Promenade, Reactor spine, Hangar,
Gravity ring.
