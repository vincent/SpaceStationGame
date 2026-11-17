class_name InventorySlot
extends PanelContainer
## One cell of the inventory grid. Tap = select, double-tap / right-click =
## use, drag onto another slot = move/merge/swap.

signal selected(index: int)
signal used(index: int)

const SIZE := Vector2(84, 84)

var index: int
var _swatch: ColorRect
var _name: Label
var _count: Label
var _selected := false


func _init(slot_index: int) -> void:
	index = slot_index
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	# PanelContainer stretches the swatch over its content area; labels are
	# anchored inside the swatch.
	_swatch = ColorRect.new()  # item colour tile
	_swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_swatch)
	_name = UITheme.label("", true, UITheme.INK)
	_name.add_theme_font_size_override("font_size", 13)
	_name.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name.clip_text = true
	_swatch.add_child(_name)
	_count = UITheme.label("", true, UITheme.TEXT)
	_count.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_count.add_theme_color_override("font_outline_color", UITheme.INK)
	_count.add_theme_constant_override("outline_size", 6)
	_swatch.add_child(_count)
	refresh()


func set_selected(value: bool) -> void:
	_selected = value
	refresh()


func refresh() -> void:
	if _swatch == null:
		return
	var slot := GameState.inventory.get_slot(index)
	var item: ItemData = null if slot.is_empty() else GameState.item_db.get_item(slot.id)
	_swatch.color = Color.TRANSPARENT
	_name.text = ""
	_count.text = ""
	tooltip_text = ""
	if item:
		_swatch.color = item.color
		_name.text = item.display_name.get_slice(" ", 0)
		_count.text = str(slot.count) if slot.count > 1 else ""
		tooltip_text = "%s\n%s" % [item.display_name, item.description]
	# Selected = cyan rim; filled = raised; empty = a faint socket.
	var style: StyleBoxFlat
	if _selected:
		style = UITheme.box(UITheme.RAISED, UITheme.CYAN, 2, 10)
	elif item:
		style = UITheme.box(UITheme.RAISED, UITheme.HAIRLINE, 1, 10)
	else:
		style = UITheme.box(Color(1, 1, 1, 0.03), Color.TRANSPARENT, 0, 10)
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
	var preview := ColorRect.new()
	preview.size = SIZE * 0.8
	preview.color = _swatch.color
	set_drag_preview(preview)
	return {"inventory_slot": index}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("inventory_slot")


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	GameState.inventory.move(data.inventory_slot, index)
	selected.emit(index)
