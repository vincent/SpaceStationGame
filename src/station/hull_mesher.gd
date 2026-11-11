@tool
class_name HullMesher
extends RefCounted
## Builds a module's hull and structure from its interior ASCII grid, as one
## watertight voxel solid (every face sits between a solid and an empty
## voxel, so there are no internal or coincident faces) plus greebles.
##
## Four voxel layers per grid cell:
##   keel  [KEEL_BOTTOM, FLOOR_TOP]        every non-space cell
##   walls [FLOOR_TOP, wall_height]        wall cells ("#")
##   roof  [wall_height, wall_height+roof] every non-space cell
##   spine [roof top, + SPINE_HEIGHT]      cells 2+ steps inside the boundary
##                                         (a stepped roof reads as a ship)
## Floor tiles (interior, not cut) sit on top of the keel.
##
## Output: {hull: ArrayMesh, detail: ArrayMesh, aabb: AABB}. `detail` holds
## small greebles that are hidden in station view.

const KEEL_BOTTOM := -0.6
const FLOOR_TOP := -0.2
const ROOF_THICKNESS := 0.4
const SPINE_HEIGHT := 0.55
const WALL_CHARS := "#"
## Greebles float this far off the hull, so their faces never coincide with it.
const GAP := 0.012

const DIRS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]

const PLAIN := Color(0.3, 0.0, 0.0)
const TRIM := Color(0.3, 0.0, 1.0)
const GLOW := Color(0.0, 1.0, 0.0)


static func build(
		grid: PackedStringArray, cell: float, offset: Vector3, wall_height: float, seed_value: int = 1
) -> Dictionary:
	var hull := MeshKit.new()
	hull.grime_bottom = KEEL_BOTTOM
	hull.grime_top = wall_height * 0.6
	var detail := MeshKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var layers := layer_ranges(wall_height)
	var size := grid_size(grid)

	for li in layers.size():
		for z in size.y:
			for x in size.x:
				var c := Vector2i(x, z)
				if is_solid(grid, c, li):
					_emit_voxel(hull, grid, c, li, layers, cell, offset)
	_add_greebles(hull, detail, grid, cell, offset, wall_height, rng)

	var hull_mesh := hull.commit()
	var detail_mesh := detail.commit()
	var aabb := hull_mesh.get_aabb() if hull_mesh else AABB()
	if detail_mesh:
		aabb = aabb.merge(detail_mesh.get_aabb())
	return {"hull": hull_mesh, "detail": detail_mesh, "aabb": aabb}


static func layer_ranges(wall_height: float) -> Array[Vector2]:
	var roof_top := wall_height + ROOF_THICKNESS
	return [
		Vector2(KEEL_BOTTOM, FLOOR_TOP),
		Vector2(FLOOR_TOP, wall_height),
		Vector2(wall_height, roof_top),
		Vector2(roof_top, roof_top + SPINE_HEIGHT),
	]


static func grid_size(grid: PackedStringArray) -> Vector2i:
	var cols := 0
	for row in grid:
		cols = maxi(cols, row.length())
	return Vector2i(cols, grid.size())


static func cell_char(grid: PackedStringArray, c: Vector2i) -> String:
	if c.y < 0 or c.y >= grid.size() or c.x < 0 or c.x >= grid[c.y].length():
		return " "
	return grid[c.y][c.x]


static func is_solid(grid: PackedStringArray, c: Vector2i, layer: int) -> bool:
	if layer < 0 or layer > 3:
		return false
	var ch := cell_char(grid, c)
	if ch == " ":
		return false
	if layer == 3:
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				if cell_char(grid, c + Vector2i(dx, dz)) == " ":
					return false
		return true
	return layer != 1 or WALL_CHARS.contains(ch)


static func _emit_voxel(
		kit: MeshKit, grid: PackedStringArray, c: Vector2i, li: int, layers: Array[Vector2],
		cell: float, offset: Vector3
) -> void:
	var center := offset + Vector3(c.x * cell, 0.0, c.y * cell)
	var h := cell * 0.5
	var y0 := layers[li].x
	var y1 := layers[li].y
	for d in DIRS:
		if is_solid(grid, c + d, li):
			continue
		var n := Vector3(d.x, 0.0, d.y)
		var side := Vector3(-n.z, 0.0, n.x) * h
		var mid := center + n * h
		var exterior := cell_char(grid, c + d) == " "
		var color := TRIM if exterior and li == 0 else PLAIN
		kit.quad(mid - side + Vector3(0, y0, 0), mid + side + Vector3(0, y0, 0),
			mid + side + Vector3(0, y1, 0), mid - side + Vector3(0, y1, 0), n, color)
	var corners := [Vector3(-h, 0, -h), Vector3(h, 0, -h), Vector3(h, 0, h), Vector3(-h, 0, h)]
	if not is_solid(grid, c, li + 1):
		var top_color := Color(0.3, 0.0, 0.18 * ((c.x + c.y) % 2)) if li >= 2 else PLAIN
		var p: Array[Vector3] = []
		for k: Vector3 in corners:
			p.append(center + k + Vector3(0, y1, 0))
		kit.quad(p[0], p[1], p[2], p[3], Vector3.UP, top_color)
	if not is_solid(grid, c, li - 1):
		var p: Array[Vector3] = []
		for k: Vector3 in corners:
			p.append(center + k + Vector3(0, y0, 0))
		kit.quad(p[0], p[1], p[2], p[3], Vector3.DOWN, Color(0.9, 0.0, 1.0) if li == 0 else PLAIN)


