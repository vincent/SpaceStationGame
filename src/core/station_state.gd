@tool
class_name StationState
extends RefCounted
## The station as data: which modules exist, where they are attached, and
## their state (derelict/repaired/upgraded), wear, power and installed parts.
## Pure logic (no nodes): the Station scene mirrors it through the signals.
##
## A record is {uid, module_id, parent, slot, own_slot, state, wear, powered,
## parts}. `parent` is 0 for the root module; `own_slot` is the module's own
## slot that meets `slot` of the parent (its orientation, see StationGrid).

signal module_added(uid: int)
## `reason`: &"repaired", &"powered", &"unpowered", &"upgraded", &"wear".
signal module_changed(uid: int, reason: StringName)
signal module_removed(uid: int)
## Everything was replaced (new game / load): rebuild from scratch.
signal reset

enum State { DERELICT, REPAIRED, UPGRADED }

## Repairs bring wear down to this; upgrades shave a bit more off.
const REPAIRED_WEAR := 0.35
const UPGRADE_WEAR_STEP := 0.08
## "Worn but cared for": wear never reaches 0.
const MIN_WEAR := 0.12

var db: ModuleDB

var _records: Dictionary[int, Dictionary] = {}
var _next_uid := 1


func _init(p_db: ModuleDB) -> void:
	db = p_db


func clear() -> void:
	_records.clear()
	_next_uid = 1
	reset.emit()


# --- Structure ---------------------------------------------------------------

## Adds a module (root when `parent_uid` is 0). Returns its uid, or 0 if the
## attachment is invalid (see `attach_error`).
func add_module(
		module_id: StringName, parent_uid: int = 0, slot: StringName = &"",
		state: State = State.REPAIRED, wear: float = 0.2, powered: bool = false,
		by_slot: StringName = &""
) -> int:
	if attach_error(module_id, parent_uid, slot, by_slot) != "":
		return 0
	var def := db.get_module(module_id)
	var uid := _next_uid
	_next_uid += 1
	_records[uid] = {
		"uid": uid, "module_id": module_id, "parent": parent_uid, "slot": slot,
		"own_slot": by_slot if by_slot != &"" else def.attach_slot,
		"state": state, "wear": clampf(wear, MIN_WEAR, 1.0), "powered": false,
		"parts": [] as Array[StringName],
	}
	module_added.emit(uid)
	if powered:
		set_powered(uid, true)
	return uid


## "" when `module_id` can attach to `slot` of `parent_uid` by its own slot
## `by_slot` (default: its attach slot), else the reason.
func attach_error(
		module_id: StringName, parent_uid: int, slot: StringName, by_slot: StringName = &""
) -> String:
	var def := db.get_module(module_id)
	if def == null:
		return "Unknown module %s" % module_id
	if parent_uid == 0:
		return ""
	if not _records.has(parent_uid):
		return "No module %d" % parent_uid
	var parent_def := get_def(parent_uid)
	var err := ""
	if not parent_def.slots.has(slot):
		err = "%s has no slot %s" % [parent_def.display_name, slot]
	elif occupant(parent_uid, slot) != 0 or (_records[parent_uid].parent != 0 and own_slot(parent_uid) == slot):
		err = "Slot is taken"
	elif not def.fits(parent_def.slots[slot]):
		err = "%s doesn't fit there" % def.display_name
	else:
		var by := by_slot if by_slot != &"" else def.attach_slot
		if not def.slots.has(by):
			err = "%s has no slot %s" % [def.display_name, by]
		elif def.slot_size(by) > parent_def.slot_size(slot):
			err = "Needs a %s hatch" % ModuleDef.SIZE_LABELS[def.slot_size(by)]
		else:
			err = StationGrid.placement_error(self, module_id, parent_uid, slot, by)
	return err


