extends GutTest

const STATION := AABB(Vector3(-20, -1, -5), Vector3(48, 6, 12))
const ROOM := AABB(Vector3(-20, -1, -5), Vector3(14, 4, 8))

var rig: DioramaCamera


func before_each() -> void:
	rig = DioramaCamera.new()
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	rig.add_child(cam)
	add_child_autofree(rig)
	rig.set_station_aabb(STATION)


## Every corner of `aabb` projects inside the camera's frame.
func _all_in_frame(aabb: AABB) -> bool:
	var view := rig.get_viewport().get_visible_rect().size
	for i in 8:
		var p := rig.camera.unproject_position(aabb.get_endpoint(i))
		if p.x < -0.5 or p.y < -0.5 or p.x > view.x + 0.5 or p.y > view.y + 0.5:
			return false
	return true


func test_rotation_is_the_fixed_oblique_angle() -> void:
	assert_almost_eq(rig.rotation_degrees.x, -28.0, 0.01)
	assert_almost_eq(rig.rotation_degrees.y, 25.0, 0.01)


func test_station_view_fits_whole_station() -> void:
	rig.focus_on(null, DioramaCamera.Tier.STATION, true)
	assert_eq(rig.t, 0.0)
	assert_true(_all_in_frame(STATION), "station fully in frame at t = 0")


func test_fit_size_grows_with_margin() -> void:
	var a: float = DioramaCamera.fit(STATION, rig.global_basis, 16.0 / 9.0, 1.0).size
	var b: float = DioramaCamera.fit(STATION, rig.global_basis, 16.0 / 9.0, 1.2).size
	assert_almost_eq(b, a * 1.2, 0.001)


func test_focus_on_ends_at_room_size_and_position() -> void:
	var target := Node3D.new()
	target.set_script(load("res://tests/unit/helpers/aabb_node.gd"))
	target.set(&"box", ROOM)
	add_child_autofree(target)
	rig.focus_on(target, DioramaCamera.Tier.ROOM)
	await wait_seconds(rig.focus_seconds + 0.2)
	assert_almost_eq(rig.t, 1.0, 0.001)
	var expected: Dictionary = DioramaCamera.fit(ROOM, rig.global_basis, rig._aspect(), rig.room_margin)
	assert_almost_eq(rig.camera.size, expected.size, 0.01)
	assert_almost_eq(rig.global_position.distance_to(expected.center), 0.0, 0.01)
	assert_true(_all_in_frame(ROOM), "room fully in frame at t = 1")


func test_zoom_tiers_are_continuous() -> void:
	var s0 := rig.size_at(0.0)
	var s1 := rig.size_at(1.0)
	assert_lt(s1, s0)
	var mid := rig.size_at(0.5)
	assert_between(mid, s1, s0)
	assert_almost_eq(rig.t_for_size(mid), 0.5, 0.001)


## True if `p` projects inside the station's camera-plane rectangle grown by
## `margin` (depth along the view axis doesn't matter in ortho).
func _inside_projected(p: Vector3, margin: float) -> bool:
	var right := rig.global_basis.x
	var up := rig.global_basis.y
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in 8:
		var c := STATION.get_endpoint(i)
		var v := Vector2(c.dot(right), c.dot(up))
		lo = lo.min(v)
		hi = hi.max(v)
	var q := Vector2(p.dot(right), p.dot(up))
	return q.x >= lo.x - margin - 0.01 and q.x <= hi.x + margin + 0.01 \
		and q.y >= lo.y - margin - 0.01 and q.y <= hi.y + margin + 0.01


func test_pan_is_clamped_to_station() -> void:
	var far := Vector3(500, 0, 0)
	var clamped := DioramaCamera.clamp_to_aabb(far, STATION, rig.global_basis, 4.0)
	assert_true(_inside_projected(clamped, 4.0))
	assert_false(_inside_projected(far, 4.0), "the far point really was outside")
	var inside := STATION.get_center()
	assert_almost_eq(DioramaCamera.clamp_to_aabb(inside, STATION, rig.global_basis, 4.0), inside, Vector3.ONE * 0.001)
	rig.pan = Vector3(1000, 1000, 0)
	rig.set_station_aabb(STATION)
	assert_true(_inside_projected(rig.global_position, rig.pan_margin), "rig clamps its own pan")


func test_zoom_changed_signal() -> void:
	watch_signals(rig)
	rig.focus_on(null, DioramaCamera.Tier.ROOM, true)
	assert_signal_emitted_with_parameters(rig, "zoom_changed", [1.0])
