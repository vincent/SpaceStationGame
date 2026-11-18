class_name TopBar
extends VBoxContainer
## Top of the HUD: floating glass pills with gaps between them, so the
## station stays visible. Left: clock (and the debug button in debug builds);
## centre: station status chips (StatusBar); right: the castaway's needs as
## compact meters (icon, name, value) with their value. In portrait the chips move to a second
## row under the clock and needs.
## Tapping the needs pill folds it to values only (an icon and a mini bar each).
## Long time skips (sleep, work) roll the clock forward visibly and show how
## much time passed ("+4 h").

const HEIGHT := 56
## A need below this reads as critical (its value turns pink, its bar pulses).
const LOW_NEED := 25.0
## Time skips at least this long (game minutes) animate the clock.
const SKIP_ANIM_MINUTES := 30.0
const SKIP_ANIM_SECONDS := 0.8
const BAR_WIDTH := 92.0
const BAR_WIDTH_COMPACT := 44.0

var status_bar: StatusBar
var bars: Dictionary[StringName, ProgressBar] = {}
var portrait := false
## Needs pill folded to values only.
var needs_compact := false
var _values: Dictionary[StringName, Label] = {}
var _names: Dictionary[StringName, Label] = {}
var _icons: Dictionary[StringName, TextureRect] = {}
var _pulses: Dictionary[StringName, Tween] = {}
var _bar_tweens: Dictionary[StringName, Tween] = {}
var _row: HBoxContainer
var _clock: PanelContainer
var _clock_label: Label
var _skip_badge: Label
var _needs: PanelContainer
var _spacer: Control
var _clock_tween: Tween


func _ready() -> void:
	name = "TopBar"
	add_theme_constant_override("separation", UITheme.SPACE_S)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row = HBoxContainer.new()
	_row.name = "Row"
	_row.add_theme_constant_override("separation", UITheme.SPACE_M)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)

	_clock = _cluster("Clock")
	var clock_row := _clock.get_child(0) as HBoxContainer
	if OS.is_debug_build():
		var dbg := UITheme.ghost_button(&"bug", _toggle_debug)
		dbg.name = "DebugButton"
		clock_row.add_child(dbg)
		(_clock.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_left = 4
	_clock_label = UITheme.title_label("")
	_clock_label.add_theme_font_override("font", UITheme.font(UITheme.FONT_NUMERIC))
	_clock_label.custom_minimum_size.x = 150
	clock_row.add_child(_clock_label)
	_skip_badge = UITheme.label("", true, UITheme.YELLOW)
	_skip_badge.name = "SkipBadge"
	_skip_badge.modulate.a = 0.0
	_skip_badge.hide()
	clock_row.add_child(_skip_badge)

	status_bar = StatusBar.new()
	status_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_row.add_child(status_bar)
	_spacer = Control.new()
	_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spacer.hide()
	_row.add_child(_spacer)

	_needs = _cluster("Needs")
	_needs.mouse_filter = Control.MOUSE_FILTER_STOP
	_needs.gui_input.connect(_on_needs_input)
	_needs.tooltip_text = "Tap to fold"
	var needs_row := _needs.get_child(0) as HBoxContainer
	needs_row.add_theme_constant_override("separation", UITheme.SPACE_L)
	needs_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for need in GameState.needs.names():
		var color: Color = HUD.NEED_COLORS.get(need, UITheme.CYAN)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 3)
		col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 4)
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var need_icon := UITheme.icon_rect(need, color, 16)
		head.add_child(need_icon)
		_icons[need] = need_icon
		var name_label := UITheme.label(String(need).capitalize(), true, UITheme.TEXT_DIM)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(name_label)
		var value := UITheme.number_label("", UITheme.TEXT, true)
		value.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(value)
		col.add_child(head)
		var bar := UITheme.bar(color, 6, Needs.MAX)
		bar.name = "Need_%s" % need
		bar.custom_minimum_size.x = BAR_WIDTH
		col.add_child(bar)
		needs_row.add_child(col)
		bars[need] = bar
		_values[need] = value
		_names[need] = name_label

	GameState.needs.changed.connect(_on_need_changed)
	GameClock.minute_changed.connect(func(_m: int) -> void: refresh_clock())
	GameClock.time_advanced.connect(_on_time_advanced)
	EventBus.game_reset.connect(refresh)
	refresh()