## The slots of `module_id` it can attach by on `slot` of `parent_uid`
## (its orientations), the default attach slot first.
func attach_options(module_id: StringName, parent_uid: int, slot: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	var def := db.get_module(module_id)
	if def == null:
		return out
	var names: Array[StringName] = [def.attach_slot]
	var others: Array[StringName] = def.slots.keys()
	others.sort_custom(_by_name)
	for s in others:
		if s != def.attach_slot:
			names.append(s)
	for s in names:
		if def.slots.has(s) and attach_error(module_id, parent_uid, slot, s) == "":
			out.append(s)
	return out


## The slot of `uid` used to attach it to its parent.
func own_slot(uid: int) -> StringName:
	if not _records.has(uid):
		return &""
	return _records[uid].get("own_slot", get_def(uid).attach_slot)


func remove_module(uid: int) -> void:
	if not _records.has(uid):
		return
	for child in children_of(uid):
		remove_module(child)
	_records.erase(uid)
	module_removed.emit(uid)


func has_module(uid: int) -> bool:
	return _records.has(uid)


func get_record(uid: int) -> Dictionary:
	return _records.get(uid, {})


func get_def(uid: int) -> ModuleDef:
	return db.get_module(_records[uid].module_id) if _records.has(uid) else null


## All uids, parents always before their children.
func uids() -> Array[int]:
	var out: Array[int] = _records.keys()
	out.sort()
	return out


func children_of(uid: int) -> Array[int]:
	var out: Array[int] = []
	for id in uids():
		if _records[id].parent == uid:
			out.append(id)
	return out


## uid of the module attached to `slot` of `parent_uid`, or 0.
func occupant(parent_uid: int, slot: StringName) -> int:
	for id in uids():
		if _records[id].parent == parent_uid and _records[id].slot == slot:
			return id
	return 0


func free_slots(uid: int) -> Array[StringName]:
	var out: Array[StringName] = []
	var def := get_def(uid)
	if def == null:
		return out
	var used := own_slot(uid) if _records[uid].parent != 0 else &""
	for slot: StringName in def.slots:
		if slot != used and occupant(uid, slot) == 0:
			out.append(slot)
	out.sort_custom(_by_name)
	return out


## First module of a type, or 0.
func find_module(module_id: StringName) -> int:
	for id in uids():
		if _records[id].module_id == module_id:
			return id
	return 0


# --- Power -------------------------------------------------------------------

func module_output(uid: int) -> float:
	if not _records.has(uid) or _records[uid].state == State.DERELICT:
		return 0.0
	return get_def(uid).power_output + _effect_sum(uid, &"power_output")


func module_draw(uid: int) -> float:
	if not _records.has(uid):
		return 0.0
	return get_def(uid).power_draw + _effect_sum(uid, &"power_draw")


func power_output() -> float:
	var total := 0.0
	for id in uids():
		total += module_output(id)
	return total


## Power used by the modules that are switched on.
func power_draw() -> float:
	var total := 0.0
	for id in uids():
		if _records[id].powered:
			total += module_draw(id)
	return total


func power_error(uid: int) -> String:
	if not _records.has(uid):
		return "No such module"
	if _records[uid].state == State.DERELICT:
		return "Repair it first"
	if not _records[uid].powered and power_draw() + module_draw(uid) > power_output() + 0.001:
		return "Not enough power (%s / %s)" % [_fmt(power_draw() + module_draw(uid)), _fmt(power_output())]
	return ""


func set_powered(uid: int, on: bool) -> bool:
	if not _records.has(uid) or _records[uid].powered == on:
		return false
	if on and power_error(uid) != "":
		return false
	_records[uid].powered = on
	module_changed.emit(uid, &"powered" if on else &"unpowered")
	return true


# --- Repair, wear & upgrades -------------------------------------------------

func repair(uid: int) -> bool:
	if not _records.has(uid) or _records[uid].state != State.DERELICT:
		return false
	_records[uid].state = State.REPAIRED
	_records[uid].wear = minf(_records[uid].wear, REPAIRED_WEAR)
	module_changed.emit(uid, &"repaired")
	return true


func set_wear(uid: int, value: float) -> void:
	if not _records.has(uid):
		return
	_records[uid].wear = clampf(value, MIN_WEAR, 1.0)
	module_changed.emit(uid, &"wear")


func installed(uid: int) -> Array[StringName]:
	var out: Array[StringName] = []
	if _records.has(uid):
		out.assign(_records[uid].parts)
	return out


func is_installed(uid: int, upgrade_id: StringName) -> bool:
	return installed(uid).has(upgrade_id)


## "" when the upgrade can be installed (ignoring its item cost).
func install_error(uid: int, upgrade_id: StringName) -> String:
	var up := db.get_upgrade(upgrade_id)
	if up == null or not _records.has(uid):
		return "Unknown upgrade"
	if up.module_id != _records[uid].module_id:
		return "Wrong module"
	if _records[uid].state == State.DERELICT:
		return "Repair it first"
	if is_installed(uid, upgrade_id):
		return "Installed"
	for req in up.requires:
		if not is_installed(uid, req):
			var req_def := db.get_upgrade(req)
			return "Needs %s" % (req_def.display_name if req_def else String(req))
	return ""


## Installs an upgrade once. Effects are derived from the installed list,
## so they can never be applied twice.
func install(uid: int, upgrade_id: StringName) -> bool:
	if install_error(uid, upgrade_id) != "":
		return false
	_records[uid].parts.append(upgrade_id)
	_records[uid].state = State.UPGRADED
	_records[uid].wear = clampf(_records[uid].wear - UPGRADE_WEAR_STEP, MIN_WEAR, 1.0)
	module_changed.emit(uid, &"upgraded")
	return true


## Upgrade level: number of installed parts.
func level(uid: int) -> int:
	return installed(uid).size()


## Sum of one effect over every installed upgrade of the whole station.
func effect_total(effect: StringName) -> float:
	var total := 0.0
	for id in uids():
		total += _effect_sum(id, effect)
	return total


func _effect_sum(uid: int, effect: StringName) -> float:
	var total := 0.0
	for upgrade_id in installed(uid):
		var up := db.get_upgrade(upgrade_id)
		if up:
			total += up.effects.get(effect, 0.0)
	return total


# --- Save / load -------------------------------------------------------------

## Visitors (docked ships) are transient and never saved.
func to_dict() -> Dictionary:
	var modules := []
	for id in uids():
		var r := _records[id]
		if get_def(id).kind == &"visitor":
			continue
		modules.append({
			"uid": id, "module_id": String(r.module_id), "parent": r.parent, "slot": String(r.slot),
			"own_slot": String(r.own_slot), "state": r.state, "wear": r.wear, "powered": r.powered,
			"parts": Array(r.parts).map(func(p: StringName) -> String: return String(p)),
		})
	return {"next_uid": _next_uid, "modules": modules}


func from_dict(data: Dictionary) -> void:
	_records.clear()
	for m: Dictionary in data.get("modules", []):
		var uid := int(m.get("uid", 0))
		if uid <= 0 or db.get_module(StringName(m.get("module_id", ""))) == null:
			push_warning("StationState: skipping invalid module %s" % m)
			continue
		var parts: Array[StringName] = []
		for p: String in m.get("parts", []):
			parts.append(StringName(p))
		var def := db.get_module(StringName(m.module_id))
		_records[uid] = {
			"uid": uid, "module_id": StringName(m.module_id), "parent": int(m.get("parent", 0)),
			"slot": StringName(m.get("slot", "")),
			"own_slot": StringName(m.get("own_slot", def.attach_slot)), "state": int(m.get("state", State.REPAIRED)),
			"wear": float(m.get("wear", 0.2)), "powered": bool(m.get("powered", false)), "parts": parts,
		}
	_next_uid = maxi(int(data.get("next_uid", 1)), (uids().max() if not _records.is_empty() else 0) + 1)
	reset.emit()


static func _by_name(a: StringName, b: StringName) -> bool:
	return String(a) < String(b)


static func _fmt(value: float) -> String:
	return str(snappedf(value, 0.1))
