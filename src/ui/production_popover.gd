class_name ProductionPopover
extends PanelContainer
## Opens under a StatusBar chip: which modules produce / use that resource
## (or power, or who the crew are and where they work), with their rate and status. Rows that aren't running are
## dimmed and say why ("Unpowered", "Needs water", "Upgrade: Hydroponics").
## Tapping a row focuses the module. Under the title, a timer: when the next
## unit arrives ("Next unit in 23 min") or when the stock runs out.

## The resource shown changed (&"" = closed); the status bar lights its chip.
signal resource_changed(id: StringName)

const WIDTH := 400.0
const STATUS_TEXT: Dictionary[int, String] = {
	Production.Status.UNPOWERED: "Unpowered",
	Production.Status.DERELICT: "Derelict — repair it",
}

## Resource (or StatusBar.POWER) shown, &"" when closed.
var resource: StringName = &""

var _title: Label
var _eta_row: HBoxContainer
var _eta: Label
var _list: VBoxContainer
var _anchor: Control


func _ready() -> void:
	name = "ProductionPopover"
	hide()
	custom_minimum_size = Vector2(WIDTH, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := UITheme.sheet()
	sb.set_content_margin_all(UITheme.SPACE_M + 2)
	sb.content_margin_left = UITheme.SPACE_L
	add_theme_stylebox_override("panel", sb)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UITheme.SPACE_S)
	add_child(vbox)
	_title = UITheme.title_label("")
	vbox.add_child(UITheme.sheet_header(_title, close))
	_eta_row = HBoxContainer.new()
	_eta_row.name = "Timer"
	_eta_row.add_theme_constant_override("separation", UITheme.SPACE_S)
	vbox.add_child(_eta_row)
	_eta_row.add_child(UITheme.icon_rect(&"clock", UITheme.YELLOW, 20))
	_eta = UITheme.label("", false, UITheme.TEXT)
	_eta_row.add_child(_eta)
	GameClock.minute_changed.connect(func(_m: int) -> void:
		if visible:
			refresh_timer())
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	vbox.add_child(_list)
	GameState.station.module_changed.connect(func(_uid: int, _r: StringName) -> void: _refresh_if_open())
	GameState.stock.count_changed.connect(func(_id: StringName, _n: int) -> void: _refresh_if_open())
	GameState.station.crew.changed.connect(_refresh_if_open)
	EventBus.game_reset.connect(close)


## Opens for `id` under `anchor`; the same chip again closes it.
func toggle(id: StringName, anchor: Control = null) -> void:
	if visible and id == resource:
		close()
		return
	resource = id
	_anchor = anchor
	custom_minimum_size.x = minf(WIDTH, get_viewport_rect().size.x - 16.0)
	refresh()
	UITheme.fade(self, true)
	_place.call_deferred()
	resource_changed.emit(id)


func close() -> void:
	hide()
	if resource != &"":
		resource = &""
		resource_changed.emit(&"")


func refresh() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var rows: Array[Dictionary]
	match resource:
		StatusBar.POWER:
			rows = power_rows()
		StatusBar.CREW:
			rows = crew_rows()
		_:
			rows = resource_rows(resource)
	if resource == StatusBar.CREW:
		var crew := GameState.station.crew
		_title.text = "Crew %d · %d bunks" % [crew.size(), crew.capacity()]
	elif resource == StatusBar.POWER:
		var st := GameState.station
		_title.text = "Power %s / %s" % [snappedf(st.power_draw(), 0.1), snappedf(st.power_output(), 0.1)]
	else:
		var item := GameState.item_db.get_item(resource)
		_title.text = "%s · %d in stock" % [item.display_name if item else String(resource), GameState.count(resource)]
	var section := ""
	for row in rows:
		if row.section != section:
			section = row.section
			var head := UITheme.label(section.to_upper(), true, UITheme.TEXT_DIM)
			head.add_theme_font_size_override("font_size", UITheme.MIN_FONT_SIZE)
			_list.add_child(head)
		_list.add_child(_make_row(row))
	refresh_timer()
	if rows.is_empty():
		_list.add_child(UITheme.label("No crew yet: traders bring drifters looking for a bunk."
			if resource == StatusBar.CREW else "Nothing makes or uses it yet.", true, UITheme.TEXT_DIM))


## The timer line of a resource: "Next unit in 23 min", "Runs out in 5 h",
## or "" (power, crew, nothing changing).
static func timer_text(id: StringName) -> String:
	if id == StatusBar.POWER or id == StatusBar.CREW or id == &"":
		return ""
	var rate: float = Production.rates(GameState.station, GameState.stock).get(id, 0.0)
	var amount := GameState.stock.amount(id)
	var eta := Production.eta_minutes(amount, rate)
	if eta == INF or absf(rate) < 0.005:
		return ""
	if rate > 0.0:
		return "Next unit in %s" % GameClock.format_duration(eta)
	return "Runs out in %s" % GameClock.format_duration(eta)


func refresh_timer() -> void:
	var text := timer_text(resource)
	_eta_row.visible = text != ""
	_eta.text = text
	_eta.add_theme_color_override("font_color", UITheme.DANGER if text.begins_with("Runs") else UITheme.TEXT)


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


## Rows for the crew chip: each member, their job (or home) and their
## lowest need when it's low. Tapping focuses where they work.
static func crew_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var st := GameState.station
	for m in st.crew.members:
		var where := "Off duty"
		var uid := m.home_uid
		if m.has_job():
			where = "Works at %s" % st.get_def(m.job_uid).display_name
			uid = m.job_uid
		var low := ""
		for need in m.needs.names():
			if m.needs.get_value(need) < 30.0:
				low = " · low %s" % need
		out.append({
			"section": "Working" if m.has_job() else "Idle", "uid": uid, "running": m.has_job(),
			"text": "%s · %s · %s%s" % [m.display_name, where, m.activity, low],
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.running and not b.running)
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


## A tappable row: status light (mint running, pink stopped) and the text.
func _make_row(row: Dictionary) -> Button:
	var b := UITheme.button(row.text, _focus.bind(int(row.uid)), UITheme.LIST_ROW)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size.y = 48
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.add_theme_font_size_override("font_size", UITheme.SMALL_FONT_SIZE)
	var light := UITheme.dot(UITheme.SUCCESS if row.running else UITheme.DANGER, 8)
	light.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	light.position.x = 14
	b.add_child(light)
	if not row.running:
		b.add_theme_color_override("font_color", UITheme.TEXT_DIM)
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
