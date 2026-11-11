@tool
class_name StationBuilder
extends Node3D
## Builds placeholder station geometry from an ASCII layout, so rooms can be
## prototyped before real art exists. Edit `layout` in the inspector and press
## "Rebuild" to preview in the editor. Generated nodes are never saved.
##
## Legend (one character = one CELL x CELL square):
##   #  wall              .  floor            (space)  nothing (outer space)
##   D  doorway (floor)   P  player spawn     L  floor + ceiling light
##   B  bed               K  kitchen          W  bay window (in a wall)
## Add new furniture by mapping a character in FURNITURE_SCENES.

const CELL := 2.0
const WALL_HEIGHT := 2.6
const FLOOR_THICKNESS := 0.2

const FURNITURE_SCENES: Dictionary[String, String] = {
	"B": "res://src/interactables/bed.tscn",
	"K": "res://src/interactables/kitchen.tscn",
	"W": "res://src/interactables/bay_window.tscn",
}
## Furniture that replaces a wall cell instead of standing on the floor.
const WALL_FURNITURE := "W"
const WALKABLE := ".PLDBK"
const FREE_FLOOR := ".PLD"

const DEFAULT_LAYOUT := """##W########
#B..#....K#
#...D..L..#
#.L.#.....W
#...#.....#
###D#######
  #.#
  #P#
  ###"""

@export_multiline var layout: String = DEFAULT_LAYOUT:
	set(value):
		layout = value
		if Engine.is_editor_hint() and is_inside_tree():
			build()
@export_tool_button("Rebuild", "Reload") var rebuild_action: Callable = build

## World position of the "P" cell, valid after build().
var spawn_position := Vector3.ZERO
var furniture_nodes: Array[Node3D] = []

var _generated: Node3D
var _grid: PackedStringArray = []
var _offset := Vector3.ZERO


func _ready() -> void:
	if Engine.is_editor_hint():
		build()


func is_built() -> bool:
	return _generated != null


func build() -> void:
	if _generated != null:
		_generated.free()
	furniture_nodes.clear()
	_generated = Node3D.new()
	_generated.name = "Generated"
	add_child(_generated)

	_grid = _parse(layout)
	var rows := _grid.size()
	var cols := 0
	for row in _grid:
		cols = maxi(cols, row.length())
	_offset = -Vector3((cols - 1) * CELL * 0.5, 0.0, (rows - 1) * CELL * 0.5)

	var floor_cells: Array[Vector3] = []
	for z in rows:
		for x in _grid[z].length():
			var c := _grid[z][x]
			var pos := cell_to_world(Vector2i(x, z))
			if c == "#":
				_add_wall(pos, Vector2i(x, z))
			elif c == WALL_FURNITURE:
				_add_furniture(c, pos, Vector2i(x, z))
			elif WALKABLE.contains(c):
				floor_cells.append(pos)
				if c == "P":
					spawn_position = pos
				elif c == "L":
					_add_light(pos)
				elif FURNITURE_SCENES.has(c):
					_add_furniture(c, pos, Vector2i(x, z))
	_add_floor(floor_cells)


func cell_to_world(cell: Vector2i) -> Vector3:
	return _offset + Vector3(cell.x * CELL, 0.0, cell.y * CELL)


func get_cell(cell: Vector2i) -> String:
	if cell.y < 0 or cell.y >= _grid.size() or cell.x < 0 or cell.x >= _grid[cell.y].length():
		return " "
	return _grid[cell.y][cell.x]


static func _parse(text: String) -> PackedStringArray:
	var lines := text.replace("\r", "").split("\n")
	while lines.size() > 0 and lines[0].strip_edges() == "":
		lines.remove_at(0)
	while lines.size() > 0 and lines[-1].strip_edges() == "":
		lines.remove_at(lines.size() - 1)
	return lines


# --- Geometry ----------------------------------------------------------------

