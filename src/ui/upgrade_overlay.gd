class_name UpgradeOverlay
extends CanvasLayer
## Labels of the exploded view, drawn like a technical diagram: one card per
## part (name, state, cost, install button) linked to the part by an ink
## leader line. Owned by ExplodedView.

const CARD_WIDTH := 300.0
const MARGIN := 20.0
const LINE_COLOR := Color(0.18, 0.89, 0.9, 0.9)

var view: ExplodedView

var _root: Control
var _lines: Control
var _title: Label
var _cards: Dictionary[ModulePart, Control] = {}


func _ready() -> void:
	layer = 20
	_root = Control.new()
	_root.theme = UITheme.get_theme()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_lines = Control.new()
	_lines.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lines.draw.connect(_draw_lines)
	_root.add_child(_lines)

	var top := PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.position.y = 12
	_title = UITheme.label("", false, Palette.YELLOW)
	top.add_child(_title)
	_root.add_child(top)

	var done := UITheme.button("Done", func() -> void: view.exit())
	done.custom_minimum_size = Vector2(200, 64)
	done.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	done.grow_horizontal = Control.GROW_DIRECTION_BOTH
	done.grow_vertical = Control.GROW_DIRECTION_BEGIN
	done.position.y -= 16
	_root.add_child(done)
	hide()


func open() -> void:
	_title.text = "%s — upgrades" % view.module.display_name()
	_rebuild_cards()
	show()


func close() -> void:
	for card: Control in _cards.values():
		card.queue_free()
	_cards.clear()
	hide()


func _rebuild_cards() -> void:
	for card: Control in _cards.values():
		card.queue_free()
	_cards.clear()
	var by_part := {}
	for up in GameState.module_db.upgrades_for(view.module.def.id):
		by_part[up.part_node] = up
	for part in view.module.get_parts():
		var card := _make_card(part, by_part.get(StringName(part.name)))
		_root.add_child(card)
		_cards[part] = card


func _make_card(part: ModulePart, up: UpgradeDef) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size.x = CARD_WIDTH
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var box := VBoxContainer.new()
	card.add_child(box)
	if up == null:
		box.add_child(UITheme.label(String(part.name).trim_prefix("part_").capitalize(), true, Palette.TEXT))
		box.add_child(UITheme.label("Built in", true, Palette.TEXT_DIM))
		return card
	box.add_child(UITheme.label(up.display_name, true, Palette.YELLOW))
	var desc := UITheme.label(up.description, true, Palette.TEXT_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(desc)
	var uid := view.module.uid
	if GameState.station.is_installed(uid, up.id):
		box.add_child(UITheme.label("Installed", true, Palette.NEON_CYAN))
		return card
	var err := GameState.upgrade_error(uid, up.id)
	var b := UITheme.button("Install · %s" % GameState.format_cost(up.cost), _buy.bind(up.id))
	b.add_theme_font_size_override("font_size", UITheme.SMALL_FONT_SIZE)
	b.disabled = err != ""
	box.add_child(b)
	if err != "" and not err.begins_with("Needs %s" % GameState.format_cost(up.cost)):
		box.add_child(UITheme.label("Locked — %s" % err, true, Palette.NEON_PINK))
	return card


func _buy(upgrade_id: StringName) -> void:
	if view.buy(upgrade_id):
		_rebuild_cards()


func _process(_delta: float) -> void:
	if not visible or view == null or not view.active:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var screen := _root.size
	var left: Array[ModulePart] = []
	var right: Array[ModulePart] = []
	for part: ModulePart in _cards:
		if not is_instance_valid(part):
			continue
		var p := cam.unproject_position(part.global_position)
		(left if p.x < screen.x * 0.5 else right).append(part)
	_stack(left, MARGIN, cam)
	_stack(right, screen.x - CARD_WIDTH - MARGIN, cam)
	_lines.queue_redraw()


func _stack(parts: Array[ModulePart], x: float, cam: Camera3D) -> void:
	parts.sort_custom(func(a: ModulePart, b: ModulePart) -> bool:
		return cam.unproject_position(a.global_position).y < cam.unproject_position(b.global_position).y)
	var y := 150.0
	for part in parts:
		var card := _cards[part]
		card.position = Vector2(x, y)
		y += card.size.y + 12.0


func _draw_lines() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	for part: ModulePart in _cards:
		if not is_instance_valid(part):
			continue
		var card := _cards[part]
		var anchor := cam.unproject_position(part.global_position)
		var on_left := card.position.x < _root.size.x * 0.5
		var edge := card.position + Vector2(card.size.x if on_left else 0.0, 28.0)
		var elbow := Vector2(lerpf(edge.x, anchor.x, 0.35), edge.y)
		_lines.draw_polyline(PackedVector2Array([edge, elbow, anchor]), LINE_COLOR, 2.0, true)
		_lines.draw_circle(anchor, 5.0, LINE_COLOR)
