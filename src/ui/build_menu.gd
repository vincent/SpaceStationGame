class_name BuildMenu
extends PanelContainer
## Opens when a ghost slot is tapped: the modules that fit that slot, their
## cost, and a Build button.

var parent_uid := 0
var slot: StringName

var _title: Label
var _list: VBoxContainer


func _ready() -> void:
	hide()
	custom_minimum_size = Vector2(420, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	_title = UITheme.label("", false, Palette.YELLOW)
	box.add_child(_title)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	box.add_child(_list)
	box.add_child(UITheme.button("Close", hide))
	EventBus.ghost_slot_tapped.connect(open)


func open(p_parent_uid: int, p_slot: StringName) -> void:
	parent_uid = p_parent_uid
	slot = p_slot
	var parent_def := GameState.station.get_def(parent_uid)
	if parent_def == null:
		return
	_title.text = "Build on %s" % parent_def.display_name
	for child in _list.get_children():
		child.queue_free()
	var accepts: PackedStringArray = parent_def.slots.get(slot, PackedStringArray())
	for def in GameState.module_db.buildable_for(accepts, parent_def.size_class):
		var err := GameState.build_error(def.id, parent_uid, slot)
		var b := UITheme.button("%s · %s" % [def.display_name, GameState.format_cost(def.build_cost)],
			_build.bind(def.id))
		b.disabled = err != ""
		b.tooltip_text = def.description
		_list.add_child(b)
		var desc := UITheme.label(def.description, true, Palette.TEXT_DIM)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(desc)
	show()


func _build(module_id: StringName) -> void:
	hide()
	GameState.build_module(module_id, parent_uid, slot)
