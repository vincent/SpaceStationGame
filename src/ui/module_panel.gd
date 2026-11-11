class_name ModulePanel
extends PanelContainer
## Bottom-left card for the focused module in room view: state, wear and
## power, with Repair / Power / Upgrade actions and a way back out to the
## station view.

var module: Module

var _title: Label
var _status: Label
var _repair: Button
var _power: Button
var _upgrade: Button
var _room_view := false


func _ready() -> void:
	custom_minimum_size = Vector2(330, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	_title = UITheme.label("", false, Palette.YELLOW)
	box.add_child(_title)
	_status = UITheme.label("", true, Palette.TEXT_DIM)
	box.add_child(_status)
	var row := HFlowContainer.new()
	box.add_child(row)
	_repair = UITheme.button("Repair", _on_repair)
	_power = UITheme.button("Power", _on_power)
	_upgrade = UITheme.button("Upgrade", func() -> void: EventBus.upgrade_view_requested.emit(module))
	for b in [_repair, _power, _upgrade]:
		b.add_theme_font_size_override("font_size", UITheme.SMALL_FONT_SIZE)
		row.add_child(b)
	var out := UITheme.button("Station view", func() -> void: EventBus.station_view_requested.emit())
	out.add_theme_font_size_override("font_size", UITheme.SMALL_FONT_SIZE)
	row.add_child(out)
	EventBus.module_focused.connect(func(m: Module) -> void:
		module = m
		refresh())
	EventBus.view_changed.connect(func(t: float) -> void:
		var room := t >= 0.6
		if room != _room_view:
			_room_view = room
			refresh())
	EventBus.upgrade_view_requested.connect(func(_m: Module) -> void: hide())
	EventBus.upgrade_view_closed.connect(refresh)
	GameState.station.module_changed.connect(func(_uid: int, _r: StringName) -> void: refresh())
	GameState.inventory.changed.connect(refresh)
	refresh()


func refresh() -> void:
	visible = _room_view and module != null and is_instance_valid(module) and module.uid != 0 \
		and GameState.station.has_module(module.uid)
	if not visible:
		return
	var st := GameState.station
	var rec := st.get_record(module.uid)
	var def := module.def
	_title.text = def.display_name
	var state_name: String = ["Derelict", "Repaired", "Upgraded ×%d" % st.level(module.uid)][rec.state]
	var power := ""
	if st.module_output(module.uid) > 0.0:
		power = "makes %s power" % snappedf(st.module_output(module.uid), 0.1)
	elif st.module_draw(module.uid) > 0.0:
		power = "%s · draws %s" % ["on" if rec.powered else "off", snappedf(st.module_draw(module.uid), 0.1)]
	_status.text = "%s · wear %d%%%s" % [state_name, roundi(rec.wear * 100.0), (" · " + power) if power else ""]

	var derelict: bool = rec.state == StationState.State.DERELICT
	_repair.visible = derelict
	if derelict:
		var err := GameState.repair_error(module.uid)
		_repair.text = "Repair · %s" % GameState.format_cost(def.repair_cost)
		_repair.disabled = err != ""
	_power.visible = not derelict and st.module_draw(module.uid) > 0.0
	_power.text = "Power off" if rec.powered else "Power on"
	_power.disabled = not rec.powered and st.power_error(module.uid) != ""
	_upgrade.visible = not derelict and not GameState.module_db.upgrades_for(def.id).is_empty()


func _on_repair() -> void:
	GameState.repair_module(module.uid)


func _on_power() -> void:
	GameState.toggle_power(module.uid)
