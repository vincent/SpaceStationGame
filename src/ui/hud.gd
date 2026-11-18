class_name HUD
extends CanvasLayer
## In-game overlay, laid out like a phone game, with the station kept in view.
## Adapts to the screen: landscape = one top row of floating pills (clock,
## station status, needs), the ModuleSheet docked bottom-left and the dock
## (Station/Room, Inventory) bottom-right; portrait = the top bar on two
## rows, the ModuleSheet as a full-width bottom sheet and the dock floating
## above it. Every action of the focused module is a HUD button; nothing
## needs a tap on a small 3D object. Back (Android / Esc) closes the topmost
## thing. Built in code so layout changes stay reviewable in diffs.

const NEED_COLORS: Dictionary[StringName, Color] = {
	Needs.FOOD: Color("f0a35e"),
	Needs.ENERGY: UITheme.CYAN,
	Needs.MORALE: Color("a99be6"),
}
const MARGIN := 16
## Height of the (one-row) top bar, a fallback before it is laid out.
const TOP_BAR_HEIGHT := 60.0
## Dock buttons (icon above a caption).
const DOCK_BUTTON := Vector2(88, 68)
const CRITICAL_MESSAGES: Dictionary[StringName, String] = {
	Needs.FOOD: "You're starving.",
	Needs.ENERGY: "You can barely keep your eyes open.",
	Needs.MORALE: "The silence is getting to you.",
}
## Toast rim colour and icon per notice kind.
const TOAST_STYLES := {
	&"info": [UITheme.YELLOW, &""],
	&"success": [UITheme.SUCCESS, &"check"],
	&"warning": [UITheme.DANGER, &"alert"],
}

var top_bar: TopBar
var status_bar: StatusBar
var inventory_panel: InventoryPanel
var module_panel: ModulePanel
var object_panel: ObjectPanel
var sheet: ModuleSheet
var build_menu: BuildMenu
var encounter_panel: EncounterPanel
var production_popover: ProductionPopover
var feedback: FeedbackLayer
## Bottom-right: zooms out to the station (room view) or back in (station view).
var view_button: Button
var inventory_button: Button
## Portrait layout (taller than wide).
var portrait := false
## The camera starts zoomed out; view_changed flips it.
var _room_view := false
var _focused: Module
var _nav_row: PanelContainer
var _layer_root: Control
var _margin: MarginContainer
var _scrim: ColorRect
var _toast: PanelContainer
var _toast_label: Label
var _toast_icon: TextureRect
var _toast_tween: Tween
var _overlay_open := false
var _free_rect := Rect2()


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
	_layer_root = layer_root
	margin.add_child(layer_root)

	# A full-rect column keeps the top bar exactly as wide as the screen
	# (a plain anchored control drifts to its minimum size on rotation).
	var top_column := VBoxContainer.new()
	top_column.name = "TopColumn"
	top_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer_root.add_child(top_column)
	top_column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	top_bar = TopBar.new()
	top_column.add_child(top_bar)
	status_bar = top_bar.status_bar

	# The focused module and its objects: one contextual sheet.
	module_panel = ModulePanel.new()
	object_panel = ObjectPanel.new()
	sheet = ModuleSheet.new(module_panel, object_panel)
	layer_root.add_child(sheet)
	sheet.layout_changed.connect(_on_sheet_moved)

	inventory_panel = InventoryPanel.new()
	inventory_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	inventory_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	inventory_panel.grow_vertical = Control.GROW_DIRECTION_BOTH

	# Dock: Station/Room + Inventory.
	_nav_row = PanelContainer.new()
	_nav_row.name = "Dock"
	var dock_sb := UITheme.glass(18)
	dock_sb.set_content_margin_all(4)
	_nav_row.add_theme_stylebox_override("panel", dock_sb)
	layer_root.add_child(_nav_row)
	var dock := HBoxContainer.new()
	dock.add_theme_constant_override("separation", 2)
	_nav_row.add_child(dock)
	view_button = UITheme.icon_button("Room", &"room", _on_view_pressed, true, UITheme.GHOST)
	view_button.name = "ViewButton"
	inventory_button = UITheme.icon_button("Inventory", &"bag", inventory_panel.toggle, true, UITheme.GHOST)
	inventory_button.name = "InventoryButton"
	for b: Button in [view_button, inventory_button]:
		b.custom_minimum_size = DOCK_BUTTON
		b.add_theme_font_size_override("font_size", UITheme.SMALL_FONT_SIZE)
		b.add_theme_color_override("icon_normal_color", UITheme.TEXT)
		b.add_theme_constant_override("h_separation", 2)
		dock.add_child(b)
	_nav_row.resized.connect(_place_dock)

	# Build menu (side sheet right in landscape, bottom sheet in portrait)
	build_menu = BuildMenu.new()
	layer_root.add_child(build_menu)
	build_menu.item_rect_changed.connect(_update_free_rect)
	build_menu.visibility_changed.connect(_update_free_rect)
	build_menu.visibility_changed.connect(_update_sheet_cover)
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
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var toast_row := HBoxContainer.new()
	toast_row.add_theme_constant_override("separation", UITheme.SPACE_S)
	toast_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.add_child(toast_row)
	_toast_icon = UITheme.icon_rect(&"check", UITheme.SUCCESS, 22)
	toast_row.add_child(_toast_icon)
	_toast_label = UITheme.label("", false, UITheme.TEXT)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_row.add_child(_toast_label)
	_toast.modulate.a = 0.0
	_toast.hide()
	layer_root.add_child(_toast)

	feedback = FeedbackLayer.new(self)
	root.add_child(feedback)

	GameState.needs.became_critical.connect(_on_need_critical)
	EventBus.toast.connect(show_toast)
	EventBus.notice.connect(show_toast)
	EventBus.module_focused.connect(func(m: Module) -> void: _focused = m)
	EventBus.room_view_changed.connect(_on_room_view_changed)
	EventBus.upgrade_view_requested.connect(func(_m: Module) -> void:
		close_menus()
		_overlay_open = true
		top_bar.hide()  # the upgrade overlay owns the top of the screen
		_nav_row.hide()
		_update_free_rect())
	EventBus.upgrade_view_closed.connect(func() -> void:
		_overlay_open = false
		top_bar.show()
		_place_dock()
		_update_free_rect.call_deferred())
	get_window().size_changed.connect(_fit_content_scale)
	get_viewport().size_changed.connect(_on_viewport_resized)
	_fit_content_scale()
	_on_viewport_resized()
	_update_scrim()


