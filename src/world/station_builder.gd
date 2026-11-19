@tool
class_name StationBuilder
extends Node3D
## Builds a module's interior from an ASCII layout: floor tiles, wall
## collisions, furniture, light anchors and slot doorways. The visible walls,
## roof and keel are the module hull (HullMesher), built by Module.
## Generated nodes are never saved.
##
## Legend (one character = one CELL x CELL square):
##   #  wall / bulkhead   .  floor            (space)  nothing (outer space)
##   D  inner doorway     P  player spawn     L  floor + ceiling light
##   B  bed               K  kitchen          W  bay window (in a wall)
##   S  salvage pile      C  console          T  trader
##   G  planter (agri bay)
##   a..z  slot doorway on the hull boundary (slot "A".."Z")
## Add new furniture by mapping a character in FURNITURE_SCENES.

const CELL := 2.0
const WALL_HEIGHT := 2.6
const FLOOR_THICKNESS := 0.2

const FURNITURE_SCENES: Dictionary[String, String] = {
	"B": "res://src/interactables/bed.tscn",
	"K": "res://src/interactables/kitchen.tscn",
	"W": "res://src/interactables/bay_window.tscn",
	"S": "res://src/interactables/salvage_pile.tscn",
	"C": "res://src/interactables/console.tscn",
	"T": "res://src/interactables/trader.tscn",
	"G": "res://src/interactables/planter.tscn",
}
## Furniture that replaces a wall cell instead of standing on the floor.
const WALL_FURNITURE := "W"
const WALKABLE := ".PLDBKSCTG"
const FREE_FLOOR := ".PLD"
const SLOT_LETTERS := "abcdefghijklmnopqrstuvwxyz"

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
## Imported art has thin walls (0.3 m) instead of whole wall cells: doorway
## (slot) cells keep their floor collision but draw no tile (it would stick out
## of the hull), and wall furniture moves this far towards the room.
var hide_slot_floor := false
var wall_furniture_inset := 0.0

## Local position of the "P" cell, valid after build() (Vector3.INF if none).
var spawn_position := Vector3.INF
var furniture_nodes: Array[Node3D] = []
## Local positions of "L" cells (floor level).
var light_positions: Array[Vector3] = []
## Slot name ("A".."Z") -> {cell: Vector2i, outward: Vector2i}.
var slot_cells: Dictionary[StringName, Dictionary] = {}

var _generated: Node3D
var _grid: PackedStringArray = []
var _offset := Vector3.ZERO


func _ready() -> void:
	if Engine.is_editor_hint():
		build()


func is_built() -> bool:
	return _generated != null


func get_grid() -> PackedStringArray:
	return _grid


func get_offset() -> Vector3:
	return _offset


func build() -> void:
	if _generated != null:
		_generated.free()
	furniture_nodes.clear()
	light_positions.clear()
	slot_cells.clear()
	spawn_position = Vector3.INF
	_generated = Node3D.new()
	_generated.name = "Generated"
	add_child(_generated)

	_grid = parse(layout)
	var size := HullMesher.grid_size(_grid)
	_offset = -Vector3((size.x - 1) * CELL * 0.5, 0.0, (size.y - 1) * CELL * 0.5)

	var floor_cells: Array[Vector3] = []
	var hidden_floor: Array[Vector3] = []
	var wall_cells: Array[Vector3] = []
	for z in size.y:
		for x in _grid[z].length():
			var c := _grid[z][x]
			var cell := Vector2i(x, z)
			var pos := cell_to_world(cell)
			if c == "#":
				wall_cells.append(pos)
			elif c == WALL_FURNITURE:
				_add_furniture(c, pos, cell)
			elif is_walkable(c):
				if hide_slot_floor and SLOT_LETTERS.contains(c):
					hidden_floor.append(pos)
				else:
					floor_cells.append(pos)
				if c == "P":
					spawn_position = pos
				elif c == "L":
					light_positions.append(pos)
				elif FURNITURE_SCENES.has(c):
					_add_furniture(c, pos, cell)
				elif SLOT_LETTERS.contains(c):
					slot_cells[StringName(c.to_upper())] = {"cell": cell, "outward": _outward(cell)}
	_add_floor(floor_cells, hidden_floor)
	_add_wall_collisions(wall_cells)


