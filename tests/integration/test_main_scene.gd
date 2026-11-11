extends GutTest
## Boots the real game scene and drives it like a player would.

const MAIN := preload("res://src/world/main.tscn")

var main: Node3D
var player: Player


func before_each() -> void:
	GameState.new_game()
	main = add_child_autofree(MAIN.instantiate())
	player = main.get_node("Player")
	await wait_until(func() -> bool: return player.navigation_ready, 5.0)


func _find_interactable(fragment: String) -> Interactable:
	for node in main.find_children("*", "Area3D", true, false):
		if node is Interactable and node.display_name.to_lower().contains(fragment):
			return node
	return null


func test_navigation_becomes_ready() -> void:
	assert_true(player.navigation_ready)


func test_navigation_mesh_is_baked() -> void:
	var region: NavigationRegion3D = main.get_node("NavigationRegion3D")
	assert_gt(region.navigation_mesh.get_polygon_count(), 0, "navmesh has polygons")


func test_player_spawns_on_spawn_cell() -> void:
	var station: StationBuilder = main.get_node("NavigationRegion3D/Station")
	assert_almost_eq(player.global_position, station.spawn_position, Vector3.ONE * 0.01)


func test_station_has_furniture() -> void:
	assert_not_null(_find_interactable("bed"), "bed")
	assert_not_null(_find_interactable("kitchen"), "kitchen")
	assert_not_null(_find_interactable("window"), "window")


func test_player_walks_to_bed_and_requests_menu() -> void:
	watch_signals(EventBus)
	var bed := _find_interactable("bed")
	player.interact_with(bed)
	await wait_until(func() -> bool: return not player.is_moving(), 15.0)
	var dist := Vector2(player.global_position.x, player.global_position.z).distance_to(
		Vector2(bed.get_approach_position().x, bed.get_approach_position().z))
	assert_lt(dist, player.interact_reach, "player reached the bed")
	assert_signal_emitted_with_parameters(EventBus, "interaction_requested", [bed])


func test_bed_menu_sleep_restores_energy() -> void:
	GameState.needs.set_value(Needs.ENERGY, 20.0)
	var bed := _find_interactable("bed")
	var actions := bed.get_actions()
	actions[-1].callback.call()  # longest sleep
	assert_gt(GameState.needs.get_value(Needs.ENERGY), 90.0)


func test_tap_on_floor_moves_player() -> void:
	var start := player.global_position
	var camera: Camera3D = main.get_node("IsoCamera")
	var station: StationBuilder = main.get_node("NavigationRegion3D/Station")
	# The corridor cell just north of the spawn (layout row 6, column 3).
	var target := station.cell_to_world(Vector2i(3, 6))
	assert_eq(station.get_cell(Vector2i(3, 6)), ".")
	main.handle_tap(camera.unproject_position(target))
	await wait_until(func() -> bool: return not player.is_moving(), 10.0)
	assert_gt(player.global_position.distance_to(start), 1.0, "player moved")
	assert_almost_eq(player.global_position.x, target.x, 0.5)
	assert_almost_eq(player.global_position.z, target.z, 0.5)
