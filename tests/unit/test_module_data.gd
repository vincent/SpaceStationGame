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


func test_upgrades_point_at_existing_parts() -> void:
	for id in db.upgrade_ids():
		var up := db.get_upgrade(id)
		var def := db.get_module(up.module_id)
		assert_not_null(def, "%s: module %s exists" % [id, up.module_id])
		var module := (load(def.scene_path) as PackedScene).instantiate() as Module
		assert_not_null(module.get_node_or_null(NodePath("Parts/%s" % up.part_node)), "%s: part %s" % [id, up.part_node])
		module.free()
		for req in up.requires:
			assert_not_null(db.get_upgrade(req), "%s requires unknown %s" % [id, req])


func test_fits() -> void:
	var hab := db.get_module(&"hab_pod")
	assert_true(hab.fits(PackedStringArray(["module"])))
	assert_false(hab.fits(PackedStringArray(["visitor"])))
	assert_false(hab.fits(PackedStringArray(["module"]), 0), "size class too small")
	assert_true(db.get_module(&"capsule").fits(PackedStringArray(["capsule"])))
