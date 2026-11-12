extends GutTest
## GameState's wallet: bulk ids live in the stock, the rest in the inventory.

func before_each() -> void:
	GameClock.paused = true
	GameState.set_story_enabled(false)
	GameState.new_game()


func after_all() -> void:
	GameClock.paused = false
	GameState.set_story_enabled(true)
	GameState.new_game()


func test_give_routes_by_bulk() -> void:
	var scrap := GameState.stock.amount(&"scrap_metal")
	GameState.give({&"scrap_metal": 3, &"power_cell": 1})
	assert_eq(GameState.stock.amount(&"scrap_metal"), scrap + 3)
	assert_eq(GameState.inventory.count_of(&"scrap_metal"), 0)
	assert_eq(GameState.inventory.count_of(&"power_cell"), GameState.STARTING_ITEMS[&"power_cell"] + 1)


func test_mixed_cost_is_all_or_nothing() -> void:
	var cost := {&"scrap_metal": 2, &"power_cell": 1}
	assert_true(GameState.pay(cost))
	assert_eq(GameState.count(&"scrap_metal"), GameState.STARTING_ITEMS[&"scrap_metal"] - 2)
	assert_eq(GameState.count(&"power_cell"), GameState.STARTING_ITEMS[&"power_cell"] - 1)
	var before := GameState.count(&"scrap_metal")
	assert_false(GameState.pay({&"scrap_metal": 1, &"power_cell": 99}))
	assert_eq(GameState.count(&"scrap_metal"), before, "nothing paid when part is missing")


func test_fractional_stock_pays_whole_units_only() -> void:
	GameState.stock.set_amount(&"water", 0.0)
	GameState.stock.add(&"water", 0.9)
	assert_false(GameState.has_all({&"water": 1}))
	GameState.stock.add(&"water", 0.1)
	assert_true(GameState.pay({&"water": 1}))


func test_trader_and_outcomes_use_the_stock() -> void:
	var food := GameState.count(&"food")
	assert_true(GameState.trade({&"scrap_metal": 4}, {&"food": 3}))
	assert_eq(GameState.stock.count(&"food"), food + 3)
	GameState.apply_outcome("take food 2")
	GameState.apply_outcome("give water 5")
	assert_eq(GameState.stock.count(&"food"), food + 1)
	assert_eq(GameState.stock.count(&"water"), GameState.STARTING_ITEMS[&"water"] + 5)
	assert_true(GameState.story_context.evaluate('item("food") == %d and has_item("power_cell", 2)' % (food + 1)))


func test_build_costs_come_from_the_stock() -> void:
	GameState.give({&"scrap_metal": 20})
	var wreck := GameState.station.find_module(&"wreck_core")
	var before := GameState.count(&"scrap_metal")
	assert_gt(GameState.build_module(&"agri_bay", wreck, &"B"), 0)
	assert_eq(GameState.count(&"scrap_metal"), before - 10)


func test_production_runs_on_the_clock() -> void:
	GameState.give({&"scrap_metal": 30})
	var wreck := GameState.station.find_module(&"wreck_core")
	assert_true(GameState.repair_module(wreck))
	assert_true(GameState.toggle_power(wreck))
	var water := GameState.stock.amount(&"water")
	GameState.sleep(8)
	assert_almost_eq(GameState.stock.amount(&"water"), water + 0.3 * 8, 0.001, "sleeping produces too")
	assert_almost_eq(Production.rates(GameState.station, GameState.stock)[&"water"], 0.3, 0.0001)
