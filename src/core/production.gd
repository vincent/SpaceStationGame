class_name Production
extends RefCounted
## Station production rules (pure, static). Every module makes and uses
## resources per game hour: `ModuleDef.production` plus the `production` of
## each installed upgrade (additive: a tier is just a bigger upgrade).
## Positive = output into the StationStock, negative = input taken from it.
##
## A module runs when it isn't derelict and is powered (or draws no power).
## Inputs are partial: it runs at min(1, available / needed) efficiency.
## Crew working there boost it (StationCrew.staffing: up to +50%), inputs
## included.
## Modules work in uid order, so a producer built earlier feeds a consumer
## built later within the same tick.

enum Status { RUNNING, STARVED, UNPOWERED, DERELICT, LOCKED }

## Probe length (hours) used to estimate live efficiencies for the UI.
const PROBE_HOURS := 1.0 / 60.0


## Nominal production of a module (def + installed upgrades), per hour.
static func base(station: StationState, uid: int) -> Dictionary[StringName, float]:
	var out: Dictionary[StringName, float] = {}
	var def := station.get_def(uid)
	if def == null:
		return out
	_add_into(out, def.production)
	for upgrade_id in station.installed(uid):
		var up := station.db.get_upgrade(upgrade_id)
		if up:
			_add_into(out, up.production)
	for id: StringName in out.keys():
		if is_zero_approx(out[id]):
			out.erase(id)
	return out


## Whether the module can run at all (ignores inputs: see `simulate`).
static func power_status(station: StationState, uid: int) -> Status:
	var rec := station.get_record(uid)
	if rec.is_empty() or rec.state == StationState.State.DERELICT:
		return Status.DERELICT
	if station.module_draw(uid) > 0.0 and not rec.powered:
		return Status.UNPOWERED
	return Status.RUNNING


## Runs every module for `hours` against `amounts` (resource -> float,
## changed in place). Returns uid -> efficiency (0..1) of each module that
## has production and can run (above 1 when staffed).
static func simulate(station: StationState, amounts: Dictionary, hours: float) -> Dictionary[int, float]:
	var efficiency: Dictionary[int, float] = {}
	if hours <= 0.0:
		return efficiency
	for uid in station.uids():
		var prod := base(station, uid)
		if prod.is_empty() or power_status(station, uid) != Status.RUNNING:
			continue
		var staff := station.crew.staffing(uid)
		var eff := staff
		for id: StringName in prod:
			if prod[id] < 0.0:
				var needed := -prod[id] * hours
				eff = minf(eff, clampf(float(amounts.get(id, 0.0)) / needed, 0.0, staff))
		for id: StringName in prod:
			amounts[id] = maxf(0.0, float(amounts.get(id, 0.0)) + prod[id] * hours * eff)
		efficiency[uid] = eff
	return efficiency


## Advances production by `minutes` on the real stock. Returns what changed
## (resource -> delta).
static func tick(station: StationState, stock: StationStock, minutes: float) -> Dictionary[StringName, float]:
	var amounts := {}
	for id in stock.ids():
		amounts[id] = stock.amount(id)
	var before := amounts.duplicate()
	simulate(station, amounts, minutes / 60.0)
	var deltas: Dictionary[StringName, float] = {}
	for id: StringName in amounts:
		var delta: float = amounts[id] - float(before.get(id, 0.0))
		if not is_zero_approx(delta):
			deltas[id] = delta
			stock.set_amount(id, amounts[id])
	return deltas


## Live efficiency of every running producer, from a short dry run on a copy
## of the stock.
static func efficiencies(station: StationState, stock: StationStock) -> Dictionary[int, float]:
	var amounts := {}
	for id in stock.ids():
		amounts[id] = stock.amount(id)
	return simulate(station, amounts, PROBE_HOURS)


## Net rate per hour of every resource (running modules at their live
## efficiency). Resources nobody produces or uses are absent.
static func rates(station: StationState, stock: StationStock) -> Dictionary[StringName, float]:
	var out: Dictionary[StringName, float] = {}
	var eff := efficiencies(station, stock)
	for uid in station.uids():
		var prod := base(station, uid)
		for id: StringName in prod:
			out[id] = out.get(id, 0.0) + prod[id] * eff.get(uid, 0.0)
	return out


## One module: {"status": Status, "rates": {resource: live rate per hour},
## "nominal": {resource: rate when running unstaffed}, "missing": input that
## starves it, "staffing": crew multiplier (1 = none)}.
## `eff` = `efficiencies()` when the caller already has it (one dry run per refresh).
static func module_rates(station: StationState, stock: StationStock, uid: int, eff: Variant = null) -> Dictionary:
	if eff == null:
		eff = efficiencies(station, stock)
	var nominal := base(station, uid)
	var status := power_status(station, uid)
	var e: float = eff.get(uid, 0.0)
	var staff := station.crew.staffing(uid)
	var missing: StringName = &""
	if status == Status.RUNNING and e < staff - 0.001:
		status = Status.STARVED
		for id: StringName in nominal:
			if nominal[id] < 0.0 and stock.amount(id) < -nominal[id] * PROBE_HOURS:
				missing = id
				break
	var live: Dictionary[StringName, float] = {}
	for id: StringName in nominal:
		live[id] = nominal[id] * e
	return {"status": status, "rates": live, "nominal": nominal, "missing": missing, "staffing": staff}


## Rows for one resource's popover: every module producing or consuming it,
## producers first, then upgrades not installed yet that would produce it
## (LOCKED). Row: {"uid", "module_id", "upgrade_id", "rate", "nominal", "status", "missing"}.
static func rows_for(station: StationState, stock: StationStock, resource: StringName) -> Array[Dictionary]:
	var producers: Array[Dictionary] = []
	var consumers: Array[Dictionary] = []
	var locked: Array[Dictionary] = []
	var eff := efficiencies(station, stock)
	for uid in station.uids():
		var info := module_rates(station, stock, uid, eff)
		var nominal: float = info.nominal.get(resource, 0.0)
		if nominal != 0.0:
			var row := {
				"uid": uid, "module_id": station.get_record(uid).module_id, "upgrade_id": &"",
				"rate": info.rates.get(resource, 0.0), "nominal": nominal,
				"status": info.status, "missing": info.missing,
			}
			(producers if nominal > 0.0 else consumers).append(row)
		for up in station.db.upgrades_for(station.get_record(uid).module_id):
			if not station.is_installed(uid, up.id) and up.production.get(resource, 0.0) > 0.0:
				locked.append({
					"uid": uid, "module_id": station.get_record(uid).module_id, "upgrade_id": up.id,
					"rate": 0.0, "nominal": up.production[resource], "status": Status.LOCKED, "missing": &"",
				})
	return producers + locked + consumers


## Game minutes until the stock of a resource changes by a whole unit at
## `rate` per hour: the next unit when rate > 0, running out (stock reaches
## 0) when rate < 0. INF when nothing changes (or nothing is left to drain).
static func eta_minutes(amount: float, rate: float) -> float:
	if rate > 0.0:
		var frac := amount - floorf(amount + 0.0001)
		return maxf(0.0, (1.0 - frac) / rate * 60.0)
	if rate < 0.0 and amount > 0.0:
		return amount / -rate * 60.0
	return INF


## True if some module (running or not) produces `resource`.
static func has_producer(station: StationState, resource: StringName) -> bool:
	for uid in station.uids():
		if base(station, uid).get(resource, 0.0) > 0.0:
			return true
	return false


static func _add_into(out: Dictionary[StringName, float], prod: Dictionary) -> void:
	for id: StringName in prod:
		out[id] = out.get(id, 0.0) + float(prod[id])
