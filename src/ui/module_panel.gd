class_name ModulePanel
extends PanelContainer
## Bottom-left card of the focused module, in station and room view: state,
## wear and power, with Power / Upgrade tiles (Repair while derelict).
## Modules with jobs get a crew row (− Crew 1/2 +); habitats show their
## bunks. The chevron folds the card to its title.

var module: Module
## Folded to the title by the chevron (kept across modules).
var collapsed := false

var _title: Label
var _fold: Button
var _body: VBoxContainer
var _status: Label
var _tiles: GridContainer
var _repair: Button
var _power: Button
var _upgrade: Button
var _crew_box: PanelContainer
var _crew_label: Label
var _crew_add: Button
var _crew_remove: Button
var _overlay_open := false


func _ready() -> void:
	name = "ModulePanel"
	custom_minimum_size = Vector2(360, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)

	var header := HBoxContainer.new()
	box.add_child(header)
	_title = UITheme.label("", false, Palette.YELLOW)
	_title.add_theme_font_size_override("font_size", 26)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	_fold = UITheme.icon_button("", &"chevron_left", toggle_collapsed)
	_fold.name = "Fold"
	_fold.flat = true
	_fold.custom_minimum_size = Vector2(44, 44)
	header.add_child(_fold)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 10)
	box.add_child(_body)
	_status = UITheme.label("", true, Palette.TEXT_DIM)
	_body.add_child(_status)

	_repair = UITheme.action_button("Repair", "", _on_repair)
	_repair.name = "Repair"
	_body.add_child(_repair)
	_tiles = GridContainer.new()
	_tiles.columns = 2
	_tiles.add_theme_constant_override("h_separation", 10)
	_body.add_child(_tiles)
	_power = UITheme.icon_button("Power", &"power_toggle", _on_power, true)
	_power.name = "Power"
	_upgrade = UITheme.icon_button("Upgrade", &"upgrade",
		func() -> void: EventBus.upgrade_view_requested.emit(module), true)
	_upgrade.name = "Upgrade"
	for b in [_power, _upgrade]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", UITheme.SMALL_FONT_SIZE + 2)
		_tiles.add_child(b)

	_crew_box = PanelContainer.new()
	var crew_sb := UITheme.box(Color(Palette.DEEP_BLUE, 0.6), Palette.VIOLET, 2, 10)
	crew_sb.set_content_margin_all(6)
	_crew_box.add_theme_stylebox_override("panel", crew_sb)
	_body.add_child(_crew_box)
	var crew_row := HBoxContainer.new()
	crew_row.add_theme_constant_override("separation", 6)
	_crew_box.add_child(crew_row)
	_crew_remove = UITheme.icon_button("", &"minus", func() -> void: GameState.station.crew.unstaff(module.uid))
	_crew_remove.name = "CrewRemove"
	_crew_label = UITheme.label("", false, Palette.TEXT)
	_crew_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_crew_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_crew_add = UITheme.icon_button("", &"plus", _on_staff)
	_crew_add.name = "CrewAdd"
	for b in [_crew_remove, _crew_add]:
		b.custom_minimum_size = Vector2(UITheme.TOUCH_SIZE, 48)
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crew_row.add_child(_crew_remove)
	crew_row.add_child(_crew_label)
	crew_row.add_child(_crew_add)

	EventBus.module_focused.connect(func(m: Module) -> void:
		module = m
		refresh())
	EventBus.upgrade_view_requested.connect(func(_m: Module) -> void:
		_overlay_open = true
		hide())
	EventBus.upgrade_view_closed.connect(func() -> void:
		_overlay_open = false
		refresh())
	GameState.station.module_changed.connect(func(_uid: int, _r: StringName) -> void: refresh())
	GameState.inventory.changed.connect(refresh)
	GameState.station.crew.changed.connect(refresh)
	GameState.stock.count_changed.connect(func(_id: StringName, _n: int) -> void: refresh())
	refresh()


func toggle_collapsed() -> void:
	collapsed = not collapsed
	refresh()


func refresh() -> void:
	visible = not _overlay_open and module != null and is_instance_valid(module) and module.uid != 0 \
		and GameState.station.has_module(module.uid)
	if not visible:
		return
	_body.visible = not collapsed
	_fold.icon = UITheme.icon(&"chevron_right" if collapsed else &"chevron_left")
	var st := GameState.station
	var rec := st.get_record(module.uid)
	var def := module.def
	_title.text = def.display_name
	if collapsed:
		return
	var state_name: String = ["Derelict", "Repaired", "Upgraded ×%d" % st.level(module.uid)][rec.state]
	var power := ""
	if st.module_output(module.uid) > 0.0:
		power = "makes %s power" % snappedf(st.module_output(module.uid), 0.1)
	elif st.module_draw(module.uid) > 0.0:
		power = "draws %s" % snappedf(st.module_draw(module.uid), 0.1)
	_status.text = "%s · wear %d%%%s" % [state_name, roundi(rec.wear * 100.0), (" · " + power) if power else ""]
	var crew := st.crew
	if crew.beds(module.uid) > 0:
		_status.text += "\nBunks %d/%d" % [crew.residents(module.uid).size(), crew.beds(module.uid)]
	var jobs := crew.jobs(module.uid)
	_crew_box.visible = jobs > 0
	if jobs > 0:
		var staffed := crew.workers(module.uid).size()
		_crew_label.text = "Crew %d/%d · +%d%%" % [staffed, jobs, roundi((crew.staffing(module.uid) - 1.0) * 100.0)]
		_crew_remove.disabled = staffed == 0
		_crew_add.disabled = staffed >= jobs or crew.idle().is_empty()

	var derelict: bool = rec.state == StationState.State.DERELICT
	_repair.visible = derelict
	if derelict:
		var err := GameState.repair_error(module.uid)
		UITheme.set_action_text(_repair, "Repair", err if err != "" else GameState.format_cost(def.repair_cost))
		_repair.disabled = err != ""
	_power.visible = not derelict and st.module_draw(module.uid) > 0.0
	_power.text = "Power off" if rec.powered else "Power on"
	_power.disabled = not rec.powered and st.power_error(module.uid) != ""
	var upgrades := GameState.module_db.upgrades_for(def.id)
	_upgrade.visible = not derelict and not upgrades.is_empty()
	var all_installed := upgrades.all(func(u: UpgradeDef) -> bool: return st.installed(module.uid).has(u.id))
	_upgrade.text = "Upgraded" if all_installed else "Upgrade"
	_upgrade.disabled = all_installed
	_tiles.visible = _power.visible or _upgrade.visible
	# A lone tile spans the row instead of leaving a hole.
	_tiles.columns = 2 if _power.visible and _upgrade.visible else 1


func _on_repair() -> void:
	GameState.repair_module(module.uid)


func _on_staff() -> void:
	var err := GameState.station.crew.staff(module.uid)
	if err != "":
		EventBus.toast.emit(err)


func _on_power() -> void:
	GameState.toggle_power(module.uid)
