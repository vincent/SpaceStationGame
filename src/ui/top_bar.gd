class_name TopBar
extends HBoxContainer
## Full-width strip at the top of the HUD: a card with the clock, station status
## chips (StatusBar) and the castaway's needs; in debug builds the debug button
## sits outside the card, at the far left.

var status_bar: StatusBar
var bars: Dictionary[StringName, ProgressBar] = {}
var _clock_label: Label


func _ready() -> void:
	name = "TopBar"
	add_theme_constant_override("separation", 12)
	var card := PanelContainer.new()
	card.name = "Card"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(card)
	var sb := UITheme.card()
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	card.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	card.add_child(row)

	_clock_label = UITheme.label("", false, Palette.YELLOW)
	_clock_label.custom_minimum_size.x = 170
	_clock_label.add_theme_font_size_override("font_size", 26)
	row.add_child(_clock_label)

	status_bar = StatusBar.new()
	status_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(status_bar)

	var needs := HBoxContainer.new()
	needs.add_theme_constant_override("separation", 12)
	needs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(needs)
	for need in GameState.needs.names():
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		col.add_child(UITheme.label(String(need).capitalize(), true, Palette.TEXT_DIM))
		var bar := ProgressBar.new()
		bar.name = "Need_%s" % need
		bar.custom_minimum_size = Vector2(100, 8)
		bar.show_percentage = false
		bar.max_value = Needs.MAX
		var fill := UITheme.box(HUD.NEED_COLORS.get(need, Palette.NEON_CYAN), Color.TRANSPARENT, 0, 4)
		fill.set_content_margin_all(0)
		bar.add_theme_stylebox_override("fill", fill)
		col.add_child(bar)
		needs.add_child(col)
		bars[need] = bar

	if OS.is_debug_build():
		var dbg := UITheme.icon_button("", &"bug", _toggle_debug)
		dbg.name = "DebugButton"
		dbg.custom_minimum_size = Vector2(UITheme.TOUCH_SIZE, UITheme.TOUCH_SIZE)
		dbg.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dbg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		add_child(dbg)
		move_child(dbg, 0)

	GameState.needs.changed.connect(_on_need_changed)
	GameClock.minute_changed.connect(func(_m: int) -> void: refresh_clock())
	EventBus.game_reset.connect(refresh)
	refresh()


func refresh() -> void:
	refresh_clock()
	for need in bars:
		bars[need].value = GameState.needs.get_value(need)


func refresh_clock() -> void:
	_clock_label.text = GameClock.format_time()


func _on_need_changed(need: StringName, value: float) -> void:
	if bars.has(need):
		bars[need].value = value


func _toggle_debug() -> void:
	var overlay := get_tree().get_first_node_in_group(&"debug_overlay") as DebugOverlay
	if overlay:
		overlay.toggle_panel()
