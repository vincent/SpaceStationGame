@tool
class_name Module
extends Node3D
## One station module: a hull cut open by the cutaway, an interior generated
## from ASCII, lights driven by power, ambient props driven by state, upgrade
## parts and attachment slots. Mirrors one StationState record (see
## apply_record()). Press "Rebuild" in the inspector to preview in the editor.
##
## Built children (never saved):
##   Built/NavRegion/Interior   StationBuilder (floors, collisions, furniture)
##   Built/Hull, Built/Detail   cut + capped structure (Detail hidden far out)
##   Built/Lights               OmniLights + fake light cards on the floor
##   Built/Ambient              props from AmbientKit (state dependent)
##   Built/Slot_X, Built/Hatch_X  slots and the hatches sealing free ones
##   Built/Pick                 Area3D used to tap the module in station view
## Authored children: Parts/part_* (ModulePart) and mount_* markers, where
## upgrades with a `mount` get their part spawned (see UpgradeDef). Imported art may also
## provide `hull` (replaces the procedural hull), `slot_*` markers (replace
## the ASCII slot letters), `light_*` anchors (extra lights), `cut_box` (the
## region the cutaway opens, instead of the whole module), `greebles*` groups
## (hidden in station view) and `prop_*` interior meshes; see
## docs/ART_PIPELINE.md. With `art_palette` set, all of it is drawn with
## palette materials (ToonMaterials.get_art_material()).

const CELL := StationBuilder.CELL
const WALL_HEIGHT := StationBuilder.WALL_HEIGHT
const LIGHT_CARD_SHADER := preload("res://assets/shaders/light_card.gdshader")
const LIGHT_ENERGY := 1.6
## Night light colour the interior lights drift towards (DayCycle.warmth()).
const NIGHT_LIGHT := Color(1.0, 0.62, 0.35)
const POWER_ON_SECONDS := 2.0
const REPAIR_SECONDS := 1.5
## Wall thickness of imported art: wall furniture (bay windows) sits inside it.
const ART_WALL := 0.3

@export var module_id: StringName
@export_multiline var interior_ascii: String = "":
	set(value):
		interior_ascii = value
		if Engine.is_editor_hint() and is_inside_tree():
			build()
@export var hull_color: Color = Color("8a8f9e")
@export var trim_color: Color = Color("3a3d4a")
## Tint of the cut section fill (cream, grey, rust...).
@export var cap_tint: Color = Color.WHITE
@export var light_color: Color = Color("b8f4ff")
@export var greeble_seed: int = 1
## Palette texture of imported art (its UVs point at swatches). Unset for
## procedural modules.
@export var art_palette: Texture2D
@export_tool_button("Rebuild", "Reload") var rebuild_action: Callable = build

var uid := 0
var def: ModuleDef
## The slot this module is attached by (StationState own_slot); "" = default.
var attach_slot_name: StringName = &""
var state: int = StationState.State.REPAIRED
var powered := true
var wear := 0.2
var installed_parts: Array[StringName] = []
var slots: Dictionary[StringName, Slot] = {}
var interior: StationBuilder
var nav_region: NavigationRegion3D
var hull: MeshInstance3D
var detail: MeshInstance3D
var pick_area: Area3D
## Module-local AABB of the hull (with greebles).
var hull_aabb := AABB()
## False while the hull is closed (see set_interior_visible()).
var interior_visible := true
## Where the module sits once attached (arrival animations move it away from
## there for a moment). Set by Station.
var rest_transform := Transform3D.IDENTITY

var _built: Node3D
var _ambient: Node3D
var _lights: Array[OmniLight3D] = []
var _light_cards: Array[MeshInstance3D] = []
var _light_levels: Array[float] = []
var _strip_level := 1.0
var _fx_level := 1.0
var _hatches: Dictionary[StringName, Node3D] = {}
var _cut_geometry: Array[GeometryInstance3D] = []
## This module's own copies of the toon_cut materials its geometry uses
## (per-module values: wear, power, cap tint, sweeps).
var _cut_materials: Array[ShaderMaterial] = []
var _art_greebles: Array[Node3D] = []
var _cut_box: MeshInstance3D
var _sequence: Tween
var _wear_tween: Tween


