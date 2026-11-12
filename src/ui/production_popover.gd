class_name ProductionPopover
extends PanelContainer
## Opens under a StatusBar chip: which modules produce / use that resource
## (or power), with their rate and status. Rows that aren't running are
## dimmed and say why ("Unpowered", "Needs water", "Upgrade: Hydroponics").
## Tapping a row focuses the module.

const WIDTH := 380.0
const STATUS_TEXT: Dictionary[int, String] = {
	Production.Status.UNPOWERED: "Unpowered",
	Production.Status.DERELICT: "Derelict — repair it",
}

## Resource (or StatusBar.POWER) shown, &"" when closed.
var resource: StringName = &""

var _title: Label
var _list: VBoxContainer
var _anchor: Control


func _ready() -> void:
	name = "ProductionPopover"
	hide()
	custom_minimum_size = Vector2(WIDTH, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)
	_title = UITheme.label("", false, Palette.YELLOW)
	vbox.add_child(_title)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	vbox.add_child(_list)
	GameState.station.module_changed.connect(func(_uid: int, _r: StringName) -> void: _refresh_if_open())
	GameState.stock.count_changed.connect(func(_id: StringName, _n: int) -> void: _refresh_if_open())
	EventBus.game_reset.connect(close)


## Opens for `id` under `anchor`; the same chip again closes it.
func toggle(id: StringName, anchor: Control = null) -> void:
	if visible and id == resource:
		close()
		return
	resource = id
	_anchor = anchor
	refresh()
	show()
	_place.call_deferred()


func close() -> void:
	hide()
	resource = &""


func refresh() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var rows := power_rows() if resource == StatusBar.POWER else resource_rows(resource)
	if resource == StatusBar.POWER:
		var st := GameState.station
		_title.text = "Power %s / %s" % [snappedf(st.power_draw(), 0.1), snappedf(st.power_output(), 0.1)]
	else:
		var item := GameState.item_db.get_item(resource)
		_title.text = "%s · %d in stock" % [item.display_name if item else String(resource), GameState.count(resource)]
	var section := ""
	for row in rows:
		if row.section != section:
			section = row.section
			_list.add_child(UITheme.label(section, true, Palette.TEXT_DIM))
		_list.add_child(_make_row(row))
	if rows.is_empty():
		_list.add_child(UITheme.label("Nothing makes or uses it yet.", true, Palette.TEXT_DIM))


## Rows {section, uid, text, running} for a resource (see Production.rows_for).
static func resource_rows(id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var st := GameState.station
	for r in Production.rows_for(st, GameState.stock, id):
		var module_name := st.get_def(r.uid).display_name
		var status: int = r.status
		var nominal: float = r.nominal
		var text := ""
		match status:
			Production.Status.RUNNING:
				text = StatusBar.format_rate(r.rate)
			Production.Status.STARVED:
				var missing := GameState.item_db.get_item(r.missing)
				text = "%s · Needs %s" % [StatusBar.format_rate(r.rate),
					missing.display_name.to_lower() if missing else "inputs"]
			Production.Status.LOCKED:
				text = "Upgrade: %s (%s)" % [GameState.module_db.get_upgrade(r.upgrade_id).display_name,
					StatusBar.format_rate(nominal)]
			_:
				text = "%s (%s)" % [STATUS_TEXT[status], StatusBar.format_rate(nominal)]
		out.append({
			"section": "Producers" if nominal > 0.0 else "Consumers", "uid": r.uid,
			"text": "%s · %s" % [module_name, text], "running": status == Production.Status.RUNNING,
		})
	return out


## Rows for the power chip: generators, then modules drawing power.
static func power_rows() -> Array[Dictionary]:
	var producers: Array[Dictionary] = []
	var consumers: Array[Dictionary] = []
	var st := GameState.station
	for uid in st.uids():
		var def := st.get_def(uid)
		var rec := st.get_record(uid)
		var derelict: bool = rec.state == StationState.State.DERELICT
		if def.power_output > 0.0 or st.module_output(uid) > 0.0:
			producers.append({
				"section": "Producers", "uid": uid, "running": not derelict,
				"text": "%s · %s" % [def.display_name, STATUS_TEXT[Production.Status.DERELICT] if derelict
					else "+%s" % snappedf(st.module_output(uid), 0.1)],
			})
		if st.module_draw(uid) > 0.0:
			var status := Production.power_status(st, uid)
			consumers.append({
				"section": "Consumers", "uid": uid, "running": status == Production.Status.RUNNING,
				"text": "%s · %s" % [def.display_name, "-%s" % snappedf(st.module_draw(uid), 0.1)
					if status == Production.Status.RUNNING
					else "%s (-%s)" % [STATUS_TEXT[status], snappedf(st.module_draw(uid), 0.1)]],
			})
	return producers + consumers


func _make_row(row: Dictionary) -> Button:
	var b := UITheme.button(row.text, _focus.bind(int(row.uid)))
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size.y = UITheme.TOUCH_SIZE * 0.75
	b.add_theme_font_size_override("font_size", UITheme.SMALL_FONT_SIZE)
	if not row.running:
		b.add_theme_color_override("font_color", Palette.TEXT_DIM)
		b.modulate.a = 0.7
	return b


func _focus(uid: int) -> void:
	close()
	for node in get_tree().get_nodes_in_group(&"station_module"):
		var module := node as Module
		if module and module.uid == uid:
			EventBus.module_focus_requested.emit(module)
			return


func _refresh_if_open() -> void:
	if visible:
		refresh()


## Under the anchor chip, kept inside the screen.
func _place() -> void:
	reset_size()
	var screen := get_viewport_rect().size
	var pos := Vector2(screen.x * 0.5 - size.x * 0.5, 80.0)
	if _anchor and is_instance_valid(_anchor):
		var r := _anchor.get_global_rect()
		pos = Vector2(r.position.x + r.size.x * 0.5 - size.x * 0.5, r.end.y + 8.0)
	pos.x = clampf(pos.x, 8.0, maxf(8.0, screen.x - size.x - 8.0))
	global_position = pos
