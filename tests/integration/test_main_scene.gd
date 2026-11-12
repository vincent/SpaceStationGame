extends GutTest
## Boots the real game scene and drives it like a player would.

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


func _find_interactable(fragment: String) -> Interactable:
	for node in main.find_children("*", "Area3D", true, false):
		if node is Interactable and node.display_name.to_lower().contains(fragment):
			return node
	return null


func _has_path(from: Vector3, to: Vector3) -> bool:
	var map := main.get_world_3d().navigation_map
	var path := NavigationServer3D.map_get_path(map, from, to, true)
	return not path.is_empty() and Vector2(path[-1].x, path[-1].z).distance_to(Vector2(to.x, to.z)) < 0.6


func test_navigation_becomes_ready() -> void:
	assert_true(player.navigation_ready)


func test_station_mirrors_game_state() -> void:
	assert_eq(station.modules.size(), 2)
	var capsule := station.find_module(&"capsule")
	var wreck := station.find_module(&"wreck_core")
	assert_not_null(capsule)
	assert_not_null(wreck)
	assert_gt(capsule.nav_region.navigation_mesh.get_polygon_count(), 0, "capsule navmesh baked")
	assert_gt(wreck.nav_region.navigation_mesh.get_polygon_count(), 0, "wreck navmesh baked")
	assert_false(capsule.get_world_aabb().intersects(wreck.get_world_aabb().grow(-0.02)), "hulls don't overlap")


func test_modules_own_their_cut_materials() -> void:
	var capsule := station.find_module(&"capsule")
	var wreck := station.find_module(&"wreck_core")
	assert_false(wreck._cut_materials.is_empty())
	for mat in wreck._cut_materials:
		assert_false(capsule._cut_materials.has(mat), "no cut material shared between modules")
	for geo in wreck._cut_geometry:
		var mat := geo.material_override as ShaderMaterial
		if mat and mat.shader == ToonMaterials.TOON_CUT_SHADER:
			assert_true(wreck._cut_materials.has(mat), "%s uses the module's own copy" % geo.name)
	wreck.set_wear(0.9)
	capsule.set_wear(0.2)
	assert_almost_eq(float(wreck._cut_materials[0].get_shader_parameter(&"wear")), 0.9, 0.001)
	assert_almost_eq(float(capsule._cut_materials[0].get_shader_parameter(&"wear")), 0.2, 0.001)


func test_player_spawns_in_capsule() -> void:
	assert_almost_eq(player.global_position, station.spawn_position(), Vector3.ONE * 0.01)
	assert_eq(station.module_at(player.global_position), station.find_module(&"capsule"))


func test_station_has_furniture() -> void:
	for name: String in ["bed", "kitchen", "window", "salvage", "console"]:
		assert_not_null(_find_interactable(name), name)


func test_path_from_capsule_to_every_wreck_room() -> void:
	var wreck := station.find_module(&"wreck_core")
	# Room A is the wreck's only walkable room (rooms B and C are closed art).
	for cell: Vector2i in [Vector2i(2, 1), Vector2i(1, 2), Vector2i(4, 2)]:
		var target := wreck.interior.to_global(wreck.interior.cell_to_world(cell))
		assert_true(_has_path(player.global_position, target), "path to wreck room at %s" % cell)


func test_player_walks_to_bed_and_requests_menu() -> void:
	watch_signals(EventBus)
	var bed := _find_interactable("bed")
	player.interact_with(bed)
	await wait_until(func() -> bool: return not player.is_moving(), 15.0)
	var dist := Vector2(player.global_position.x, player.global_position.z).distance_to(
		Vector2(bed.get_approach_position().x, bed.get_approach_position().z))
	assert_lt(dist, player.interact_reach, "player reached the bed")
	assert_signal_emitted_with_parameters(EventBus, "interaction_requested", [bed])


func test_tap_on_floor_moves_player_in_room_view() -> void:
	await wait_until(func() -> bool: return camera.t > 0.99, 2.0)
	var capsule := station.find_module(&"capsule")
	var start := player.global_position
	var target := capsule.interior.to_global(capsule.interior.cell_to_world(Vector2i(2, 2)))
	main.handle_tap(camera.camera.unproject_position(target))
	await wait_until(func() -> bool: return not player.is_moving(), 10.0)
	assert_gt(player.global_position.distance_to(start), 1.0, "player moved")
	assert_almost_eq(player.global_position.x, target.x, 0.5)
	assert_almost_eq(player.global_position.z, target.z, 0.5)


