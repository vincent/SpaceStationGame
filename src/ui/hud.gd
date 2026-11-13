class_name HUD
extends CanvasLayer
## In-game overlay, laid out like a phone game: top bar (clock, station
## status, needs), focused module card bottom-left, its objects' cards
## bottom-right above the Station/Room and Inventory buttons. Every action of
## the focused module is a HUD button; nothing needs a tap on a small 3D
## object. Built in code so layout changes stay reviewable in diffs.

const NEED_COLORS: Dictionary[StringName, Color] = {
	Needs.FOOD: Palette.ORANGE,
	Needs.ENERGY: Palette.NEON_CYAN,
	Needs.MORALE: Palette.NEON_PINK,
}
const MARGIN := 16
## Height reserved for the top bar when sizing the object cards.
const TOP_BAR_HEIGHT := 84.0
const CRITICAL_MESSAGES: Dictionary[StringName, String] = {
	Needs.FOOD: "You're starving.",
	Needs.ENERGY: "You can barely keep your eyes open.",
	Needs.MORALE: "The silence is getting to you.",
}

var top_bar: TopBar
var status_bar: StatusBar
var inventory_panel: InventoryPanel
var module_panel: ModulePanel
var object_panel: ObjectPanel
var build_menu: BuildMenu
var encounter_panel: EncounterPanel
var production_popover: ProductionPopover
## Bottom-right: zooms out to the station (room view) or back in (station view).
var view_button: Button
var inventory_button: Button
## The camera starts zoomed out; view_changed flips it.
var _room_view := false
var _focused: Module
var _nav_row: HBoxContainer
var _toast: Label
var _toast_tween: Tween


func _ready() -> void:
	layer = 10
	add_to_group(&"hud")
	var root := Control.new()
	root.name = "Root"
	root.theme = UITheme.get_theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, MARGIN)
	root.add_child(margin)

	var layer_root := Control.new()
	layer_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(layer_root)

	top_bar = TopBar.new()
	top_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	layer_root.add_child(top_bar)
	status_bar = top_bar.status_bar

	# Focused module (bottom-left)
	module_panel = ModulePanel.new()
	module_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	module_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	layer_root.add_child(module_panel)

	# Bottom-right column: object cards above the Station/Room + Inventory buttons
	inventory_panel = InventoryPanel.new()
	inventory_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	inventory_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	inventory_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var column := VBoxContainer.new()
	column.name = "RightColumn"
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 12)
	column.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	column.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	column.grow_vertical = Control.GROW_DIRECTION_BEGIN
	layer_root.add_child(column)
	object_panel = ObjectPanel.new()
	column.add_child(object_panel)
	_nav_row = HBoxContainer.new()
	_nav_row.alignment = BoxContainer.ALIGNMENT_END
	_nav_row.add_theme_constant_override("separation", 12)
	column.add_child(_nav_row)
	view_button = UITheme.icon_button("Room", &"room", _on_view_pressed)
	view_button.name = "ViewButton"
	inventory_button = UITheme.icon_button("Inventory", &"bag", inventory_panel.toggle)
	inventory_button.name = "InventoryButton"
	for b in [view_button, inventory_button]:
		b.custom_minimum_size = Vector2(150, 64)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_nav_row.add_child(b)

	# Build menu (centre)
	build_menu = BuildMenu.new()
	build_menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	build_menu.grow_horizontal = Control.GROW_DIRECTION_BOTH
	build_menu.grow_vertical = Control.GROW_DIRECTION_BOTH
	layer_root.add_child(build_menu)
	layer_root.add_child(inventory_panel)

	# Encounter (story beat) panel, centre-top
	encounter_panel = EncounterPanel.new()
	encounter_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	encounter_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	encounter_panel.position.y = 120
	layer_root.add_child(encounter_panel)

	production_popover = ProductionPopover.new()
	layer_root.add_child(production_popover)
	status_bar.chip_pressed.connect(production_popover.toggle)

	# Toast (top-center, under the top bar)
	_toast = UITheme.label("", false, Palette.TEXT)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.position.y = TOP_BAR_HEIGHT + 16
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_color_override("font_outline_color", Palette.NIGHT)
	_toast.add_theme_constant_override("outline_size", 8)
	_toast.modulate.a = 0.0
	layer_root.add_child(_toast)

	GameState.needs.became_critical.connect(_on_need_critical)
	EventBus.toast.connect(show_toast)
	EventBus.module_focused.connect(func(m: Module) -> void: _focused = m)
	EventBus.room_view_changed.connect(_on_room_view_changed)
	EventBus.upgrade_view_requested.connect(func(_m: Module) -> void:
		close_menus()
		top_bar.hide()  # the upgrade overlay owns the top of the screen
		_nav_row.hide())
	EventBus.upgrade_view_closed.connect(func() -> void:
		top_bar.show()
		_nav_row.show())
	get_viewport().size_changed.connect(_fit_object_panel)
	_fit_object_panel()


## Closes floating menus (called when the player taps the world). The module
## and object cards are part of the HUD and stay.
func close_menus() -> void:
	inventory_panel.hide()
	build_menu.hide()
	production_popover.close()


func is_menu_open() -> bool:
	return inventory_panel.visible or build_menu.visible or production_popover.visible


## Station view in room view, Room view in station view.
func toggle_view() -> void:
	if _room_view:
		EventBus.station_view_requested.emit()
	elif _focused and is_instance_valid(_focused):
		EventBus.module_focus_requested.emit(_focused)


func show_toast(message: String) -> void:
	_toast.text = message
	if _toast_tween:
		_toast_tween.kill()
	_toast.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(2.0)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.6)


func _on_view_pressed() -> void:
	toggle_view()


func _on_room_view_changed(room: bool) -> void:
	_room_view = room
	view_button.text = "Station" if room else "Room"
	view_button.icon = UITheme.icon(&"map" if room else &"room")


## The object cards may grow up to the space left under the top bar.
func _fit_object_panel() -> void:
	var screen := get_viewport().get_visible_rect().size
	object_panel.max_height = maxf(160.0, screen.y - 2.0 * MARGIN - TOP_BAR_HEIGHT - 64.0 - 2.0 * 12.0)


func _on_need_critical(need: StringName) -> void:
	show_toast(CRITICAL_MESSAGES.get(need, "%s is critical." % need))
