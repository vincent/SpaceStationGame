class_name StationGrid
extends RefCounted
## Station placement maths, scene-free (works on ModuleDef + StationState only).
##
## Every module has a plan footprint (rectangles in its local XZ plane, metres)
## and slot frames (local position + yaw, +Z out of the module). A child is
## placed so that its own slot meets the parent's slot face to face, exactly
## like Slot.mate_transform() does in the scene, so the two always agree
## (test_module_data checks the frames against the module scenes).
##
## Footprint: `ModuleDef.massing` when set (imported art), else the layout's
## non-space cells, using HullMesher's thin outer walls. Plan only: parts
## floating above the modules' roofs are left out of `massing`.

## Footprints may touch; they overlap only beyond this (m).
const TOLERANCE := 0.05
## Size of the spatial hash cells (m) used to find a footprint's neighbours.
const BUCKET := 8.0


## Per-def cache of slot_frames() / footprint() (parsing the layout is slow and
## placement checks call them O(modules) times):
## instance id -> [layout, slot_frames, massing, frames, rects]. An entry is
## recomputed when the def's layout, slot frames or massing were replaced.
static var _cache: Dictionary[int, Array] = {}


static func _cached(def: ModuleDef) -> Array:
	var entry: Array = _cache.get(def.get_instance_id(), [])
	if entry.is_empty() or entry[0] != def.layout or not is_same(entry[1], def.slot_frames) \
			or not is_same(entry[2], def.massing):
		entry = [def.layout, def.slot_frames, def.massing, _compute_slot_frames(def), _compute_footprint(def)]
		_cache[def.get_instance_id()] = entry
	return entry


## Slot letter -> local frame (origin at the doorway's outer face + Slot.GAP,
## basis z pointing out of the module). Shared (cached): don't modify.
static func slot_frames(def: ModuleDef) -> Dictionary[StringName, Transform3D]:
	return _cached(def)[3]


static func _compute_slot_frames(def: ModuleDef) -> Dictionary[StringName, Transform3D]:
	var out: Dictionary[StringName, Transform3D] = {}
	var grid := StationBuilder.parse(def.layout)
	var offset := _offset(grid)
	var cells := {}
	for z in grid.size():
		for x in grid[z].length():
			var c := grid[z][x]
			if StationBuilder.SLOT_LETTERS.contains(c):
				var slot_name := StringName(c.to_upper())
				if not cells.has(slot_name):
					cells[slot_name] = []
				cells[slot_name].append(Vector2i(x, z))
	for slot_name: StringName in cells:
		var list: Array = cells[slot_name]
		var centre := Vector2.ZERO
		for cell: Vector2i in list:
			centre += Vector2(cell)
		centre /= list.size()
		var out2 := outward(grid, list[0])
		var out3 := Vector3(out2.x, 0, out2.y)
		var door := offset + Vector3(centre.x * StationBuilder.CELL, 0, centre.y * StationBuilder.CELL)
		out[slot_name] = frame(door + out3 * (StationBuilder.CELL * 0.5 + Slot.GAP), atan2(out3.x, out3.z))
	for slot_name: StringName in def.slot_frames:
		var f: Vector3 = def.slot_frames[slot_name]
		out[slot_name] = frame(Vector3(f.x, 0, f.y), deg_to_rad(f.z))
	return out


static func frame(pos: Vector3, yaw: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), pos)


## Direction from a boundary cell towards outer space.
static func outward(grid: PackedStringArray, cell: Vector2i) -> Vector2i:
	for dir: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if HullMesher.cell_char(grid, cell + dir) == " ":
			return dir
	return Vector2i.DOWN


## Local plan footprint (x -> Rect2.x, z -> Rect2.y).
static func footprint(def: ModuleDef) -> Array[Rect2]:
	return _cached(def)[4]


static func _compute_footprint(def: ModuleDef) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if not def.massing.is_empty():
		out.assign(def.massing)
		return out
	var grid := StationBuilder.parse(def.layout)
	var lines := HullMesher.edge_lines(grid, StationBuilder.CELL, _offset(grid))
	var xs: PackedFloat32Array = lines.x
	var zs: PackedFloat32Array = lines.z
	for z in grid.size():
		for x in grid[z].length():
			if grid[z][x] != " ":
				out.append(Rect2(xs[x], zs[z], xs[x + 1] - xs[x], zs[z + 1] - zs[z]))
	return out


## World transform of a child module whose `own_slot` meets `parent_slot`.
## Same formula as Slot.mate_transform().
static func mate(parent_xform: Transform3D, parent_def: ModuleDef, parent_slot: StringName,
		def: ModuleDef, own_slot: StringName) -> Transform3D:
	var flip := Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	return parent_xform * slot_frames(parent_def)[parent_slot] * flip * slot_frames(def)[own_slot].inverse()


