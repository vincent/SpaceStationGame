extends Node
## Owns the simulation state (needs, inventory) and the actions that change it
## (sleep, cook, use item...). Scenes and UI call these methods instead of
## poking at Needs/Inventory directly, so rules live in one place.

const SAVE_PATH := "user://savegame.json"
const SAVE_VERSION := 1
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
}

var item_db := ItemDB.new()
var needs := Needs.new()
var inventory: Inventory
var activity: StringName = &"idle"


func _init() -> void:
	item_db.load_dir()
	inventory = Inventory.new(item_db, INVENTORY_SLOTS)


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
	EventBus.game_reset.emit()


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


# --- Save / load -------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"clock": GameClock.to_dict(),
		"needs": needs.to_dict(),
		"inventory": inventory.to_dict(),
	}


func from_dict(data: Dictionary) -> void:
	GameClock.from_dict(data.get("clock", {}))
	needs.from_dict(data.get("needs", {}))
	inventory.from_dict(data.get("inventory", {}))
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
