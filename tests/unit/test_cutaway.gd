extends GutTest

const MODULE := AABB(Vector3(-7, -0.6, -4), Vector3(14, 4.2, 8))


func test_open_amount_thresholds() -> void:
	assert_eq(CutawayController.open_amount(0.0), 0.0)
	assert_eq(CutawayController.open_amount(0.3), 0.0, "closed below 0.3")
	assert_between(CutawayController.open_amount(0.5), 0.1, 0.9)
	assert_eq(CutawayController.open_amount(0.7), 1.0, "fully open above 0.7")


func test_closed_box_is_empty() -> void:
	var box := CutawayController.compute_box(MODULE, 0.0, 0.0)
	assert_almost_eq(box.size.y, 0.0, 0.0001)


func test_focused_room_is_never_inside_the_box() -> void:
	for amount: float in [0.0, 0.5, 1.0]:
		var box := CutawayController.compute_box(MODULE, 0.0, amount)
		for room: Vector3 in [Vector3(0, 0.9, 0), Vector3(-5, 0.5, 2), Vector3(5, 1.0, -2)]:
			assert_false(box.has_point(room), "room point %s outside box (open %s)" % [room, amount])


func test_camera_to_room_segment_crosses_the_box() -> void:
	var box := CutawayController.compute_box(MODULE, 0.0, 1.0)
	var basis := Basis.from_euler(Vector3(deg_to_rad(-28.0), deg_to_rad(25.0), 0.0))
	var room := Vector3(0, 0.9, 0)
	var cam := room + basis.z * 80.0
	assert_not_null(box.intersects_segment(cam, room), "line of sight passes through the cut")


func test_box_covers_hull_top_and_cuts_walls_at_cut_height() -> void:
	var box := CutawayController.compute_box(MODULE, 0.0, 1.0)
	assert_gt(box.end.y, MODULE.end.y)
	assert_almost_eq(box.position.y, CutawayController.CUT_HEIGHT, 0.001)
	assert_lt(box.position.x, MODULE.position.x)
	assert_lt(box.position.x, MODULE.position.x - CutawayController.MARGIN + 0.001)
	assert_lt(CutawayController.MARGIN, Slot.GAP * 2.0, "never nicks a neighbour")
