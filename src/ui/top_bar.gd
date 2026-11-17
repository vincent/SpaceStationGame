class_name TopBar
extends HBoxContainer
## Top row of the HUD: floating glass pills with gaps between them, so the
## station stays visible. Left: clock (and the debug button in debug builds);
## centre: station status chips (StatusBar); right: the castaway's needs as
## compact meters with their value.

const HEIGHT := 52
## A need below this reads as critical (its value turns pink).
const LOW_NEED := 25.0

var status_bar: StatusBar
var bars: Dictionary[StringName, ProgressBar] = {}
var _values: Dictionary[StringName, Label] = {}
var _clock_label: Label


func _ready() -> void:
	name = "TopBar"
	add_theme_constant_override("separation", UITheme.SPACE_M)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var clock := _cluster("Clock")
	var clock_row := clock.get_child(0) as HBoxContainer
	if OS.is_debug_build():
		var dbg := UITheme.ghost_button(&"bug", _toggle_debug)
		dbg.name = "DebugButton"
		dbg.custom_minimum_size = Vector2(40, 40)
		clock_row.add_child(dbg)
		(clock.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_left = 4
	_clock_label = UITheme.title_label("")
	_clock_label.custom_minimum_size.x = 150
	clock_row.add_child(_clock_label)

	status_bar = StatusBar.new()
	status_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(status_bar)

	var needs := _cluster("Needs")
	var needs_row := needs.get_child(0) as HBoxContainer
	needs_row.add_theme_constant_override("separation", UITheme.SPACE_L)
	for need in GameState.needs.names():
		var color: Color = HUD.NEED_COLORS.get(need, UITheme.CYAN)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 3)
		col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var head := HBoxContainer.new()
		var name_label := UITheme.label(String(need).capitalize(), true, UITheme.TEXT_DIM)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(name_label)
		var value := UITheme.label("", true, UITheme.TEXT)
		head.add_child(value)
		col.add_child(head)
		var bar := ProgressBar.new()
		bar.name = "Need_%s" % need
		bar.custom_minimum_size = Vector2(92, 6)
		bar.show_percentage = false
		bar.max_value = Needs.MAX
		var fill := UITheme.box(color, Color.TRANSPARENT, 0, 3)
		fill.set_content_margin_all(0)
		bar.add_theme_stylebox_override("fill", fill)
		col.add_child(bar)
		needs_row.add_child(col)
		bars[need] = bar
		_values[need] = value

	GameState.needs.changed.connect(_on_need_changed)
	GameClock.minute_changed.connect(func(_m: int) -> void: refresh_clock())
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
	pill.add_child(row)
	add_child(pill)
	return pill


func refresh() -> void:
	refresh_clock()
	for need in bars:
		_on_need_changed(need, GameState.needs.get_value(need))


func refresh_clock() -> void:
	_clock_label.text = GameClock.format_time()


func _on_need_changed(need: StringName, value: float) -> void:
	if not bars.has(need):
		return
	bars[need].value = value
	_values[need].text = str(roundi(value))
	_values[need].add_theme_color_override("font_color", UITheme.DANGER if value < LOW_NEED else UITheme.TEXT)


func _toggle_debug() -> void:
	var overlay := get_tree().get_first_node_in_group(&"debug_overlay") as DebugOverlay
	if overlay:
		overlay.toggle_panel()
