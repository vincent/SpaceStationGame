class_name StatusBar
extends HFlowContainer
## Station status in the top bar: one chip per resource that matters (stock > 0
## or a producer exists) showing its icon and amount, plus power and crew chips.
## Net rates live in the popover.
## Chips appear the first time their resource matters and then stay, so the
## start of the game stays clean. Tapping a chip opens the ProductionPopover.

signal chip_pressed(id: StringName, chip: Control)

## Chip id of the power budget (not an item).
const POWER := &"power"
## Chip id of the crew (members / bunks), shown once there are bunks.
const CREW := &"crew"

var chips: Dictionary[StringName, Chip] = {}
var _shown: Dictionary[StringName, bool] = {}


## One tappable chip: icon (or colour dot) and amount, "⚡ 1.0/6".
class Chip:
	extends PanelContainer

	signal pressed

	var id: StringName
	var amount_label: Label
	## Net rate per hour, kept for tests and tinting (not displayed).
	var rate: float = 0.0

	func _init(p_id: StringName, color: Color, icon_name: StringName = &"") -> void:
		id = p_id
		name = "Chip_%s" % id
		mouse_filter = Control.MOUSE_FILTER_STOP
		var sb := UITheme.box(Color(Palette.DEEP_BLUE, 0.85), Color.TRANSPARENT, 0, 18)
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		sb.content_margin_left = 12
		sb.content_margin_right = 14
		add_theme_stylebox_override("panel", sb)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(row)
		if UITheme.icon(icon_name):
			row.add_child(UITheme.icon_rect(icon_name, color, 22))
		else:
			var dot := Panel.new()
			dot.custom_minimum_size = Vector2(12, 12)
			dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			dot.add_theme_stylebox_override("panel", UITheme.box(color, Color.TRANSPARENT, 0, 6))
			row.add_child(dot)
		amount_label = UITheme.label("", false, Palette.TEXT)
		amount_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(amount_label)

	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb and mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			accept_event()
			EventBus.sfx.emit(&"click")
			pressed.emit()

	func set_values(text: String, p_rate: float) -> void:
		amount_label.text = text
		rate = p_rate
		# A draining resource reads pink; the popover tells by how much.
		amount_label.add_theme_color_override("font_color", Palette.NEON_PINK if rate <= -0.005 else Palette.TEXT)


func _ready() -> void:
	name = "StatusBar"
	alignment = FlowContainer.ALIGNMENT_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("h_separation", 8)
	add_theme_constant_override("v_separation", 6)
	_add_chip(POWER, Palette.NEON_CYAN, &"power")
	_add_chip(CREW, Palette.TEXT_DIM, &"crew")
	for item in resources():
		_add_chip(item.id, item.color, item.id)
	GameClock.minute_changed.connect(func(_m: int) -> void: refresh())
	GameState.stock.count_changed.connect(func(_id: StringName, _n: int) -> void: refresh())
	GameState.station.module_changed.connect(func(_uid: int, _r: StringName) -> void: refresh())
	GameState.station.module_added.connect(func(_uid: int) -> void: refresh())
	GameState.station.module_removed.connect(func(_uid: int) -> void: refresh())
	GameState.station.reset.connect(refresh)
	GameState.station.crew.changed.connect(refresh)
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
	chips[POWER].set_values("%s/%s" % [snappedf(st.power_draw(), 0.1), snappedf(st.power_output(), 0.1)], 0.0)
	chips[CREW].visible = st.crew.capacity() > 0 or st.crew.size() > 0
	chips[CREW].set_values("%d/%d" % [st.crew.size(), st.crew.capacity()], 0.0)
	for item in resources():
		var id := item.id
		if stock.amount(id) > 0.0 or Production.has_producer(st, id):
			_shown[id] = true
		var chip := chips[id]
		chip.visible = _shown.get(id, false)
		if chip.visible:
			chip.set_values(str(stock.count(id)), rates.get(id, 0.0))


func _add_chip(id: StringName, color: Color, icon_name: StringName) -> void:
	var chip := Chip.new(id, color, icon_name)
	chip.pressed.connect(func() -> void: chip_pressed.emit(id, chip))
	add_child(chip)
	chips[id] = chip
