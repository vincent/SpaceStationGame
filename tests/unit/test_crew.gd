extends GutTest
## Crew rules on a scratch station: beds, jobs, staffing, schedule, meals, save.

var db: ModuleDB
var st: StationState
var stock: StationStock
var wreck: int


func before_each() -> void:
	db = ModuleDB.new()
	db.load_dirs()
	st = StationState.new(db)
	stock = StationStock.new()
	wreck = st.add_module(&"wreck_core", 0, &"", StationState.State.DERELICT, 1.0, false)
	st.add_module(&"capsule", wreck, &"A", StationState.State.REPAIRED, 0.25, true)


## A repaired, powered station with a dormitory (6 bunks) and a greenhouse.
func _station() -> Dictionary:
	st.repair(wreck)
	var bay := st.add_module(&"greenhouse", wreck, &"B", StationState.State.REPAIRED, 0.3, false)
	assert_true(st.set_powered(bay, true), "bay powered")
	var hab := _attach_anywhere(&"dorm")
	if hab == 0:  # no direct fit: through a corridor
		var corridor := _attach_anywhere(&"corridor")
		assert_gt(corridor, 0, "corridor attached")
		hab = _attach_anywhere(&"dorm")
	assert_gt(hab, 0, "dorm attached")
	return {"bay": bay, "hab": hab}


func _attach_anywhere(module_id: StringName) -> int:
	for uid in st.uids():
		for slot in st.free_slots(uid):
			for by in st.attach_options(module_id, uid, slot):
				return st.add_module(module_id, uid, slot, StationState.State.REPAIRED, 0.3, false, by)
	return 0


func test_beds_need_a_habitat() -> void:
	assert_eq(st.crew.capacity(), 0, "the capsule bunk is the castaway's")
	assert_null(st.crew.add("Ines"), "no bed, no crew")
	var hab: int = _station().hab
	assert_eq(st.crew.beds(hab), 6)
	assert_eq(st.crew.capacity(), 6)
	for i in 6:
		var m := st.crew.add("Crew %d" % i)
		assert_not_null(m)
		assert_eq(m.home_uid, hab)
	assert_eq(st.crew.free_beds(), 0)
	assert_null(st.crew.add("Yara"), "station full")


func test_assign_and_staffing() -> void:
	var s := _station()
	var a := st.crew.add("Ines")
	var b := st.crew.add("Tomas")
	assert_eq(st.crew.jobs(s.bay), 2)
	assert_eq(st.crew.staffing(s.bay), 1.0)
	assert_ne(st.crew.assign_error(a.id, s.hab), "", "no jobs in a habitat")
	assert_eq(st.crew.assign(a.id, s.bay), "")
	assert_almost_eq(st.crew.staffing(s.bay), 1.25, 0.0001)
	assert_eq(st.crew.assign(b.id, s.bay), "")
	assert_almost_eq(st.crew.staffing(s.bay), 1.5, 0.0001)
	assert_eq(st.crew.workers(s.bay).size(), 2)
	assert_true(st.crew.idle().is_empty())
	assert_true(st.crew.unassign(a.id))
	assert_eq(st.crew.workers(s.bay).size(), 1)
	assert_eq(st.crew.assign_error(a.id, wreck), "")


func test_staffed_production() -> void:
	var s := _station()
	stock.add(&"water", 50.0)
	var unstaffed: float = Production.rates(st, stock)[&"food"]
	var a := st.crew.add("Ines")
	st.crew.assign(a.id, s.bay)
	var info := Production.module_rates(st, stock, s.bay)
	assert_eq(info.status, Production.Status.RUNNING, "staffing isn't starvation")
	assert_almost_eq(info.staffing, 1.25, 0.0001)
	assert_almost_eq(Production.rates(st, stock)[&"food"], unstaffed * 1.25, 0.0001)


func test_schedule() -> void:
	var n := Needs.new()
	assert_eq(CrewSchedule.activity(23.0, n, true), &"sleeping")
	assert_eq(CrewSchedule.activity(3.0, n, false), &"sleeping")
	assert_eq(CrewSchedule.activity(10.0, n, true), &"working")
	assert_eq(CrewSchedule.activity(10.0, n, false), &"idle")
	assert_eq(CrewSchedule.activity(12.5, n, true), &"working", "not hungry: keeps working")
	n.set_value(Needs.FOOD, 50.0)
	assert_eq(CrewSchedule.activity(12.5, n, true), &"eating")
	n.set_value(Needs.ENERGY, 5.0)
	assert_eq(CrewSchedule.activity(10.0, n, true), &"sleeping", "exhausted")


func test_meals_use_station_food() -> void:
	_station()
	var a := st.crew.add("Ines")
	a.needs.set_value(Needs.FOOD, 40.0)
	stock.add(&"food", 2.0)
	var eaten := CrewSchedule.tick(st, stock, 12.0 * 60.0, 30.0, GameState.ACTIVITY_RATES)
	assert_almost_eq(eaten, CrewSchedule.MEAL_FOOD, 0.0001)
	assert_almost_eq(stock.amount(&"food"), 2.0 - CrewSchedule.MEAL_FOOD, 0.0001)
	assert_gt(a.needs.get_value(Needs.FOOD), 80.0)


func test_starving_crew_lose_morale() -> void:
	_station()
	var a := st.crew.add("Ines")
	a.needs.set_value(Needs.FOOD, 5.0)
	var morale := a.needs.get_value(Needs.MORALE)
	CrewSchedule.tick(st, stock, 10.0 * 60.0, 60.0, GameState.ACTIVITY_RATES)
	assert_lt(a.needs.get_value(Needs.MORALE), morale - Needs.DEFAULT_DECAY[Needs.MORALE])


func test_long_skip_tracks_the_hour() -> void:
	_station()
	var a := st.crew.add("Ines")
	a.needs.set_value(Needs.ENERGY, 30.0)
	CrewSchedule.tick(st, stock, 22.0 * 60.0, 8.0 * 60.0, GameState.ACTIVITY_RATES)
	assert_gt(a.needs.get_value(Needs.ENERGY), 95.0, "slept through the night")
	assert_eq(a.activity, &"sleeping")


func test_save_round_trip() -> void:
	var s := _station()
	var a := st.crew.add("Ines", 3)
	st.crew.assign(a.id, s.bay)
	a.needs.set_value(Needs.MORALE, 42.0)
	var copy := StationState.new(db)
	copy.from_dict(JSON.parse_string(JSON.stringify(st.to_dict())))
	assert_eq(copy.crew.size(), 1)
	var b := copy.crew.members[0]
	assert_eq(b.display_name, "Ines")
	assert_eq(b.look, 3)
	assert_eq(b.job_uid, s.bay)
	assert_eq(b.home_uid, s.hab)
	assert_almost_eq(b.needs.get_value(Needs.MORALE), 42.0, 0.001)
	assert_eq(copy.crew.add("Tomas").id, a.id + 1, "ids keep counting")


func test_removed_module_drops_job() -> void:
	var s := _station()
	var a := st.crew.add("Ines")
	st.crew.assign(a.id, s.bay)
	st.remove_module(s.bay)
	assert_false(a.has_job())