## Closes floating menus (called when the player taps the world). The module
## sheet is part of the HUD and stays.
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


## Back (Android back button, Esc): closes the topmost thing. False when
## there was nothing to close (station view, no menu).
func handle_back() -> bool:
	if production_popover.visible:
		production_popover.close()
	elif build_menu.visible:
		build_menu.hide()
	elif inventory_panel.visible:
		inventory_panel.hide()
	elif sheet.handle_back():
		pass
	elif _room_view and not _overlay_open:
		EventBus.station_view_requested.emit()
	else:
		return false
	EventBus.sfx.emit(&"click")
	return true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and handle_back():
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		handle_back()


## Height of the top bar as laid out (one or two rows).
func top_bar_height() -> float:
	if top_bar == null or not top_bar.is_inside_tree():
		return TOP_BAR_HEIGHT
	return maxf(top_bar.get_combined_minimum_size().y, TopBar.HEIGHT) + 4.0


## Screen area (UI px) not covered by the top bar and the sheet (portrait;
## landscape keeps the whole screen: the panels sit in its corners).
func free_rect() -> Rect2:
	return _free_rect


## `kind`: &"info" (default), &"success", &"warning" (rim colour and icon).
func show_toast(message: String, kind: StringName = &"info") -> void:
	var style: Array = TOAST_STYLES.get(kind, TOAST_STYLES[&"info"])
	var sb := UITheme.pill(UITheme.GLASS, Color(style[0], 0.7))
	sb.content_margin_left = 18 if style[1] != &"" else 22
	sb.content_margin_right = 22
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	sb.set_border_width_all(2 if kind != &"info" else 1)
	_toast.add_theme_stylebox_override("panel", sb)
	_toast_icon.visible = style[1] != &""
	if _toast_icon.visible:
		_toast_icon.texture = UITheme.icon(style[1])
		_toast_icon.modulate = style[0]
	_toast_label.text = message
	var area := _layer_root.size.x if _layer_root else 1280.0
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_toast_label.custom_minimum_size.x = 0.0
	if _toast_label.get_minimum_size().x > area - 120.0:  # long message on a narrow screen: wrap
		_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_toast_label.custom_minimum_size.x = area - 120.0
	if _toast_tween:
		_toast_tween.kill()
	_toast.reset_size()
	_toast.show()
	var top := top_bar_height()
	_toast.position = Vector2(roundf((_toast.get_parent_area_size().x - _toast.size.x) * 0.5), top)
	_toast.modulate.a = 0.0
	_toast.pivot_offset = _toast.size * 0.5
	_toast.scale = Vector2(0.92, 0.92) if kind == &"success" else Vector2.ONE
	_toast_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.15)
	_toast_tween.parallel().tween_property(_toast, "position:y", top + 12, 0.25)
	_toast_tween.parallel().tween_property(_toast, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK)
	_toast_tween.tween_interval(2.0)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.5)
	_toast_tween.tween_callback(_toast.hide)


