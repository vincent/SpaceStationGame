extends GutTest

var builder: StationBuilder


func before_each() -> void:
	builder = add_child_autofree(StationBuilder.new())


func test_default_layout_builds_spawn_and_furniture() -> void:
	builder.build()
	assert_true(builder.is_built())
	assert_eq(builder.furniture_nodes.size(), 4, "bed, kitchen, 2 windows")


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
	assert_lt(approach.distance_to(builder.cell_to_world(Vector2i(2, 1))), StationBuilder.CELL * 0.5)


func test_rebuild_replaces_geometry() -> void:
	builder.build()
	builder.build()
	assert_eq(builder.get_children().size(), 1, "only one Generated node")


func test_cutaway_rule() -> void:
	var view := Vector3(-1, 0, -1).normalized()  # camera looks towards -X -Z
	assert_true(CutawayController.should_cut(Vector3(2, 0, 2), Vector3.ZERO, view, 9.0), "wall in front")
	assert_false(CutawayController.should_cut(Vector3(-2, 0, -2), Vector3.ZERO, view, 9.0), "wall behind")
	assert_false(CutawayController.should_cut(Vector3(20, 0, 20), Vector3.ZERO, view, 9.0), "too far")