# --- Greebles ----------------------------------------------------------------

static func _add_greebles(
		hull: MeshKit, detail: MeshKit, grid: PackedStringArray, cell: float, offset: Vector3,
		wall_height: float, rng: RandomNumberGenerator
) -> void:
	var size := grid_size(grid)
	var roof_top := wall_height + ROOF_THICKNESS
	var roof_cells: Array[Vector2i] = []
	for z in size.y:
		for x in size.x:
			var c := Vector2i(x, z)
			if cell_char(grid, c) == " ":
				continue
			roof_cells.append(c)
			_add_wall_dressing(hull, detail, grid, c, cell, offset, wall_height)
	if roof_cells.is_empty():
		return

	# Vents on the roof.
	for c in roof_cells:
		if rng.randf() < 0.28:
			var p := _cell_pos(c, cell, offset) + Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4))
			detail.box(p + Vector3(0, _top(grid, c, roof_top) + GAP + 0.14, 0), Vector3(0.7, 0.28, 0.5), TRIM)

	# Pipes running along X over the roof (one per long run of a chosen row).
	for row in [1, size.y - 2]:
		var run_start := -1
		for x in size.x + 1:
			var inside := x < size.x and cell_char(grid, Vector2i(x, row)) != " "
			if inside and run_start < 0:
				run_start = x
			elif not inside and run_start >= 0:
				if x - run_start >= 3:
					var a := _cell_pos(Vector2i(run_start, row), cell, offset)
					var b := _cell_pos(Vector2i(x - 1, row), cell, offset)
					var mid := (a + b) * 0.5 + Vector3(0, roof_top + GAP + 0.14, (0.5 if row == 1 else -0.5))
					detail.cylinder(mid, 0.13, b.x - a.x + cell * 0.6, 0, TRIM, 8)
				run_start = -1

	# Silhouette pieces: a tank and an antenna with a beacon.
	var tank_cell := roof_cells[rng.randi_range(0, roof_cells.size() - 1)]
	var tank_pos := _cell_pos(tank_cell, cell, offset) + Vector3(0, _top(grid, tank_cell, roof_top) + GAP + 0.5, 0)
	hull.cylinder(tank_pos, 0.48, cell * 0.9, 2, Color(0.2, 0.0, 0.5), 12)
	var mast_cell := roof_cells[rng.randi_range(0, roof_cells.size() - 1)]
	var mast := _cell_pos(mast_cell, cell, offset) + Vector3(0.5, _top(grid, mast_cell, roof_top) + GAP, -0.5)
	hull.box(mast + Vector3(0, 1.1, 0), Vector3(0.09, 2.2, 0.09), TRIM)
	hull.box(mast + Vector3(0, 2.32, 0), Vector3(0.22, 0.22, 0.22), GLOW)

	# Hanging keel tanks underneath.
	for i in 2:
		var c := roof_cells[rng.randi_range(0, roof_cells.size() - 1)]
		var p := _cell_pos(c, cell, offset) + Vector3(0, KEEL_BOTTOM - GAP - 0.3, 0)
		hull.cylinder(p, 0.3, cell * 0.8, 0, TRIM, 8)


## Ribs (detail) and a running-light strip (hull: its glow shows power even
## in station view) on every exterior wall face of a cell.
static func _add_wall_dressing(
		hull: MeshKit, detail: MeshKit, grid: PackedStringArray, c: Vector2i, cell: float, offset: Vector3,
		wall_height: float
) -> void:
	if not WALL_CHARS.contains(cell_char(grid, c)):
		return
	var center := _cell_pos(c, cell, offset)
	var h := cell * 0.5
	for d in DIRS:
		if cell_char(grid, c + d) != " ":
			continue
		var n := Vector3(d.x, 0.0, d.y)
		var side := Vector3(-n.z, 0.0, n.x)
		var face := center + n * h
		# Rib at one edge of the face (every face → one rib per cell edge).
		var rib_depth := 0.12
		var rib := face + side * (h - 0.15) + n * (GAP + rib_depth * 0.5)
		var rib_h := wall_height + ROOF_THICKNESS - KEEL_BOTTOM
		var rib_size := Vector3(0.22, rib_h, 0.22)
		rib_size[0 if absf(n.x) > 0.5 else 2] = rib_depth
		detail.box(rib + Vector3(0, KEEL_BOTTOM + rib_h * 0.5, 0), rib_size, TRIM)
		# Running-light strip between the ribs.
		var strip := face - side * 0.15 + n * (GAP + 0.03)
		var strip_size := Vector3(cell - 0.4, 0.08, cell - 0.4)
		strip_size[0 if absf(n.x) > 0.5 else 2] = 0.06
		hull.box(strip + Vector3(0, wall_height * 0.72, 0), strip_size, GLOW)


## Height of the hull top over a cell (roof, or spine when there is one).
static func _top(grid: PackedStringArray, c: Vector2i, roof_top: float) -> float:
	return roof_top + SPINE_HEIGHT if is_solid(grid, c, 3) else roof_top


static func _cell_pos(c: Vector2i, cell: float, offset: Vector3) -> Vector3:
	return offset + Vector3(c.x * cell, 0.0, c.y * cell)
