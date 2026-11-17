class_name InventoryPanel
extends PanelContainer
## RPG-style inventory grid with an item details row.

const COLUMNS := 5

var _slots: Array[InventorySlot] = []
var _selected := -1
var _details_name: Label
var _details_text: Label
var _use_button: Button


func _ready() -> void:
	name = "InventoryPanel"
	hide()
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", UITheme.sheet())
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UITheme.SPACE_M + 2)
	add_child(vbox)
	vbox.add_child(UITheme.sheet_header(UITheme.title_label("Inventory"), hide))

	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", UITheme.SPACE_S)
	grid.add_theme_constant_override("v_separation", UITheme.SPACE_S)
	vbox.add_child(grid)
	for i in GameState.inventory.size:
		var slot := InventorySlot.new(i)
		slot.selected.connect(_select)
		slot.used.connect(_use)
		grid.add_child(slot)
		_slots.append(slot)

	# Details: selected item (name + description) on the left, Use on the right.
	var details := HBoxContainer.new()
	details.add_theme_constant_override("separation", UITheme.SPACE_M)
	details.custom_minimum_size.y = 64
	vbox.add_child(details)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	details.add_child(text)
	_details_name = UITheme.label("", false, Palette.NEON_CYAN)
	text.add_child(_details_name)
	_details_text = UITheme.label("Tap an item. Double-tap to use, drag to move.", true, Palette.TEXT_DIM)
	_details_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details_text.custom_minimum_size = Vector2(COLUMNS * InventorySlot.SIZE.x - 140, 0)
	text.add_child(_details_text)
	_use_button = UITheme.button("Use", func() -> void: _use(_selected), UITheme.PRIMARY)
	_use_button.custom_minimum_size.x = 120
	_use_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_use_button.disabled = true
	details.add_child(_use_button)

	GameState.inventory.changed.connect(_refresh)
	EventBus.game_reset.connect(_refresh)


func toggle() -> void:
	if visible:
		hide()
	else:
		_refresh()
		UITheme.fade(self, true)


func _select(index: int) -> void:
	_selected = index
	_refresh()


func _use(index: int) -> void:
	if index >= 0:
		GameState.use_item(index)


func _refresh() -> void:
	for slot in _slots:
		slot.set_selected(slot.index == _selected)
	var item: ItemData = null
	if _selected >= 0 and not GameState.inventory.is_empty_slot(_selected):
		item = GameState.item_db.get_item(GameState.inventory.get_slot(_selected).id)
	_details_name.text = item.display_name if item else ""
	if item:
		_details_text.text = item.description
	_details_name.visible = item != null
	_use_button.disabled = item == null or not item.usable
