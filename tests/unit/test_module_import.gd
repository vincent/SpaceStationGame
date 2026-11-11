extends GutTest


func test_classify() -> void:
	assert_eq(ModuleImportRules.classify("hull"), ModuleImportRules.Kind.HULL)
	assert_eq(ModuleImportRules.classify("slot_A"), ModuleImportRules.Kind.SLOT)
	assert_eq(ModuleImportRules.classify("part_reactor"), ModuleImportRules.Kind.PART)
	assert_eq(ModuleImportRules.classify("light_galley"), ModuleImportRules.Kind.LIGHT)
	assert_eq(ModuleImportRules.classify("floor-col"), ModuleImportRules.Kind.COLLISION)
	assert_eq(ModuleImportRules.classify("deck-nav"), ModuleImportRules.Kind.NAV)
	assert_eq(ModuleImportRules.classify("pipe_01"), ModuleImportRules.Kind.NONE)
	assert_eq(ModuleImportRules.slot_name("slot_b"), &"B")


func test_apply_converts_nodes() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	for n: String in ["slot_a", "light_main", "part_dish"]:
		var node := Node3D.new()
		node.name = n
		root.add_child(node)
		node.owner = root
	var part := root.get_node("part_dish")
	part.set_meta(&"extras", {"explode_dir": [0, 1, 0]})
	var deck := MeshInstance3D.new()
	deck.name = "deck-nav"
	var plane := PlaneMesh.new()
	plane.size = Vector2(4, 4)
	deck.mesh = plane
	root.add_child(deck)
	deck.owner = root
	assert_eq(ModuleImportRules.apply(root), 4)
	assert_true(root.get_node("slot_a") is Marker3D)
	assert_true(root.get_node("light_main").is_in_group(&"light_anchor"))
	var converted := root.get_node("Parts/part_dish")
	assert_true(converted is ModulePart)
	assert_eq(converted.explode_dir, Vector3.UP)
	assert_false(deck.visible)
	var body := deck.get_child(0) as StaticBody3D
	assert_eq(body.collision_layer, Layers.WORLD)
