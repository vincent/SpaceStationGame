class_name HUD
extends CanvasLayer
## In-game overlay: clock, needs bars, inventory button, object menus, toasts.
## Built in code so layout changes stay reviewable in diffs.

const NEED_COLORS: Dictionary[StringName, Color] = {
	Needs.FOOD: Palette.ORANGE,
	Needs.ENERGY: Palette.NEON_CYAN,
	Needs.MORALE: Palette.NEON_PINK,
}
const CRITICAL_MESSAGES: Dictionary[StringName, String] = {
	Needs.FOOD: "You're starving.",
	Needs.ENERGY: "You can barely keep your eyes open.",
	Needs.MORALE: "The silence is getting to you.",
}

var interaction_menu: InteractionMenu
var inventory_panel: InventoryPanel
var _clock_label: Label
var _bars: Dictionary[StringName, ProgressBar] = {}
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
		margin.add_theme_constant_override("margin_" + side, 16)
	root.add_child(margin)

	var layer_root := Control.new()
	layer_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(layer_root)

	# Clock (top-left)
	var clock_panel := PanelContainer.new()
	_clock_label = UITheme.label("", false, Palette.YELLOW)
	clock_panel.add_child(_clock_label)
	layer_root.add_child(clock_panel)

	# Needs (top-right)
	var needs_panel := PanelContainer.new()
	needs_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	needs_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var needs_box := VBoxContainer.new()
	needs_panel.add_child(needs_box)
	for need in GameState.needs.names():
		var row := HBoxContainer.new()
		var name_label := UITheme.label(String(need).capitalize(), true)
		name_label.custom_minimum_size.x = 80
		row.add_child(name_label)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(170, 18)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.show_percentage = false
		bar.max_value = Needs.MAX
		var fill := UITheme.box(NEED_COLORS.get(need, Palette.NEON_CYAN), Color.TRANSPARENT, 0, 4)
		fill.set_content_margin_all(0)
		bar.add_theme_stylebox_override("fill", fill)
		row.add_child(bar)
		needs_box.add_child(row)
		_bars[need] = bar
	layer_root.add_child(needs_panel)

	# Inventory button (bottom-right)
	inventory_panel = InventoryPanel.new()
	inventory_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	inventory_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	inventory_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var bag := UITheme.button("Inventory", inventory_panel.toggle)
	bag.custom_minimum_size = Vector2(160, 64)
	bag.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	bag.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	bag.grow_vertical = Control.GROW_DIRECTION_BEGIN
	layer_root.add_child(bag)

	# Interaction menu (bottom-center)
	interaction_menu = InteractionMenu.new()
	interaction_menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	interaction_menu.grow_horizontal = Control.GROW_DIRECTION_BOTH
	interaction_menu.grow_vertical = Control.GROW_DIRECTION_BEGIN
	layer_root.add_child(interaction_menu)
	layer_root.add_child(inventory_panel)

	# Toast (top-center)
	_toast = UITheme.label("", false, Palette.TEXT)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.position.y = 70
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_color_override("font_outline_color", Palette.NIGHT)
	_toast.add_theme_constant_override("outline_size", 8)
	_toast.modulate.a = 0.0
	layer_root.add_child(_toast)

	GameState.needs.changed.connect(_on_need_changed)
	GameState.needs.became_critical.connect(_on_need_critical)
	GameClock.minute_changed.connect(func(_m: int) -> void: _refresh_clock())
	EventBus.toast.connect(show_toast)
	EventBus.game_reset.connect(_refresh_all)
	_refresh_all()


## Closes floating menus (called when the player taps the world).
func close_menus() -> void:
	interaction_menu.close()
	inventory_panel.hide()


func show_toast(message: String) -> void:
	_toast.text = message
	if _toast_tween:
		_toast_tween.kill()
	_toast.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(2.0)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.6)


func _refresh_all() -> void:
	_refresh_clock()
	for need in _bars:
		_bars[need].value = GameState.needs.get_value(need)


func _refresh_clock() -> void:
	_clock_label.text = GameClock.format_time()


func _on_need_changed(need: StringName, value: float) -> void:
	if _bars.has(need):
		_bars[need].value = value


func _on_need_critical(need: StringName) -> void:
	show_toast(CRITICAL_MESSAGES.get(need, "%s is critical." % need))