func _ready() -> void:
	add_to_group(&"station_module")
	if Engine.is_editor_hint():
		build()


func build() -> void:
	if _built != null:
		_built.free()
	slots.clear()
	_hatches.clear()
	_lights.clear()
	_light_cards.clear()
	_light_levels.clear()
	_cut_geometry.clear()
	_cut_materials.clear()
	_built = Node3D.new()
	_built.name = "Built"
	add_child(_built)

	nav_region = NavigationRegion3D.new()
	nav_region.name = "NavRegion"
	nav_region.navigation_mesh = make_navigation_mesh()
	_built.add_child(nav_region)
	interior = StationBuilder.new()
	interior.name = "Interior"
	interior.layout = interior_ascii
	if has_art():
		interior.hide_slot_floor = true
		interior.wall_furniture_inset = CELL * 0.5 - ART_WALL * 0.5
	elif _wall_furniture_in_thin_walls():
		interior.wall_furniture_inset = CELL * 0.5 - HullMesher.THIN_WALL * 0.5
	nav_region.add_child(interior)
	interior.build()

	_build_hull()
	for node in interior.furniture_nodes:
		if node is Interactable and (node as Interactable).structural:
			for geo in node.find_children("*", "GeometryInstance3D", true, false):
				_cut_geometry.append(geo as GeometryInstance3D)
	_build_lights()
	_build_slots()
	_spawn_mounted_parts()
	_build_parts()
	_style_art()
	_build_pick_area()
	_ambient = Node3D.new()
	_ambient.name = "Ambient"
	_built.add_child(_ambient)
	_localize_cut_materials()
	_apply_instance_params()
	_apply_light_levels()
	refresh_parts()


static func make_navigation_mesh() -> NavigationMesh:
	var nav := NavigationMesh.new()
	nav.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav.geometry_collision_mask = Layers.WORLD
	nav.cell_size = 0.25
	nav.cell_height = 0.25
	nav.agent_height = 1.75
	nav.agent_radius = 0.5
	nav.agent_max_climb = 0.25
	return nav


func bake_navigation() -> void:
	nav_region.bake_navigation_mesh(false)
	sync_navigation_transform()


## Pushes the region's current transform to the NavigationServer. Moving a
## module in the frame it entered the tree can leave the server copy stale.
func sync_navigation_transform() -> void:
	if nav_region and nav_region.is_inside_tree():
		NavigationServer3D.region_set_transform(nav_region.get_rid(), nav_region.global_transform)


func get_world_aabb() -> AABB:
	return global_transform * hull_aabb


## World AABB at the rest transform (layout / camera framing).
func get_rest_aabb() -> AABB:
	return rest_transform * hull_aabb


## True when the module uses imported art (an authored `hull`).
func has_art() -> bool:
	return get_node_or_null(^"hull") is MeshInstance3D


## World bounds of everything the cutaway must slice: the art's `cut_box` if
## it has one, else hull + visible parts.
func get_cut_aabb() -> AABB:
	if _cut_box != null:
		return global_transform * (_cut_box.transform * _cut_box.get_aabb())
	var box := get_world_aabb()
	for part in get_parts():
		if part.visible and part.is_inside_tree():
			box = box.merge(global_transform * part.get_aabb_in(self))
	return box


## Interior spawn point in world space (Vector3.INF if the layout has no "P").
func get_spawn_position() -> Vector3:
	if interior.spawn_position == Vector3.INF:
		return Vector3.INF
	return interior.global_transform * interior.spawn_position


func get_attach_slot() -> Slot:
	if attach_slot_name != &"":
		return slots.get(attach_slot_name)
	return slots.get(def.attach_slot if def else &"A")


func get_parts() -> Array[ModulePart]:
	var out: Array[ModulePart] = []
	var root := get_node_or_null(^"Parts")
	if root:
		for child in root.get_children():
			if child is ModulePart:
				out.append(child)
	return out


