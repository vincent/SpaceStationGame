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
