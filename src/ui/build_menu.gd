class_name BuildMenu
extends PanelContainer
## Sheet that opens when a ghost slot is tapped: the modules that fit that
## slot, one compact entry each (name, cost chips, description). Tapping an
## entry selects and previews it; one footer acts on the selection: Rotate
## (modules with several slots: which of its slots attaches; the station
## outlines the result) and a single yellow Build with the cost. The sheet
## sits on the right (landscape) or at the bottom, up to half of the screen
## (portrait), so the previewed module stays visible.

const WIDTH := 420.0
## Space kept free below the side sheet (dock), landscape.
const BOTTOM := 104.0
## Portrait: the bottom sheet takes at most this share of the screen.
const PORTRAIT_FRACTION := 0.5

## Space kept free above the sheet (top bar); set by the HUD.
var top_margin := HUD.TOP_BAR_HEIGHT + 8.0
## Bottom sheet instead of a side sheet; set by the HUD.
var portrait := false:
	set(value):
		portrait = value
		if visible:
			_fit_height()

var parent_uid := 0
var slot: StringName

var _title: Label
var _scroll: ScrollContainer
var _list: VBoxContainer
## Module id -> own slot it attaches by (the chosen rotation).
var _orientation: Dictionary[StringName, StringName] = {}
var _preview_id: StringName
var _entries: Dictionary[StringName, PanelContainer] = {}
var _footer: VBoxContainer
var _hint: Label
var _rotate_button: Button
var _build_button: Button


func _ready() -> void:
	name = "BuildMenu"
	hide()
	custom_minimum_size = Vector2(WIDTH, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", UITheme.sheet())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UITheme.SPACE_M)
	add_child(box)
	_title = UITheme.title_label("")
	box.add_child(UITheme.sheet_header(_title, hide))
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_scroll)
	var gutter := MarginContainer.new()  # room for the scroll bar
	gutter.add_theme_constant_override("margin_right", 10)
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(gutter)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", UITheme.SPACE_S)
	gutter.add_child(_list)

	# Footer: what the selection needs, Rotate, Build.
	_footer = VBoxContainer.new()
	_footer.name = "Footer"
	_footer.add_theme_constant_override("separation", UITheme.SPACE_S)
	box.add_child(_footer)
	_hint = UITheme.label("", true, UITheme.DANGER)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_footer.add_child(_hint)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", UITheme.SPACE_M)
	_footer.add_child(actions)
	_rotate_button = UITheme.icon_button("Rotate", &"rotate", func() -> void: _rotate(_preview_id))
	_rotate_button.name = "Rotate"
	actions.add_child(_rotate_button)
	_build_button = UITheme.cta_button("Build", &"plus", {}, func() -> void: _build(_preview_id))
	_build_button.name = "Build"
	_build_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(_build_button)
	EventBus.ghost_slot_tapped.connect(open)
	visibility_changed.connect(func() -> void:
		if not visible:
			EventBus.build_preview.emit(&"", 0, &"", &""))


func open(p_parent_uid: int, p_slot: StringName) -> void:
	parent_uid = p_parent_uid
	slot = p_slot
	var parent_def := GameState.station.get_def(parent_uid)
	if parent_def == null:
		return
	_title.text = "Build on %s" % parent_def.display_name
	_orientation.clear()
	_entries.clear()
	_preview_id = &""
	for child in _list.get_children():
		child.queue_free()
	var accepts: PackedStringArray = parent_def.slots.get(slot, PackedStringArray())
	for def in GameState.module_db.buildable_for(accepts, parent_def.slot_size(slot)):
		var options := GameState.station.attach_options(def.id, parent_uid, slot)
		var by: StringName = options[0] if not options.is_empty() else def.attach_slot
		_orientation[def.id] = by
		var entry := _make_entry(def, options, GameState.build_error(def.id, parent_uid, slot, by))
		_list.add_child(entry)
		_entries[def.id] = entry
		if _preview_id == &"" and not options.is_empty():
			_preview(def.id)
	if _entries.is_empty():
		_list.add_child(UITheme.label("Nothing fits this hatch yet.", true, UITheme.TEXT_DIM))
	_footer.visible = _preview_id != &""
	UITheme.fade(self, true)
	_fit_height.call_deferred()


