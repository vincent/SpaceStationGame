class_name EncounterPanel
extends PanelContainer
## Shows the encounter on screen (GameState.current_encounter): title,
## lines and one button per choice ("Continue" when it has none). The
## "radio" channel gets a transmission header. Toast encounters never get here.

const WIDTH := 560.0

var _channel: Label
var _title: Label
var _body: Label
var _choices: VBoxContainer


func _ready() -> void:
	hide()
	custom_minimum_size = Vector2(WIDTH, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := UITheme.sheet()
	sb.set_content_margin_all(22)
	add_theme_stylebox_override("panel", sb)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UITheme.SPACE_M + 2)
	add_child(vbox)
	_channel = UITheme.label("", true, UITheme.CYAN)
	_channel.add_theme_font_size_override("font_size", UITheme.SMALL_FONT_SIZE - 2)
	vbox.add_child(_channel)
	_title = UITheme.title_label("")
	vbox.add_child(_title)
	_body = UITheme.label("", false, UITheme.TEXT)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size.x = WIDTH - 44
	_body.add_theme_constant_override("line_spacing", 4)
	vbox.add_child(_body)
	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", UITheme.SPACE_S + 2)
	vbox.add_child(_choices)
	EventBus.encounter_started.connect(open)
	EventBus.encounter_finished.connect(func(_e: EncounterDef) -> void: hide())
	EventBus.game_reset.connect(_sync)
	_sync()


func open(enc: EncounterDef) -> void:
	_channel.visible = enc.channel == &"radio"
	_channel.text = "◉  INCOMING TRANSMISSION"
	_title.text = enc.title
	_title.visible = enc.title != ""
	_body.text = "\n".join(enc.lines)
	for child in _choices.get_children():
		child.queue_free()
	if enc.choices.is_empty():
		_choices.add_child(UITheme.button("Continue", _pick.bind(-1), UITheme.PRIMARY))
	for i in enc.choices.size():
		# The first choice is the main one; the others are outlined.
		var b := UITheme.button(String(enc.choices[i].get("text", "…")), _pick.bind(i),
			UITheme.PRIMARY if i == 0 else &"")
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.disabled = not GameState.is_choice_enabled(enc, i)
		_choices.add_child(b)
	show()


func _pick(choice: int) -> void:
	GameState.resolve_encounter(choice)


## Shows whatever GameState has on screen (the panel may be created after
## the encounter started, e.g. the intro at boot).
func _sync() -> void:
	if GameState.current_encounter:
		open(GameState.current_encounter)
	else:
		hide()
