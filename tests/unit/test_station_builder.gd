extends GutTest

var builder: StationBuilder


func before_each() -> void:
	builder = add_child_autofree(StationBuilder.new())


func test_default_layout_builds_spawn_and_furniture() -> void:
	builder.build()
	assert_true(builder.is_built())
	assert_eq(builder.furniture_nodes.size(), 4, "bed, kitchen, 2 windows")
	assert_eq(builder.light_positions.size(), 2)


func test_custom_layout() -> void:
	builder.layout = "#####\n#P.B#\n#####"
	builder.build()
	assert_eq(builder.get_cell(Vector2i(1, 1)), "P")
	assert_eq(builder.get_cell(Vector2i(99, 99)), " ", "outside is space")
	assert_eq(builder.spawn_position, builder.cell_to_world(Vector2i(1, 1)))


func test_furniture_approach_point_is_on_free_neighbor() -> void:
	builder.layout = "#####\n#P.B#\n#####"
	builder.build()
	var bed := builder.furniture_nodes[0] as Interactable
	var approach := bed.get_approach_position()
	assert_lt(approach.distance_to(builder.to_global(builder.cell_to_world(Vector2i(2, 1)))), StationBuilder.CELL * 0.5)


func test_approach_point_follows_the_module() -> void:
	builder.layout = "#####\n#P.B#\n#####"
	builder.build()
	var bed := builder.furniture_nodes[0] as Interactable
	var before := bed.get_approach_position()
	builder.position = Vector3(10, 0, 5)
	assert_almost_eq(bed.get_approach_position(), before + Vector3(10, 0, 5), Vector3.ONE * 0.001)


func test_slot_letters_become_slot_cells_facing_space() -> void:
	builder.layout = "##b##\n#P..a\n#####"
	builder.build()
	assert_eq(builder.slot_cells.keys().size(), 2)
	assert_eq(builder.slot_cells[&"A"].cell, Vector2i(4, 1))
	assert_eq(builder.slot_cells[&"A"].outward, Vector2i.RIGHT)
	assert_eq(builder.slot_cells[&"B"].outward, Vector2i.UP)
	assert_true(StationBuilder.is_walkable("a"), "slot doorways are walkable")


func test_rebuild_replaces_geometry() -> void:
	builder.build()
	builder.build()
	assert_eq(builder.get_children().size(), 1, "only one Generated node")