## Glass pill holding an HBox, added to the row.
func _cluster(cluster_name: String) -> PanelContainer:
	var pill := PanelContainer.new()
	pill.name = cluster_name
	pill.custom_minimum_size.y = HEIGHT
	pill.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var sb := UITheme.pill()
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.shadow_color = UITheme.SHADOW
	sb.shadow_size = 6
	pill.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITheme.SPACE_S)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(row)
	_row.add_child(pill)
	return pill


## Portrait: clock and needs on the first row, the status chips on a second.
func set_portrait(value: bool) -> void:
	portrait = value
	if portrait and status_bar.get_parent() == _row:
		_row.remove_child(status_bar)
		add_child(status_bar)
	elif not portrait and status_bar.get_parent() == self:
		remove_child(status_bar)
		_row.add_child(status_bar)
		_row.move_child(status_bar, 1)
	_spacer.visible = portrait
	status_bar.alignment = FlowContainer.ALIGNMENT_BEGIN if portrait else FlowContainer.ALIGNMENT_CENTER


func set_needs_compact(value: bool) -> void:
	needs_compact = value
	for need in bars:
		_names[need].visible = not needs_compact
		bars[need].custom_minimum_size.x = BAR_WIDTH_COMPACT if needs_compact else BAR_WIDTH
	_needs.tooltip_text = "Tap to show names" if needs_compact else "Tap to fold"


func refresh() -> void:
	if _clock_tween:
		_clock_tween.kill()
	refresh_clock()
	for need in bars:
		_on_need_changed(need, GameState.needs.get_value(need))


func refresh_clock() -> void:
	if _clock_tween and _clock_tween.is_running():
		return
	_clock_label.text = GameClock.format_time()


## A long skip rolls the displayed time from where it was to now.
func _on_time_advanced(minutes: float) -> void:
	if minutes < SKIP_ANIM_MINUTES or not is_inside_tree():
		return
	if _clock_tween:
		_clock_tween.kill()
	var to := GameClock.total_minutes
	_clock_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_clock_tween.tween_method(func(m: float) -> void: _clock_label.text = GameClock.format_minutes(m),
		to - minutes, to, SKIP_ANIM_SECONDS)
	_clock_tween.tween_callback(refresh_clock)
	UITheme.pulse(_clock, 1.06, 0.4)
	_skip_badge.text = "+" + GameClock.format_duration(minutes)
	_skip_badge.show()
	_skip_badge.modulate.a = 1.0
	var fade := _skip_badge.create_tween()
	fade.tween_interval(SKIP_ANIM_SECONDS + 1.2)
	fade.tween_property(_skip_badge, "modulate:a", 0.0, 0.5)
	fade.tween_callback(_skip_badge.hide)


func _on_need_changed(need: StringName, value: float) -> void:
	if not bars.has(need):
		return
	var bar := bars[need]
	if _bar_tweens.has(need):
		_bar_tweens[need].kill()
		_bar_tweens.erase(need)
	# Big jumps (eating, sleeping) slide; the slow decay just ticks.
	if absf(bar.value - value) > 3.0 and bar.is_inside_tree():
		var tw := bar.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(bar, "value", value, 0.6)
		_bar_tweens[need] = tw
	else:
		bar.value = value
	_values[need].text = str(roundi(value))
	var low := value < LOW_NEED
	_values[need].add_theme_color_override("font_color", UITheme.DANGER if low else UITheme.TEXT)
	_icons[need].modulate = UITheme.DANGER if low else HUD.NEED_COLORS.get(need, UITheme.CYAN)
	_set_pulse(need, low)


## Critical needs breathe gently until they recover.
func _set_pulse(need: StringName, on: bool) -> void:
	var bar := bars[need]
	if on and not _pulses.has(need) and bar.is_inside_tree():
		var tw := bar.create_tween().set_loops()
		tw.tween_property(bar, "modulate:a", 0.35, 0.6).set_trans(Tween.TRANS_SINE)
		tw.tween_property(bar, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_SINE)
		_pulses[need] = tw
	elif not on and _pulses.has(need):
		_pulses[need].kill()
		_pulses.erase(need)
		bar.modulate.a = 1.0


func _on_needs_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
		accept_event()
		EventBus.sfx.emit(&"click")
		set_needs_compact(not needs_compact)


func _toggle_debug() -> void:
	var overlay := get_tree().get_first_node_in_group(&"debug_overlay") as DebugOverlay
	if overlay:
		overlay.toggle_panel()
