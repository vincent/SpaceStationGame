class_name InventorySlot
extends PanelContainer
## One cell of the inventory grid. Tap = select, double-tap / right-click =
## use, drag onto another slot = move/merge/swap.

signal selected(index: int)
signal used(index: int)

const SIZE := Vector2(84, 84)

var index: int
var _tile: Panel
var _icon: TextureRect
var _initial: Label
var _name: Label
var _count: Label
var _selected := false
var _color := Color.TRANSPARENT


func _init(slot_index: int) -> void:
	index = slot_index
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	# Item: a tinted rounded tile with its icon (or initial), its short name
	# under it and the count as a badge in the corner.
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	_tile = Panel.new()
	_tile.custom_minimum_size = Vector2(44, 44)
	_tile.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_tile)
	_icon = UITheme.icon_rect(&"", UITheme.TEXT, 28)
	_icon.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_icon.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_icon.grow_vertical = Control.GROW_DIRECTION_BOTH
	_tile.add_child(_icon)
	_initial = UITheme.title_label("")
	_initial.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_initial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tile.add_child(_initial)
	_name = UITheme.label("", true, UITheme.TEXT_DIM)
	_name.add_theme_font_size_override("font_size", UITheme.MIN_FONT_SIZE)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_name)
	_count = UITheme.number_label("", UITheme.TEXT, true)
	_count.add_theme_color_override("font_outline_color", UITheme.INK)
	_count.add_theme_constant_override("outline_size", 6)
	_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tile.add_child(_count)  # badge on the tile's bottom-right corner
	_count.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_count.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_count.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count.position += Vector2(10, 8)
	refresh()


func set_selected(value: bool) -> void:
	_selected = value
	refresh()


func refresh() -> void:
	if _tile == null:
		return
	var slot := GameState.inventory.get_slot(index)
	var item: ItemData = null if slot.is_empty() else GameState.item_db.get_item(slot.id)
	_tile.visible = item != null
	_name.text = ""
	_count.text = ""
	tooltip_text = ""
	_color = Color.TRANSPARENT
	if item:
		_color = item.color if item.color.a > 0.0 else UITheme.TEXT_DIM
		var tile_sb := UITheme.box(Color(_color, 0.16), Color(_color, 0.55), 1, 10)
		tile_sb.set_content_margin_all(0)
		_tile.add_theme_stylebox_override("panel", tile_sb)
		_icon.texture = UITheme.icon(item.id)
		_icon.modulate = _color.lerp(Color.WHITE, 0.25)
		_icon.visible = _icon.texture != null
		_initial.visible = not _icon.visible
		_initial.text = item.display_name.left(1).to_upper()
		_initial.add_theme_color_override("font_color", _color.lerp(Color.WHITE, 0.25))
		_name.text = item.display_name.get_slice(" ", 0)
		_count.text = str(slot.count) if slot.count > 1 else ""
		tooltip_text = "%s\n%s" % [item.display_name, item.description]
	# Selected = cyan rim; filled = raised; empty = a faint socket.
	var style: StyleBoxFlat
	if _selected:
		style = UITheme.box(Color(UITheme.CYAN, 0.1), UITheme.CYAN, 2, 12)
	elif item:
		style = UITheme.box(UITheme.RAISED, UITheme.HAIRLINE, 1, 12)
	else:
		style = UITheme.box(Color(1, 1, 1, 0.03), Color.TRANSPARENT, 0, 12)
	style.set_content_margin_all(6)
	add_theme_stylebox_override("panel", style)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT or (event.button_index == MOUSE_BUTTON_LEFT and event.double_click):
			used.emit(index)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			selected.emit(index)


func _get_drag_data(_at_position: Vector2) -> Variant:
	if GameState.inventory.is_empty_slot(index):
		return null
	var preview := Panel.new()
	preview.size = Vector2(52, 52)
	var sb := UITheme.box(Color(_color, 0.5), _color, 2, 12)
	preview.add_theme_stylebox_override("panel", sb)
	set_drag_preview(preview)
	return {"inventory_slot": index}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("inventory_slot")


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	GameState.inventory.move(data.inventory_slot, index)
	selected.emit(index)
