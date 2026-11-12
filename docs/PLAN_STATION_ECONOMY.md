# Plan — station economy (resources & production)

Status: **implemented** (P1–P6). Developer guide: `docs/CONTENT_PIPELINE.md` §4.
Deviations: the `produced` trigger counts whole units in the story counter
`produced_<id>`; planters (`G` layout character) are interactables that show
the bay's status; the status bar hides during the exploded view;
`--popover=<id>` opens a popover for screenshots.

The station gets its own state: stocks of **resources** (scrap, water,
food...) that **powered modules produce and
consume** every game hour. A top status bar shows each resource; tapping one
lists the modules that produce or consume it, including the ones currently
not running and why.

Decisions (from the design Q&A):

| Topic | Decision |
|---|---|
| Model | **Stock + rate**: modules add to/remove from a stockpile over time; the bar shows amount and net rate (`Food 37 +1.2/h`). No storage cap for now. |
| Inventory | **Bulk items become station resources** (scrap, water, food). The personal inventory keeps carried/special items (power cells, future tools). |
| Tiers | **One food, more of it**: there is a single `food` resource. Advanced tiers (upgrades, later bigger modules) just produce more food; their production adds to the module's. |
| Sinks | Player needs (kitchen meals), trade, and **inputs of other modules** (chains: water → food). Build/repair/upgrade costs keep working (scrap is a resource now). |
| Eating | **Kitchen meals**: one action per food resource, taking 1 from the stock. |
| First producer | New buildable **Agri bay** module, procedural placeholder hull (like `hab_pod`); Blender art later. |

## 1. Data model

### Resources are items with `bulk = true`

`ItemData` gets `@export var bulk: bool`. A bulk item never sits in the
inventory: it lives in the station stock. Keeping resources as items means
every cost dictionary (`build_cost`, `repair_cost`, upgrade `cost`, trader
offers, `give`/`take` outcomes) keeps using the same ids, with no second
registry.

| id | Display | bulk | Notes |
|---|---|---|---|
| `scrap_metal` | Scrap | yes | salvage, trade; pays for building |
| `water` | Water | yes | input of the agri bay; produced by the wreck's tank |
| `food` | Food | yes | replaces `ration` (migrated); meal: +30 food |
| `power_cell` | Power cell | no | stays a carried item |

Power stays what it is (a rate budget, not a stock) but moves into the bar
as a chip, with the same popover (producers / consumers / off).

### `StationStock` (new, `src/core/station_stock.gd`)

Pure `RefCounted`: `Dictionary[StringName, float]` amounts (fractional, so
slow rates accumulate; shown floored). `amount`, `add`, `remove`, `has_all`,
`changed(id, amount)` signal, `to_dict`/`from_dict`.

### One wallet for costs

`GameState` gets `count(id)`, `has_all(cost)`, `give(items)`, `pay(cost)`.
They send bulk ids to `stock` and the rest to `inventory`. Every direct
`inventory.has_all/remove/add` used for costs and rewards switches to them:
`perform`, `trade`, `build_module`, `repair_module`, `buy_upgrade`,
`can_afford_any_module`, `apply_outcome` (give/take), `StoryContext.item/has_item`,
kitchen, trader, salvage pile, and the debug "give".

### Production on modules and upgrades

- `ModuleDef.production: Dictionary[StringName, float]`: per game hour,
  positive = output, negative = input. Example agri bay:
  `{food: 0.15, water: -0.15}`.
- `UpgradeDef.production` (same shape) **adds** to the module's base
  production. A tier is just an upgrade with a bigger output (and usually a
  bigger input / power draw); no replacement rules.

### `Production` rules (new, `src/core/production.gd`, pure)

Each module's **status** for production:

| Status | When | Shown as |
|---|---|---|
| `RUNNING` | not derelict, powered (or draws no power), inputs available | `+0.15/h` |
| `STARVED` | running but an input stock is empty | "Needs water" |
| `UNPOWERED` | switched off | "Unpowered" |
| `DERELICT` | not repaired | "Derelict — repair it" |
| `LOCKED` | (popover only) an upgrade that would produce it is not installed | "Upgrade: Hydroponics" |

- `rates(station) -> {resource: net per hour}` is used for the bar.
- `module_rates(uid)` returns `{resource: rate}` and a status, and is used
  for the popover.
- `tick(station, stock, minutes)` runs on `GameClock.time_advanced` (so
  sleeping and skipping time produce too). Inputs are partial: a module
  runs at `min(1, available / needed)` efficiency. That rule is deterministic
  and unit-testable. Modules tick in uid order, so a producer built earlier
  feeds a consumer built later within the same tick. That's good enough at
  this scale.
- Wear doesn't change output (could come later as an efficiency factor).

## 2. Content (first pass)