func _on_view_pressed() -> void:
	toggle_view()


func _on_room_view_changed(room: bool) -> void:
	_room_view = room
	view_button.text = "Station" if room else "Room"
	view_button.icon = UITheme.icon(&"map" if room else &"room")


## The canvas keeps its text size in both orientations: 1280x720 base in
## landscape, 720x1280 in portrait (otherwise portrait shrinks the UI ~0.56x).
func _fit_content_scale() -> void:
	var win := get_window()
	if win == null or win.content_scale_mode == Window.CONTENT_SCALE_MODE_DISABLED:
		return
	var s := win.size
	var want := UITheme.PORTRAIT_BASE if s.y > s.x else UITheme.LANDSCAPE_BASE
	if win.content_scale_size != want:
		win.content_scale_size = want


func _on_viewport_resized() -> void:
	_apply_safe_area()
	apply_layout(UITheme.is_portrait(get_viewport()))


## Re-anchors everything for the orientation (called on every resize).
func apply_layout(p_portrait: bool) -> void:
	portrait = p_portrait
	top_bar.set_portrait(portrait)
	var screen := get_viewport().get_visible_rect().size
	var top := top_bar_height()
	var usable_h := screen.y - 2.0 * MARGIN
	sheet.apply_layout(portrait, usable_h - top - UITheme.SPACE_M, usable_h)
	build_menu.top_margin = top + 8.0
	build_menu.portrait = portrait
	encounter_panel.position.y = top + (24.0 if portrait else 40.0)
	_place_dock.call_deferred()


func _on_sheet_moved() -> void:
	_place_dock()
	_update_free_rect()


## Landscape: bottom-right. Portrait: right, floating just above the sheet
## (hidden when the sheet is pulled up to the top bar).
func _place_dock() -> void:
	if _layer_root == null:
		return
	_nav_row.reset_size()
	var area := _layer_root.size
	var d := _nav_row.size
	var y := area.y - d.y
	if portrait and sheet.visible:
		y = sheet.position.y - d.y - UITheme.SPACE_M
	_nav_row.position = Vector2(area.x - d.x, y).round()
	_nav_row.visible = not _overlay_open and y >= top_bar_height() + UITheme.SPACE_M


func _update_free_rect() -> void:
	var screen := get_viewport().get_visible_rect().size
	var r := Rect2(Vector2.ZERO, screen)
	if portrait and _overlay_open:  # exploded view: the model on top, its cards below
		r = Rect2(0.0, 70.0, screen.x, screen.y * UpgradeOverlay.PORTRAIT_TOP - 80.0)
	elif portrait:
		var top := top_bar.get_global_rect().end.y if top_bar.visible else 0.0
		var bottom := sheet.get_global_rect().position.y if sheet.visible else screen.y
		if build_menu.visible:  # keep the previewed module above the build sheet
			bottom = minf(bottom, build_menu.get_global_rect().position.y)
		r = Rect2(0.0, top, screen.x, maxf(bottom - top, screen.y * 0.25))
	if not r.is_equal_approx(_free_rect):
		_free_rect = r
		EventBus.hud_insets_changed.emit(r)


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


## Portrait: the build sheet takes the bottom; the module sheet fades away
## under it instead of showing through.
func _update_sheet_cover() -> void:
	var covered := portrait and build_menu.visible
	var tw := sheet.create_tween()
	tw.tween_property(sheet, "modulate:a", 0.0 if covered else 1.0, UITheme.FOLD_TIME)
	_nav_row.modulate.a = 0.0 if covered else 1.0


func _update_scrim() -> void:
	UITheme.fade(_scrim, inventory_panel.visible or encounter_panel.visible)


func _on_need_critical(need: StringName) -> void:
	show_toast(CRITICAL_MESSAGES.get(need, "%s is critical." % need), &"warning")
