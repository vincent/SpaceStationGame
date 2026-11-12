class_name StationStock
extends RefCounted
## The station's stockpile of bulk resources (items with `bulk = true`:
## scrap, water, food...). Amounts are fractional so slow production rates
## accumulate; the UI shows them floored. No storage cap (yet).
## Pure logic: Production fills and drains it, GameState's wallet spends it.

## Any change (fires every game minute while something produces).
signal changed(id: StringName, amount: float)
## The whole-unit count changed: what costs and most UI care about.
signal count_changed(id: StringName, count: int)

## Tolerance for float drift: 2.9999999 scrap counts as 3.
const EPSILON := 0.0001

var _amounts: Dictionary[StringName, float] = {}


func clear() -> void:
	var ids := _amounts.keys()
	_amounts.clear()
	for id: StringName in ids:
		changed.emit(id, 0.0)
		count_changed.emit(id, 0)


func amount(id: StringName) -> float:
	return _amounts.get(id, 0.0)


## Whole units available (what the player sees).
func count(id: StringName) -> int:
	return floori(amount(id) + EPSILON)


func set_amount(id: StringName, value: float) -> void:
	value = maxf(value, 0.0)
	if is_equal_approx(value, amount(id)) and _amounts.has(id):
		return
	var before := count(id)
	var is_new := not _amounts.has(id)
	_amounts[id] = value
	changed.emit(id, value)
	if count(id) != before or is_new:
		count_changed.emit(id, count(id))


func add(id: StringName, value: float) -> void:
	if value != 0.0:
		set_amount(id, amount(id) + value)


## Removes `value`. All-or-nothing: false (and no change) if there's not enough.
func remove(id: StringName, value: float) -> bool:
	if amount(id) + EPSILON < value:
		return false
	set_amount(id, amount(id) - value)
	return true


func has_all(cost: Dictionary) -> bool:
	for id: StringName in cost:
		if amount(id) + EPSILON < float(cost[id]):
			return false
	return true


## Every resource ever stocked (even at 0), sorted.
func ids() -> Array[StringName]:
	var out: Array[StringName] = _amounts.keys()
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out


func to_dict() -> Dictionary:
	var out := {}
	for id in ids():
		out[String(id)] = _amounts[id]
	return out


func from_dict(data: Dictionary) -> void:
	clear()
	for id: String in data:
		set_amount(StringName(id), float(data[id]))