func test_tap_module_in_station_view_focuses_it() -> void:
	var wreck := station.find_module(&"wreck_core")
	camera.focus_on(main.focused, DioramaCamera.Tier.STATION, true)
	main.handle_tap(camera.camera.unproject_position(wreck.get_world_aabb().get_center()))
	assert_eq(main.focused, wreck)
	await wait_until(func() -> bool: return not camera.is_tweening(), 2.0)
	assert_almost_eq(camera.t, 1.0, 0.001)


func test_cut_opens_in_room_view_and_closes_in_station_view() -> void:
	var cutaway: CutawayController = main.get_node("CutawayController")
	await wait_until(func() -> bool: return cutaway.open > 0.99, 2.0)
	assert_true(cutaway.cut_on)
	assert_true(cutaway.get_box().has_point(main.focused.get_world_aabb().get_center() + Vector3(0, 2.4, 0)),
		"roof is inside the cut")
	camera.focus_on(main.focused, DioramaCamera.Tier.STATION, true)
	await wait_until(func() -> bool: return cutaway.open < 0.01, 2.0)
	assert_false(cutaway.cut_on)


func test_repair_and_power_wreck() -> void:
	var wreck := station.find_module(&"wreck_core")
	var uid := wreck.uid
	GameState.repair_module(uid)
	assert_eq(wreck.state, StationState.State.REPAIRED)
	watch_signals(EventBus)
	assert_true(GameState.toggle_power(uid))
	assert_signal_emitted(EventBus, "power_on_started")
	assert_true(wreck.is_sequence_running())
	await wait_seconds(Module.POWER_ON_SECONDS + 0.3)
	assert_false(wreck.is_sequence_running())


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
	var front := station.get_module(GameState.build_module(&"agri_bay", wreck.uid, &"C"))
	var side := station.get_module(GameState.build_module(&"hab_pod", wreck.uid, &"B"))
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


func test_exploded_view_returns_parts_to_rest() -> void:
	var view: ExplodedView = main.get_node("ExplodedView")
	var capsule := station.find_module(&"capsule")
	main.focus_module(capsule, true)
	var rest := {}
	for part in capsule.get_parts():
		rest[part] = part.transform
	EventBus.upgrade_view_requested.emit(capsule)
	assert_true(view.active)
	await wait_seconds(ExplodedView.SECONDS + 0.4)
	var moved := false
	for part in capsule.get_parts():
		moved = moved or not part.transform.origin.is_equal_approx(rest[part].origin)
	assert_true(moved, "parts exploded")
	assert_true(view.buy(&"capsule_solar"), "buy an upgrade from the exploded view")
	assert_true(capsule.get_node("Parts/part_solar_wings").visible)
	await wait_seconds(0.8)
	view.exit()
	await wait_seconds(ExplodedView.SECONDS + 0.6)
	for part in capsule.get_parts():
		assert_eq(part.transform, rest[part], "%s back at rest" % part.name)
	assert_false(view.active)


func test_visitor_docks_and_leaves() -> void:
	var director: VisitorDirector = main.get_node("VisitorDirector")
	assert_false(director.arrive(), "no powered dock yet")
	var wreck := station.find_module(&"wreck_core")
	GameState.repair_module(wreck.uid)
	GameState.toggle_power(wreck.uid)
	assert_true(director.arrive())
	var ship := station.get_module(director.visitor_uid)
	assert_not_null(ship)
	assert_eq(ship.def.kind, &"visitor")
	assert_not_null(_find_interactable("trader"))
	await wait_seconds(VisitorDirector.APPROACH_SECONDS + 0.3)
	# The docked ship sits inside the wreck's bounds: standing in it must
	# focus the ship (camera follow + cutaway), not the wreck.
	assert_eq(station.module_at(_find_interactable("trader").global_position), ship)
	director.depart()
	await wait_seconds(VisitorDirector.APPROACH_SECONDS + 0.3)
	assert_eq(director.visitor_uid, 0)
	assert_eq(station.modules.size(), 2, "ship gone")


