extends GutTest
## StressLayout: grows a big, valid station for perf tests.

var db: ModuleDB
var st: StationState


func before_each() -> void:
	db = ModuleDB.new()
	db.load_dirs()
	st = StationState.new(db)
	var wreck := st.add_module(&"wreck_core", 0, &"", StationState.State.REPAIRED, 0.3, false)
	st.add_module(&"capsule", wreck, &"A")


func test_grows_many_modules() -> void:
	var added := StressLayout.grow(st, 60)
	assert_eq(added, 60, "the station has room for 60 more modules")
	assert_eq(st.uids().size(), 62)


func test_no_overlaps() -> void:
	StressLayout.grow(st, 60)
	var all := StationGrid.transforms(st)
	var rects := {}
	for uid in st.uids():
		rects[uid] = StationGrid.world_rects(st.get_def(uid), all[uid])
	var ids := st.uids()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			assert_false(StationGrid.overlaps(rects[ids[i]], rects[ids[j]]),
				"%s overlaps %s" % [st.get_record(ids[i]).module_id, st.get_record(ids[j]).module_id])


func test_deterministic() -> void:
	StressLayout.grow(st, 30, 7)
	var first: Array = st.uids().map(func(u: int) -> StringName: return st.get_record(u).module_id)
	before_each()
	StressLayout.grow(st, 30, 7)
	var second: Array = st.uids().map(func(u: int) -> StringName: return st.get_record(u).module_id)
	assert_eq(first, second)
