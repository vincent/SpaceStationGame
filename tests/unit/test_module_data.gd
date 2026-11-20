extends GutTest
## Validates every ModuleDef / UpgradeDef against its module scene.

var db: ModuleDB


func before_all() -> void:
	db = ModuleDB.new()
	db.load_dirs()


func test_modules_load() -> void:
	assert_gt(db.module_ids().size(), 3)
	assert_not_null(db.get_module(&"capsule"))
	assert_not_null(db.get_module(&"wreck_core"))


func test_every_module_scene_matches_its_definition() -> void:
	for id in db.module_ids():
		var def := db.get_module(id)
		assert_true(ResourceLoader.exists(def.scene_path), "%s scene exists" % id)
		var module := (load(def.scene_path) as PackedScene).instantiate() as Module
		assert_not_null(module, "%s root is a Module" % id)
		assert_eq(module.module_id, id)
		module.def = def
		add_child_autofree(module)
		module.build()
		for slot: StringName in def.slots:
			assert_true(module.slots.has(slot), "%s scene has slot %s" % [id, slot])
		for slot: StringName in module.slots:
			assert_true(def.slots.has(slot), "%s def declares slot %s" % [id, slot])
		assert_true(module.slots.has(def.attach_slot), "%s attach slot exists" % id)
		assert_eq(def.layout, module.interior_ascii, "%s def layout = scene interior_ascii" % id)
		# StationGrid places modules from data only: its slot frames must be the scene's.
		var frames := StationGrid.slot_frames(def)
		for slot: StringName in module.slots:
			var s: Slot = module.slots[slot]
			assert_true(frames.has(slot), "%s grid knows slot %s" % [id, slot])
			if frames.has(slot):
				var f: Transform3D = frames[slot]
				assert_almost_eq(f.origin, s.transform.origin, Vector3.ONE * 0.02, "%s slot %s position" % [id, slot])
				assert_almost_eq(f.basis.z, s.transform.basis.z, Vector3.ONE * 0.02, "%s slot %s facing" % [id, slot])
				var rects := StationGrid.footprint(def)
				var inside := false
				for r in rects:
					inside = inside or r.grow(-0.05).has_point(Vector2(f.origin.x, f.origin.z))
				assert_false(inside, "%s slot %s lies outside its footprint" % [id, slot])


func test_upgrades_resolve_to_parts() -> void:
	for id in db.upgrade_ids():
		var up := db.get_upgrade(id)
		var def := db.get_module(up.module_id)
		assert_not_null(def, "%s: module %s exists" % [id, up.module_id])
		if def == null:
			continue
		var module := (load(def.scene_path) as PackedScene).instantiate() as Module
		module.def = def
		add_child_autofree(module)
		var authored := module.has_node(NodePath("Parts/%s" % up.part_node))
		if up.mount != &"":
			assert_false(authored, "%s: mounted part %s must not also be authored" % [id, up.part_node])
			assert_not_null(module.get_mount(up.mount), "%s: scene has mount_%s" % [id, up.mount])
		module.build()
		var part := module.get_node_or_null(NodePath("Parts/%s" % up.part_node)) as ModulePart
		assert_not_null(part, "%s: part %s" % [id, up.part_node])
		if part and up.mount != &"":
			var mount := module.get_mount(up.mount)
			assert_almost_eq(part.global_position, mount.global_position, Vector3.ONE * 0.001,
				"%s: part sits on its mount" % id)


func test_upgrade_definitions_are_valid() -> void:
	var items := ItemDB.new()
	items.load_dir()
	for id in db.upgrade_ids():
		var up := db.get_upgrade(id)
		var errors := up.validate(items)
		assert_eq(errors.size(), 0, "\n".join(errors))
		for req in up.requires:
			var req_def := db.get_upgrade(req)
			assert_not_null(req_def, "%s requires unknown %s" % [id, req])
			if req_def:
				assert_eq(req_def.module_id, up.module_id, "%s requires an upgrade of another module" % id)
		assert_false(_requires_cycle(id, []), "%s: requires cycle" % id)


func test_production_uses_bulk_items() -> void:
	var items := ItemDB.new()
	items.load_dir()
	var producers := 0
	for id in db.module_ids():
		var def := db.get_module(id)
		var errors := UpgradeDef.validate_production(String(id), def.production, items)
		assert_eq(errors.size(), 0, "\n".join(errors))
		producers += 1 if not def.production.is_empty() else 0
	assert_gt(producers, 1, "the wreck and the greenhouse produce")


func test_part_nodes_are_unique_per_module() -> void:
	for module_id in db.module_ids():
		var seen := {}
		for up in db.upgrades_for(module_id):
			assert_false(seen.has(up.part_node), "%s: two upgrades reveal %s" % [module_id, up.part_node])
			seen[up.part_node] = true


func _requires_cycle(id: StringName, path: Array) -> bool:
	if path.has(id):
		return true
	var up := db.get_upgrade(id)
	if up == null:
		return false
	for req in up.requires:
		if _requires_cycle(req, path + [id]):
			return true
	return false


func test_fits() -> void:
	var hab := db.get_module(&"hab_pod")
	assert_true(hab.fits(PackedStringArray(["module"])))
	assert_false(hab.fits(PackedStringArray(["visitor"])))
	assert_false(hab.fits(PackedStringArray(["module"]), 0), "size class too small")
	assert_true(db.get_module(&"capsule").fits(PackedStringArray(["capsule"])))


func test_crew_data() -> void:
	for id in db.module_ids():
		var def := db.get_module(id)
		assert_gte(def.jobs, 0, "%s: jobs" % id)
		if def.jobs > 0:
			assert_false(def.production.is_empty(), "%s: jobs only make sense on producers" % id)
	assert_eq(db.get_module(&"dorm").crew_beds(), 6)
	assert_eq(db.get_module(&"greenhouse").jobs, 2)


## Furniture (B, K, C, S, T, G) and "#" cells block the navmesh: every doorway must
## still reach every other one over free floor, or the castaway can't walk through.
func test_every_doorway_reaches_the_others() -> void:
	var free := StationBuilder.FREE_FLOOR + StationBuilder.SLOT_LETTERS
	for id in db.module_ids():
		var grid := StationBuilder.parse(db.get_module(id).layout)
		var doors: Array[Vector2i] = []
		for r in grid.size():
			for c in grid[r].length():
				if StationBuilder.SLOT_LETTERS.contains(grid[r][c]):
					doors.append(Vector2i(c, r))
		if doors.size() < 2:
			continue
		var seen: Dictionary[Vector2i, bool] = {doors[0]: true}
		var todo: Array[Vector2i] = [doors[0]]
		while not todo.is_empty():
			var cell: Vector2i = todo.pop_back()
			for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var n := cell + d
				if seen.has(n) or n.y < 0 or n.y >= grid.size() or n.x < 0 or n.x >= grid[n.y].length():
					continue
				if free.contains(grid[n.y][n.x]):
					seen[n] = true
					todo.append(n)
		for door in doors:
			assert_true(seen.has(door), "%s: doorway '%s' reachable from '%s'" % [
				id, grid[door.y][door.x], grid[doors[0].y][doors[0].x]])
