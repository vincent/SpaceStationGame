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
## Thin walls: an outer row/column of the grid holding only walls (no floor,
## furniture or slot doorway; bay windows are fine) is THIN_WALL deep instead
## of a whole cell, hugging the room like imported art. The grid is just
## stretched (edge_lines()), so the solid stays watertight and the interior
## (floor, furniture, slots) keeps its uniform cells.
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
## Depth of an outer wall-only row/column (m), same as imported art walls.
const THIN_WALL := 0.3
## Characters an outer row/column may hold and still be thinned.
const THIN_CHARS := "# W"

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
	var lines := edge_lines(grid, cell, offset)

	for li in layers.size():
		for z in size.y:
			for x in size.x:
				var c := Vector2i(x, z)
				if is_solid(grid, c, li):
					_emit_voxel(hull, grid, c, li, layers, lines)
	_add_greebles(hull, detail, grid, lines, cell, wall_height, rng)

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


## Cell boundaries: {x: PackedFloat32Array (cols + 1), z: (rows + 1)}. Uniform
## cells centred on `offset + c * cell`, except thin outer wall lines.
static func edge_lines(grid: PackedStringArray, cell: float, offset: Vector3) -> Dictionary:
	var size := grid_size(grid)
	var xs := PackedFloat32Array()
	var zs := PackedFloat32Array()
	for i in size.x + 1:
		xs.append(offset.x + (i - 0.5) * cell)
	for i in size.y + 1:
		zs.append(offset.z + (i - 0.5) * cell)
	if size.x > 2:
		if _is_thin_line(grid, Vector2i(0, 0), Vector2i(0, 1)):
			xs[0] = xs[1] - THIN_WALL
		if _is_thin_line(grid, Vector2i(size.x - 1, 0), Vector2i(0, 1)):
			xs[size.x] = xs[size.x - 1] + THIN_WALL
	if size.y > 2:
		if _is_thin_line(grid, Vector2i(0, 0), Vector2i(1, 0)):
			zs[0] = zs[1] - THIN_WALL
		if _is_thin_line(grid, Vector2i(0, size.y - 1), Vector2i(1, 0)):
			zs[size.y] = zs[size.y - 1] + THIN_WALL
	return {"x": xs, "z": zs}


## True if cell `c` lies in a thinned outer row/column.
static func is_thin_cell(grid: PackedStringArray, c: Vector2i) -> bool:
	var size := grid_size(grid)
	return (size.x > 2 and ((c.x == 0 and _is_thin_line(grid, Vector2i(0, 0), Vector2i(0, 1)))
			or (c.x == size.x - 1 and _is_thin_line(grid, Vector2i(c.x, 0), Vector2i(0, 1))))) \
		or (size.y > 2 and ((c.y == 0 and _is_thin_line(grid, Vector2i(0, 0), Vector2i(1, 0)))
			or (c.y == size.y - 1 and _is_thin_line(grid, Vector2i(0, c.y), Vector2i(1, 0)))))


static func _is_thin_line(grid: PackedStringArray, start: Vector2i, step: Vector2i) -> bool:
	var size := grid_size(grid)
	var c := start
	var walls := 0
	while c.x < size.x and c.y < size.y:
		var ch := cell_char(grid, c)
		if not THIN_CHARS.contains(ch):
			return false
		if ch != " ":
			walls += 1
		c += step
	return walls > 0


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
		kit: MeshKit, grid: PackedStringArray, c: Vector2i, li: int, layers: Array[Vector2], lines: Dictionary
) -> void:
	var b := _bounds(c, lines)
	var center := Vector3(b.get_center().x, 0.0, b.get_center().y)
	var hx := b.size.x * 0.5
	var hz := b.size.y * 0.5
	var y0 := layers[li].x
	var y1 := layers[li].y
	for d in DIRS:
		if is_solid(grid, c + d, li):
			continue
		var n := Vector3(d.x, 0.0, d.y)
		var side := Vector3(-n.z, 0.0, n.x) * (hz if d.x != 0 else hx)
		var mid := center + n * (hx if d.x != 0 else hz)
		var exterior := cell_char(grid, c + d) == " "
		var color := TRIM if exterior and li == 0 else PLAIN
		kit.quad(mid - side + Vector3(0, y0, 0), mid + side + Vector3(0, y0, 0),
			mid + side + Vector3(0, y1, 0), mid - side + Vector3(0, y1, 0), n, color)
	var corners := [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz)]
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


## Cell footprint (x, z) from the edge lines.
static func _bounds(c: Vector2i, lines: Dictionary) -> Rect2:
	var xs: PackedFloat32Array = lines.x
	var zs: PackedFloat32Array = lines.z
	return Rect2(xs[c.x], zs[c.y], xs[c.x + 1] - xs[c.x], zs[c.y + 1] - zs[c.y])


static func _center(c: Vector2i, lines: Dictionary) -> Vector3:
	var m := _bounds(c, lines).get_center()
	return Vector3(m.x, 0.0, m.y)


