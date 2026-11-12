class_name StatusBar
extends HFlowContainer
## Top-centre station status: one chip per resource that matters (stock > 0
## or a producer exists) showing amount and net rate, plus a power chip.
## Chips appear the first time their resource matters and then stay, so the
## start of the game stays clean. Tapping a chip opens the ProductionPopover.

signal chip_pressed(id: StringName, chip: Control)

## Chip id of the power budget (not an item).
const POWER := &"power"

var chips: Dictionary[StringName, Chip] = {}
var _shown: Dictionary[StringName, bool] = {}


## One tappable chip: colour dot, "Food 37", rate "+0.15/h".
class Chip:
	extends PanelContainer

	signal pressed

	var id: StringName
	var amount_label: Label
	var rate_label: Label

	func _init(p_id: StringName, color: Color) -> void:
		id = p_id
		name = "Chip_%s" % id
		mouse_filter = Control.MOUSE_FILTER_STOP
		var sb := UITheme.box(Color(Palette.NIGHT, 0.85), Color(color, 0.7), 2, 14)
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		sb.content_margin_left = 10
		sb.content_margin_right = 12
		add_theme_stylebox_override("panel", sb)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(row)
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(12, 12)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.add_theme_stylebox_override("panel", UITheme.box(color, Color.TRANSPARENT, 0, 6))
		row.add_child(dot)
		amount_label = UITheme.label("", true, Palette.TEXT)
		amount_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(amount_label)
		rate_label = UITheme.label("", true, Palette.MINT)
		rate_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(rate_label)

	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb and mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			accept_event()
			EventBus.sfx.emit(&"click")
			pressed.emit()

	func set_values(text: String, rate: float) -> void:
		amount_label.text = text
		rate_label.visible = absf(rate) >= 0.005
		rate_label.text = StatusBar.format_rate(rate)
		rate_label.add_theme_color_override("font_color", Palette.MINT if rate > 0.0 else Palette.NEON_PINK)


func _ready() -> void:
	name = "StatusBar"
	alignment = FlowContainer.ALIGNMENT_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("h_separation", 8)
	add_theme_constant_override("v_separation", 6)
	_add_chip(POWER, Palette.NEON_CYAN)
	for item in resources():
		_add_chip(item.id, item.color)
	GameClock.minute_changed.connect(func(_m: int) -> void: refresh())
	GameState.stock.count_changed.connect(func(_id: StringName, _n: int) -> void: refresh())
	GameState.station.module_changed.connect(func(_uid: int, _r: StringName) -> void: refresh())
	GameState.station.module_added.connect(func(_uid: int) -> void: refresh())
	GameState.station.module_removed.connect(func(_uid: int) -> void: refresh())
	GameState.station.reset.connect(refresh)
	EventBus.game_reset.connect(func() -> void:
		_shown.clear()
		refresh())
	refresh()


## Bulk items (station resources), in id order.
static func resources() -> Array[ItemData]:
	var out: Array[ItemData] = []
	for id in GameState.item_db.ids():
		var item := GameState.item_db.get_item(id)
		if item.bulk:
			out.append(item)
	return out


## "+0.15/h", "-1.2/h"
static func format_rate(rate: float) -> String:
	return ("%+.1f/h" if absf(rate) >= 1.0 else "%+.2f/h") % rate


func refresh() -> void:
	var st := GameState.station
	var stock := GameState.stock
	var rates := Production.rates(GameState.station, GameState.stock)
	chips[POWER].set_values("Power %s/%s" % [snappedf(st.power_draw(), 0.1), snappedf(st.power_output(), 0.1)], 0.0)
	for item in resources():
		var id := item.id
		if stock.amount(id) > 0.0 or Production.has_producer(st, id):
			_shown[id] = true
		var chip := chips[id]
		chip.visible = _shown.get(id, false)
		if chip.visible:
			chip.set_values("%s %d" % [item.display_name, stock.count(id)], rates.get(id, 0.0))


func _add_chip(id: StringName, color: Color) -> void:
	var chip := Chip.new(id, color)
	chip.pressed.connect(func() -> void: chip_pressed.emit(id, chip))
	add_child(chip)
	chips[id] = chip
