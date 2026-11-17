class_name HUD
extends CanvasLayer
## In-game overlay, laid out like a phone game, with the station kept in the
## middle of the screen: a top row of floating pills (clock, station status,
## needs), the focused module's card bottom-left, its objects' accordion
## bottom-right above a two-button dock (Station/Room, Inventory). Every
## action of the focused module is a HUD button; nothing needs a tap on a
## small 3D object. Built in code so layout changes stay reviewable in diffs.

const NEED_COLORS: Dictionary[StringName, Color] = {
	Needs.FOOD: Color("f0a35e"),
	Needs.ENERGY: UITheme.CYAN,
	Needs.MORALE: Color("a99be6"),
}
const MARGIN := 16
## Height reserved for the top bar when sizing the object cards.
const TOP_BAR_HEIGHT := 60.0
## Dock buttons (icon above a caption).
const DOCK_BUTTON := Vector2(84, 64)
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
var _nav_row: PanelContainer
var _margin: MarginContainer
var _scrim: ColorRect
var _toast: PanelContainer
var _toast_label: Label
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

	_scrim = UITheme.scrim()
	root.add_child(_scrim)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_margin = margin
	_apply_safe_area()
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
	column.add_theme_constant_override("separation", UITheme.SPACE_M)
	column.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	column.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	column.grow_vertical = Control.GROW_DIRECTION_BEGIN
	layer_root.add_child(column)
	object_panel = ObjectPanel.new()
	column.add_child(object_panel)
	_nav_row = PanelContainer.new()
	_nav_row.name = "Dock"
	_nav_row.size_flags_horizontal = Control.SIZE_SHRINK_END
	var dock_sb := UITheme.glass(18)
	dock_sb.set_content_margin_all(4)
	_nav_row.add_theme_stylebox_override("panel", dock_sb)
	column.add_child(_nav_row)
	var dock := HBoxContainer.new()
	dock.add_theme_constant_override("separation", 2)
	_nav_row.add_child(dock)
	view_button = UITheme.icon_button("Room", &"room", _on_view_pressed, true, UITheme.GHOST)
	view_button.name = "ViewButton"
	inventory_button = UITheme.icon_button("Inventory", &"bag", inventory_panel.toggle, true, UITheme.GHOST)
	inventory_button.name = "InventoryButton"
	for b: Button in [view_button, inventory_button]:
		b.custom_minimum_size = DOCK_BUTTON
		b.add_theme_font_size_override("font_size", UITheme.SMALL_FONT_SIZE - 1)
		b.add_theme_color_override("icon_normal_color", UITheme.TEXT)
		b.add_theme_constant_override("h_separation", 2)
		dock.add_child(b)

	# Build menu (side sheet, right: the ghost preview stays visible)
	build_menu = BuildMenu.new()
	layer_root.add_child(build_menu)
	layer_root.add_child(inventory_panel)

	# Encounter (story beat) panel, centre-top
	encounter_panel = EncounterPanel.new()
	encounter_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	encounter_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	encounter_panel.position.y = TOP_BAR_HEIGHT + 40
	layer_root.add_child(encounter_panel)

	production_popover = ProductionPopover.new()
	layer_root.add_child(production_popover)
	status_bar.chip_pressed.connect(production_popover.toggle)
	production_popover.resource_changed.connect(status_bar.set_active)

	# Modal sheets dim the station behind them.
	for panel: Control in [inventory_panel, encounter_panel]:
		panel.visibility_changed.connect(_update_scrim)

	# Toast (top-center pill, under the top row)
	_toast = PanelContainer.new()
	_toast.name = "Toast"
	var toast_sb := UITheme.pill(UITheme.GLASS, Color(UITheme.YELLOW, 0.6))
	toast_sb.content_margin_left = 22
	toast_sb.content_margin_right = 22
	toast_sb.content_margin_top = 10
	toast_sb.content_margin_bottom = 10
	_toast.add_theme_stylebox_override("panel", toast_sb)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.position.y = TOP_BAR_HEIGHT + 12
	_toast_label = UITheme.label("", false, UITheme.TEXT)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_child(_toast_label)
	_toast.modulate.a = 0.0
	_toast.hide()
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
	get_viewport().size_changed.connect(_apply_safe_area)
	_fit_object_panel()
	_update_scrim()


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
	_toast_label.text = message
	if _toast_tween:
		_toast_tween.kill()
	_toast.reset_size()
	_toast.show()
	_toast.position = Vector2(roundf((_toast.get_parent_area_size().x - _toast.size.x) * 0.5), TOP_BAR_HEIGHT)
	_toast.modulate.a = 0.0
	_toast_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.15)
	_toast_tween.parallel().tween_property(_toast, "position:y", TOP_BAR_HEIGHT + 12, 0.25)
	_toast_tween.tween_interval(2.0)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.5)
	_toast_tween.tween_callback(_toast.hide)


func _on_view_pressed() -> void:
	toggle_view()


func _on_room_view_changed(room: bool) -> void:
	_room_view = room
	view_button.text = "Station" if room else "Room"
	view_button.icon = UITheme.icon(&"map" if room else &"room")


## The object cards may grow up to the space left under the top bar.
func _fit_object_panel() -> void:
	var screen := get_viewport().get_visible_rect().size
	object_panel.max_height = maxf(160.0, screen.y - 2.0 * MARGIN - TOP_BAR_HEIGHT - DOCK_BUTTON.y - 8.0
		- 2.0 * UITheme.SPACE_M)


## Margins: MARGIN, plus the display cutouts / rounded corners on phones.
func _apply_safe_area() -> void:
	var insets := {"left": 0.0, "right": 0.0, "top": 0.0, "bottom": 0.0}
	if OS.has_feature("mobile"):
		var window := Vector2(DisplayServer.window_get_size())
		var safe := Rect2(DisplayServer.get_display_safe_area())
		if window.x > 0.0 and window.y > 0.0 and safe.size.x > 0.0:
			var to_ui := get_viewport().get_visible_rect().size / window
			insets.left = safe.position.x * to_ui.x
			insets.top = safe.position.y * to_ui.y
			insets.right = (window.x - safe.end.x) * to_ui.x
			insets.bottom = (window.y - safe.end.y) * to_ui.y
	for side: String in insets:
		_margin.add_theme_constant_override("margin_" + side, MARGIN + maxi(0, roundi(insets[side])))


func _update_scrim() -> void:
	UITheme.fade(_scrim, inventory_panel.visible or encounter_panel.visible)


func _on_need_critical(need: StringName) -> void:
	show_toast(CRITICAL_MESSAGES.get(need, "%s is critical." % need))
