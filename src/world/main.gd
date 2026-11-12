extends Node3D
## Root of the game scene: builds the station from GameState, frames it with
## the diorama camera, and turns screen taps into orders.
##
## Touch mapping:
##   station view (zoomed out): tap module = focus/zoom in · tap ghost slot =
##     build menu · drag = pan
##   room view (zoomed in): tap floor = walk · tap object = its actions ·
##     tap another module = focus it · "Station view" button = back out

## A press that moves further than this (px) is a drag, not a tap.
const TAP_MAX_DISTANCE := 18.0
## Zoom position above which taps act inside rooms.
const ROOM_VIEW_T := 0.5
## Seconds of input-free time before the frame rate drops to the idle cap.
const IDLE_AFTER := 2.0
const IDLE_FPS := 30
const ACTIVE_FPS := 60

var focused: Module
## Skip the intro zoom (tests, screenshots).
var skip_intro := false

var _press_position := Vector2.INF
var _last_input_msec := 0
var _follow_timer := 0.0

@onready var station: Station = $Station
@onready var player: Player = $Player
@onready var camera: DioramaCamera = $DioramaCamera
@onready var cutaway: CutawayController = $CutawayController
@onready var hud: HUD = $HUD
@onready var tap_marker: MeshInstance3D = $TapMarker
@onready var exploded_view: ExplodedView = $ExplodedView


func _ready() -> void:
	_setup_environment()
	tap_marker.material_override = ToonMaterials.get_material(Palette.YELLOW, 3.0, false)
	tap_marker.hide()
	station.layout_changed.connect(_on_layout_changed)
	camera.zoom_changed.connect(func(t: float) -> void: EventBus.view_changed.emit(t))
	EventBus.game_reset.connect(_on_game_reset)
	EventBus.module_focus_requested.connect(focus_module)
	EventBus.station_view_requested.connect(show_station_view)
	station.bind(GameState.station)
	_start(true)


func _start(intro: bool) -> void:
	respawn_player()
	_on_layout_changed()
	var home := station.module_at(player.global_position)
	if home == null:
		home = station.get_module(GameState.station.uids()[0])
	if intro and not skip_intro:
		# Beauty shot of the whole station, then glide into the capsule.
		camera.focus_on(home, DioramaCamera.Tier.STATION, true)
		_set_focused(home)
		get_tree().create_timer(1.2).timeout.connect(func() -> void:
			if not skip_intro and camera.t < 0.01 and focused == home:
				focus_module(home))
	else:
		focus_module(home, true)
	_await_navigation()


## Waits until the navigation map (which syncs asynchronously after the
## per-module bakes) contains the player's position before letting them move.
func _await_navigation() -> void:
	player.navigation_ready = false
	var map := get_world_3d().navigation_map
	for i in 600:
		await get_tree().physics_frame
		if not is_instance_valid(player):
			return
		if NavigationServer3D.map_get_iteration_id(map) > 0 and \
				NavigationServer3D.map_get_closest_point(map, player.global_position).distance_to(player.global_position) < 1.0:
			player.navigation_ready = true
			return
	push_error("Navigation map never became ready: is the player spawn on a floor cell?")


func respawn_player() -> void:
	player.teleport(station.spawn_position())


func focus_module(module: Module, instant: bool = false) -> void:
	if module == null:
		return
	_set_focused(module)
	camera.focus_on(module, DioramaCamera.Tier.ROOM, instant)


func show_station_view() -> void:
	camera.focus_on(focused, DioramaCamera.Tier.STATION)


func is_room_view() -> bool:
	return camera.t >= ROOM_VIEW_T


func _set_focused(module: Module) -> void:
	focused = module
	cutaway.set_focus(module)
	EventBus.module_focused.emit(module)


func _on_layout_changed() -> void:
	camera.set_station_aabb(station.get_aabb())
	cutaway.mark_visibility_dirty()


func _on_game_reset() -> void:
	_start(false)


func _input(_event: InputEvent) -> void:
	_last_input_msec = Time.get_ticks_msec()


func _process(delta: float) -> void:
	var busy := Time.get_ticks_msec() - _last_input_msec < IDLE_AFTER * 1000.0 \
		or camera.is_tweening() or player.is_moving()
	Engine.max_fps = ACTIVE_FPS if busy else IDLE_FPS
	# In room view the camera follows the castaway from module to module.
	_follow_timer -= delta
	if _follow_timer <= 0.0:
		_follow_timer = 0.3
		if is_room_view() and not camera.is_tweening() and player.is_moving():
			var here := station.module_at(player.global_position)
			if here and here != focused:
				focus_module(here)


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


## Public so integration tests can simulate taps.
func handle_tap(screen_position: Vector2) -> void:
	if exploded_view.active:
		return
	hud.close_menus()
	if not is_room_view():
		_tap_station_view(screen_position)
		return
	var hit := raycast_screen(screen_position, Layers.TAP_MASK)
	if hit.is_empty():
		var pick := raycast_screen(screen_position, Layers.MODULE_PICK)
		var other := _module_of(pick.get("collider"))
		if other and other != focused:
			focus_module(other)
		return
	var target := Interactable.from_collider(hit.collider)
	# Taps on another (closed) module focus it instead of acting through its roof.
	var here := station.module_at(hit.position)
	if here and here != focused:
		focus_module(here)
		return
	if target:
		player.interact_with(target)
		_show_marker(target.get_approach_position())
	else:
		player.move_to(hit.position)
		_show_marker(hit.position)


func _tap_station_view(screen_position: Vector2) -> void:
	var hit := raycast_screen(screen_position, Layers.MODULE_PICK)
	if hit.is_empty():
		return
	var area := hit.collider as Node
	if area.has_meta(&"ghost_slot"):
		EventBus.ghost_slot_tapped.emit(int(area.get_meta(&"ghost_parent_uid")), area.get_meta(&"ghost_slot"))
		return
	var module := _module_of(area)
	if module:
		focus_module(module)


func raycast_screen(screen_position: Vector2, mask: int) -> Dictionary:
	var cam := camera.camera
	var from := cam.project_ray_origin(screen_position)
	var to := from + cam.project_ray_normal(screen_position) * cam.far
	var query := PhysicsRayQueryParameters3D.create(from, to, mask)
	query.collide_with_areas = true
	return get_world_3d().direct_space_state.intersect_ray(query)


static func _module_of(node: Variant) -> Module:
	var n := node as Node
	while n != null:
		if n is Module:
			return n
		n = n.get_parent()
	return null


func _show_marker(pos: Vector3) -> void:
	tap_marker.global_position = pos + Vector3(0, 0.03, 0)
	tap_marker.scale = Vector3.ONE * 0.4
	tap_marker.show()
	var tween := create_tween()
	tween.tween_property(tap_marker, "scale", Vector3.ONE, 0.25)
	tween.tween_callback(tap_marker.hide).set_delay(0.15)


## Global darkness: low ambient and a cold key light, so unpowered modules
## read as near-black silhouettes with a rim; interior lights do the rest.
func _setup_environment() -> void:
	var env := Environment.new()
	# The starfield itself is drawn by the camera's Backdrop node.
	env.background_mode = Environment.BG_COLOR
	env.background_color = Palette.NIGHT
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Palette.DEEP_BLUE.lerp(Palette.VIOLET, 0.35)
	env.ambient_light_energy = 0.55
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.0
	$WorldEnvironment.environment = env