## The `mount_<mount_id>` marker, or null.
func get_mount(mount_id: StringName) -> Node3D:
	for node in find_children("mount_*", "Node3D", true, false):
		if ModuleImportRules.mount_name(node.name) == mount_id and (_built == null or not _built.is_ancestor_of(node)):
			return node as Node3D
	return null


func display_name() -> String:
	return def.display_name if def else String(module_id)


# --- State -------------------------------------------------------------------

## Mirrors a StationState record. With `animate`, changes play their reward
## sequences (repair sweep, power-on, part pop).
func apply_record(rec: Dictionary, animate: bool) -> void:
	var was_derelict := state == StationState.State.DERELICT
	var was_powered := powered
	state = int(rec.get("state", state))
	powered = bool(rec.get("powered", powered))
	installed_parts.assign(rec.get("parts", []))
	var target_wear := float(rec.get("wear", wear))

	if animate and was_derelict and state != StationState.State.DERELICT:
		play_repair(target_wear)
	elif animate and not is_equal_approx(target_wear, wear):
		_tween_wear(target_wear, REPAIR_SECONDS)
	else:
		set_wear(target_wear)

	if animate and powered and not was_powered:
		play_power_on()
	elif animate and was_powered and not powered:
		play_power_off()
	elif not animate:
		_set_power_instant(1.0 if powered else 0.0)
	refresh_parts()
	refresh_ambient()


## Interiors are only drawn while cut open (a closed hull hides them anyway):
## floor tiles, furniture (not structural pieces like windows), interior
## lights and props. Collisions stay, so navigation and taps are unaffected.
func set_interior_visible(on: bool) -> void:
	if interior == null or interior_visible == on:
		return
	interior_visible = on
	var generated := interior.get_node_or_null(^"Generated")
	if generated:
		for child in generated.get_children():
			if child is Node3D and not (child is Interactable and (child as Interactable).structural):
				(child as Node3D).visible = on
	var lights := _built.get_node_or_null(^"Lights") as Node3D
	if lights:
		lights.visible = on
	for prop in get_tree().get_nodes_in_group(&"interior_prop"):
		if is_ancestor_of(prop):
			(prop as Node3D).visible = on


## Small greebles are hidden in the zoomed-out station view.
func set_detail_visible(on: bool) -> void:
	if detail:
		detail.visible = on
	for group in _art_greebles:
		group.visible = on


func set_wear(value: float) -> void:
	wear = value
	_set_param(&"wear", wear)


## Shows parts that are always there or installed; hides the others.
func refresh_parts() -> void:
	var by_part := _upgrade_by_part()
	for part in get_parts():
		var upgrade_id: StringName = by_part.get(part.name, &"")
		part.visible = part.always_visible or upgrade_id == &"" or installed_parts.has(upgrade_id) \
			or Engine.is_editor_hint()


## Upgrade id that reveals each part node (part name -> upgrade id).
func _upgrade_by_part() -> Dictionary:
	var out := {}
	if not Engine.is_editor_hint() and def != null:
		for up in GameState.module_db.upgrades_for(def.id):
			out[StringName(up.part_node)] = up.id
	return out


func refresh_ambient() -> void:
	if _ambient == null:
		return
	for child in _ambient.get_children():
		child.queue_free()
	if not Engine.is_editor_hint():
		AmbientKit.populate(self, _ambient)


## Free slot doorways are sealed by a hatch; attached ones are open.
func set_slot_open(slot_name: StringName, open: bool) -> void:
	var hatch: Node3D = _hatches.get(slot_name)
	if hatch == null:
		return
	hatch.visible = not open
	var body := hatch.get_node_or_null(^"Body") as StaticBody3D
	if body:
		body.collision_layer = 0 if open else Layers.WALLS


## Call after the module moved (attach): world-space sweep range etc.
func refresh_world_params() -> void:
	_apply_instance_params()


# --- Sequences ---------------------------------------------------------------