# --- Greebles ----------------------------------------------------------------

static func _add_greebles(
		hull: MeshKit, detail: MeshKit, grid: PackedStringArray, lines: Dictionary, cell: float,
		wall_height: float, rng: RandomNumberGenerator
) -> void:
	var size := grid_size(grid)
	var roof_top := wall_height + ROOF_THICKNESS
	# Roof props only go on whole cells (a thin wall is too narrow).
	var roof_cells: Array[Vector2i] = []
	for z in size.y:
		for x in size.x:
			var c := Vector2i(x, z)
			if cell_char(grid, c) == " ":
				continue
			_add_wall_dressing(hull, detail, grid, c, lines, wall_height)
			var b := _bounds(c, lines)
			if minf(b.size.x, b.size.y) > cell * 0.9:
				roof_cells.append(c)
	if roof_cells.is_empty():
		return

	# Vents on the roof.
	for c in roof_cells:
		if rng.randf() < 0.28:
			var p := _center(c, lines) + Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4))
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
					var x0: float = lines.x[run_start] + cell * 0.2
					var x1: float = lines.x[x] - cell * 0.2
					var z := _center(Vector2i(run_start, row), lines).z
					var mid := Vector3((x0 + x1) * 0.5, roof_top + GAP + 0.14, z + (0.5 if row == 1 else -0.5))
					detail.cylinder(mid, 0.13, x1 - x0, 0, TRIM, 8)
				run_start = -1

	# Silhouette pieces: a tank and an antenna with a beacon.
	var tank_cell := roof_cells[rng.randi_range(0, roof_cells.size() - 1)]
	var tank_pos := _center(tank_cell, lines) + Vector3(0, _top(grid, tank_cell, roof_top) + GAP + 0.5, 0)
	hull.cylinder(tank_pos, 0.48, cell * 0.9, 2, Color(0.2, 0.0, 0.5), 12)
	var mast_cell := roof_cells[rng.randi_range(0, roof_cells.size() - 1)]
	var mast := _center(mast_cell, lines) + Vector3(0.5, _top(grid, mast_cell, roof_top) + GAP, -0.5)
	hull.box(mast + Vector3(0, 1.1, 0), Vector3(0.09, 2.2, 0.09), TRIM)
	hull.box(mast + Vector3(0, 2.32, 0), Vector3(0.22, 0.22, 0.22), GLOW)

	# Hanging keel tanks underneath.
	for i in 2:
		var c := roof_cells[rng.randi_range(0, roof_cells.size() - 1)]
		var p := _center(c, lines) + Vector3(0, KEEL_BOTTOM - GAP - 0.3, 0)
		hull.cylinder(p, 0.3, cell * 0.8, 0, TRIM, 8)


## Ribs (detail) and a running-light strip (hull: its glow shows power even
## in station view) on every exterior wall face of a cell.
static func _add_wall_dressing(
		hull: MeshKit, detail: MeshKit, grid: PackedStringArray, c: Vector2i, lines: Dictionary,
		wall_height: float
) -> void:
	if not WALL_CHARS.contains(cell_char(grid, c)):
		return
	var b := _bounds(c, lines)
	var center := _center(c, lines)
	for d in DIRS:
		if cell_char(grid, c + d) != " ":
			continue
		var n := Vector3(d.x, 0.0, d.y)
		var side := Vector3(-n.z, 0.0, n.x)
		var h := (b.size.y if d.x != 0 else b.size.x) * 0.5  # half width of the face
		if h < 0.5:
			continue  # the thin end of a thin wall
		var face := center + n * ((b.size.x if d.x != 0 else b.size.y) * 0.5)
		# Rib at one edge of the face (every face → one rib per cell edge).
		var rib_depth := 0.12
		var rib := face + side * (h - 0.15) + n * (GAP + rib_depth * 0.5)
		var rib_h := wall_height + ROOF_THICKNESS - KEEL_BOTTOM
		var rib_size := Vector3(0.22, rib_h, 0.22)
		rib_size[0 if absf(n.x) > 0.5 else 2] = rib_depth
		detail.box(rib + Vector3(0, KEEL_BOTTOM + rib_h * 0.5, 0), rib_size, TRIM)
		# Running-light strip between the ribs.
		var strip := face - side * 0.15 + n * (GAP + 0.03)
		var strip_size := Vector3(h * 2.0 - 0.4, 0.08, h * 2.0 - 0.4)
		strip_size[0 if absf(n.x) > 0.5 else 2] = 0.06
		hull.box(strip + Vector3(0, wall_height * 0.72, 0), strip_size, GLOW)


## Height of the hull top over a cell (roof, or spine when there is one).
static func _top(grid: PackedStringArray, c: Vector2i, roof_top: float) -> float:
	return roof_top + SPINE_HEIGHT if is_solid(grid, c, 3) else roof_top

