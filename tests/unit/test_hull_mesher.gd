extends GutTest
## The cutaway's back-face capping only works on watertight hulls.

const LAYOUTS := [
	"#####\n#P..a\n#####",
	"######c#####v####\n#S...#.....#....#\na..L.D..L..D..L.b\n#..C.#..S..#.C..#\n#######W#########",
	"  ###\n###.#\n#...#\n#####",
]


## Every directed edge must be matched by its reverse: the surface is closed
## and consistently oriented (no holes, no flipped faces).
static func open_edges(mesh: ArrayMesh) -> int:
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var key := func(v: Vector3) -> Vector3i: return Vector3i((v * 1000.0).round())
	var edges := {}
	for t in range(0, idx.size(), 3):
		for k in 3:
			var a: Vector3i = key.call(verts[idx[t + k]])
			var b: Vector3i = key.call(verts[idx[t + (k + 1) % 3]])
			var e := [a, b]
			edges[e] = edges.get(e, 0) + 1
	var bad := 0
	for e: Array in edges:
		if edges[e] != edges.get([e[1], e[0]], 0):
			bad += 1
	return bad


func _build(layout: String) -> Dictionary:
	var grid := StationBuilder.parse(layout)
	return HullMesher.build(grid, 2.0, Vector3.ZERO, 2.6, 3)


func test_hull_is_watertight() -> void:
	for layout: String in LAYOUTS:
		var res := _build(layout)
		assert_eq(open_edges(res.hull), 0, "hull closed for\n%s" % layout)
		assert_eq(open_edges(res.detail), 0, "greebles closed for\n%s" % layout)


func test_walls_are_solid_only_on_wall_cells() -> void:
	var grid := StationBuilder.parse("#####\n#P..a\n#####")
	assert_true(HullMesher.is_solid(grid, Vector2i(0, 0), 1), "wall")
	assert_false(HullMesher.is_solid(grid, Vector2i(1, 1), 1), "floor is open")
	assert_false(HullMesher.is_solid(grid, Vector2i(4, 1), 1), "slot doorway is open")
	assert_true(HullMesher.is_solid(grid, Vector2i(1, 1), 0), "keel under floor")
	assert_true(HullMesher.is_solid(grid, Vector2i(1, 1), 2), "roof over floor")
	assert_false(HullMesher.is_solid(grid, Vector2i(9, 9), 0), "space")


func test_aabb_wraps_layout() -> void:
	var res := _build("#####\n#P..a\n#####")
	var aabb: AABB = res.aabb
	assert_true(aabb.has_point(Vector3(4, 1, 2)), "contains a cell centre")
	assert_lt(aabb.position.y, HullMesher.KEEL_BOTTOM + 0.001)
	assert_gt(aabb.end.y, 2.6 + HullMesher.ROOF_THICKNESS)


func test_spine_only_deep_inside() -> void:
	var grid := StationBuilder.parse(LAYOUTS[1])
	assert_true(HullMesher.is_solid(grid, Vector2i(8, 2), 3))
	assert_false(HullMesher.is_solid(grid, Vector2i(8, 1), 3))


func test_outer_wall_lines_are_thin() -> void:
	# Trader-like: top/bottom rows and the left column hold only walls -> thin;
	# the right column has the slot doorway -> stays a whole cell.
	var grid := StationBuilder.parse("#####\n#T..a\n#####")
	var lines := HullMesher.edge_lines(grid, 2.0, Vector3.ZERO)
	assert_almost_eq(lines.x[1] - lines.x[0], HullMesher.THIN_WALL, 0.001, "left wall thin")
	assert_almost_eq(lines.x[5] - lines.x[4], 2.0, 0.001, "doorway column whole")
	assert_almost_eq(lines.z[1] - lines.z[0], HullMesher.THIN_WALL, 0.001, "top wall thin")
	assert_almost_eq(lines.z[3] - lines.z[2], HullMesher.THIN_WALL, 0.001, "bottom wall thin")
	assert_almost_eq(lines.x[2] - lines.x[1], 2.0, 0.001, "room cells untouched")
	var aabb: AABB = _build("#####\n#T..a\n#####").aabb
	assert_lt(aabb.size.z, 2.0 + 2.0 * HullMesher.THIN_WALL + 0.5, "hull hugs the room")
	# A bay window in an outer wall still allows thinning; floor does not.
	assert_true(HullMesher.is_thin_cell(StationBuilder.parse("##W##\n#...#\n##a##"), Vector2i(2, 0)))
	assert_false(HullMesher.is_thin_cell(StationBuilder.parse("##W##\n#...#\n##a##"), Vector2i(2, 2)))
