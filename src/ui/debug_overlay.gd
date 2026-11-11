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
		["Cut on/off", _toggle_cut],
		["Back faces", _toggle_backfaces],
		["To spawn", _teleport_to_spawn],
		["Visitor", _summon_visitor],
	])
	_add_row("Focused module", [
		["Repair", _cheat_repair],
		["Power", func() -> void: _with_focus(func(m: Module) -> void: GameState.toggle_power(m.uid))],
		["Wear +", _change_wear.bind(0.2)],
		["Wear −", _change_wear.bind(-0.2)],
		["Upgrade view", func() -> void: _with_focus(EventBus.upgrade_view_requested.emit)],
	])
	_add_camera_sliders.call_deferred()
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
	_stats.text = "FPS %d (cap %d) · %.1f ms · draw calls %d · tris %dk · objects %d\n%s · speed x%s%s\nactivity: %s" % [
		Engine.get_frames_per_second(),
		Engine.max_fps,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000,
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
## tools/screenshot.sh, tools/golden.sh and handy to reproduce a state:
##   --debug-panel          open this panel
##   --inventory            open the inventory
##   --freeze               pause the clock and character routines (goldens)
##   --repair=<module_id>   repair a module instantly (also: all)
##   --power=<module_id>    repair + power a module instantly (also: all)
##   --upgrade=<upgrade_id> install an upgrade instantly
##   --visitor              dock a trader ship now (needs a powered dock)
##   --focus=<module_id>    focus a module; --view=station|room picks the zoom
##   --cut=off              disable the cutaway; --backfaces paints holes magenta
##   --explode              open the exploded view of the focused module
##   --interact=<name>      walk to the first object whose name contains <name>
##   --time=<HH>            jump the clock forward to that hour
##   --screenshot=<path>    save a PNG after --delay=<seconds> (default 3) and quit
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
	var main := get_tree().current_scene
	if args.has("freeze"):
		GameClock.paused = true
		for r: Node in main.find_children("*", "PlayerRoutine", true, false):
			r.set(&"enabled", false)
		for life: Node in main.find_children("*", "ExteriorLife", true, false):
			life.process_mode = Node.PROCESS_MODE_DISABLED
	for key: String in ["repair", "power"]:
		if args.has(key):
			_cheat_state(String(args[key]), key == "power")
	if args.has("upgrade"):
		var up := GameState.module_db.get_upgrade(StringName(args.upgrade))
		if up:
			var uid := GameState.station.find_module(up.module_id)
			GameState.station.repair(uid)
			GameState.station.install(uid, up.id)
	if args.has("visitor"):
		_summon_visitor()
	if args.has("cut") and args.cut == "off":
		_toggle_cut()
	if args.has("backfaces"):
		_toggle_backfaces()
	if args.has("focus") or args.has("view"):
		_cli_view(main, String(args.get("focus", "")), String(args.get("view", "room")))
	if args.has("explode"):
		await get_tree().create_timer(0.8).timeout
		_with_focus(EventBus.upgrade_view_requested.emit)
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


func _cli_view(main: Node, module_id: String, view: String) -> void:
	if not main.has_method(&"focus_module"):
		return
	main.set(&"skip_intro", true)
	var station := main.get_node(^"Station") as Station
	var module: Module = station.find_module(StringName(module_id)) if module_id != "" else main.get(&"focused")
	if module == null:
		push_warning("--focus: no module '%s'" % module_id)
		return
	main.call(&"focus_module", module, true)
	if view == "station":
		(main.get_node(^"DioramaCamera") as DioramaCamera).focus_on(module, DioramaCamera.Tier.STATION, true)


func _cheat_state(module_id: String, power: bool) -> void:
	var st := GameState.station
	for uid in st.uids():
		if module_id == "all" or String(st.get_record(uid).module_id) == module_id:
			st.repair(uid)
			if power:
				st.set_powered(uid, true)


func _with_focus(action: Callable) -> void:
	var main := get_tree().current_scene
	var module: Module = main.get(&"focused") if main else null
	if module:
		action.call(module)
	else:
		EventBus.toast.emit("No focused module")


func _cheat_repair() -> void:
	_with_focus(func(m: Module) -> void: GameState.station.repair(m.uid))


func _change_wear(delta: float) -> void:
	_with_focus(func(m: Module) -> void:
		GameState.station.set_wear(m.uid, GameState.station.get_record(m.uid).wear + delta))


func _toggle_cut() -> void:
	for c: CutawayController in get_tree().get_nodes_in_group(&"cutaway_controller"):
		c.enabled = not c.enabled
		EventBus.toast.emit("Cutaway %s" % ("on" if c.enabled else "off"))


func _toggle_backfaces() -> void:
	var on := not bool(RenderingServer.global_shader_parameter_get(&"debug_backfaces"))
	RenderingServer.global_shader_parameter_set(&"debug_backfaces", on)
	EventBus.toast.emit("Back faces %s" % ("magenta" if on else "normal"))


func _summon_visitor() -> void:
	var director := get_tree().current_scene.find_children("*", "VisitorDirector", true, false)
	if director.is_empty() or not (director[0] as VisitorDirector).arrive():
		EventBus.toast.emit("No powered docking slot free")


## Pitch / yaw / size sliders to tune the diorama angle on device.
func _add_camera_sliders() -> void:
	var cam := get_tree().current_scene.get_node_or_null(^"DioramaCamera") as DioramaCamera \
		if get_tree().current_scene else null
	if cam == null:
		return
	_content.add_child(UITheme.label("Camera", true, Palette.TEXT_DIM))
	for spec: Array in [["pitch", -80.0, -5.0, "pitch_deg"], ["yaw", -90.0, 90.0, "yaw_deg"],
			["size (0 = auto)", 0.0, 120.0, "size_override"]]:
		var row := HBoxContainer.new()
		var label := UITheme.label("%s %.0f" % [spec[0], cam.get(spec[3])], true)
		label.custom_minimum_size.x = 150
		row.add_child(label)
		var slider := HSlider.new()
		slider.min_value = spec[1]
		slider.max_value = spec[2]
		slider.step = 0.5
		slider.value = cam.get(spec[3])
		slider.custom_minimum_size = Vector2(240, UITheme.TOUCH_SIZE * 0.6)
		slider.value_changed.connect(func(v: float) -> void:
			cam.set(spec[3], v)
			label.text = "%s %.0f" % [spec[0], v]
			cam.set_station_aabb(cam.get_station_aabb()))
		row.add_child(slider)
		_content.add_child(row)


func _teleport_to_spawn() -> void:
	var main := get_tree().current_scene
	if main and main.has_method(&"respawn_player"):
		main.respawn_player()
