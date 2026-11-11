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
