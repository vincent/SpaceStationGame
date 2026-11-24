extends GutTest

var db: ModuleDB
var st: StationState
var wreck: int
var capsule: int


func before_each() -> void:
	db = ModuleDB.new()
	db.load_dirs()
	st = StationState.new(db)
	wreck = st.add_module(&"wreck_core", 0, &"", StationState.State.DERELICT, 1.0, false)
	capsule = st.add_module(&"capsule", wreck, &"A", StationState.State.REPAIRED, 0.25, true)


func test_story_start() -> void:
	assert_gt(wreck, 0)
	assert_gt(capsule, 0)
	assert_eq(st.get_record(capsule).parent, wreck)
	assert_true(st.get_record(capsule).powered)
	assert_false(st.get_record(wreck).powered)


func test_attach_rules() -> void:
	assert_eq(st.attach_error(&"hab_pod", wreck, &"A"), "Slot is taken")
	assert_ne(st.attach_error(&"hab_pod", wreck, &"V"), "", "visitor dock refuses modules")
	assert_ne(st.attach_error(&"hab_pod", wreck, &"Z"), "", "unknown slot")
	assert_eq(st.attach_error(&"hab_pod", wreck, &"B"), "")
	assert_eq(st.attach_error(&"trader_ship", wreck, &"V"), "")
	assert_eq(st.add_module(&"hab_pod", wreck, &"A"), 0, "taken slot rejected")
	var hab := st.add_module(&"hab_pod", wreck, &"B")
	assert_gt(hab, 0)
	assert_eq(st.occupant(wreck, &"B"), hab)
	assert_false(st.free_slots(wreck).has(&"B"))


func test_power_budget() -> void:
	assert_eq(st.power_output(), 3.0, "capsule makes 3")
	assert_eq(st.power_draw(), 1.0, "capsule draws 1")
	assert_eq(st.power_error(wreck), "Repair it first")
	assert_false(st.set_powered(wreck, true))
	st.repair(wreck)
	assert_true(st.set_powered(wreck, true), "1 + 2 <= 3")
	assert_eq(st.power_draw(), 3.0)
	var hab := st.add_module(&"hab_pod", wreck, &"B")
	assert_ne(st.power_error(hab), "", "no power left for the hab")
	var solar := st.add_module(&"solar_array", wreck, &"C")
	assert_eq(st.power_output(), 6.0, "solar adds 3 without being switched on")
	assert_true(st.set_powered(hab, true))
	assert_true(st.set_powered(wreck, false))
	assert_eq(st.power_draw(), 2.0)
	assert_gt(solar, 0)


func test_solar_arrays_chain() -> void:
	var first := st.add_module(&"solar_array", wreck, &"C")
	assert_true(st.free_slots(first).has(&"B"), "the array offers its north hatch")
	assert_eq(st.attach_error(&"solar_array", first, &"B"), "", "an array fits on an array")
	var second := st.add_module(&"solar_array", first, &"B")
	assert_eq(st.attach_error(&"solar_array", second, &"B"), "", "and the chain goes on")
	assert_gt(st.add_module(&"solar_array", second, &"B"), second)


func test_repair_lowers_wear_but_never_to_zero() -> void:
	assert_true(st.repair(wreck))
	assert_false(st.repair(wreck), "only once")
	assert_eq(st.get_record(wreck).state, StationState.State.REPAIRED)
	assert_almost_eq(st.get_record(wreck).wear, StationState.REPAIRED_WEAR, 0.001)
	st.set_wear(wreck, 0.0)
	assert_almost_eq(st.get_record(wreck).wear, StationState.MIN_WEAR, 0.001)


func test_upgrade_prerequisites_and_effects_apply_once() -> void:
	assert_eq(st.install_error(capsule, &"capsule_thruster"), "Needs Solar wings")
	assert_true(st.install(capsule, &"capsule_solar"))
	assert_false(st.install(capsule, &"capsule_solar"), "already installed")
	assert_eq(st.power_output(), 5.0, "+2 once")
	assert_eq(st.install_error(capsule, &"capsule_thruster"), "")
	assert_eq(st.install_error(capsule, &"wreck_reactor"), "Wrong module")
	assert_eq(st.install_error(wreck, &"wreck_reactor"), "Repair it first")
	assert_eq(st.get_record(capsule).state, StationState.State.UPGRADED)
	assert_eq(st.level(capsule), 1)
	assert_true(st.install(capsule, &"capsule_antenna"))
	assert_almost_eq(st.effect_total(&"morale_decay"), -0.5, 0.001)


func test_save_round_trip_skips_visitors() -> void:
	st.repair(wreck)
	st.install(capsule, &"capsule_solar")
	var hab := st.add_module(&"hab_pod", wreck, &"B", StationState.State.REPAIRED, 0.4, false)
	st.add_module(&"trader_ship", wreck, &"V")
	var json := JSON.stringify(st.to_dict())
	var copy := StationState.new(db)
	copy.from_dict(JSON.parse_string(json))
	assert_eq(copy.uids().size(), 3, "trader not saved")
	assert_eq(copy.get_record(hab).slot, &"B")
	assert_eq(copy.get_record(hab).parent, wreck)
	assert_eq(copy.installed(capsule), [&"capsule_solar"] as Array[StringName])
	assert_eq(copy.power_output(), st.power_output())
	assert_gt(copy.add_module(&"solar_array", wreck, &"C"), hab, "uids keep increasing")


func test_remove_module_removes_children() -> void:
	var hab := st.add_module(&"hab_pod", wreck, &"B")
	watch_signals(st)
	st.remove_module(wreck)
	assert_false(st.has_module(hab))
	assert_false(st.has_module(capsule))
	assert_signal_emit_count(st, "module_removed", 3)
