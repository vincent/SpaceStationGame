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
	hide()
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	add_child(vbox)

	var header := HBoxContainer.new()
	header.add_child(UITheme.label("Inventory", false, Palette.YELLOW))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	header.add_child(UITheme.button("Close", hide))
	vbox.add_child(header)

	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	vbox.add_child(grid)
	for i in GameState.inventory.size:
		var slot := InventorySlot.new(i)
		slot.selected.connect(_select)
		slot.used.connect(_use)
		grid.add_child(slot)
		_slots.append(slot)

	_details_name = UITheme.label("", false, Palette.NEON_CYAN)
	vbox.add_child(_details_name)
	_details_text = UITheme.label("Tap an item. Double-tap to use, drag to move.", true, Palette.TEXT_DIM)
	_details_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details_text.custom_minimum_size = Vector2(COLUMNS * InventorySlot.SIZE.x, 0)
	vbox.add_child(_details_text)
	_use_button = UITheme.button("Use", func() -> void: _use(_selected))
	_use_button.disabled = true
	vbox.add_child(_use_button)

	GameState.inventory.changed.connect(_refresh)
	EventBus.game_reset.connect(_refresh)


func toggle() -> void:
	visible = not visible
	if visible:
		_refresh()


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
	_use_button.disabled = item == null or not item.usable
