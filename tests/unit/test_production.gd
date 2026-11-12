extends GutTest
## Production rules on a scratch station (not the GameState one).

var modules: ModuleDB
var station: StationState
var stock: StationStock
var wreck: int


func before_each() -> void:
	modules = ModuleDB.new()
	modules.load_dirs()
	station = StationState.new(modules)
	stock = StationStock.new()
	wreck = station.add_module(&"wreck_core", 0, &"", StationState.State.DERELICT, 1.0, false)
	station.add_module(&"capsule", wreck, &"A", StationState.State.REPAIRED, 0.25, true)


## A repaired agri bay on the wreck, plus a solar array so there's power.
func _agri(powered: bool = true) -> int:
	station.repair(wreck)
	station.add_module(&"solar_array", wreck, &"C", StationState.State.REPAIRED, 0.3, false)
	var bay := station.add_module(&"agri_bay", wreck, &"B", StationState.State.REPAIRED, 0.3, false)
	if powered:
		assert_true(station.set_powered(bay, true), "enough power for the bay")
	return bay


func test_statuses() -> void:
	var st := Production.module_rates(station, stock, wreck)
	assert_eq(st.status, Production.Status.DERELICT)
	station.repair(wreck)
	assert_eq(Production.module_rates(station, stock, wreck).status, Production.Status.UNPOWERED)
	station.set_powered(wreck, true)
	var running := Production.module_rates(station, stock, wreck)
	assert_eq(running.status, Production.Status.RUNNING)
	assert_almost_eq(running.rates[&"water"], 0.3, 0.0001)


func test_starved_without_inputs() -> void:
	var bay := _agri()
	var info := Production.module_rates(station, stock, bay)
	assert_eq(info.status, Production.Status.STARVED)
	assert_eq(info.missing, &"water")
	stock.add(&"water", 5.0)
	assert_eq(Production.module_rates(station, stock, bay).status, Production.Status.RUNNING)


func test_net_rates() -> void:
	_agri()
	station.set_powered(wreck, true)
	stock.add(&"water", 5.0)
	var rates := Production.rates(station, stock)
	assert_almost_eq(rates[&"food"], 0.15, 0.0001)
	assert_almost_eq(rates[&"water"], 0.3 - 0.15, 0.0001)


func test_partial_inputs() -> void:
	var bay := _agri()
	stock.add(&"water", 0.15 * 0.5)  # half of what one hour needs
	Production.tick(station, stock, 60.0)
	assert_almost_eq(stock.amount(&"food"), 0.15 * 0.5, 0.0001, "runs at 50 % efficiency")
	assert_almost_eq(stock.amount(&"water"), 0.0, 0.0001)
	assert_eq(Production.module_rates(station, stock, bay).status, Production.Status.STARVED)


func test_upgrade_production_adds_to_the_base() -> void:
	var bay := _agri()
	assert_true(station.install(bay, &"agri_hydroponics"))
	var base := Production.base(station, bay)
	assert_almost_eq(base[&"food"], 0.35, 0.0001)
	assert_almost_eq(base[&"water"], -0.3, 0.0001)
	assert_almost_eq(station.module_draw(bay), 2.0, 0.0001, "the tier draws more power")


func test_chain_wreck_water_feeds_the_agri_bay_for_a_day() -> void:
	_agri()
	assert_true(station.set_powered(wreck, true))
	for hour in 24:
		Production.tick(station, stock, 60.0)
	assert_almost_eq(stock.amount(&"food"), 0.15 * 24, 0.001)
	assert_almost_eq(stock.amount(&"water"), (0.3 - 0.15) * 24, 0.001)


func test_one_long_tick_equals_many_short_ones() -> void:
	_agri()
	station.set_powered(wreck, true)
	Production.tick(station, stock, 8 * 60.0)  # a night's sleep is one advance
	assert_almost_eq(stock.amount(&"food"), 0.15 * 8, 0.001, "the wreck fills the tank first (uid order)")


func test_unpowered_and_derelict_make_nothing() -> void:
	var bay := _agri(false)
	stock.add(&"water", 5.0)
	var deltas := Production.tick(station, stock, 600.0)
	assert_true(deltas.is_empty())
	assert_eq(Production.module_rates(station, stock, bay).status, Production.Status.UNPOWERED)


func test_rows_for_a_resource() -> void:
	var bay := _agri(false)
	var rows := Production.rows_for(station, stock, &"food")
	assert_eq(rows.size(), 2, "the bay + its locked hydroponics tier")
	assert_eq(rows[0].uid, bay)
	assert_eq(rows[0].status, Production.Status.UNPOWERED)
	assert_eq(rows[1].status, Production.Status.LOCKED)
	assert_eq(rows[1].upgrade_id, &"agri_hydroponics")
	var water := Production.rows_for(station, stock, &"water")
	assert_eq(water[0].uid, wreck, "producers first")
	assert_eq(water[-1].uid, bay, "consumers last")
	assert_lt(water[-1].nominal, 0.0)
	assert_true(Production.has_producer(station, &"food"))
	assert_false(Production.has_producer(station, &"scrap_metal"))
