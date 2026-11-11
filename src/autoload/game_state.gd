extends Node
## Owns the simulation state (needs, inventory, station) and the actions that
## change it (sleep, cook, use item, build, repair, power, upgrade...). Scenes
## and UI call these methods instead of poking at Needs/Inventory/StationState
## directly, so rules live in one place.

const SAVE_PATH := "user://savegame.json"
## 2: station modules (StationState) added.
const SAVE_VERSION := 2
const INVENTORY_SLOTS := 20

const STARTING_ITEMS: Dictionary[StringName, int] = {
	&"ration": 4,
	&"water": 4,
	&"scrap_metal": 12,
	&"power_cell": 2,
}

## Need decay overrides (per game hour) while doing an activity.
## Negative = the need is restored.
const ACTIVITY_RATES: Dictionary[StringName, Dictionary] = {
	&"idle": {},
	&"sleeping": {Needs.ENERGY: -12.5, Needs.FOOD: 2.0, Needs.MORALE: 0.0},
	&"stargazing": {Needs.MORALE: -20.0},
	&"cooking": {},
	&"working": {Needs.ENERGY: 9.0, Needs.FOOD: 5.0, Needs.MORALE: 0.5},
}
## Lowest decay per hour upgrades can bring a need down to.
const MIN_DECAY := 0.2

var item_db := ItemDB.new()
var module_db := ModuleDB.new()
var needs := Needs.new()
var inventory: Inventory
var station: StationState
var activity: StringName = &"idle"


func _init() -> void:
	item_db.load_dir()
	module_db.load_dirs()
	inventory = Inventory.new(item_db, INVENTORY_SLOTS)
	station = StationState.new(module_db)
	station.module_changed.connect(func(_uid: int, _reason: StringName) -> void: _apply_upgrade_effects())
	station.reset.connect(_apply_upgrade_effects)


func _ready() -> void:
	GameClock.time_advanced.connect(_on_time_advanced)
	new_game()


func new_game() -> void:
	GameClock.reset()
	needs.reset()
	inventory.clear()
	for id: StringName in STARTING_ITEMS:
		inventory.add(id, STARTING_ITEMS[id])
	activity = &"idle"
	_new_station()
	EventBus.game_reset.emit()


## Story start: the rescue capsule docked to a dark, derelict wreck.
func _new_station() -> void:
	station.clear()
	var wreck := station.add_module(&"wreck_core", 0, &"", StationState.State.DERELICT, 1.0, false)
	station.add_module(&"capsule", wreck, &"A", StationState.State.REPAIRED, 0.25, true)


## Skips `minutes` of game time while doing `activity_name`.
func spend_time(minutes: float, activity_name: StringName = &"idle") -> void:
	assert(ACTIVITY_RATES.has(activity_name), "Unknown activity %s" % activity_name)
	var previous := activity
	activity = activity_name
	GameClock.advance(minutes)
	activity = previous


func sleep(hours: float) -> void:
	spend_time(hours * GameClock.MINUTES_PER_HOUR, &"sleeping")
	EventBus.toast.emit("You slept %d h." % roundi(hours))


## Recipe-like action: consumes `cost` items, takes time, applies effects.
## Returns false (and changes nothing) if the items are missing.
func perform(cost: Dictionary, minutes: float, effects: Dictionary, activity_name: StringName = &"idle") -> bool:
	if not inventory.has_all(cost):
		return false
	for id: StringName in cost:
		inventory.remove(id, int(cost[id]))
	spend_time(minutes, activity_name)
	for need: StringName in effects:
		needs.change(need, float(effects[need]))
	return true


## Adds items (salvage, trades...). Whatever doesn't fit is lost.
func gain(items: Dictionary) -> void:
	for id: StringName in items:
		inventory.add(id, int(items[id]))


## Swaps `give` for `get_items`. False (and nothing changes) if `give` is missing.
func trade(give: Dictionary, get_items: Dictionary) -> bool:
	if not inventory.has_all(give):
		return false
	for id: StringName in give:
		inventory.remove(id, int(give[id]))
	gain(get_items)
	return true


## Ongoing activity while time flows normally (character routines).
func begin_activity(activity_name: StringName) -> void:
	assert(ACTIVITY_RATES.has(activity_name), "Unknown activity %s" % activity_name)
	activity = activity_name


func end_activity() -> void:
	activity = &"idle"


func use_item(slot_index: int) -> bool:
	var slot := inventory.get_slot(slot_index)
	if slot.is_empty():
		return false
	var item := item_db.get_item(slot.id)
	if item == null or not item.usable:
		EventBus.toast.emit("Can't use that.")
		return false
	inventory.remove_from_slot(slot_index, 1)
	for need: StringName in item.use_effects:
		needs.change(need, item.use_effects[need])
	EventBus.toast.emit("Used %s." % item.display_name)
	return true