## Power-on (~2 s): strips sweep along the hull, lights flicker on room by
## room starting from the entrance, screens boot last.
func play_power_on() -> void:
	_kill_sequence()
	EventBus.power_on_started.emit(self)
	_strip_level = 0.0
	_fx_level = 0.0
	for i in _light_levels.size():
		_light_levels[i] = 0.0
	_apply_light_levels()
	_set_param(&"power_level", 0.0)
	_sequence = create_tween().set_parallel()
	_sequence.tween_method(_set_strip_level, 0.0, 1.0, POWER_ON_SECONDS * 0.8).set_delay(0.2)
	var order := _lights_from_entrance()
	for n in order.size():
		var i := order[n]
		var t0 := 0.25 + n * (POWER_ON_SECONDS * 0.6 / maxf(1.0, order.size()))
		for step: Array in [[0.0, 0.6], [0.06, 0.0], [0.12, 1.0], [0.2, 0.15], [0.3, 1.0]]:
			_sequence.tween_callback(_set_light_level.bind(i, step[1])).set_delay(t0 + step[0])
	for step: Array in [[1.5, 0.7], [1.6, 0.0], [1.7, 1.0]]:
		_sequence.tween_callback(_set_fx_level.bind(step[1])).set_delay(step[0])


func play_power_off() -> void:
	_kill_sequence()
	_sequence = create_tween().set_parallel()
	_sequence.tween_method(_set_power_instant, 1.0, 0.0, 0.5)


## Repair: a yellow sweep runs along the hull while the rust recedes.
func play_repair(target_wear: float) -> void:
	EventBus.sfx.emit(&"repair")
	_tween_wear(target_wear, REPAIR_SECONDS)
	var flash := create_tween()
	flash.tween_method(func(v: float) -> void: _set_param(&"repair_flash", v), 0.001, 1.0, REPAIR_SECONDS)
	flash.tween_callback(func() -> void: _set_param(&"repair_flash", 0.0))


func is_sequence_running() -> bool:
	return _sequence != null and _sequence.is_running()


func _tween_wear(target: float, seconds: float) -> void:
	if _wear_tween:
		_wear_tween.kill()
	_wear_tween = create_tween()
	_wear_tween.tween_method(set_wear, wear, target, seconds).set_trans(Tween.TRANS_SINE)


func _kill_sequence() -> void:
	if _sequence:
		_sequence.kill()
		_sequence = null


func _set_power_instant(level: float) -> void:
	_set_strip_level(level)
	_set_fx_level(level)
	for i in _light_levels.size():
		_light_levels[i] = level
	_apply_light_levels()


func _set_strip_level(level: float) -> void:
	_strip_level = level
	_set_param(&"power_level", level)


func _set_fx_level(level: float) -> void:
	_fx_level = level
	for node in find_children("*", "GeometryInstance3D", true, false):
		if node.is_in_group(&"powered_fx"):
			var mat := (node as GeometryInstance3D).material_override as ShaderMaterial
			if mat:  # each fx mesh owns its material (AmbientKit, Console)
				mat.set_shader_parameter(&"active", level)


func _set_light_level(index: int, level: float) -> void:
	_light_levels[index] = level
	_apply_light_levels()


func _apply_light_levels() -> void:
	var scale := 1.0
	var warmth := 0.0
	if not Engine.is_editor_hint():
		var hour := GameClock.total_minutes / GameClock.MINUTES_PER_HOUR
		scale = DayCycle.light_scale(hour)
		warmth = DayCycle.warmth(hour)
	var color := light_color.lerp(NIGHT_LIGHT, warmth * 0.75)
	for i in _lights.size():
		_lights[i].light_energy = LIGHT_ENERGY * _light_levels[i] * scale
		_lights[i].light_color = color
		_lights[i].visible = _light_levels[i] > 0.01
		var card_mat := _light_cards[i].material_override as ShaderMaterial
		card_mat.set_shader_parameter(&"intensity", _light_levels[i] * scale)
		card_mat.set_shader_parameter(&"tint", color)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or _lights.is_empty():
		return
	# Clock lighting changes slowly; refresh a few times per second is plenty.
	if Engine.get_process_frames() % 15 == uid % 15:
		_apply_light_levels()


