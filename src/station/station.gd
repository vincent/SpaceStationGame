class_name Station
extends Node3D
## Scene mirror of GameState.station (StationState): instantiates module
## scenes, snaps them slot to slot, links their navigation, shows ghost
## outlines on empty slots, and plays state changes on the modules.

signal module_attached(module: Module)
## The station's bounding box changed (camera framing).
signal layout_changed

const GHOST_SHADER := preload("res://assets/shaders/ghost.gdshader")

var state: StationState
var modules: Dictionary[int, Module] = {}

var _links: Dictionary[int, NavigationLink3D] = {}
var _ghosts: Node3D
var _preview: MeshInstance3D
var _ghost_material: ShaderMaterial


func _ready() -> void:
	_ghosts = Node3D.new()
	_ghosts.name = "Ghosts"
	add_child(_ghosts)
	_ghost_material = ShaderMaterial.new()
	_ghost_material.shader = GHOST_SHADER
	_preview = MeshInstance3D.new()
	_preview.name = "BuildPreview"
	_preview.material_override = _ghost_material
	_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_preview)
	EventBus.build_preview.connect(show_build_preview)


## Starts mirroring `p_state` (usually GameState.station).
func bind(p_state: StationState) -> void:
	if state:
		state.module_added.disconnect(_on_module_added)
		state.module_changed.disconnect(_on_module_changed)
		state.module_removed.disconnect(_on_module_removed)
		state.reset.disconnect(rebuild)
	state = p_state
	state.module_added.connect(_on_module_added)
	state.module_changed.connect(_on_module_changed)
	state.module_removed.connect(_on_module_removed)
	state.reset.connect(rebuild)
	if not GameState.inventory.changed.is_connected(refresh_ghosts):
		GameState.inventory.changed.connect(refresh_ghosts)
		GameState.stock.count_changed.connect(func(_id: StringName, _n: int) -> void: refresh_ghosts())
	rebuild()


func rebuild() -> void:
	for module: Module in modules.values():
		module.free()
	for link: NavigationLink3D in _links.values():
		link.free()
	modules.clear()
	_links.clear()
	for uid in state.uids():
		_spawn(uid, false)
	refresh_ghosts()
	layout_changed.emit()


func get_module(uid: int) -> Module:
	return modules.get(uid)


func find_module(module_id: StringName) -> Module:
	for module: Module in modules.values():
		if module.def and module.def.id == module_id:
			return module
	return null


## The module whose hull contains `world_pos` (null if outside every hull).
## The module containing `world_pos`. Bounds can nest (a ship docked inside a
## big module's box, e.g. the trader at the wreck), so the smallest wins.
func module_at(world_pos: Vector3) -> Module:
	var best: Module = null
	var best_volume := INF
	for module: Module in modules.values():
		var box := module.get_world_aabb().grow(0.05)
		if box.has_point(world_pos) and box.get_volume() < best_volume:
			best = module
			best_volume = box.get_volume()
	return best


func get_aabb() -> AABB:
	var out := AABB()
	var first := true
	for module: Module in modules.values():
		out = module.get_rest_aabb() if first else out.merge(module.get_rest_aabb())
		first = false
	return out


## The player's spawn: the first module with a "P" cell.
func spawn_position() -> Vector3:
	for uid in state.uids():
		var p := modules[uid].get_spawn_position()
		if p != Vector3.INF:
			return p
	return Vector3.ZERO


## Snaps `module` onto `slot` (its own attach slot meets the target slot),
## opens both doorways and links their navigation.
func attach(module: Module, slot: Slot) -> void:
	var own := module.get_attach_slot()
	assert(own != null, "%s has no attach slot" % module.name)
	module.global_transform = slot.mate_transform(own)
	module.rest_transform = module.global_transform
	slot.occupied_by = module
	own.occupied_by = slot.module
	slot.module.set_slot_open(slot.slot_name, true)
	module.set_slot_open(own.slot_name, true)
	module.refresh_world_params()

	var link := NavigationLink3D.new()
	link.name = "Link_%d" % module.uid
	link.bidirectional = true
	add_child(link)
	link.global_transform = Transform3D.IDENTITY
	link.start_position = slot.module.rest_transform * slot.door_position
	link.end_position = module.to_global(own.door_position)
	_links[module.uid] = link
	module_attached.emit(module)


func detach(module: Module) -> void:
	var own := module.get_attach_slot()
	if own and own.occupied_by:
		var parent_slot: Slot = null
		for s: Slot in own.occupied_by.slots.values():
			if s.occupied_by == module:
				parent_slot = s
		if parent_slot:
			parent_slot.occupied_by = null
			parent_slot.module.set_slot_open(parent_slot.slot_name, false)
	if _links.has(module.uid):
		_links[module.uid].queue_free()
		_links.erase(module.uid)


# --- Ghost slots -------------------------------------------------------------

## Dashed outlines on free slots that can take a module, when the player can
## afford at least one buildable module.
func refresh_ghosts() -> void:
	if _ghosts == null:
		return
	for child in _ghosts.get_children():
		child.queue_free()
	if state == null or not GameState.can_afford_any_module():
		return
	for uid in state.uids():
		var module: Module = modules.get(uid)
		if module == null or state.get_record(uid).state == StationState.State.DERELICT:
			continue
		for slot_name in state.free_slots(uid):
			var slot: Slot = module.slots.get(slot_name)
			if slot == null:
				continue
			var box := _ghost_box(uid, slot)
			if box.has_volume():
				_ghosts.add_child(_make_ghost(uid, slot_name, box))