func _on_time_advanced(minutes: float) -> void:
	needs.tick(minutes / GameClock.MINUTES_PER_HOUR, ACTIVITY_RATES.get(activity, {}))


# --- Station actions ---------------------------------------------------------

## "" when the module can be built on `slot` of `parent_uid`, else why not.
func build_error(module_id: StringName, parent_uid: int, slot: StringName) -> String:
	var def := module_db.get_module(module_id)
	if def == null or not def.buildable:
		return "Can't build that"
	var err := station.attach_error(module_id, parent_uid, slot)
	if err != "":
		return err
	if not inventory.has_all(def.build_cost):
		return "Needs %s" % format_cost(def.build_cost)
	return ""


func build_module(module_id: StringName, parent_uid: int, slot: StringName) -> int:
	if build_error(module_id, parent_uid, slot) != "":
		return 0
	var def := module_db.get_module(module_id)
	_pay(def.build_cost)
	spend_time(def.build_minutes, &"working")
	var uid := station.add_module(module_id, parent_uid, slot, StationState.State.REPAIRED, 0.3, false)
	EventBus.toast.emit("%s attached." % def.display_name)
	return uid


func repair_error(uid: int) -> String:
	var def := station.get_def(uid)
	if def == null:
		return "No such module"
	if station.get_record(uid).state != StationState.State.DERELICT:
		return "Already repaired"
	if not inventory.has_all(def.repair_cost):
		return "Needs %s" % format_cost(def.repair_cost)
	return ""


func repair_module(uid: int) -> bool:
	if repair_error(uid) != "":
		return false
	var def := station.get_def(uid)
	_pay(def.repair_cost)
	spend_time(def.repair_minutes, &"working")
	station.repair(uid)
	EventBus.toast.emit("%s repaired." % def.display_name)
	return true


## Switches a module's power. Returns false with a toast if impossible.
func toggle_power(uid: int) -> bool:
	var on := not bool(station.get_record(uid).get("powered", false))
	var err := station.power_error(uid) if on else ""
	if err != "":
		EventBus.toast.emit(err)
		return false
	return station.set_powered(uid, on)


func upgrade_error(uid: int, upgrade_id: StringName) -> String:
	var err := station.install_error(uid, upgrade_id)
	if err != "":
		return err
	var up := module_db.get_upgrade(upgrade_id)
	if not inventory.has_all(up.cost):
		return "Needs %s" % format_cost(up.cost)
	return ""


func buy_upgrade(uid: int, upgrade_id: StringName) -> bool:
	if upgrade_error(uid, upgrade_id) != "":
		return false
	var up := module_db.get_upgrade(upgrade_id)
	_pay(up.cost)
	spend_time(up.minutes, &"working")
	station.install(uid, upgrade_id)
	return true


## True if at least one buildable module is affordable (ghost slots show).
func can_afford_any_module() -> bool:
	for id in module_db.module_ids():
		var def := module_db.get_module(id)
		if def.buildable and inventory.has_all(def.build_cost):
			return true
	return false


## "4 scrap metal + 1 power cell"
func format_cost(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for id: StringName in cost:
		var item := item_db.get_item(id)
		parts.append("%d %s" % [cost[id], item.display_name.to_lower() if item else String(id)])
	return " + ".join(parts) if not parts.is_empty() else "nothing"


func _pay(cost: Dictionary) -> void:
	for id: StringName in cost:
		inventory.remove(id, int(cost[id]))


## Upgrade effects like "morale_decay" shift the needs' base decay rates.
func _apply_upgrade_effects() -> void:
	for need: StringName in Needs.DEFAULT_DECAY:
		var bonus := station.effect_total(StringName("%s_decay" % need))
		needs.decay_per_hour[need] = maxf(MIN_DECAY, Needs.DEFAULT_DECAY[need] + bonus)


# --- Save / load -------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"clock": GameClock.to_dict(),
		"needs": needs.to_dict(),
		"inventory": inventory.to_dict(),
		"station": station.to_dict(),
	}


func from_dict(data: Dictionary) -> void:
	GameClock.from_dict(data.get("clock", {}))
	needs.from_dict(data.get("needs", {}))
	inventory.from_dict(data.get("inventory", {}))
	if data.has("station"):
		station.from_dict(data.station)
	else:
		_new_station()  # version 1 saves had no station
	EventBus.game_reset.emit()


func save_game(path: String = SAVE_PATH) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Save failed: %s" % error_string(FileAccess.get_open_error()))
		return false
	file.store_string(JSON.stringify(to_dict(), "\t"))
	return true


func load_game(path: String = SAVE_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		push_error("Save file is corrupted: %s" % path)
		return false
	from_dict(data)
	return true


func has_save(path: String = SAVE_PATH) -> bool:
	return FileAccess.file_exists(path)
