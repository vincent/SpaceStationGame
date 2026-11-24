extends GutTest
## Building, trashing and reloading the station in the real game scene.

const MAIN := preload("res://src/world/main.tscn")

var main: Node3D
var player: Player
var station: Station
var camera: DioramaCamera


func before_each() -> void:
	GameClock.paused = true
	GameState.new_game()
	main = MAIN.instantiate()
	main.skip_intro = true
	add_child_autofree(main)
	player = main.get_node("Player")
	station = main.get_node("Station")
	camera = main.get_node("DioramaCamera")
	(main.get_node("Player/Routine") as PlayerRoutine).enabled = false
	await wait_until(func() -> bool: return player.navigation_ready, 5.0)


func after_all() -> void:
	GameClock.paused = false
	GameState.new_game()


func _has_path(from: Vector3, to: Vector3) -> bool:
	var map := main.get_world_3d().navigation_map
	var path := NavigationServer3D.map_get_path(map, from, to, true)
	return not path.is_empty() and Vector2(path[-1].x, path[-1].z).distance_to(Vector2(to.x, to.z)) < 0.6


func test_building_a_module_attaches_and_links_navigation() -> void:
	var wreck := station.find_module(&"wreck_core")
	GameState.give({&"scrap_metal": 20})
	GameState.repair_module(wreck.uid)
	var before := camera.get_station_aabb()
	var uid := GameState.build_module(&"hab_pod", wreck.uid, &"C")
	assert_gt(uid, 0)
	var hab := station.get_module(uid)
	assert_not_null(hab)
	assert_eq(wreck.slots[&"C"].occupied_by, hab)
	assert_gt(camera.get_station_aabb().size.length(), before.size.length(), "camera AABB updated")
	await wait_seconds(0.8)  # arrival animation + navigation map sync
	var room := hab.interior.to_global(hab.interior.cell_to_world(Vector2i(2, 1)))
	assert_true(_has_path(player.global_position, room), "path from capsule to the new module")


func test_trashing_a_module_moves_the_castaway_out() -> void:
	var wreck := station.find_module(&"wreck_core")
	GameState.give({&"scrap_metal": 20})
	GameState.repair_module(wreck.uid)
	var uid := GameState.build_module(&"hab_pod", wreck.uid, &"C")
	var hab := station.get_module(uid)
	await wait_seconds(0.8)  # arrival animation + navigation map sync
	player.teleport(hab.floor_positions()[0])
	main.focus_module(hab, true)
	assert_eq(station.module_at(player.global_position), hab)
	var scrap := GameState.count(&"scrap_metal")
	assert_true(GameState.trash_module(uid))
	assert_eq(station.module_at(player.global_position), wreck, "castaway moved to the parent")
	assert_eq(main.focused, wreck, "camera focus follows")
	assert_null(station.get_module(uid))
	assert_null(wreck.slots[&"C"].occupied_by, "slot freed")
	assert_eq(GameState.count(&"scrap_metal"), scrap + 8, "refund")
	await wait_seconds(0.7)  # lift-off
	assert_false(is_instance_valid(hab), "module freed after lifting off")


func test_branching_station_through_connectors() -> void:
	var wreck := station.find_module(&"wreck_core")
	GameState.give({&"scrap_metal": 60})
	GameState.repair_module(wreck.uid)
	var corridor := GameState.build_module(&"corridor", wreck.uid, &"B")
	var hub := GameState.build_module(&"hub_x", corridor, &"B")
	assert_gt(hub, 0)
	# Rotated: the T attaches by its slot B, not its default A.
	var t := GameState.build_module(&"junction_t", hub, &"B", &"B")
	assert_gt(t, 0)
	var hab := GameState.build_module(&"hab_pod", hub, &"D")
	assert_gt(hab, 0)
	var hub_module := station.get_module(hub)
	var t_module := station.get_module(t)
	assert_eq(t_module.get_attach_slot().slot_name, &"B")
	assert_eq(hub_module.slots[&"B"].occupied_by, t_module)
	# The scene agrees with the data-side placement (StationGrid).
	var expected: Dictionary[int, Transform3D] = StationGrid.transforms(GameState.station)
	for uid: int in expected:
		var module := station.get_module(uid)
		assert_almost_eq(module.rest_transform.origin, expected[uid].origin, Vector3.ONE * 0.02,
			"%s placed as StationGrid says" % module.name)
	# No two hulls overlap.
	var mods: Array = station.modules.values()
	for i in mods.size():
		for j in range(i + 1, mods.size()):
			var a: Module = mods[i]
			var b: Module = mods[j]
			if a.def.kind == &"visitor" or b.def.kind == &"visitor":
				continue
			assert_false(StationGrid.overlaps(
				StationGrid.world_rects(a.def, a.rest_transform), StationGrid.world_rects(b.def, b.rest_transform)),
				"%s / %s overlap" % [a.name, b.name])
	await wait_seconds(0.8)  # arrival animations + navigation map sync
	var far := station.get_module(hab)
	var room := far.interior.to_global(far.interior.cell_to_world(Vector2i(2, 1)))
	assert_true(_has_path(player.global_position, room), "walk from the capsule through corridor + hub")
	var end := t_module.interior.to_global(t_module.interior.cell_to_world(Vector2i(1, 1)))
	assert_true(_has_path(player.global_position, end), "walk into the rotated T-junction")


func test_modules_on_wreck_slots_dont_overlap() -> void:
	var wreck := station.find_module(&"wreck_core")
	var capsule := station.find_module(&"capsule")
	GameState.give({&"scrap_metal": 40})
	GameState.repair_module(wreck.uid)
	var front := station.get_module(GameState.build_module(&"hab_pod", wreck.uid, &"C"))
	var side := station.get_module(GameState.build_module(&"greenhouse", wreck.uid, &"B"))
	assert_not_null(front)
	assert_not_null(side)
	var front_box := front.get_rest_aabb().grow(-0.02)
	var side_box := side.get_rest_aabb().grow(-0.02)
	assert_false(front_box.intersects(capsule.get_world_aabb()), "slot C module clears the capsule")
	assert_false(front_box.intersects(side_box), "slot C module clears the slot B module")


func test_load_rebuilds_station() -> void:
	var wreck := station.find_module(&"wreck_core")
	GameState.give({&"scrap_metal": 20})
	GameState.repair_module(wreck.uid)
	GameState.build_module(&"hab_pod", wreck.uid, &"B")
	var path := "user://test_main_save.json"
	GameState.save_game(path)
	GameState.new_game()
	assert_eq(station.modules.size(), 2)
	GameState.load_game(path)
	assert_eq(station.modules.size(), 3)
	await wait_until(func() -> bool: return player.navigation_ready, 5.0)
	assert_true(player.navigation_ready)
	DirAccess.remove_absolute(path)