func cell_to_world(cell: Vector2i) -> Vector3:
	return _offset + Vector3(cell.x * CELL, 0.0, cell.y * CELL)


func get_cell(cell: Vector2i) -> String:
	return HullMesher.cell_char(_grid, cell)


static func is_walkable(c: String) -> bool:
	return c.length() == 1 and (WALKABLE.contains(c) or SLOT_LETTERS.contains(c))


static func parse(text: String) -> PackedStringArray:
	var lines := text.replace("\r", "").split("\n")
	while lines.size() > 0 and lines[0].strip_edges() == "":
		lines.remove_at(0)
	while lines.size() > 0 and lines[-1].strip_edges() == "":
		lines.remove_at(lines.size() - 1)
	return lines


## Direction from a boundary cell towards outer space.
func _outward(cell: Vector2i) -> Vector2i:
	for dir: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if get_cell(cell + dir) == " ":
			return dir
	push_warning("StationBuilder: slot at %s is not on the hull boundary" % cell)
	return Vector2i.DOWN


# --- Geometry ----------------------------------------------------------------

## `collision_only` cells get a floor collider but no visible tile.
func _add_floor(cells: Array[Vector3], collision_only: Array[Vector3] = []) -> void:
	if cells.is_empty() and collision_only.is_empty():
		return
	var tile := BoxMesh.new()
	tile.size = Vector3(CELL - 0.06, FLOOR_THICKNESS, CELL - 0.06)
	tile.material = ToonMaterials.get_material(Palette.FLOOR, 0.0, false)

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
	for pos in cells + collision_only:
		var col := CollisionShape3D.new()
		col.shape = shape
		col.position = pos + Vector3(0, -FLOOR_THICKNESS * 0.5, 0)
		body.add_child(col)


## One body for every wall cell (the visible walls are part of the hull mesh).
func _add_wall_collisions(cells: Array[Vector3]) -> void:
	var body := StaticBody3D.new()
	body.name = "Walls"
	body.collision_layer = Layers.WALLS
	body.collision_mask = 0
	_generated.add_child(body)
	var shape := BoxShape3D.new()
	shape.size = Vector3(CELL, WALL_HEIGHT, CELL)
	for pos in cells:
		var col := CollisionShape3D.new()
		col.shape = shape
		col.position = pos + Vector3(0, WALL_HEIGHT * 0.5, 0)
		body.add_child(col)


func _add_furniture(c: String, pos: Vector3, cell: Vector2i) -> void:
	var scene := load(FURNITURE_SCENES[c]) as PackedScene
	var node := scene.instantiate() as Node3D
	node.position = pos
	var facing := _find_free_neighbor(cell)
	if facing != Vector2i.ZERO:
		node.rotation.y = atan2(facing.x, facing.y)
		if c == WALL_FURNITURE:
			node.position += Vector3(facing.x, 0.0, facing.y) * wall_furniture_inset
	_generated.add_child(node)
	furniture_nodes.append(node)
	if node is Interactable and facing != Vector2i.ZERO:
		# The object faces its free neighbour (+Z), so the approach point is
		# straight ahead; it follows the module wherever it gets attached.
		(node as Interactable).approach_distance = CELL * 0.8


## Direction (unit grid step) of the first adjacent free floor cell.
func _find_free_neighbor(cell: Vector2i) -> Vector2i:
	for dir: Vector2i in [Vector2i.DOWN, Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP]:
		if FREE_FLOOR.contains(get_cell(cell + dir)):
			return dir
	return Vector2i.ZERO
