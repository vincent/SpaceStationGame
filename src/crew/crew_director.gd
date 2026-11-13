class_name CrewDirector
extends Node3D
## Mirrors the crew (GameState.station.crew) as CrewNPC nodes and hands them
## spots to go to: their bunk at night, a workstation in their job module, a
## kitchen at meal times, free floor to wander. Spots are claimed so two
## NPCs never share one. Also hides NPCs standing in closed modules (the
## cutaway only draws the open interior) and snaps them into place after a
## time skip.

const NPC_SCENE := preload("res://src/crew/crew_npc.tscn")
## Time skips longer than this (game minutes) teleport NPCs to their spot.
const SNAP_MINUTES := 30.0
const VISIBILITY_SECONDS := 0.25

@export var station: Station

var npcs: Dictionary[int, CrewNPC] = {}

## Spot key (furniture node instance id or floor cell) -> crew id.
var _claims: Dictionary = {}
var _visibility_timer := 0.0


func _ready() -> void:
	GameState.station.crew.changed.connect(sync)
	EventBus.game_reset.connect(_respawn_all)
	GameClock.time_advanced.connect(_on_time_advanced)
	_respawn_all.call_deferred()


## Adds / removes NPCs to match the crew data.
func sync() -> void:
	var crew := GameState.station.crew
	for id: int in npcs.keys():
		var m := crew.get_member(id)
		if m == null or m != npcs[id].member:
			_despawn(id)
	for m in crew.members:
		if not npcs.has(m.id):
			_spawn(m)


func _respawn_all() -> void:
	for id: int in npcs.keys():
		_despawn(id)
	sync()


func _spawn(m: CrewMember) -> void:
	var npc: CrewNPC = NPC_SCENE.instantiate()
	npc.name = "Crew%d" % m.id
	npc.member = m
	npc.director = self
	add_child(npc)
	npcs[m.id] = npc
	_settle(npc)


## Puts a new NPC on the navmesh: a few tries, as the station may still be
## settling (modules flying in, navigation syncing).
func _settle(npc: CrewNPC) -> void:
	for attempt in 4:
		if not is_instance_valid(npc):
			return
		npc.teleport(_entry_position(npc.member))
		if await npc.await_navigation(120):
			return
	if is_instance_valid(npc):
		push_warning("CrewDirector: %s never reached the navmesh" % npc.member.display_name)


func _despawn(id: int) -> void:
	release(npcs[id])
	npcs[id].queue_free()
	npcs.erase(id)


## Where a crew member appears: a floor cell of their home, else the spawn.
func _entry_position(m: CrewMember) -> Vector3:
	var cells := _floor_cells(station.get_module(m.home_uid))
	return cells.pick_random() if not cells.is_empty() else station.spawn_position()


# --- Spots -------------------------------------------------------------------

## Claims a spot for `npc` doing `activity` (releasing its previous one):
## {"pos": where to stand, "face": what to look at, "bed": mattress centre}.
## Empty when nothing fits.
func claim_spot(npc: CrewNPC, activity: StringName) -> Dictionary:
	release(npc)
	var m := npc.member
	var spot := {}
	match activity:
		&"sleeping":
			spot = _furniture_spot(npc, _modules([m.home_uid]), func(i: Interactable) -> bool:
				return i.routine_tag == &"sleep", true)
		&"working":
			spot = _furniture_spot(npc, _modules([m.job_uid]), func(i: Interactable) -> bool:
				return i.routine_tag != &"sleep" and not i.structural)
		&"eating":
			spot = _furniture_spot(npc, station.modules.values(), func(i: Interactable) -> bool:
				return i.routine_tag == &"eat")
	if spot.is_empty():
		spot = _floor_spot(npc, activity)
	return spot


func release(npc: CrewNPC) -> void:
	for key: Variant in _claims.keys():
		if _claims[key] == npc.member.id:
			_claims.erase(key)


func _furniture_spot(npc: CrewNPC, modules: Array, accept: Callable, bed: bool = false) -> Dictionary:
	for module: Module in modules:
		if module == null or module.interior == null:
			continue
		for node in module.interior.furniture_nodes:
			var item := node as Interactable
			if item == null or not accept.call(item) or _claims.has(item.get_instance_id()):
				continue
			_claims[item.get_instance_id()] = npc.member.id
			var spot := {"pos": item.get_approach_position(), "face": item.global_position}
			if bed:
				spot.bed = item.global_position
			return spot
	return {}


## A free floor cell: in the job / home module for work and sleep, anywhere
## usable when idle or eating.
func _floor_spot(npc: CrewNPC, activity: StringName) -> Dictionary:
	var m := npc.member
	var modules: Array
	match activity:
		&"working":
			modules = _modules([m.job_uid])
		&"sleeping":
			modules = _modules([m.home_uid])
		_:
			modules = _wander_modules()
	modules.shuffle()
	for module: Module in modules:
		var cells := _floor_cells(module)
		cells.shuffle()
		for pos: Vector3 in cells:
			var key := Vector3i(pos.round())
			if not _claims.has(key):
				_claims[key] = m.id
				return {"pos": pos}
	return {}


## Repaired station modules (no visiting ships).
func _wander_modules() -> Array:
	var out := []
	for module: Module in station.modules.values():
		if module.def.kind != &"visitor" and module.state != StationState.State.DERELICT:
			out.append(module)
	return out


func _modules(uids: Array) -> Array:
	var out := []
	for uid: int in uids:
		var module := station.get_module(uid)
		if module:
			out.append(module)
	return out


## World positions of a module's free floor cells (`.`, `P`, `L`, `D`), where
## the module rests (a new module may still be flying in).
func _floor_cells(module: Module) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if module == null or module.interior == null:
		return out
	var grid := module.interior.get_grid()
	for z in grid.size():
		for x in grid[z].length():
			if StationBuilder.FREE_FLOOR.contains(grid[z][x]):
				var local := module.to_local(module.interior.to_global(module.interior.cell_to_world(Vector2i(x, z))))
				out.append(module.rest_transform * local)
	return out


# --- Visibility & time skips ---------------------------------------------------

func _process(delta: float) -> void:
	_visibility_timer -= delta
	if _visibility_timer > 0.0:
		return
	_visibility_timer = VISIBILITY_SECONDS
	for npc: CrewNPC in npcs.values():
		var here := station.module_at(npc.global_position)
		npc.visible = here == null or here.interior_visible


func _on_time_advanced(minutes: float) -> void:
	if minutes < SNAP_MINUTES:
		return
	for npc: CrewNPC in npcs.values():
		if npc.navigation_ready:
			npc.snap_to_activity()
