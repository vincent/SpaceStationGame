extends GutTest
## StationGrid: placement of branching stations (orientation, overlaps).

var db: ModuleDB
var st: StationState
var wreck: int


func before_each() -> void:
	db = ModuleDB.new()
	db.load_dirs()
	st = StationState.new(db)
	wreck = st.add_module(&"wreck_core", 0, &"", StationState.State.REPAIRED, 0.3, false)
	st.add_module(&"capsule", wreck, &"A")


func test_starting_station_does_not_overlap() -> void:
	var all := StationGrid.transforms(st)
	var capsule := st.find_module(&"capsule")
	assert_false(StationGrid.overlaps(
		StationGrid.world_rects(db.get_module(&"wreck_core"), all[wreck]),
		StationGrid.world_rects(db.get_module(&"capsule"), all[capsule])))


func test_child_faces_its_parent_slot() -> void:
	var corridor := st.add_module(&"corridor", wreck, &"B")
	assert_ne(corridor, 0)
	var xform: Transform3D = StationGrid.transforms(st)[corridor]
	# Wreck slot B faces -X: the corridor runs along -X, its slot B at the far end.
	var far: Transform3D = xform * StationGrid.slot_frames(db.get_module(&"corridor"))[&"B"]
	assert_lt(far.origin.x, -4.45 - 5.0)
	assert_almost_eq(far.basis.z, Vector3.LEFT, Vector3.ONE * 0.01)


func test_own_slot_is_not_free() -> void:
	var corridor := st.add_module(&"corridor", wreck, &"B")
	assert_eq(st.free_slots(corridor), [&"B"] as Array[StringName])
	assert_ne(st.attach_error(&"corridor", corridor, &"A"), "", "can't build on the slot it attaches by")


func test_rotation_options() -> void:
	var hub := st.add_module(&"hub_x", wreck, &"B")
	assert_eq(st.attach_options(&"junction_t", hub, &"B").size(), 3, "a T fits a hub arm by any of its 3 slots")
	assert_eq(st.attach_options(&"hab_pod", hub, &"B"), [&"A"] as Array[StringName])
	var t := st.add_module(&"junction_t", hub, &"D", StationState.State.REPAIRED, 0.3, false, &"B")
	assert_eq(st.own_slot(t), &"B")
	assert_eq(st.free_slots(t), [&"A", &"C"] as Array[StringName])


func test_overlapping_placement_is_blocked() -> void:
	# Two doorways 2 m apart on the same side: a 6.6 m wide hab pod on one
	# leaves no room for anything wide on the other.
	var root := ModuleDef.new()
	root.id = &"test_root"
	root.display_name = "Test root"
	root.layout = "#ab#\n#..#\n####"
	root.slots = {&"A": PackedStringArray(["module"]), &"B": PackedStringArray(["module"])}
	db.register_module(root)
	var st2 := StationState.new(db)
	var r := st2.add_module(&"test_root")
	assert_ne(st2.add_module(&"hab_pod", r, &"A"), 0)
	assert_string_contains(st2.attach_error(&"hab_pod", r, &"B"), "Blocked by Hab pod")
	assert_eq(st2.attach_options(&"hab_pod", r, &"B"), [] as Array[StringName])


func test_save_keeps_orientation_and_migrates_old_saves() -> void:
	var hub := st.add_module(&"hub_x", wreck, &"B")
	var t := st.add_module(&"junction_t", hub, &"D", StationState.State.REPAIRED, 0.3, false, &"C")
	var data := st.to_dict()
	var copy := StationState.new(db)
	copy.from_dict(data)
	assert_eq(copy.own_slot(t), &"C")
	for m: Dictionary in data.modules:
		m.erase("own_slot")
	copy.from_dict(data)
	assert_eq(copy.own_slot(t), &"A", "v4 saves attach by the default slot")


func test_hatch_sizes() -> void:
	var big := ModuleDef.new()
	big.id = &"test_big"
	big.display_name = "Big"
	big.size_class = 3
	big.buildable = true
	big.layout = "#####\n#...#\n##a##"
	big.slots = {&"A": PackedStringArray(["module"])}
	db.register_module(big)
	assert_eq(st.attach_error(&"test_big", wreck, &"B"), "Needs a large hatch")
	var adapter := st.add_module(&"adapter_ml", wreck, &"B")
	assert_ne(adapter, 0)
	assert_eq(st.attach_options(&"adapter_ml", wreck, &"C"), [&"A"] as Array[StringName],
		"its L side can't go on an M hatch")
	assert_eq(st.attach_error(&"test_big", adapter, &"B"), "")
	assert_eq(st.attach_error(&"hab_pod", adapter, &"B"), "", "smaller fits a larger hatch")