func test_upgrade_cards_fit_on_screen() -> void:
	var view: ExplodedView = main.get_node("ExplodedView")
	var wreck := station.find_module(&"wreck_core")  # the module with the most parts
	main.focus_module(wreck, true)
	EventBus.upgrade_view_requested.emit(wreck)
	await wait_seconds(ExplodedView.SECONDS + 0.4)
	var overlay := view.find_children("*", "UpgradeOverlay", false, false)[0] as UpgradeOverlay
	var screen := overlay.get_viewport().get_visible_rect().size
	var cards := overlay.find_children("*", "PanelContainer", true, false)
	assert_gt(cards.size(), 5)
	for node in cards:
		var card := node as Control
		if not card.visible or card.get_parent() is PanelContainer:
			continue
		var rect := Rect2(card.position, card.size * card.scale)
		assert_true(Rect2(Vector2.ZERO, screen).encloses(rect), "card %s inside the screen" % rect)
	view.exit()
	await wait_seconds(ExplodedView.SECONDS + 0.6)


func test_idle_routine_waits_while_upgrade_view_is_open() -> void:
	var routine := main.get_node("Player/Routine") as PlayerRoutine
	routine.enabled = true
	var view: ExplodedView = main.get_node("ExplodedView")
	var capsule := station.find_module(&"capsule")
	main.focus_module(capsule, true)
	EventBus.upgrade_view_requested.emit(capsule)
	assert_true(routine.is_ui_busy())
	routine._process(PlayerRoutine.IDLE_SECONDS + 1.0)
	assert_eq(routine.phase, PlayerRoutine.Phase.IDLE, "no routine while upgrading")
	assert_false(player.is_moving())
	view.exit()
	await wait_seconds(ExplodedView.SECONDS + 0.6)
	# A routine already walking stops when a menu opens.
	assert_true(routine.start_routine())
	assert_eq(routine.phase, PlayerRoutine.Phase.WALKING)
	EventBus.upgrade_view_requested.emit(capsule)
	routine._process(0.016)
	assert_eq(routine.phase, PlayerRoutine.Phase.IDLE)
	assert_false(player.is_moving(), "stopped when the upgrade view opened")
	view.exit()
	routine.enabled = false
	await wait_seconds(ExplodedView.SECONDS + 0.6)


func test_agri_bay_shows_in_the_status_bar_and_popover() -> void:
	var hud := get_tree().get_first_node_in_group(&"hud") as HUD
	var bar := hud.status_bar
	var wreck := station.find_module(&"wreck_core")
	GameState.give({&"scrap_metal": 40, &"power_cell": 1})
	GameState.stock.set_amount(&"water", 0.0)
	GameState.repair_module(wreck.uid)
	assert_true(GameState.toggle_power(wreck.uid))
	assert_gt(GameState.build_module(&"solar_array", wreck.uid, &"C"), 0)
	var bay := GameState.build_module(&"agri_bay", wreck.uid, &"B")
	assert_gt(bay, 0)
	assert_true(GameState.toggle_power(bay))
	assert_true(bar.chips[&"food"].visible, "food chip (starting stock + a producer)")
	assert_true(bar.chips[StatusBar.POWER].visible)
	var food := GameState.stock.amount(&"food")
	GameClock.advance(600)
	assert_almost_eq(GameState.stock.amount(&"food"), food + 0.15 * 10, 0.01)
	assert_string_contains(bar.chips[&"food"].amount_label.text, str(GameState.stock.count(&"food")))
	assert_eq(bar.chips[&"food"].rate_label.text, "+0.15/h")

	var popover := hud.production_popover
	popover.toggle(&"food", bar.chips[&"food"])
	assert_true(popover.visible)
	var texts := _button_texts(popover)
	assert_true(texts.any(func(t: String) -> bool: return t.begins_with("Agri bay · +0.15/h")), str(texts))
	assert_true(texts.any(func(t: String) -> bool: return t.contains("Upgrade: Hydroponics")), str(texts))
	assert_true(GameState.toggle_power(bay))  # off
	texts = _button_texts(popover)
	assert_true(texts.any(func(t: String) -> bool: return t.begins_with("Agri bay · Unpowered")), str(texts))
	popover.toggle(&"food", bar.chips[&"food"])
	assert_false(popover.visible, "the same chip closes it")


func _button_texts(root: Node) -> Array:
	var out := []
	for b in root.find_children("*", "Button", true, false):
		if not b.is_queued_for_deletion():
			out.append((b as Button).text)
	return out