## One module: name and cost chips, then its description (or why it can't
## attach here). Modules that can't attach anywhere on this hatch are dimmed.
func _make_entry(def: ModuleDef, options: Array, err: String) -> PanelContainer:
	var entry := PanelContainer.new()
	entry.name = "Entry_%s" % def.id
	entry.mouse_filter = Control.MOUSE_FILTER_STOP
	entry.gui_input.connect(func(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb and mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed and not options.is_empty():
			accept_event()
			EventBus.sfx.emit(&"click")
			_preview(def.id))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	entry.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UITheme.SPACE_M)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(head)
	var title := UITheme.label(def.display_name, false, UITheme.TEXT)
	title.add_theme_font_override("font", UITheme.font(UITheme.FONT_UI_BOLD))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(title)
	var cost := UITheme.cost_chips(def.build_cost, true)
	cost.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(cost)

	var blocked := options.is_empty()
	var desc := UITheme.label(err if err != "" and blocked else def.description, true,
		UITheme.DANGER if blocked else UITheme.TEXT_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(desc)
	if blocked:
		entry.modulate.a = 0.55
	_style_entry(entry, false)
	return entry


func _style_entry(entry: PanelContainer, selected: bool) -> void:
	var sb := UITheme.box(Color(UITheme.CYAN, 0.08) if selected else Color(UITheme.RAISED, 0.6),
		UITheme.CYAN if selected else UITheme.HAIRLINE, 2 if selected else 1, UITheme.RADIUS_BUTTON)
	sb.set_content_margin_all(UITheme.SPACE_M + 2)
	sb.content_margin_top = UITheme.SPACE_M
	sb.content_margin_bottom = UITheme.SPACE_M
	entry.add_theme_stylebox_override("panel", sb)


## Sizes the scroll area to the list, capped to the free height; docks right.
func _fit_height() -> void:
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var area := get_parent_area_size()
	custom_minimum_size.x = area.x if portrait else minf(WIDTH, area.x)
	var content_h := _list.get_parent_control().get_combined_minimum_size().y
	var chrome := get_combined_minimum_size().y - _scroll.custom_minimum_size.y
	var room := area.y * PORTRAIT_FRACTION if portrait else area.y - top_margin - BOTTOM
	_scroll.custom_minimum_size.y = maxf(0.0, minf(content_h, room - chrome))
	_scroll.scroll_vertical = 0
	reset_size()
	if portrait:
		position = Vector2(0.0, area.y - size.y).round()
	else:
		position = Vector2(area.x - size.x, top_margin).round()


## Next orientation of `module_id` (the next of its slots that fits).
func _rotate(module_id: StringName) -> void:
	var options := GameState.station.attach_options(module_id, parent_uid, slot)
	if options.is_empty():
		return
	var i := options.find(_orientation.get(module_id, &""))
	_orientation[module_id] = options[(i + 1) % options.size()]
	_preview(module_id)


func _preview(module_id: StringName) -> void:
	_preview_id = module_id
	for id in _entries:
		_style_entry(_entries[id], id == module_id)
	EventBus.build_preview.emit(module_id, parent_uid, slot, _orientation.get(module_id, &""))
	_refresh_footer()


## The footer follows the selection (and its rotation: some fit, some overlap).
func _refresh_footer() -> void:
	var def := GameState.module_db.get_module(_preview_id)
	_footer.visible = def != null
	if def == null:
		return
	var err := GameState.build_error(_preview_id, parent_uid, slot, _orientation.get(_preview_id, &""))
	UITheme.set_cta(_build_button, "Build", def.build_cost)
	_build_button.disabled = err != ""
	# Missing resources already show as pink chips.
	_hint.text = err
	_hint.visible = err != "" and not err.begins_with("Needs")
	_rotate_button.visible = GameState.station.attach_options(_preview_id, parent_uid, slot).size() > 1


func _build(module_id: StringName) -> void:
	if module_id == &"":
		return
	hide()
	GameState.build_module(module_id, parent_uid, slot, _orientation.get(module_id, &""))
