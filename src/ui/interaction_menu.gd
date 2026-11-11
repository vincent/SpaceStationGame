class_name InteractionMenu
extends PanelContainer
## Action menu of a station object. Opens on EventBus.interaction_requested.

var _title: Label
var _list: VBoxContainer
var _target: Interactable


func _ready() -> void:
	hide()
	custom_minimum_size = Vector2(380, 0)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	add_child(vbox)
	_title = UITheme.label("", false, Palette.YELLOW)
	vbox.add_child(_title)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	vbox.add_child(_list)
	vbox.add_child(UITheme.button("Close", close))
	EventBus.interaction_requested.connect(open)


func open(target: Interactable) -> void:
	_target = target
	_title.text = target.display_name
	for child in _list.get_children():
		child.queue_free()
	for action in target.get_actions():
		var b := UITheme.button(action.label, _on_action.bind(action))
		b.disabled = not action.enabled
		if not action.enabled and action.hint != "":
			b.text = "%s — %s" % [action.label, action.hint]
		_list.add_child(b)
	show()


func close() -> void:
	if visible:
		hide()
		_target = null
		EventBus.interaction_closed.emit()


func _on_action(action: InteractionAction) -> void:
	close()
	action.callback.call()
