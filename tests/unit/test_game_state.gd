extends GutTest
## Uses the GameState/GameClock autoloads; each test starts a new game.

func before_each() -> void:
	GameClock.paused = true
	GameState.new_game()


func after_all() -> void:
	GameClock.paused = false
	GameState.new_game()


func test_new_game_gives_starting_items() -> void:
	for id in GameState.STARTING_ITEMS:
		assert_eq(GameState.inventory.count_of(id), GameState.STARTING_ITEMS[id])


func test_time_passing_decays_needs() -> void:
	GameClock.advance(120)
	assert_lt(GameState.needs.get_value(Needs.FOOD), Needs.MAX)


func test_sleep_restores_energy_and_advances_clock() -> void:
	GameState.needs.set_value(Needs.ENERGY, 10)
	var before := GameClock.total_minutes
	GameState.sleep(8)
	assert_almost_eq(GameClock.total_minutes - before, 480.0, 0.01)
	assert_eq(GameState.needs.get_value(Needs.ENERGY), Needs.MAX)
	assert_eq(GameState.activity, &"idle", "activity restored after sleeping")


func test_perform_consumes_cost_and_applies_effects() -> void:
	GameState.needs.set_value(Needs.FOOD, 20)
	var ok := GameState.perform({&"ration": 1, &"water": 1}, 30, {Needs.FOOD: 40.0})
	assert_true(ok)
	assert_eq(GameState.inventory.count_of(&"ration"), GameState.STARTING_ITEMS[&"ration"] - 1)
	assert_gt(GameState.needs.get_value(Needs.FOOD), 55.0)


func test_perform_fails_without_items() -> void:
	var before := GameClock.total_minutes
	assert_false(GameState.perform({&"power_cell": 99}, 30, {}))
	assert_eq(GameClock.total_minutes, before, "no time spent")


func test_use_item_applies_effect() -> void:
	GameState.needs.set_value(Needs.FOOD, 50)
	var slot := -1
	for i in GameState.inventory.size:
		var s := GameState.inventory.get_slot(i)
		if not s.is_empty() and s.id == &"ration":
			slot = i
	assert_true(GameState.use_item(slot))
	assert_eq(GameState.needs.get_value(Needs.FOOD), 65.0)


func test_cannot_use_material() -> void:
	for i in GameState.inventory.size:
		var s := GameState.inventory.get_slot(i)
		if not s.is_empty() and s.id == &"scrap_metal":
			assert_false(GameState.use_item(i))


func test_save_and_load() -> void:
	var path := "user://test_save.json"
	GameClock.advance(300)
	GameState.inventory.remove(&"ration", 2)
	assert_true(GameState.save_game(path))
	var saved_minutes := GameClock.total_minutes
	GameState.new_game()
	assert_true(GameState.load_game(path))
	assert_eq(GameClock.total_minutes, saved_minutes)
	assert_eq(GameState.inventory.count_of(&"ration"), GameState.STARTING_ITEMS[&"ration"] - 2)
	DirAccess.remove_absolute(path)


# --- Station actions ---------------------------------------------------------

func _wreck() -> int:
	return GameState.station.find_module(&"wreck_core")


func test_new_game_starts_with_capsule_docked_to_dark_wreck() -> void:
	var st := GameState.station
	assert_eq(st.uids().size(), 2)
	assert_eq(st.get_record(_wreck()).state, StationState.State.DERELICT)
	assert_true(st.get_record(st.find_module(&"capsule")).powered)


func test_repair_costs_scrap_and_time() -> void:
	var before := GameClock.total_minutes
	assert_true(GameState.repair_module(_wreck()))
	assert_eq(GameState.inventory.count_of(&"scrap_metal"), GameState.STARTING_ITEMS[&"scrap_metal"] - 6)
	assert_gt(GameClock.total_minutes, before)
	assert_false(GameState.repair_module(_wreck()), "already repaired")


func test_repair_needs_scrap() -> void:
	GameState.inventory.remove(&"scrap_metal", GameState.inventory.count_of(&"scrap_metal"))
	assert_string_starts_with(GameState.repair_error(_wreck()), "Needs")
	assert_false(GameState.repair_module(_wreck()))


func test_toggle_power() -> void:
	assert_false(GameState.toggle_power(_wreck()), "derelict can't be powered")
	GameState.repair_module(_wreck())
	assert_true(GameState.toggle_power(_wreck()))
	assert_true(GameState.station.get_record(_wreck()).powered)


func test_build_module_on_free_slot() -> void:
	assert_true(GameState.can_afford_any_module())
	var uid := GameState.build_module(&"hab_pod", _wreck(), &"B")
	assert_gt(uid, 0)
	assert_eq(GameState.inventory.count_of(&"scrap_metal"), GameState.STARTING_ITEMS[&"scrap_metal"] - 8)
	assert_eq(GameState.build_module(&"hab_pod", _wreck(), &"B"), 0, "slot taken")
	assert_eq(GameState.build_module(&"capsule", _wreck(), &"C"), 0, "not buildable")


func test_upgrade_effects_change_need_decay() -> void:
	var capsule := GameState.station.find_module(&"capsule")
	var base := GameState.needs.decay_per_hour[Needs.MORALE]
	assert_true(GameState.buy_upgrade(capsule, &"capsule_antenna"))
	assert_almost_eq(GameState.needs.decay_per_hour[Needs.MORALE], base - 0.5, 0.001)
	assert_false(GameState.buy_upgrade(capsule, &"capsule_antenna"), "only once")
	assert_almost_eq(GameState.needs.decay_per_hour[Needs.MORALE], base - 0.5, 0.001, "effect applied once")


func test_trade_and_gain() -> void:
	assert_true(GameState.trade({&"scrap_metal": 3}, {&"ration": 2}))
	assert_eq(GameState.inventory.count_of(&"ration"), GameState.STARTING_ITEMS[&"ration"] + 2)
	assert_false(GameState.trade({&"scrap_metal": 999}, {&"ration": 1}))


func test_save_load_round_trip_includes_station() -> void:
	GameState.gain({&"scrap_metal": 20})
	GameState.repair_module(_wreck())
	var hab := GameState.build_module(&"hab_pod", _wreck(), &"B")
	var path := "user://test_station_save.json"
	assert_true(GameState.save_game(path))
	GameState.new_game()
	assert_false(GameState.station.has_module(hab))
	assert_true(GameState.load_game(path))
	assert_true(GameState.station.has_module(hab))
	assert_eq(GameState.station.get_record(_wreck()).state, StationState.State.REPAIRED)
	DirAccess.remove_absolute(path)


func test_version_1_save_gets_the_story_station() -> void:
	var data := GameState.to_dict()
	data.erase("station")
	GameState.station.clear()
	GameState.from_dict(data)
	assert_eq(GameState.station.uids().size(), 2)
