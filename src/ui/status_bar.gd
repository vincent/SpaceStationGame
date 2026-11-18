class_name StatusBar
extends HFlowContainer
## Station status in the top bar: one chip per resource that matters (stock > 0
## or a producer exists) showing its icon, amount and a small trend chevron
## (mint up = filling, pink down = draining), plus power and crew chips.
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
	var trend: TextureRect
	## Net rate per hour, kept for tests and tinting (not displayed).
	var rate: float = 0.0
	## Progress (0..1) towards the next whole unit, < 0 = no strip.
	var progress: float = -1.0
	var _color: Color

	func _init(p_id: StringName, color: Color, icon_name: StringName = &"") -> void:
		id = p_id
		_color = color
		name = "Chip_%s" % id
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size.y = TopBar.HEIGHT
		set_active(false)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(row)
		if UITheme.icon(icon_name):
			row.add_child(UITheme.icon_rect(icon_name, color, 22))
		else:
			row.add_child(UITheme.dot(color, 12))
		amount_label = UITheme.number_label("", UITheme.TEXT)
		amount_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		amount_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(amount_label)
		trend = UITheme.icon_rect(&"chevron_up", UITheme.SUCCESS, 14)
		trend.name = "Trend"
		trend.hide()
		row.add_child(trend)

	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb and mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			accept_event()
			EventBus.sfx.emit(&"click")
			pressed.emit()

	## Cyan rim while its popover is open.
	func set_active(active: bool) -> void:
		var sb := UITheme.pill(UITheme.GLASS, UITheme.CYAN if active else UITheme.GLASS_RIM)
		sb.content_margin_left = 14
		sb.content_margin_right = 16
		sb.shadow_color = UITheme.SHADOW
		sb.shadow_size = 6
		if active:
			sb.set_border_width_all(2)
		add_theme_stylebox_override("panel", sb)

	## Thin strip along the bottom of the pill: how close the next unit is.
	func set_progress(value: float) -> void:
		if not is_equal_approx(value, progress):
			progress = value
			queue_redraw()

	func _draw() -> void:
		if progress < 0.0:
			return
		var x0 := 16.0
		var x1 := size.x - 16.0
		var y := size.y - 7.0
		draw_line(Vector2(x0, y), Vector2(x1, y), Color(1, 1, 1, 0.08), 3.0, true)
		if progress > 0.0:
			draw_line(Vector2(x0, y), Vector2(lerpf(x0, x1, clampf(progress, 0.0, 1.0)), y),
				Color(_color, 0.9), 3.0, true)

	## "Something arrived": the chip bounces and its amount flashes.
	func bump() -> void:
		UITheme.pulse(self, 1.15, 0.35)
		UITheme.flash(amount_label, UITheme.SUCCESS, 0.6)

	func set_values(text: String, p_rate: float) -> void:
		amount_label.text = text
		rate = p_rate
		# A draining resource reads pink; the popover tells by how much.
		var draining := rate <= -0.005
		amount_label.add_theme_color_override("font_color", UITheme.DANGER if draining else UITheme.TEXT)
		trend.visible = draining or rate >= 0.005
		if trend.visible:
			trend.texture = UITheme.icon(&"chevron_down" if draining else &"chevron_up")
			trend.modulate = UITheme.DANGER if draining else UITheme.SUCCESS


func _ready() -> void:
	name = "StatusBar"
	alignment = FlowContainer.ALIGNMENT_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("h_separation", UITheme.SPACE_S)
	add_theme_constant_override("v_separation", 6)
	_add_chip(POWER, UITheme.YELLOW, &"power")
	_add_chip(CREW, UITheme.TEXT_DIM, &"crew")
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
			var rate: float = rates.get(id, 0.0)
			chip.set_values(str(stock.count(id)), rate)
			chip.set_progress(stock.amount(id) - floorf(stock.amount(id) + 0.0001) if rate > 0.005 else -1.0)


## Highlights the chip `id` (the popover's), none for &"".
func set_active(id: StringName) -> void:
	for key in chips:
		chips[key].set_active(key == id)


func _add_chip(id: StringName, color: Color, icon_name: StringName) -> void:
	var chip := Chip.new(id, color, icon_name)
	chip.pressed.connect(func() -> void: chip_pressed.emit(id, chip))
	add_child(chip)
	chips[id] = chip