func _add_floor(cells: Array[Vector3]) -> void:
	var tile := BoxMesh.new()
	tile.size = Vector3(CELL - 0.06, FLOOR_THICKNESS, CELL - 0.06)
	tile.material = ToonMaterials.get_material(Palette.STEEL, 0.0, false)

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = tile
	multimesh.instance_count = cells.size()
	for i in cells.size():
		multimesh.set_instance_transform(i, Transform3D(Basis(), cells[i] + Vector3(0, -FLOOR_THICKNESS * 0.5, 0)))
	var visual := MultiMeshInstance3D.new()
	visual.name = "FloorTiles"
	visual.multimesh = multimesh
	_generated.add_child(visual)

	var body := StaticBody3D.new()
	body.name = "Floor"
	body.collision_layer = Layers.WORLD
	_generated.add_child(body)
	var shape := BoxShape3D.new()
	shape.size = Vector3(CELL, FLOOR_THICKNESS, CELL)
	for pos in cells:
		var col := CollisionShape3D.new()
		col.shape = shape
		col.position = pos + Vector3(0, -FLOOR_THICKNESS * 0.5, 0)
		body.add_child(col)


func _add_wall(pos: Vector3, cell: Vector2i) -> void:
	var wall := Node3D.new()
	wall.name = "Wall_%d_%d" % [cell.x, cell.y]
	wall.position = pos
	wall.add_to_group(&"cutaway")
	_generated.add_child(wall)

	var body := StaticBody3D.new()
	body.collision_layer = Layers.WALLS
	wall.add_child(body)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(CELL, WALL_HEIGHT, CELL)
	col.shape = shape
	col.position.y = WALL_HEIGHT * 0.5
	body.add_child(col)

	# Visual is scaled down by CutawayController; collision stays.
	var visual := Node3D.new()
	visual.name = "Visual"
	wall.add_child(visual)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(CELL, WALL_HEIGHT, CELL)
	mesh.mesh = box
	mesh.position.y = WALL_HEIGHT * 0.5
	mesh.material_override = ToonMaterials.get_material(Palette.ANTHRACITE)
	visual.add_child(mesh)
	var trim := MeshInstance3D.new()
	var trim_box := BoxMesh.new()
	trim_box.size = Vector3(CELL - 0.3, 0.04, CELL - 0.3)
	trim.mesh = trim_box
	trim.position.y = WALL_HEIGHT
	trim.material_override = ToonMaterials.get_material(Palette.DEEP_BLUE.lerp(Palette.VIOLET, 0.35), 0.0, false)
	visual.add_child(trim)


func _add_light(pos: Vector3) -> void:
	var light := OmniLight3D.new()
	light.position = pos + Vector3(0, WALL_HEIGHT - 0.3, 0)
	light.light_color = Palette.NEON_CYAN.lerp(Color.WHITE, 0.3)
	light.light_energy = 1.6
	light.omni_range = CELL * 3.5
	_generated.add_child(light)


func _add_furniture(c: String, pos: Vector3, cell: Vector2i) -> void:
	var scene := load(FURNITURE_SCENES[c]) as PackedScene
	var node := scene.instantiate() as Node3D
	node.position = pos
	var facing := _find_free_neighbor(cell)
	if facing != Vector2i.ZERO:
		node.rotation.y = atan2(facing.x, facing.y)
	_generated.add_child(node)
	furniture_nodes.append(node)
	if not Engine.is_editor_hint() and node is Interactable and facing != Vector2i.ZERO:
		var dir := Vector3(facing.x, 0, facing.y)
		(node as Interactable).approach_point = global_transform * (pos + dir * CELL * 0.8)


## Direction (unit grid step) of the first adjacent free floor cell.
func _find_free_neighbor(cell: Vector2i) -> Vector2i:
	for dir: Vector2i in [Vector2i.DOWN, Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP]:
		if FREE_FLOOR.contains(get_cell(cell + dir)):
			return dir
	return Vector2i.ZERO
