extends Node
## Station time. The base unit is the game minute (stored as a float).
## Time flows continuously at `minutes_per_second` while not paused, and can
## jump forward with `advance()` (sleeping, cooking, waiting...).

## Fired on every change, with the number of game minutes that elapsed.
## Simulation systems (needs, machines...) listen to this one.
signal time_advanced(minutes: float)
## Fired at most once per advance, when the displayed minute changes.
signal minute_changed(total_minutes: int)
## Fired once for every hour boundary crossed (a long sleep fires several).
signal hour_passed(total_hours: int)
## Fired once for every day boundary crossed. `day` is 1-based.
signal day_passed(day: int)

const MINUTES_PER_HOUR := 60
const HOURS_PER_DAY := 24
const MINUTES_PER_DAY := MINUTES_PER_HOUR * HOURS_PER_DAY
## New games start on day 1 at 08:00.
const START_MINUTES := 8.0 * MINUTES_PER_HOUR

## Game minutes per real second. 1.0 = one in-game day lasts 24 real minutes.
@export var minutes_per_second: float = 1.0
var paused: bool = false
var total_minutes: float = START_MINUTES


func _process(delta: float) -> void:
	if paused or minutes_per_second <= 0.0:
		return
	advance(delta * minutes_per_second)


## Moves time forward by `minutes` game minutes and emits the matching signals.
func advance(minutes: float) -> void:
	if minutes <= 0.0:
		return
	var before := total_minutes
	total_minutes += minutes
	time_advanced.emit(minutes)
	_emit_boundaries(before, total_minutes)


func reset() -> void:
	total_minutes = START_MINUTES
	paused = false


## 1-based day number.
func day() -> int:
	return floori(total_minutes / MINUTES_PER_DAY) + 1


func hour() -> int:
	return floori(total_minutes / MINUTES_PER_HOUR) % HOURS_PER_DAY


func minute() -> int:
	return floori(total_minutes) % MINUTES_PER_HOUR


func is_night() -> bool:
	var h := hour()
	return h < 6 or h >= 22


## "Day 3 · 07:05"
func format_time() -> String:
	return "Day %d · %02d:%02d" % [day(), hour(), minute()]


func to_dict() -> Dictionary:
	return {"total_minutes": total_minutes, "minutes_per_second": minutes_per_second}


func from_dict(data: Dictionary) -> void:
	total_minutes = float(data.get("total_minutes", START_MINUTES))
	minutes_per_second = float(data.get("minutes_per_second", 1.0))


func _emit_boundaries(before: float, after: float) -> void:
	var m0 := floori(before)
	var m1 := floori(after)
	if m1 == m0:
		return
	minute_changed.emit(m1)
	for h in range(floori(before / MINUTES_PER_HOUR) + 1, floori(after / MINUTES_PER_HOUR) + 1):
		hour_passed.emit(h)
	for d in range(floori(before / MINUTES_PER_DAY) + 1, floori(after / MINUTES_PER_DAY) + 1):
		day_passed.emit(d + 1)
