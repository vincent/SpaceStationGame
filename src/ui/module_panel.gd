class_name ModulePanel
extends PanelContainer
## Bottom-left card of the focused module, in station and room view. Header:
## state light (pink derelict, cyan repaired, yellow upgraded), name, fold
## chevron. Body: one status line (state, wear, power, bunks), a row of
## compact actions (Repair while derelict, else Power / Upgrade) and, for
## modules with jobs, an inline crew stepper (− Crew 1/2 · +25% +).
## Folded, the card shrinks to its header (a pill).

const WIDTH := 330.0

var module: Module
## Folded to the title by the chevron (kept across modules).
var collapsed := false

var _dot: Panel
var _title: Label
var _fold: Button
var _body: VBoxContainer
var _status: Label
var _tiles: HBoxContainer
var _repair: Button
var _power: Button
var _upgrade: Button
var _crew_box: HBoxContainer
var _crew_label: Label
var _crew_add: Button
var _crew_remove: Button
var _overlay_open := false


func _ready() -> void:
	name = "ModulePanel"
	custom_minimum_size = Vector2(WIDTH, 0)
	add_theme_stylebox_override("panel", UITheme.card(true))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UITheme.SPACE_M)
	add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", UITheme.SPACE_M)
	header.mouse_filter = Control.MOUSE_FILTER_STOP
	header.gui_input.connect(_on_header_input)
	box.add_child(header)
	_dot = UITheme.dot(UITheme.CYAN, 10)
	header.add_child(_dot)
	_title = UITheme.title_label("")
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(_title)
	_fold = UITheme.ghost_button(&"chevron_down", toggle_collapsed)
	_fold.name = "Fold"
	header.add_child(_fold)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", UITheme.SPACE_M)
	box.add_child(_body)
	_status = UITheme.label("", true, UITheme.TEXT_DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(_status)

	_repair = UITheme.action_button("Repair", "", _on_repair, UITheme.PRIMARY)
	_repair.name = "Repair"
	_body.add_child(_repair)
	_tiles = HBoxContainer.new()
	_tiles.add_theme_constant_override("separation", UITheme.SPACE_M)
	_body.add_child(_tiles)
	_power = UITheme.icon_button("Power", &"power_toggle", _on_power)
	_power.name = "Power"
	_upgrade = UITheme.icon_button("Upgrade", &"upgrade",
		func() -> void: EventBus.upgrade_view_requested.emit(module), false, UITheme.PRIMARY)
	_upgrade.name = "Upgrade"
	for b in [_power, _upgrade]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_tiles.add_child(b)

	# Inline stepper: − Crew 1/2 · +25% +
	_crew_box = HBoxContainer.new()
	_crew_box.name = "Crew"
	_crew_box.add_theme_constant_override("separation", UITheme.SPACE_S)
	_body.add_child(_crew_box)
	_crew_box.add_child(UITheme.icon_rect(&"crew", UITheme.TEXT_DIM, 22))
	_crew_label = UITheme.label("", false, UITheme.TEXT)
	_crew_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_crew_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_crew_remove = _stepper(&"minus", func() -> void: GameState.station.crew.unstaff(module.uid))
	_crew_remove.name = "CrewRemove"
	_crew_add = _stepper(&"plus", _on_staff)
	_crew_add.name = "CrewAdd"
	_crew_box.add_child(_crew_label)
	_crew_box.add_child(_crew_remove)
	_crew_box.add_child(_crew_add)

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


## Round outlined − / + button of the crew stepper.
func _stepper(icon_name: StringName, callback: Callable) -> Button:
	var b := UITheme.icon_button("", icon_name, callback)
	b.custom_minimum_size = Vector2(UITheme.GHOST_SIZE + 4, UITheme.GHOST_SIZE)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return b


func toggle_collapsed() -> void:
	collapsed = not collapsed
	refresh()


func refresh() -> void:
	visible = not _overlay_open and module != null and is_instance_valid(module) and module.uid != 0 \
		and GameState.station.has_module(module.uid)
	if not visible:
		return
	_body.visible = not collapsed
	_fold.icon = UITheme.icon(&"chevron_down" if collapsed else &"chevron_up")
	var st := GameState.station
	var rec := st.get_record(module.uid)
	var def := module.def
	_title.text = def.display_name
	var derelict: bool = rec.state == StationState.State.DERELICT
	var upgraded: bool = rec.state == StationState.State.UPGRADED
	_set_dot(UITheme.DANGER if derelict else UITheme.YELLOW if upgraded else UITheme.CYAN)
	# Folded: a slim pill, no cyan selection frame.
	custom_minimum_size.x = 0.0 if collapsed else WIDTH
	add_theme_stylebox_override("panel", UITheme.card(not collapsed))
	if collapsed:
		_fit.call_deferred()
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
		_status.text += " · bunks %d/%d" % [crew.residents(module.uid).size(), crew.beds(module.uid)]
	var jobs := crew.jobs(module.uid)
	_crew_box.visible = jobs > 0
	if jobs > 0:
		var staffed := crew.workers(module.uid).size()
		_crew_label.text = "Crew %d/%d · +%d%%" % [staffed, jobs, roundi((crew.staffing(module.uid) - 1.0) * 100.0)]
		_crew_remove.disabled = staffed == 0
		_crew_add.disabled = staffed >= jobs or crew.idle().is_empty()

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
	_fit.call_deferred()


## Shrinks to the content, keeping the bottom-left corner in place (a plain
## reset_size() would keep the top edge instead).
func _fit() -> void:
	var min_size := get_combined_minimum_size()
	offset_top = offset_bottom - min_size.y
	offset_right = offset_left + min_size.x


func _set_dot(color: Color) -> void:
	(_dot.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = color


func _on_header_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
		accept_event()
		EventBus.sfx.emit(&"click")
		toggle_collapsed()


func _on_repair() -> void:
	GameState.repair_module(module.uid)


func _on_staff() -> void:
	var err := GameState.station.crew.staff(module.uid)
	if err != "":
		EventBus.toast.emit(err)


func _on_power() -> void:
	GameState.toggle_power(module.uid)
