class_name BuildMenu
extends PanelContainer
## Opens when a ghost slot is tapped: the modules that fit that slot, their
## cost, a Build button and, for modules with several slots, a Rotate button
## (which of its slots attaches; the station outlines the result).

## Max share of the screen height the module list takes before it scrolls.
const MAX_LIST_HEIGHT := 0.6

var parent_uid := 0
var slot: StringName

var _title: Label
var _scroll: ScrollContainer
var _list: VBoxContainer
## Module id -> own slot it attaches by (the chosen rotation).
var _orientation: Dictionary[StringName, StringName] = {}
var _preview_id: StringName


func _ready() -> void:
	hide()
	custom_minimum_size = Vector2(420, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	_title = UITheme.label("", false, Palette.YELLOW)
	box.add_child(_title)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_scroll)
	var gutter := MarginContainer.new()  # room for the scroll bar
	gutter.add_theme_constant_override("margin_right", 14)
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(gutter)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	gutter.add_child(_list)
	box.add_child(UITheme.button("Close", hide))
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
	_preview_id = &""
	for child in _list.get_children():
		child.queue_free()
	var accepts: PackedStringArray = parent_def.slots.get(slot, PackedStringArray())
	for def in GameState.module_db.buildable_for(accepts, parent_def.slot_size(slot)):
		var options := GameState.station.attach_options(def.id, parent_uid, slot)
		var by: StringName = options[0] if not options.is_empty() else def.attach_slot
		_orientation[def.id] = by
		var err := GameState.build_error(def.id, parent_uid, slot, by)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_list.add_child(row)
		var b := UITheme.button("%s · %s" % [def.display_name, GameState.format_cost(def.build_cost)],
			_build.bind(def.id))
		b.name = "Build_%s" % def.id
		b.disabled = err != ""
		b.tooltip_text = err if err != "" else def.description
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
		if options.size() > 1:
			var r := UITheme.button("Rotate", _rotate.bind(def.id))
			r.name = "Rotate_%s" % def.id
			row.add_child(r)
		var desc := UITheme.label(err if options.is_empty() else def.description, true, Palette.TEXT_DIM)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(desc)
		if _preview_id == &"" and not options.is_empty():
			_preview(def.id)
	show()
	_fit_height.call_deferred()


## Sizes the scroll area to the list, capped to a share of the screen.
func _fit_height() -> void:
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var screen := get_viewport().get_visible_rect().size
	var content_h := _list.get_parent_control().get_combined_minimum_size().y
	_scroll.custom_minimum_size.y = minf(content_h, screen.y * MAX_LIST_HEIGHT)
	_scroll.scroll_vertical = 0
	reset_size()
	position = ((screen - size) * 0.5).round()


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
	EventBus.build_preview.emit(module_id, parent_uid, slot, _orientation.get(module_id, &""))


func _build(module_id: StringName) -> void:
	hide()
	GameState.build_module(module_id, parent_uid, slot, _orientation.get(module_id, &""))
