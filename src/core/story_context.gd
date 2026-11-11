class_name StoryContext
extends RefCounted
## Read-only view of the game that encounter conditions are evaluated against
## (Godot Expression with this object as base instance). Every public method
## here is a function conditions can call; `subject` is an input variable.
## Keep it read-only: conditions must never change the game.
##
##   flag("met_signal")            story flag set?
##   count("debris_seen")          story counter
##   seen("first_signal")          times an encounter fired
##   hours_since("first_signal")   game hours since it last fired (INF if never)
##   item("scrap_metal")           items carried
##   has_item("scrap_metal", 5)    at least that many
##   has_module("hab_pod")         a module of that type exists
##   repaired("wreck_core")        exists and isn't derelict
##   powered("wreck_core")         exists and switched on
##   has_upgrade("wreck_dish")     installed on any module
##   power()                       spare power (output - draw)
##   need("morale")                0..100
##   day(), hour()                 game clock
##   chance(0.3)                   random roll (prefer EncounterDef.chance)

const INPUTS: PackedStringArray = ["subject"]

var story: StoryState
var inventory: Inventory
var station: StationState
var needs: Needs
var rng := RandomNumberGenerator.new()

var _cache: Dictionary[String, Expression] = {}


func _init(p_story: StoryState, p_inventory: Inventory, p_station: StationState, p_needs: Needs) -> void:
	story = p_story
	inventory = p_inventory
	station = p_station
	needs = p_needs
	rng.randomize()


## True if `condition` holds ("" always does). Errors count as false and
## are reported once.
func evaluate(condition: String, subject: StringName = &"") -> bool:
	if condition.strip_edges() == "":
		return true
	var expr := _parse(condition)
	if expr == null:
		return false
	var result: Variant = expr.execute([String(subject)], self, false)
	if expr.has_execute_failed():
		push_error("Encounter condition failed: '%s': %s" % [condition, expr.get_error_text()])
		return false
	return bool(result)


## "" if the condition parses and runs (on the current state), else why not.
func check_expression(condition: String) -> String:
	if condition.strip_edges() == "":
		return ""
	var expr := Expression.new()
	if expr.parse(condition, INPUTS) != OK:
		return "'%s': %s" % [condition, expr.get_error_text()]
	expr.execute([""], self, false)
	if expr.has_execute_failed():
		return "'%s': %s" % [condition, expr.get_error_text()]
	return ""


func _parse(condition: String) -> Expression:
	if _cache.has(condition):
		return _cache[condition]
	var expr := Expression.new()
	if expr.parse(condition, INPUTS) != OK:
		push_error("Encounter condition doesn't parse: '%s': %s" % [condition, expr.get_error_text()])
		expr = null
	_cache[condition] = expr
	return expr


# --- Functions available to conditions ---------------------------------------

func flag(name: String) -> bool:
	return story.flag(StringName(name))


func count(name: String) -> int:
	return story.count(StringName(name))


func seen(id: String) -> int:
	return story.times_seen(StringName(id))


func hours_since(id: String) -> float:
	var last := story.last_seen(StringName(id))
	return INF if last == -INF else (GameClock.total_minutes - last) / GameClock.MINUTES_PER_HOUR


func item(id: String) -> int:
	return inventory.count_of(StringName(id))


func has_item(id: String, amount: int) -> bool:
	return inventory.count_of(StringName(id)) >= amount


func has_module(module_id: String) -> bool:
	return station.find_module(StringName(module_id)) != 0


func repaired(module_id: String) -> bool:
	var uid := station.find_module(StringName(module_id))
	return uid != 0 and station.get_record(uid).state != StationState.State.DERELICT


func powered(module_id: String) -> bool:
	var uid := station.find_module(StringName(module_id))
	return uid != 0 and bool(station.get_record(uid).powered)


func has_upgrade(upgrade_id: String) -> bool:
	for uid in station.uids():
		if station.is_installed(uid, StringName(upgrade_id)):
			return true
	return false


func power() -> float:
	return station.power_output() - station.power_draw()


func need(name: String) -> float:
	return needs.get_value(StringName(name))


func day() -> int:
	return GameClock.day()


func hour() -> int:
	return GameClock.hour()


func chance(p: float) -> bool:
	return rng.randf() < p
