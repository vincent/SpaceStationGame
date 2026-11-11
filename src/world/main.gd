extends Node3D
## Root of the game scene: builds the station, bakes navigation, and turns
## screen taps into player orders.

## A press that moves further than this (px) is a drag, not a tap.
const TAP_MAX_DISTANCE := 18.0

var _press_position := Vector2.INF

@onready var nav_region: NavigationRegion3D = $NavigationRegion3D
@onready var station: StationBuilder = $NavigationRegion3D/Station
@onready var player: Player = $Player
@onready var camera: IsoCamera = $IsoCamera
@onready var hud: HUD = $HUD
@onready var tap_marker: MeshInstance3D = $TapMarker


func _ready() -> void:
	_setup_environment()
	station.build()
	respawn_player()
	_bake_navigation()
	tap_marker.material_override = ToonMaterials.get_material(Palette.YELLOW, 3.0, false)
	tap_marker.hide()


## Bakes the navmesh from the generated station, then waits until the
## navigation map (which syncs asynchronously) contains the player's position
## before letting the player move.
func _bake_navigation() -> void:
	player.navigation_ready = false
	nav_region.bake_navigation_mesh(false)
	var map := nav_region.get_navigation_map()
	for i in 600:
		if NavigationServer3D.map_get_iteration_id(map) > 0 and \
				NavigationServer3D.map_get_closest_point(map, player.global_position).distance_to(player.global_position) < 1.0:
			player.navigation_ready = true
			return
		await get_tree().physics_frame
	push_error("Navigation map never became ready: is the player spawn on a floor cell?")


func respawn_player() -> void:
	player.teleport(station.spawn_position)
	camera.snap_to_target()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if event.pressed:
		_press_position = event.position
	elif _press_position != Vector2.INF:
		var is_tap: bool = event.position.distance_to(_press_position) <= TAP_MAX_DISTANCE
		_press_position = Vector2.INF
		if is_tap and not camera.is_gesturing():
			handle_tap(event.position)


## Raycasts from a screen position and orders the player. Public so
## integration tests can simulate taps.
func handle_tap(screen_position: Vector2) -> void:
	var hit := raycast_screen(screen_position)
	if hit.is_empty():
		return
	hud.close_menus()
	var target := Interactable.from_collider(hit.collider)
	if target:
		player.interact_with(target)
		_show_marker(target.get_approach_position())
	else:
		player.move_to(hit.position)
		_show_marker(hit.position)


func raycast_screen(screen_position: Vector2) -> Dictionary:
	var from := camera.project_ray_origin(screen_position)
	var to := from + camera.project_ray_normal(screen_position) * camera.far
	var query := PhysicsRayQueryParameters3D.create(from, to, Layers.TAP_MASK)
	query.collide_with_areas = true
	return get_world_3d().direct_space_state.intersect_ray(query)


func _show_marker(pos: Vector3) -> void:
	tap_marker.global_position = pos + Vector3(0, 0.03, 0)
	tap_marker.scale = Vector3.ONE * 0.4
	tap_marker.show()
	var tween := create_tween()
	tween.tween_property(tap_marker, "scale", Vector3.ONE, 0.25)
	tween.tween_callback(tap_marker.hide).set_delay(0.15)


func _setup_environment() -> void:
	var env := Environment.new()
	# The starfield itself is drawn by the camera's Backdrop node.
	env.background_mode = Environment.BG_COLOR
	env.background_color = Palette.NIGHT
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Palette.VIOLET.lerp(Palette.DEEP_BLUE, 0.3)
	env.ambient_light_energy = 0.9
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.0
	$WorldEnvironment.environment = env