## Station-local outline of the smallest buildable module that fits `slot`
## (empty AABB when none does). Uses the real placement (StationGrid), so the
## ghost sits on the station plane and never cuts into a neighbour.
func _ghost_box(uid: int, slot: Slot) -> AABB:
	var best := AABB()
	for def in GameState.module_db.buildable_for(slot.accepts, slot.size_class):
		var options := state.attach_options(def.id, uid, slot.slot_name)
		if options.is_empty():
			continue
		var box := _footprint_box(def, uid, slot.slot_name, options[0])
		if not best.has_volume() or box.size.x * box.size.z < best.size.x * best.size.z:
			best = box
	return best


## Station-local bounding box `def` would occupy on `slot` of `parent_uid`,
## attached by its own slot `by_slot`.
func _footprint_box(def: ModuleDef, parent_uid: int, slot: StringName, by_slot: StringName) -> AABB:
	var xform := StationGrid.mate(StationGrid.transforms(state)[parent_uid], state.get_def(parent_uid), slot, def, by_slot)
	var rects := StationGrid.world_rects(def, xform)
	var r: Rect2 = rects[0]
	for other in rects:
		r = r.merge(other)
	var bottom := HullMesher.KEEL_BOTTOM
	var height := Module.WALL_HEIGHT - bottom + HullMesher.ROOF_THICKNESS
	return AABB(Vector3(r.position.x, bottom, r.position.y), Vector3(r.size.x, height, r.size.y))


## Outlines the footprint `module_id` would take on `slot` of `parent_uid`,
## attached by its own slot `by_slot` (empty `module_id`: hide).
func show_build_preview(module_id: StringName, parent_uid: int, slot: StringName, by_slot: StringName) -> void:
	var def := GameState.module_db.get_module(module_id)
	if def == null or not state.has_module(parent_uid):
		_preview.mesh = null
		return
	var kit := MeshKit.new()
	kit.box_edges(_footprint_box(def, parent_uid, slot, by_slot), 0.09, Color.WHITE)
	_preview.mesh = kit.commit()


func _make_ghost(uid: int, slot_name: StringName, box: AABB) -> Node3D:
	var ghost := Node3D.new()
	ghost.name = "Ghost_%d_%s" % [uid, slot_name]
	var kit := MeshKit.new()
	kit.box_edges(box, 0.09, Color.WHITE)
	var mesh := MeshInstance3D.new()
	mesh.mesh = kit.commit()
	mesh.material_override = _ghost_material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ghost.add_child(mesh)
	var area := Area3D.new()
	area.collision_layer = Layers.MODULE_PICK
	area.collision_mask = 0
	area.monitoring = false
	area.set_meta(&"ghost_parent_uid", uid)
	area.set_meta(&"ghost_slot", slot_name)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	col.shape = shape
	col.position = box.get_center()
	area.add_child(col)
	ghost.add_child(area)
	return ghost


# --- StationState mirroring --------------------------------------------------

func _spawn(uid: int, animate: bool) -> Module:
	var def := state.get_def(uid)
	var scene := load(def.scene_path) as PackedScene
	var module := scene.instantiate() as Module
	module.uid = uid
	module.def = def
	module.attach_slot_name = state.own_slot(uid)
	module.name = "Module_%s_%d" % [def.id, uid]
	add_child(module)
	module.build()
	modules[uid] = module
	module.rest_transform = module.global_transform
	var rec := state.get_record(uid)
	if rec.parent != 0 and modules.has(rec.parent):
		var parent_slot: Slot = modules[rec.parent].slots.get(rec.slot)
		if parent_slot:
			attach(module, parent_slot)
		else:
			push_error("Station: %s has no slot %s" % [modules[rec.parent].name, rec.slot])
	module.refresh_world_params()
	module.apply_record(rec, false)
	module.bake_navigation()
	if animate and def.kind != &"visitor":  # visitors fly in (VisitorDirector)
		_play_arrival(module)
	return module


## A freshly built module drops into place with a small squash.
func _play_arrival(module: Module) -> void:
	var rest := module.global_transform
	module.global_position = rest.origin + Vector3(0, 6, 0)
	var tween := module.create_tween()
	tween.tween_property(module, "global_position", rest.origin, 0.6).set_trans(Tween.TRANS_BACK)
	tween.tween_callback(func() -> void:
		module.sync_navigation_transform()
		EventBus.sfx.emit(&"snap"))
	# Navigation and links were computed at the rest transform already.


func _on_module_added(uid: int) -> void:
	if modules.has(uid):
		return
	_spawn(uid, true)
	refresh_ghosts()
	layout_changed.emit()


func _on_module_changed(uid: int, _reason: StringName) -> void:
	var module: Module = modules.get(uid)
	if module:
		module.apply_record(state.get_record(uid), true)
	refresh_ghosts()


func _on_module_removed(uid: int) -> void:
	var module: Module = modules.get(uid)
	if module == null:
		return
	detach(module)
	modules.erase(uid)
	module.queue_free()
	refresh_ghosts()
	layout_changed.emit()