## Light indices sorted by distance from the attach doorway.
func _lights_from_entrance() -> Array[int]:
	var origin := Vector3.ZERO
	var slot := get_attach_slot()
	if slot:
		origin = slot.position
	var order: Array[int] = []
	for i in _lights.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		return _lights[a].position.distance_to(origin) < _lights[b].position.distance_to(origin))
	return order


# --- Building ----------------------------------------------------------------

## Procedural hull: are all bay windows in thinned outer walls (HullMesher)?
## Then they move in to sit inside the thin wall, as in imported art.
func _wall_furniture_in_thin_walls() -> bool:
	var grid := StationBuilder.parse(interior_ascii)
	var found := false
	for z in grid.size():
		for x in grid[z].length():
			if StationBuilder.WALL_FURNITURE.contains(grid[z][x]):
				if not HullMesher.is_thin_cell(grid, Vector2i(x, z)):
					return false
				found = true
	return found


func _build_hull() -> void:
	var mat := ToonMaterials.get_cut_material(hull_color, 0.0, true, trim_color)
	var authored := get_node_or_null(^"hull") as MeshInstance3D
	if authored:
		hull = authored
		hull.material_override = ToonMaterials.get_art_material(art_palette, true) if art_palette else mat
		hull_aabb = hull.transform * hull.get_aabb()
		_cut_geometry.append(hull)
		return
	var res := HullMesher.build(interior.get_grid(), CELL, interior.get_offset(), WALL_HEIGHT, greeble_seed)
	hull_aabb = res.aabb
	hull = MeshInstance3D.new()
	hull.name = "Hull"
	hull.mesh = res.hull
	hull.material_override = mat
	_built.add_child(hull)
	_cut_geometry.append(hull)
	detail = MeshInstance3D.new()
	detail.name = "Detail"
	detail.mesh = res.detail
	detail.material_override = ToonMaterials.get_cut_material(hull_color, 0.0, false, trim_color)
	detail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_built.add_child(detail)
	_cut_geometry.append(detail)


func _build_lights() -> void:
	var root := Node3D.new()
	root.name = "Lights"
	_built.add_child(root)
	var card_mat := ShaderMaterial.new()
	card_mat.shader = LIGHT_CARD_SHADER
	card_mat.set_shader_parameter("color", light_color)
	var card_mesh := PlaneMesh.new()
	card_mesh.size = Vector2(CELL * 2.4, CELL * 2.4)
	var positions := interior.light_positions.duplicate()
	for anchor in find_children("light_*", "Node3D", true, false):
		if anchor.is_in_group(&"light_anchor"):
			positions.append((anchor as Node3D).position - Vector3(0, WALL_HEIGHT - 0.5, 0))
	for pos: Vector3 in positions:
		var light := OmniLight3D.new()
		light.position = pos + Vector3(0, WALL_HEIGHT - 0.5, 0)
		light.light_color = light_color
		light.omni_range = CELL * 3.4
		light.light_energy = LIGHT_ENERGY
		light.light_cull_mask &= ~Layers.RENDER_EXTERIOR
		light.add_to_group(&"interior_light")
		root.add_child(light)
		var card := MeshInstance3D.new()
		card.mesh = card_mesh
		card.material_override = card_mat.duplicate()  # own intensity / tint
		card.position = pos + Vector3(0, 0.02, 0)
		card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(card)
		_lights.append(light)
		_light_cards.append(card)
		_light_levels.append(1.0)


