class_name Needs
extends RefCounted
## The character's basic needs. Every need is a value from 0 (desperate) to
## 100 (fully satisfied) that decays over game time.
## Pure logic: no nodes, no autoloads, so it is easy to unit test.

signal changed(need: StringName, value: float)
## Emitted when a need drops below CRITICAL (once per crossing).
signal became_critical(need: StringName)

const MAX := 100.0
const CRITICAL := 15.0

const FOOD := &"food"
const ENERGY := &"energy"
const MORALE := &"morale"

## Loss per game hour when nothing special is happening.
const DEFAULT_DECAY: Dictionary[StringName, float] = {
	FOOD: 4.0,
	ENERGY: 5.0,
	MORALE: 1.5,
}

var values: Dictionary[StringName, float] = {}
var decay_per_hour: Dictionary[StringName, float] = {}


func _init() -> void:
	reset()


func reset() -> void:
	decay_per_hour = DEFAULT_DECAY.duplicate()
	for need: StringName in DEFAULT_DECAY:
		values[need] = MAX
		changed.emit(need, MAX)


func names() -> Array[StringName]:
	return values.keys()


func get_value(need: StringName) -> float:
	return values.get(need, 0.0)


func set_value(need: StringName, value: float) -> void:
	assert(values.has(need), "Unknown need: %s" % need)
	var old: float = values[need]
	var new_value := clampf(value, 0.0, MAX)
	if is_equal_approx(old, new_value):
		return
	values[need] = new_value
	changed.emit(need, new_value)
	if old >= CRITICAL and new_value < CRITICAL:
		became_critical.emit(need)


func change(need: StringName, delta: float) -> void:
	set_value(need, get_value(need) + delta)


## Applies `hours` of decay. `rate_overrides` replaces the per-hour decay of
## some needs during an activity; negative decay means the need is restored
## (e.g. sleeping: {ENERGY: -12.5}).
func tick(hours: float, rate_overrides: Dictionary = {}) -> void:
	for need: StringName in values:
		var rate: float = rate_overrides.get(need, decay_per_hour.get(need, 0.0))
		change(need, -rate * hours)


func is_critical(need: StringName) -> bool:
	return get_value(need) < CRITICAL


func to_dict() -> Dictionary:
	var out := {}
	for need: StringName in values:
		out[String(need)] = values[need]
	return out


func from_dict(data: Dictionary) -> void:
	for key: String in data:
		if values.has(StringName(key)):
			set_value(StringName(key), float(data[key]))
