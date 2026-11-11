class_name Inventory
extends RefCounted
## Grid of slots holding item stacks. A slot is either empty ({}) or
## {"id": StringName, "count": int}. Pure logic, UI binds to `changed`.

signal changed

var size: int
var slots: Array[Dictionary] = []
var _db: ItemDB


func _init(db: ItemDB, slot_count: int = 20) -> void:
	_db = db
	size = slot_count
	clear()


func clear() -> void:
	slots.clear()
	for i in size:
		slots.append({})
	changed.emit()


func get_slot(index: int) -> Dictionary:
	return slots[index]


func is_empty_slot(index: int) -> bool:
	return slots[index].is_empty()


## Adds items, filling existing stacks first. Returns how many did NOT fit.
func add(id: StringName, count: int = 1) -> int:
	assert(_db.has(id), "Unknown item: %s" % id)
	var remaining := count
	var max_stack := _db.max_stack(id)
	for slot in slots:
		if remaining == 0:
			break
		if not slot.is_empty() and slot.id == id and slot.count < max_stack:
			var moved := mini(remaining, max_stack - slot.count)
			slot.count += moved
			remaining -= moved
	for i in size:
		if remaining == 0:
			break
		if slots[i].is_empty():
			var moved := mini(remaining, max_stack)
			slots[i] = {"id": id, "count": moved}
			remaining -= moved
	if remaining != count:
		changed.emit()
	return remaining


## Removes `count` items. All-or-nothing: returns false and changes nothing if
## there are not enough.
func remove(id: StringName, count: int = 1) -> bool:
	if count_of(id) < count:
		return false
	var remaining := count
	for i in range(size - 1, -1, -1):
		var slot := slots[i]
		if remaining == 0:
			break
		if slot.is_empty() or slot.id != id:
			continue
		var taken := mini(remaining, slot.count)
		slot.count -= taken
		remaining -= taken
		if slot.count == 0:
			slots[i] = {}
	changed.emit()
	return true


func remove_from_slot(index: int, count: int = 1) -> bool:
	var slot := slots[index]
	if slot.is_empty() or slot.count < count:
		return false
	slot.count -= count
	if slot.count == 0:
		slots[index] = {}
	changed.emit()
	return true


func count_of(id: StringName) -> int:
	var total := 0
	for slot in slots:
		if not slot.is_empty() and slot.id == id:
			total += slot.count
	return total


func has_all(requirements: Dictionary) -> bool:
	for id: StringName in requirements:
		if count_of(id) < int(requirements[id]):
			return false
	return true


## Drag & drop: merges into a stack of the same item (up to max stack),
## otherwise swaps the two slots.
func move(from: int, to: int) -> void:
	if from == to or slots[from].is_empty():
		return
	var src := slots[from]
	var dst := slots[to]
	if not dst.is_empty() and dst.id == src.id:
		var space: int = _db.max_stack(src.id) - dst.count
		var moved := mini(space, src.count)
		dst.count += moved
		src.count -= moved
		if src.count == 0:
			slots[from] = {}
	else:
		slots[from] = dst
		slots[to] = src
	changed.emit()


func to_dict() -> Dictionary:
	var out: Array = []
	for slot in slots:
		out.append({} if slot.is_empty() else {"id": String(slot.id), "count": slot.count})
	return {"size": size, "slots": out}


func from_dict(data: Dictionary) -> void:
	size = int(data.get("size", size))
	clear()
	var saved: Array = data.get("slots", [])
	for i in mini(saved.size(), size):
		var s: Dictionary = saved[i]
		if s.is_empty() or not _db.has(StringName(s.id)):
			continue
		slots[i] = {"id": StringName(s.id), "count": int(s.count)}
	changed.emit()
