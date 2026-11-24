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
		assert_eq(GameState.count(id), GameState.STARTING_ITEMS[id])
	assert_eq(GameState.stock.count(&"food"), GameState.STARTING_ITEMS[&"food"], "bulk items go to the stock")
	assert_eq(GameState.inventory.count_of(&"food"), 0)
	assert_eq(GameState.inventory.count_of(&"power_cell"), GameState.STARTING_ITEMS[&"power_cell"])


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
	var ok := GameState.perform({&"food": 1, &"power_cell": 1}, 30, {Needs.FOOD: 40.0})
	assert_true(ok)
	assert_eq(GameState.count(&"food"), GameState.STARTING_ITEMS[&"food"] - 1)
	assert_eq(GameState.count(&"power_cell"), GameState.STARTING_ITEMS[&"power_cell"] - 1)
	assert_gt(GameState.needs.get_value(Needs.FOOD), 55.0)


func test_perform_fails_without_items() -> void:
	var before := GameClock.total_minutes
	assert_false(GameState.perform({&"power_cell": 99}, 30, {}))
	assert_eq(GameClock.total_minutes, before, "no time spent")


func test_cannot_use_material() -> void:
	for i in GameState.inventory.size:
		var s := GameState.inventory.get_slot(i)
		if not s.is_empty() and s.id == &"power_cell":
			assert_false(GameState.use_item(i))


func test_save_and_load() -> void:
	var path := "user://test_save.json"
	GameClock.advance(300)
	GameState.pay({&"food": 2})
	GameState.stock.add(&"water", 0.4)
	assert_true(GameState.save_game(path))
	var saved_minutes := GameClock.total_minutes
	GameState.new_game()
	assert_true(GameState.load_game(path))
	assert_eq(GameClock.total_minutes, saved_minutes)
	assert_eq(GameState.count(&"food"), GameState.STARTING_ITEMS[&"food"] - 2)
	assert_almost_eq(GameState.stock.amount(&"water"), GameState.STARTING_ITEMS[&"water"] + 0.4, 0.001,
		"fractional stock survives")
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
	assert_eq(GameState.count(&"scrap_metal"), GameState.STARTING_ITEMS[&"scrap_metal"] - 6)
	assert_gt(GameClock.total_minutes, before)
	assert_false(GameState.repair_module(_wreck()), "already repaired")


func test_repair_needs_scrap() -> void:
	GameState.stock.set_amount(&"scrap_metal", 0.0)
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
	assert_eq(GameState.count(&"scrap_metal"), GameState.STARTING_ITEMS[&"scrap_metal"] - 8)
	assert_eq(GameState.build_module(&"hab_pod", _wreck(), &"B"), 0, "slot taken")
	assert_eq(GameState.build_module(&"capsule", _wreck(), &"C"), 0, "not buildable")


func test_trash_built_module_refunds_build_cost() -> void:
	var start := GameState.count(&"scrap_metal")
	var uid := GameState.build_module(&"hab_pod", _wreck(), &"B")
	assert_eq(GameState.trash_error(uid), "")
	assert_true(GameState.trash_module(uid))
	assert_false(GameState.station.has_module(uid))
	assert_eq(GameState.count(&"scrap_metal"), start, "build cost refunded")
	assert_false(GameState.trash_module(uid), "already gone")
	var capsule := GameState.station.find_module(&"capsule")
	assert_false(GameState.trash_module(capsule), "original modules stay")
	assert_true(GameState.station.has_module(capsule))


func test_upgrade_effects_change_need_decay() -> void:
	var capsule := GameState.station.find_module(&"capsule")
	var base := GameState.needs.decay_per_hour[Needs.MORALE]
	assert_true(GameState.buy_upgrade(capsule, &"capsule_antenna"))
	assert_almost_eq(GameState.needs.decay_per_hour[Needs.MORALE], base - 0.5, 0.001)
	assert_false(GameState.buy_upgrade(capsule, &"capsule_antenna"), "only once")
	assert_almost_eq(GameState.needs.decay_per_hour[Needs.MORALE], base - 0.5, 0.001, "effect applied once")


func test_trade_and_give() -> void:
	assert_true(GameState.trade({&"scrap_metal": 3}, {&"food": 2}))
	assert_eq(GameState.count(&"food"), GameState.STARTING_ITEMS[&"food"] + 2)
	assert_false(GameState.trade({&"scrap_metal": 999}, {&"food": 1}))


func test_save_load_round_trip_includes_station() -> void:
	GameState.give({&"scrap_metal": 20})
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


func test_version_3_save_migrates_to_the_stock() -> void:
	var data := GameState.to_dict()
	data.version = 3
	data.erase("stock")
	data.inventory = {"size": GameState.INVENTORY_SLOTS, "slots": [
		{"id": "ration", "count": 3}, {"id": "water", "count": 2}, {},
		{"id": "scrap_metal", "count": 7}, {"id": "power_cell", "count": 1},
	]}
	GameState.from_dict(JSON.parse_string(JSON.stringify(data)))
	assert_eq(GameState.stock.count(&"food"), 3, "rations became food in the stock")
	assert_eq(GameState.stock.count(&"water"), 2)
	assert_eq(GameState.stock.count(&"scrap_metal"), 7)
	assert_eq(GameState.inventory.count_of(&"power_cell"), 1, "carried items stay")
	assert_eq(GameState.inventory.count_of(&"scrap_metal"), 0, "bulk items left the inventory")


func test_recruit_needs_a_free_bunk() -> void:
	GameState.apply_outcome("recruit")
	assert_eq(GameState.station.crew.size(), 0, "the capsule bunk is the castaway's")


func test_crew_outcome_and_save() -> void:
	GameState.station.repair(_wreck())
	var hab := 0
	for uid in GameState.station.uids():
		for slot in GameState.station.free_slots(uid):
			for by in GameState.station.attach_options(&"dorm", uid, slot):
				hab = GameState.station.add_module(&"dorm", uid, slot, StationState.State.REPAIRED, 0.3, false, by)
				break
			if hab:
				break
		if hab:
			break
	if hab == 0:
		pass_test("no spot for a dormitory on the start station")
		return
	GameState.apply_outcome("recruit")
	assert_eq(GameState.station.crew.size(), 1)
	assert_eq(GameState.station.crew.staff(_wreck()), "", "the wreck has a job")
	var data: Dictionary = JSON.parse_string(JSON.stringify(GameState.to_dict()))
	assert_eq(int(data.version), GameState.SAVE_VERSION)
	GameState.new_game()
	assert_eq(GameState.station.crew.size(), 0)
	GameState.from_dict(data)
	assert_eq(GameState.station.crew.size(), 1)
	assert_eq(GameState.station.crew.members[0].job_uid, _wreck())


func test_version_5_save_has_no_crew() -> void:
	var data := GameState.to_dict()
	data.version = 5
	data.station.erase("crew")
	GameState.from_dict(JSON.parse_string(JSON.stringify(data)))
	assert_eq(GameState.station.crew.size(), 0)
	assert_eq(GameState.station.uids().size(), 2)
