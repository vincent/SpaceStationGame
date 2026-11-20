extends GutTest
## Story beats through GameState (autoloads): triggers, choices, schedules,
## save/load. Also a smoke run of the main beat chain.

func before_each() -> void:
	GameClock.paused = true
	GameState.set_story_enabled(true)
	GameState.new_game()


func after_all() -> void:
	GameClock.paused = false
	GameState.new_game()


func test_new_game_opens_the_intro() -> void:
	assert_eq(GameState.current_encounter.id, &"intro")
	assert_true(GameState.story.flag(&"intro_seen"), "outcomes apply when it starts")
	assert_true(GameState.resolve_encounter())
	assert_null(GameState.current_encounter)


func test_repairing_the_wreck_starts_a_beat_once() -> void:
	GameState.resolve_encounter()
	var uid := GameState.station.find_module(&"wreck_core")
	GameState.station.repair(uid)
	assert_eq(GameState.current_encounter.id, &"wreck_lights")
	GameState.resolve_encounter()
	assert_true(GameState.story.flag(&"wreck_awake"))
	assert_eq(GameState.story.times_seen(&"wreck_lights"), 1)


func test_encounters_queue_while_one_is_open() -> void:
	assert_eq(GameState.current_encounter.id, &"intro")
	GameState.station.repair(GameState.station.find_module(&"wreck_core"))
	assert_eq(GameState.current_encounter.id, &"intro", "the open one stays")
	GameState.resolve_encounter()
	assert_eq(GameState.current_encounter.id, &"wreck_lights", "the queued one follows")


func test_dish_signal_chain_reaches_the_trader() -> void:
	watch_signals(EventBus)
	GameState.resolve_encounter()
	var uid := GameState.station.find_module(&"wreck_core")
	GameState.station.repair(uid)
	GameState.resolve_encounter()
	GameState.station.install(uid, &"wreck_dish")
	assert_eq(GameState.current_encounter.id, &"first_signal")
	assert_false(GameState.resolve_encounter(), "a choice is required")
	assert_true(GameState.resolve_encounter(0))
	assert_true(GameState.story.flag(&"met_signal"))
	GameClock.advance(5 * 60.0)
	assert_signal_not_emitted(EventBus, "visitor_requested")
	GameClock.advance(61.0)
	assert_eq(GameState.current_encounter.id, &"trader_rescue")
	assert_signal_emitted(EventBus, "visitor_requested")


func test_disabled_choice_cannot_be_picked() -> void:
	GameState.resolve_encounter()
	var night := GameState.encounter_db.get_encounter(&"lonely_night")
	assert_true(GameState.fire_encounter(&"lonely_night", true))
	assert_false(GameState.is_choice_enabled(night, 1), "needs met_signal")
	assert_false(GameState.resolve_encounter(1))
	assert_true(GameState.resolve_encounter(0))


func test_outcomes() -> void:
	var scrap := GameState.count(&"scrap_metal")
	GameState.apply_outcome("give scrap_metal 2")
	GameState.apply_outcome("take scrap_metal 100")
	assert_eq(GameState.count(&"scrap_metal"), 0, "take clamps at what's there")
	assert_gt(scrap, 0)
	GameState.needs.set_value(Needs.MORALE, 50.0)
	GameState.apply_outcome("need morale 10")
	assert_eq(GameState.needs.get_value(Needs.MORALE), 60.0)
	GameState.apply_outcome("count trades 2")
	assert_eq(GameState.story.count(&"trades"), 2)


func test_story_survives_save_and_load() -> void:
	GameState.apply_outcome("flag met_signal")
	GameState.apply_outcome("schedule trader_rescue 2")
	var data: Dictionary = JSON.parse_string(JSON.stringify(GameState.to_dict()))
	GameState.new_game()
	GameState.resolve_encounter()
	assert_false(GameState.story.flag(&"met_signal"))
	GameState.from_dict(data)
	assert_true(GameState.story.flag(&"met_signal"))
	assert_eq(GameState.current_encounter.id, &"intro", "the open encounter is restored")
	assert_eq(GameState.story.scheduled.size(), 1)


func test_disabling_the_story_closes_and_mutes() -> void:
	GameState.set_story_enabled(false)
	assert_null(GameState.current_encounter)
	GameState.station.repair(GameState.station.find_module(&"wreck_core"))
	assert_null(GameState.current_encounter)
	GameState.set_story_enabled(true)


func test_first_food_fires_the_harvest_beat() -> void:
	GameState.resolve_encounter()
	GameState.give({&"scrap_metal": 40, &"power_cell": 1})
	var wreck := GameState.station.find_module(&"wreck_core")
	GameState.station.repair(wreck)
	GameState.resolve_encounter()  # wreck_lights
	GameState.station.set_powered(wreck, true)
	assert_gt(GameState.build_module(&"solar_array", wreck, &"C"), 0)
	var bay := GameState.build_module(&"greenhouse", wreck, &"B")
	while GameState.current_encounter:
		GameState.resolve_encounter(0)
	assert_true(GameState.toggle_power(bay))
	while GameState.current_encounter:
		GameState.resolve_encounter(0)
	assert_eq(GameState.story.count(&"produced_food"), 0)
	GameClock.advance(60.0 / 0.15 + 5.0)
	assert_eq(GameState.story.count(&"produced_food"), 1)
	assert_eq(GameState.story.times_seen(&"first_harvest"), 1, "fired (maybe queued behind an hourly beat)")
	assert_gt(GameState.story_context.rate("food"), 0.0)
