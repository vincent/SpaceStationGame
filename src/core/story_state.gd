class_name StoryState
extends RefCounted
## Story memory, saved with the game: counters (a flag is a counter > 0),
## when each encounter last fired and how often, and scheduled follow-ups.
## Pure data; GameState drives it.

## name -> int
var counters: Dictionary[StringName, int] = {}
## encounter id -> {"count": int, "last": float (game minutes)}
var seen: Dictionary[StringName, Dictionary] = {}
## [{"id": StringName, "at": float (game minutes)}], sorted by "at".
var scheduled: Array[Dictionary] = []


func clear() -> void:
	counters.clear()
	seen.clear()
	scheduled.clear()


func flag(name: StringName) -> bool:
	return counters.get(name, 0) > 0


func set_flag(name: StringName, on: bool = true) -> void:
	if on:
		counters[name] = maxi(1, counters.get(name, 0))
	else:
		counters.erase(name)


func count(name: StringName) -> int:
	return counters.get(name, 0)


func add(name: StringName, delta: int) -> void:
	counters[name] = counters.get(name, 0) + delta


func mark_seen(id: StringName, now: float) -> void:
	var rec: Dictionary = seen.get(id, {"count": 0, "last": now})
	rec.count = int(rec.count) + 1
	rec.last = now
	seen[id] = rec


func times_seen(id: StringName) -> int:
	return int(seen.get(id, {}).get("count", 0))


## Game minutes of the last firing, or -INF.
func last_seen(id: StringName) -> float:
	return float(seen.get(id, {}).get("last", -INF))


func schedule(id: StringName, at: float) -> void:
	scheduled.append({"id": id, "at": at})
	scheduled.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.at < b.at)


## Removes and returns the ids whose time has come, earliest first.
func pop_due(now: float) -> Array[StringName]:
	var out: Array[StringName] = []
	while not scheduled.is_empty() and float(scheduled[0].at) <= now:
		out.append(StringName(scheduled.pop_front().id))
	return out


func to_dict() -> Dictionary:
	var c := {}
	for k: StringName in counters:
		c[String(k)] = counters[k]
	var s := {}
	for k: StringName in seen:
		s[String(k)] = {"count": seen[k].count, "last": seen[k].last}
	return {
		"counters": c, "seen": s,
		"scheduled": scheduled.map(func(e: Dictionary) -> Dictionary: return {"id": String(e.id), "at": e.at}),
	}


func from_dict(data: Dictionary) -> void:
	clear()
	for k: String in data.get("counters", {}):
		counters[StringName(k)] = int(data.counters[k])
	for k: String in data.get("seen", {}):
		var rec: Dictionary = data.seen[k]
		seen[StringName(k)] = {"count": int(rec.get("count", 1)), "last": float(rec.get("last", 0.0))}
	for e: Dictionary in data.get("scheduled", []):
		schedule(StringName(e.get("id", "")), float(e.get("at", 0.0)))
