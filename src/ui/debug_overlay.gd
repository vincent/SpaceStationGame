class_name DebugOverlay
extends CanvasLayer
## Developer cheats, only in debug builds (editor runs and debug APKs).
## Toggle with F3 or the "DBG" button. Add new tools with `_add_row()`.

var _panel: PanelContainer
var _content: VBoxContainer
var _stats: Label
var _item_picker: OptionButton


func _ready() -> void:
	layer = 50
	if not OS.is_debug_build():
		queue_free()
		return
	var root := Control.new()
	root.theme = UITheme.get_theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var toggle := UITheme.button("DBG", toggle_panel)
	toggle.custom_minimum_size = Vector2(64, 44)
	toggle.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	toggle.position.y = 8
	toggle.modulate.a = 0.6
	root.add_child(toggle)

	_panel = PanelContainer.new()
	_panel.position = Vector2(16, 90)
	_panel.hide()
	root.add_child(_panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(430, 540)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)

	_stats = UITheme.label("", true, Palette.NEON_CYAN)
	_content.add_child(_stats)

	_add_row("Time", [
		["Pause", func() -> void: GameClock.paused = not GameClock.paused],
		["x1", _set_speed.bind(1.0)],
		["x10", _set_speed.bind(10.0)],
		["x60", _set_speed.bind(60.0)],
	])
	_add_row("Skip", [
		["+15 min", GameClock.advance.bind(15.0)],
		["+1 h", GameClock.advance.bind(60.0)],
		["+8 h", GameClock.advance.bind(480.0)],
	])
	_add_row("Needs", [
		["Fill", _set_all_needs.bind(Needs.MAX)],
		["Half", _set_all_needs.bind(50.0)],
		["Critical", _set_all_needs.bind(Needs.CRITICAL - 1.0)],
	])

	_item_picker = OptionButton.new()
	_item_picker.custom_minimum_size.y = UITheme.TOUCH_SIZE
	for id in GameState.item_db.ids():
		_item_picker.add_item(String(id))
	_content.add_child(UITheme.label("Items", true, Palette.TEXT_DIM))
	var item_row := HBoxContainer.new()
	item_row.add_child(_item_picker)
	item_row.add_child(UITheme.button("Give 5", _give_selected))
	_content.add_child(item_row)

	_add_row("World", [
		["Walls", func() -> void: get_tree().call_group(&"cutaway_controller", &"cycle_mode")],
		["To spawn", _teleport_to_spawn],
	])
	_add_row("Game", [
		["Save", func() -> void: EventBus.toast.emit("Saved" if GameState.save_game() else "Save failed")],
		["Load", func() -> void: EventBus.toast.emit("Loaded" if GameState.load_game() else "No save")],
		["New", GameState.new_game],
	])
	_run_cli_commands.call_deferred()


func toggle_panel() -> void:
	_panel.visible = not _panel.visible


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		toggle_panel()


func _process(_delta: float) -> void:
	if _panel == null or not _panel.visible:
		return
	_stats.text = "FPS %d · draw calls %d · objects %d\n%s · speed x%s%s\nactivity: %s" % [
		Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		GameClock.format_time(),
		GameClock.minutes_per_second,
		" (paused)" if GameClock.paused else "",
		GameState.activity,
	]


## Adds a labelled row of buttons. `buttons` = [[text, callable], ...]
func _add_row(title: String, buttons: Array) -> void:
	_content.add_child(UITheme.label(title, true, Palette.TEXT_DIM))
	var row := HFlowContainer.new()
	for entry: Array in buttons:
		row.add_child(UITheme.button(entry[0], entry[1]))
	_content.add_child(row)


func _set_speed(value: float) -> void:
	GameClock.minutes_per_second = value
	GameClock.paused = false


func _set_all_needs(value: float) -> void:
	for need in GameState.needs.names():
		GameState.needs.set_value(need, value)


func _give_selected() -> void:
	var id := StringName(_item_picker.get_item_text(_item_picker.selected))
	var leftover := GameState.inventory.add(id, 5)
	EventBus.toast.emit("Gave %d %s" % [5 - leftover, id])


## Command-line dev hooks (after "--" on the Godot command line), used by
## tools/screenshot.sh and handy for reproducing a state quickly:
##   --debug-panel        open this panel
##   --inventory          open the inventory
##   --walls=down|up      force cutaway mode
##   --interact=<name>    walk to the first object whose name contains <name>
##   --time=<HH>          jump the clock forward to that hour
##   --screenshot=<path>  save a PNG after --delay=<seconds> (default 3) and quit
func _run_cli_commands() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		args[parts[0]] = parts[1] if parts.size() > 1 else ""
	if args.has("debug-panel"):
		_panel.show()
	var hud := get_tree().get_first_node_in_group(&"hud") as HUD
	if args.has("inventory") and hud:
		hud.inventory_panel.toggle()
	if args.has("walls"):
		for c: CutawayController in get_tree().get_nodes_in_group(&"cutaway_controller"):
			c.mode = CutawayController.Mode.ALL_DOWN if args.walls == "down" else CutawayController.Mode.ALL_UP
	if args.has("time"):
		var target_hour := int(args.time)
		GameClock.advance(fposmod((target_hour - GameClock.hour()) * 60.0 - GameClock.minute(), 1440.0))
	if args.has("interact"):
		_interact_with_named(String(args.interact))
	if args.has("screenshot"):
		await get_tree().create_timer(float(args.get("delay", "3"))).timeout
		var image := get_viewport().get_texture().get_image()
		image.convert(Image.FORMAT_RGB8)
		var path := String(args.screenshot)
		var err := image.save_png(path)
		print("Screenshot %s -> %s" % [error_string(err), ProjectSettings.globalize_path(path)])
		get_tree().quit()


func _interact_with_named(fragment: String) -> void:
	var player := get_tree().get_first_node_in_group(&"player") as Player
	for node in get_tree().current_scene.find_children("*", "Area3D", true, false):
		if node is Interactable and (node as Interactable).display_name.to_lower().contains(fragment.to_lower()):
			player.interact_with(node)
			return
	push_warning("--interact: nothing matches '%s'" % fragment)


func _teleport_to_spawn() -> void:
	var main := get_tree().current_scene
	if main and main.has_method(&"respawn_player"):
		main.respawn_player()