func _build_slots() -> void:
	var hatch_mat := ToonMaterials.get_cut_material(trim_color, 0.0, true, Palette.YELLOW)
	var doors := {}
	for slot_name: StringName in interior.slot_cells:
		var info: Dictionary = interior.slot_cells[slot_name]
		var out2: Vector2i = info.outward
		doors[slot_name] = [interior.cell_to_world(info.cell), Vector3(out2.x, 0, out2.y)]
	# Imported art: slot_* markers (+Z out) win over ASCII slot letters.
	for marker in find_children("slot_*", "Marker3D", true, false):
		var m := marker as Marker3D
		var out := m.basis.z.normalized()
		doors[ModuleImportRules.slot_name(m.name)] = [m.position - out * (CELL * 0.5 + Slot.GAP), out]
	for slot_name: StringName in doors:
		var door: Vector3 = doors[slot_name][0]
		var out3: Vector3 = doors[slot_name][1]
		var slot := Slot.new()
		slot.name = "Slot_%s" % slot_name
		slot.slot_name = slot_name
		slot.module = self
		slot.door_position = door
		slot.position = door + out3 * (CELL * 0.5 + Slot.GAP)
		slot.rotation.y = atan2(out3.x, out3.z)
		if def:
			slot.accepts = def.slots.get(slot_name, PackedStringArray(["module"]))
			slot.size_class = def.slot_size(slot_name)
		_built.add_child(slot)
		slots[slot_name] = slot
		_hatches[slot_name] = _make_hatch(slot_name, door, out3, hatch_mat)


## A door panel sealing the doorway of a free slot (+ its collision).
func _make_hatch(slot_name: StringName, door: Vector3, out3: Vector3, mat: Material) -> Node3D:
	var hatch := Node3D.new()
	hatch.name = "Hatch_%s" % slot_name
	hatch.position = door + out3 * (CELL * 0.5 - 0.2)
	hatch.rotation.y = atan2(out3.x, out3.z)
	_built.add_child(hatch)
	var height := WALL_HEIGHT - HullMesher.FLOOR_TOP - 0.02
	var kit := MeshKit.new()
	kit.box(Vector3(0, HullMesher.FLOOR_TOP + 0.01 + height * 0.5, 0), Vector3(CELL - 0.02, height, 0.3),
		Color(0.4, 0.0, 0.0))
	kit.box(Vector3(0, 1.1, 0.17), Vector3(CELL * 0.6, 0.12, 0.04), Color(0.0, 1.0, 0.0))
	var mesh := MeshInstance3D.new()
	mesh.mesh = kit.commit()
	mesh.material_override = mat
	hatch.add_child(mesh)
	_cut_geometry.append(mesh)
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = Layers.WALLS
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(CELL, WALL_HEIGHT, 0.3)
	col.shape = shape
	col.position.y = WALL_HEIGHT * 0.5
	body.add_child(col)
	hatch.add_child(body)
	return hatch


## Upgrades with a `mount` and no authored part get a ModulePart spawned on
## their marker: the art scene if any, else the procedural placeholder.
func _spawn_mounted_parts() -> void:
	if Engine.is_editor_hint():
		return
	var parts_root := get_node_or_null(^"Parts") as Node3D
	for up in GameState.module_db.upgrades_for(def.id if def else module_id):
		if up.mount == &"" or (parts_root and parts_root.has_node(NodePath(String(up.part_node)))):
			continue
		var marker := get_mount(up.mount)
		if marker == null:
			push_error("%s: upgrade %s wants mount_%s, which the scene lacks" % [name, up.id, up.mount])
			continue
		if parts_root == null:
			parts_root = Node3D.new()
			parts_root.name = "Parts"
			add_child(parts_root)
		var part := ModulePart.new()
		part.name = String(up.part_node)
		part.transform = _local_transform(parts_root).affine_inverse() * _local_transform(marker)
		var up_axis := _local_transform(marker).basis.y.normalized()
		part.explode_dir = up.explode_dir if up.explode_dir != Vector3.ZERO else up_axis
		if up.part_scene:
			part.kind = ModulePart.Kind.CUSTOM
			part.add_child(up.part_scene.instantiate())
		else:
			part.kind = up.part_kind
			part.length = up.part_length
			part.mirror = up.part_mirror
		parts_root.add_child(part)


## Transform of a descendant relative to this module.
func _local_transform(node: Node3D) -> Transform3D:
	var t := node.transform
	var parent := node.get_parent()
	while parent != self and parent is Node3D:
		t = (parent as Node3D).transform * t
		parent = parent.get_parent()
	return t