- **Agri bay** (`data/modules/agri_bay.tres`, `src/station/modules/agri_bay.tscn`):
  - Buildable, size 1, 10 scrap, power draw 1.5.
  - Production: food +0.15/h, water −0.15/h. About 3.6 meals a
    day, roughly the castaway's food decay of 4/h.
  - Procedural hull with a green-tinted palette. Interior has planter rows
    (a new layout character, or AmbientKit props) and slot A.
  - Mount `mount_rack` for the hydroponics part.
- **Hydroponics** (`data/upgrades/agri_hydroponics.tres`):
  - Tier 2: adds food +0.2/h, water −0.15/h (total food +0.35/h); power draw +0.5.
  - Cost: scrap + a power cell. Part: placeholder `GARDEN` kind on `mount_rack`.
- **Water**: the wreck's big tank. `wreck_core.production = {water: 0.3}`
  while powered. That gives the tank a role and makes the first chain:
  repair and power the wreck, then build an agri bay.
- **Kitchen**:
  - "Eat (+30 food)" takes 1 food from the stock. Effects come from the
    item's `use_effects`.
  - The idle routine eats when food is in stock.
  - The "ration + water" cooking recipe goes away. Water is now only an
    agri input, and it can come back as a recipe later.
- **Trader**: the offers are re-priced for the new ids. Add an offer that
  sells food to the trader, as a first income loop.
- **Story**: a new `produced` trigger fires on the first unit of each
  resource, with subject = the resource id. A `first_harvest` beat uses it.
  A new condition function `rate("food")` gives the net rate.

## 3. UI

- **Top status bar** (`src/ui/status_bar.gd`, `StatusBar`), at the top
  centre between the clock (top-left) and the needs (top-right):
  - One chip per resource that has stock or a producer, plus power.
  - Each chip shows a colour dot (`ItemData.color`), the amount, and the net
    rate (green/red, hidden when 0). The power chip shows `Power 4/7`.
  - Chips appear the first time a resource matters (stock > 0 or a
    producer exists), so the start of the game stays clean.
  - Compact for phone width; the chip text wraps under 720 px.
- **Production popover** (`src/ui/production_popover.gd`):
  - Opens under the tapped chip.
  - Producers come first, then consumers. Each row shows module name,
    rate, and status, with non-running rows greyed out and showing the
    reason.
  - Tapping a row focuses that module (station view). Tapping outside or
    on the same chip closes it.
- The power label is removed from the clock panel, since it's now a chip.
  The encounter panel (y 120) and the needs panel are checked for overlap
  at 1280×720 and at phone size.
- The inventory panel lists only non-bulk items.
- The debug panel's "give" adds 5 of the chosen item to the stock or the
  inventory as appropriate. A new `--stock=<id>:<n>,...` hook sets the
  stock for screenshots.

## 4. Save & migration

- `SAVE_VERSION` 4 adds `stock` (resource → float).
- Loading a v≤3 save:
  - bulk items found in the inventory move to the stock;
  - `ration` becomes `food`;
  - power and production simply resume.
- `test_save` covers the migration with a v3 fixture.

## 5. Tests

- `test_station_stock`: add/remove/has_all, fractional amounts, save round trip.
- `test_production`, using a fake station:
  - statuses (running, unpowered, derelict, starved);
  - net rates;
  - partial inputs;
  - upgrade production adding to the base;
  - a chain (wreck water feeding the agri bay) over 24 h;
  - tick over a sleep.
- `test_module_data` and `test_item_db`: production ids are bulk items, and
  every production rate is non-zero.
- `test_wallet`: costs paid from stock and inventory mixed; the trader and
  outcomes use stock.
- Integration: building an agri bay and powering it makes the chip appear
  and the amount grow after `GameClock.advance(600)`. The popover lists it,
  and after power-off it shows "Unpowered".
- Goldens: the bar changes the HUD. Re-record with `/update-goldens` after
  review.

## 6. Phases

| # | What |
|---|---|
| P1 | `ItemData.bulk`, `StationStock`, wallet in `GameState`, call sites migrated, `ration`→`food`, save v4 + migration, tests |
| P2 | `ModuleDef/UpgradeDef.production` (additive), `Production` (status, rates, tick) wired to `time_advanced`, tests |
| P3 | Content: wreck water, agri bay module + scene, hydroponics upgrade, kitchen meals, trader offers |
| P4 | `StatusBar` + `ProductionPopover`, power chip, inventory filter, debug hooks |
| P5 | Story: `produced` trigger, `rate()` condition, `first_harvest` beat |
| P6 | Docs (`CONTENT_PIPELINE.md` "Production" section, `CLAUDE.md` how-to "New resource / producer", `ROADMAP.md`), screenshots, goldens |

Later: storage caps (silos), wear → efficiency, production-chain overview
screen, Blender art for the agri bay, conversion modules (scrap → parts),
crew consuming food.