## uid -> world transform of every module (root at the origin).
## World transform of every module (cached on the state until its structure
## changes: shared, don't modify).
static func transforms(state: StationState) -> Dictionary[int, Transform3D]:
	if state.placement_cache.has(&"transforms"):
		return state.placement_cache[&"transforms"]
	var out: Dictionary[int, Transform3D] = {}
	for uid in state.uids():  # parents always come first
		var rec := state.get_record(uid)
		if rec.parent == 0 or not out.has(rec.parent):
			out[uid] = Transform3D.IDENTITY
			continue
		var parent_def := state.get_def(rec.parent)
		var def := state.get_def(uid)
		var own := state.own_slot(uid)
		if not slot_frames(parent_def).has(rec.slot) or not slot_frames(def).has(own):
			out[uid] = Transform3D.IDENTITY
			continue
		out[uid] = mate(out[rec.parent], parent_def, rec.slot, def, own)
	state.placement_cache[&"transforms"] = out
	return out


static func world_rects(def: ModuleDef, xform: Transform3D) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for r in footprint(def):
		var a := xform * Vector3(r.position.x, 0, r.position.y)
		var b := xform * Vector3(r.end.x, 0, r.end.y)
		out.append(Rect2(Vector2(a.x, a.z), Vector2.ZERO).expand(Vector2(b.x, b.z)))
	return out


static func overlaps(a: Array[Rect2], b: Array[Rect2]) -> bool:
	for ra in a:
		var shrunk := ra.grow(-TOLERANCE)
		for rb in b:
			if shrunk.intersects(rb.grow(-TOLERANCE)):
				return true
	return false


## "" when the module fits there in plan, else the reason. Visitors (docked
## ships) neither block nor get blocked: they come and go.
static func placement_error(state: StationState, module_id: StringName, parent_uid: int,
		slot: StringName, own_slot: StringName) -> String:
	var def := state.db.get_module(module_id)
	var parent_def := state.get_def(parent_uid)
	if not slot_frames(def).has(own_slot):
		return "%s has no slot %s" % [def.display_name, own_slot]
	if not slot_frames(parent_def).has(slot):
		return "%s has no slot %s" % [parent_def.display_name, slot]
	if def.kind == &"visitor":
		return ""
	var all := transforms(state)
	var xform := mate(all[parent_uid], parent_def, slot, def, own_slot)
	var yaw := xform.basis.get_euler().y
	if absf(fposmod(yaw + PI / 4.0, PI / 2.0) - PI / 4.0) > 0.01:
		return "Slots don't line up"
	var rects := world_rects(def, xform)
	var box := bounds(rects).grow(-TOLERANCE)
	var placed := _placed_rects(state)
	for uid in _nearby(state, box):
		var entry: Array = placed[uid]  # [bounds, rects]
		if box.intersects(entry[0]) and overlaps(rects, entry[1]):
			return "Blocked by %s" % state.get_def(uid).display_name
	return ""


## uid -> [bounds, world rects] of every non-visitor module, and the spatial
## hash of their bounds (cached on the state until its structure changes).
static func _placed_rects(state: StationState) -> Dictionary:
	if state.placement_cache.has(&"rects"):
		return state.placement_cache[&"rects"]
	var all := transforms(state)
	var out := {}
	var buckets := {}
	for uid in all:
		var def := state.get_def(uid)
		if def.kind == &"visitor":
			continue
		var rects := world_rects(def, all[uid])
		var box := bounds(rects)
		out[uid] = [box, rects]
		for cell in _cells(box):
			if not buckets.has(cell):
				buckets[cell] = [] as Array[int]
			buckets[cell].append(uid)
	state.placement_cache[&"rects"] = out
	state.placement_cache[&"buckets"] = buckets
	return out


## Modules whose bounds share a hash cell with `box`, in uid order.
static func _nearby(state: StationState, box: Rect2) -> Array[int]:
	_placed_rects(state)
	var buckets: Dictionary = state.placement_cache[&"buckets"]
	var found := {}
	for cell in _cells(box):
		for uid: int in buckets.get(cell, []):
			found[uid] = true
	var out: Array[int] = []
	out.assign(found.keys())
	out.sort()
	return out


static func _cells(box: Rect2) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var lo := Vector2i((box.position / BUCKET).floor())
	var hi := Vector2i((box.end / BUCKET).floor())
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			out.append(Vector2i(x, y))
	return out


## Bounding rectangle of `rects` (empty Rect2 when there are none).
static func bounds(rects: Array[Rect2]) -> Rect2:
	var out := rects[0] if not rects.is_empty() else Rect2()
	for r in rects:
		out = out.merge(r)
	return out


static func _offset(grid: PackedStringArray) -> Vector3:
	var size := HullMesher.grid_size(grid)
	return -Vector3((size.x - 1) * StationBuilder.CELL * 0.5, 0.0, (size.y - 1) * StationBuilder.CELL * 0.5)