func _build_parts() -> void:
	var mat := ToonMaterials.get_cut_material(hull_color.lerp(Color.WHITE, 0.15), 0.0, true, trim_color)
	var art_mat: Material = ToonMaterials.get_art_material(art_palette, true) if art_palette else mat
	for part in get_parts():
		# Imported parts (CUSTOM) use the palette; procedural placeholders keep the module colours.
		part.build(art_mat if part.kind == ModulePart.Kind.CUSTOM else mat)
		_cut_geometry.append_array(part.geometries())


## Imported art besides hull and parts: greebles (structure, cut by the
## cutaway, hidden in station view), prop_* (interior: never cut, hidden
## while the hull is closed) and frame* (canopy struts: never cut, always
## visible). `cut_box` only defines the cut region.
func _style_art() -> void:
	_art_greebles.clear()
	_cut_box = get_node_or_null(^"cut_box") as MeshInstance3D
	if _cut_box:
		_cut_box.visible = false
	if not has_art():
		return
	var cut_mat: Material = ToonMaterials.get_art_material(art_palette, true) if art_palette else hull.material_override
	var prop_mat: Material = ToonMaterials.get_art_material(art_palette, false) if art_palette else cut_mat
	for child in get_children():
		if child == _built or child == hull or child == _cut_box or child.name == &"Parts":
			continue
		var child_name := String(child.name)
		var is_prop := child_name.begins_with("prop_")
		var is_frame := child_name.begins_with("frame")
		if is_prop:
			child.add_to_group(&"interior_prop")
		elif child_name.begins_with("greebles"):
			_art_greebles.append(child as Node3D)
		var meshes: Array[Node] = child.find_children("*", "MeshInstance3D", true, false)
		if child is MeshInstance3D:
			meshes.append(child)
		for node in meshes:
			var mesh := node as MeshInstance3D
			if not mesh.visible:  # "-nav" sources are hidden by the import script
				continue
			mesh.material_override = prop_mat if is_prop or is_frame else cut_mat
			if is_frame:
				mesh.layers = Layers.RENDER_EXTERIOR
			if not (is_prop or is_frame):
				_cut_geometry.append(mesh)


func _build_pick_area() -> void:
	pick_area = Area3D.new()
	pick_area.name = "Pick"
	pick_area.collision_layer = Layers.MODULE_PICK
	pick_area.collision_mask = 0
	pick_area.monitoring = false
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = hull_aabb.size
	col.shape = shape
	col.position = hull_aabb.get_center()
	pick_area.add_child(col)
	_built.add_child(pick_area)


func _apply_instance_params() -> void:
	var world := get_world_aabb() if is_inside_tree() else hull_aabb
	_set_param(&"sweep_range", Vector2(world.position.x, world.end.x))
	_set_param(&"cap_tint", cap_tint)
	_set_param(&"wear", wear)
	_set_param(&"power_level", _strip_level)


func _set_param(param: StringName, value: Variant) -> void:
	for mat in _cut_materials:
		mat.set_shader_parameter(param, value)


## Swaps the shared (cached) toon_cut materials of the cut geometry for copies
## owned by this module, so _set_param() changes this module only.
func _localize_cut_materials() -> void:
	var local := {}  # shared material -> this module's copy
	var swap := func(mat: Material) -> Material:
		if not (mat is ShaderMaterial and (mat as ShaderMaterial).shader == ToonMaterials.TOON_CUT_SHADER):
			return null
		if not local.has(mat):
			var copy := mat.duplicate() as ShaderMaterial  # shallow: the outline next_pass stays shared
			local[mat] = copy
			_cut_materials.append(copy)
		return local[mat]
	for geo in _cut_geometry:
		var over: Material = swap.call(geo.material_override)
		if over:
			geo.material_override = over
		elif geo is MeshInstance3D and (geo as MeshInstance3D).mesh:
			var mesh := geo as MeshInstance3D
			for i in mesh.get_surface_override_material_count():
				var surface: Material = swap.call(mesh.get_active_material(i))
				if surface:
					mesh.set_surface_override_material(i, surface)
