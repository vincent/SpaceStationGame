class_name ExplodedView
extends Node
## Exploded-view upgrade screen (signature feature): the camera holds, the
## focused module's parts fly outwards along their explode direction with a
## stagger, missing parts appear as ghost outlines, and an overlay labels
## each part like a technical diagram. Buying an upgrade fills the ghost, the
## part flies in and snaps; leaving reassembles everything exactly.

signal opened(module: Module)
signal closed

const DISTANCE := 3.2
const STAGGER := 0.07
const SECONDS := 0.5
const GHOST_SHADER := preload("res://assets/shaders/ghost.gdshader")

@export var camera: DioramaCamera
@export var cutaway: CutawayController

var module: Module
var active := false
var bought_any := false

var _rest: Dictionary[ModulePart, Transform3D] = {}
var _ghosts: Dictionary[ModulePart, MeshInstance3D] = {}
var _tween: Tween
var _overlay: UpgradeOverlay
var _ghost_material: ShaderMaterial
var _saved_margin := 0.0


func _ready() -> void:
	_ghost_material = ShaderMaterial.new()
	_ghost_material.shader = GHOST_SHADER
	_ghost_material.set_shader_parameter("color", Palette.YELLOW)
	_overlay = UpgradeOverlay.new()
	_overlay.view = self
	add_child(_overlay)
	EventBus.upgrade_view_requested.connect(enter)


## Where a part sits when exploded (module-local), from its rest transform.
static func exploded_origin(rest: Vector3, explode_dir: Vector3, center: Vector3, distance: float) -> Vector3:
	var dir := explode_dir
	if dir.length_squared() < 0.0001:
		dir = rest - center
		dir.y = maxf(dir.y, 0.5)
	return rest + dir.normalized() * distance


func enter(target: Module) -> void:
	if active or target == null or target.get_parts().is_empty():
		if target and target.get_parts().is_empty():
			EventBus.toast.emit("Nothing to upgrade here yet.")
		return
	module = target
	active = true
	bought_any = false
	cutaway.force_closed = true
	camera.input_enabled = false
	_saved_margin = camera.room_margin
	camera.room_margin = 2.1
	camera.focus_on(module, DioramaCamera.Tier.ROOM)
	_rest.clear()
	var center := module.hull_aabb.get_center()
	var i := 0
	for part in module.get_parts():
		_rest[part] = part.transform
		var goal := part.transform
		goal.origin = exploded_origin(part.transform.origin, part.explode_dir, center, DISTANCE)
		if not part.visible:
			_ghosts[part] = _make_ghost(part, goal)
		_tween_part(part, goal, i * STAGGER)
		i += 1
	EventBus.sfx.emit(&"explode")
	_overlay.open()
	opened.emit(module)


func exit() -> void:
	if not active:
		return
	_overlay.close()
	for ghost: MeshInstance3D in _ghosts.values():
		ghost.queue_free()
	_ghosts.clear()
	var i := 0
	for part: ModulePart in _rest:
		_tween_part(part, _rest[part], i * STAGGER * 0.5)
		i += 1
	# Land exactly on the rest transforms whatever the tween did.
	get_tree().create_timer(SECONDS + i * STAGGER * 0.5 + 0.05).timeout.connect(_finish_exit.bind(module))
	camera.room_margin = _saved_margin
	camera.focus_on(module, DioramaCamera.Tier.ROOM)
	camera.input_enabled = true
	cutaway.force_closed = false
	active = false
	EventBus.upgrade_view_closed.emit()
	closed.emit()


## Rest transform of a part (valid while exploded).
func rest_transform(part: ModulePart) -> Transform3D:
	return _rest.get(part, part.transform)


func is_ghost(part: ModulePart) -> bool:
	return _ghosts.has(part)


## Buys the upgrade revealing `part`. The ghost fills and the part snaps in.
func buy(upgrade_id: StringName) -> bool:
	if not active or not GameState.buy_upgrade(module.uid, upgrade_id):
		return false
	var up := GameState.module_db.get_upgrade(upgrade_id)
	var part := module.get_node_or_null(NodePath("Parts/%s" % up.part_node)) as ModulePart
	bought_any = true
	if part == null:
		return true
	if _ghosts.has(part):
		_ghosts[part].queue_free()
		_ghosts.erase(part)
	part.visible = true
	var slot_xform := part.transform
	var start := slot_xform
	start.origin += (slot_xform.origin - _rest[part].origin).normalized() * DISTANCE * 1.5
	part.transform = start
	var t := part.create_tween()
	t.tween_property(part, "transform", slot_xform, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_callback(_snap.bind(part))
	t.tween_property(part, "scale", Vector3(1.25, 0.8, 1.25), 0.06)
	t.tween_property(part, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	return true


func _snap(part: ModulePart) -> void:
	EventBus.part_snapped.emit(module, StringName(part.name))
	EventBus.sfx.emit(&"snap")
	Input.vibrate_handheld(30)
	var sparks := AmbientKit.sparks(Vector3.ZERO, RandomNumberGenerator.new())
	part.add_child(sparks)
	sparks.get_child(0).call(&"restart")
	get_tree().create_timer(1.0).timeout.connect(sparks.queue_free)


func _finish_exit(target: Module) -> void:
	for part: ModulePart in _rest:
		if is_instance_valid(part):
			part.transform = _rest[part]
	_rest.clear()
	if is_instance_valid(target):
		target.refresh_parts()
		if bought_any:
			if target.powered:
				target.play_power_on()
			else:
				target.play_repair(target.wear)


func _tween_part(part: ModulePart, goal: Transform3D, delay: float) -> void:
	var t := part.create_tween()
	t.tween_property(part, "transform", goal, SECONDS).set_delay(delay) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)


func _make_ghost(part: ModulePart, at: Transform3D) -> MeshInstance3D:
	var was_visible := part.visible
	part.visible = true
	var box := Transform3D(Basis(), Vector3.ZERO)
	var aabb := part.get_aabb_in(part)
	part.visible = was_visible
	var kit := MeshKit.new()
	kit.box_edges(box * aabb, 0.07, Color.WHITE)
	var ghost := MeshInstance3D.new()
	ghost.name = "Ghost_%s" % part.name
	ghost.mesh = kit.commit()
	ghost.material_override = _ghost_material
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	part.get_parent().add_child(ghost)
	ghost.transform = part.transform
	var t := ghost.create_tween()
	t.tween_property(ghost, "transform", at, SECONDS)
	return ghost
