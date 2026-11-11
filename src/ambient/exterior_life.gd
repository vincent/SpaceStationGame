class_name ExteriorLife
extends Node3D
## Life outside the hull: now and then a distant ship crosses behind the
## station with blinking running lights, or a chunk of debris drifts past.

@export var camera: DioramaCamera
@export var station: Station
@export var min_seconds: float = 18.0
@export var max_seconds: float = 40.0

var rng := RandomNumberGenerator.new()
var _timer := 5.0


func _ready() -> void:
	rng.randomize()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0 or camera == null or station == null:
		return
	_timer = rng.randf_range(min_seconds, max_seconds)
	if rng.randf() < 0.6:
		spawn_traffic()
	else:
		spawn_debris()


## A small ship crossing far behind the station, right to left or back.
func spawn_traffic() -> Node3D:
	var kit := MeshKit.new()
	kit.box(Vector3.ZERO, Vector3(2.4, 0.5, 0.8), Color(0.3, 0, 0.6))
	kit.box(Vector3(-1.3, 0, 0), Vector3(0.2, 0.25, 0.25), Color(0, 1, 0))
	var ship := MeshInstance3D.new()
	ship.mesh = kit.commit()
	ship.material_override = ToonMaterials.get_cut_material(Palette.STEEL, 0.0, true)
	ship.set_instance_shader_parameter(&"sweep_range", Vector2(-1000, 1000))
	ship.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := OmniLight3D.new()
	light.light_color = Palette.NEON_PINK if rng.randf() < 0.5 else Palette.NEON_CYAN
	light.omni_range = 3.0
	ship.add_child(light)
	return _cross(ship, 0.4, rng.randf_range(16.0, 26.0), func() -> void:
		var blink := light.create_tween().set_loops()
		blink.tween_property(light, "light_energy", 0.0, 0.5)
		blink.tween_property(light, "light_energy", 2.0, 0.1))


func spawn_debris() -> Node3D:
	var rock := AmbientKit.debris(AABB(), rng)
	return _cross(rock, 0.0, rng.randf_range(22.0, 34.0), Callable())


func _cross(node: Node3D, depth_bias: float, seconds: float, on_ready: Callable) -> Node3D:
	var aabb := station.get_aabb()
	var right := camera.global_basis.x
	var back := -camera.global_basis.z * (aabb.size.length() * (0.6 + depth_bias))
	var reach := aabb.size.length() * 0.9 + 10.0
	var dir := 1.0 if rng.randf() < 0.5 else -1.0
	var height := Vector3(0, rng.randf_range(-4.0, 10.0), 0)
	var from := aabb.get_center() + back + height - right * reach * dir
	var to := aabb.get_center() + back + height * 0.8 + right * reach * dir
	add_child(node)
	node.global_position = from
	node.look_at(to)
	node.rotate_object_local(Vector3.UP, PI * 0.5)
	if on_ready.is_valid():
		on_ready.call()
	var t := node.create_tween()
	t.tween_property(node, "global_position", to, seconds)
	t.tween_callback(node.queue_free)
	return node
