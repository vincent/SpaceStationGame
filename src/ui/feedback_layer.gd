class_name FeedbackLayer
extends Control
## Success feedback drawn over the world (never takes input):
## - rewards (EventBus.reward): "+3 ⚙" pops where the items came from (the
##   salvage pile, the trader...) and flies to its status chip (or to the
##   Inventory button), which then bounces. Production pops just under its chip.
## - repairs, upgrades and new modules: a mint ring bursts on the module.
## Kept cheap: a few labels at a time, one tween each.

## Most reward labels in flight at once (more just bump the chip).
const MAX_LABELS := 6
const POP_SECONDS := 0.25
const FLY_SECONDS := 0.55

var hud: HUD
var _active := 0


func _init(p_hud: HUD) -> void:
	hud = p_hud


func _ready() -> void:
	name = "FeedbackLayer"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	EventBus.reward.connect(_on_reward)
	GameState.station.module_changed.connect(func(uid: int, reason: StringName) -> void:
		if reason in [&"repaired", &"upgraded"]:
			burst_on_module(uid))
	GameState.station.module_added.connect(func(uid: int) -> void:
		if not GameState._quiet and is_inside_tree():  # not on new game / load
			# The Station mirror attaches (and drops in) the module first.
			get_tree().create_timer(0.4).timeout.connect(burst_on_module.bind(uid)))


## Number of reward labels currently animating (tests).
func active_labels() -> int:
	return _active


func _on_reward(items: Dictionary, source: Node3D) -> void:
	if not is_inside_tree() or not is_visible_in_tree():
		return
	var i := 0
	for id: StringName in items:
		var n := int(items[id])
		if n <= 0:
			continue
		var target := _target_for(id)
		var to := target.get_global_rect().get_center() if target else size * 0.5
		var from := to + Vector2(0, 64)
		if source and is_instance_valid(source) and source.is_inside_tree():
			var cam := get_viewport().get_camera_3d()
			var p := source.global_position + Vector3(0, 0.8, 0)
			if cam and not cam.is_position_behind(p):
				from = cam.unproject_position(p)
		from += Vector2(0, -26 * i)
		i += 1
		if _active >= MAX_LABELS:
			_arrive(target)
			continue
		_fly(id, n, from, to, target, i * 0.08)


## The status chip of a bulk item, else the Inventory button.
func _target_for(id: StringName) -> Control:
	var chip: Control = hud.status_bar.chips.get(id)
	if chip and chip.is_visible_in_tree():
		return chip
	if hud.inventory_button and hud.inventory_button.is_visible_in_tree():
		return hud.inventory_button
	return null


func _fly(id: StringName, n: int, from: Vector2, to: Vector2, target: Control, delay: float) -> void:
	var pill := PanelContainer.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := UITheme.pill(Color(UITheme.PANEL_SOLID, 0.92), Color(UITheme.SUCCESS, 0.7))
	sb.content_margin_left = 10
	sb.content_margin_right = 12
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	pill.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(row)
	var item := GameState.item_db.get_item(id)
	var text := "+%d" % n
	if UITheme.icon(id):
		row.add_child(UITheme.icon_rect(id, item.color if item and item.color.a > 0.0 else UITheme.TEXT, 20))
	else:
		text = "+%d %s" % [n, item.display_name if item else String(id)]
	row.add_child(UITheme.label(text, false, UITheme.SUCCESS))
	add_child(pill)
	_active += 1
	pill.reset_size()
	var half := pill.size * 0.5
	pill.pivot_offset = half
	pill.position = from - half
	pill.scale = Vector2(0.6, 0.6)
	pill.modulate.a = 0.0
	var rise := from + Vector2(0, -34)
	var tw := pill.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(pill, "modulate:a", 1.0, 0.1)
	tw.parallel().tween_property(pill, "scale", Vector2.ONE, POP_SECONDS) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(pill, "position", rise - half, POP_SECONDS) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.25)
	# Arc to the chip: a quadratic curve bowing sideways.
	var ctrl := rise.lerp(to, 0.5) + Vector2((to.x - rise.x) * -0.25, -60)
	tw.tween_method(func(t: float) -> void:
		var a := rise.lerp(ctrl, t)
		var b := ctrl.lerp(to, t)
		pill.position = a.lerp(b, t) - half
		pill.scale = Vector2.ONE * lerpf(1.0, 0.55, t), 0.0, 1.0, FLY_SECONDS) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(pill, "modulate:a", 0.0, FLY_SECONDS * 0.4).set_delay(FLY_SECONDS * 0.6)
	tw.tween_callback(func() -> void:
		_active -= 1
		_arrive(target)
		pill.queue_free())


func _arrive(target: Control) -> void:
	if target == null or not is_instance_valid(target):
		return
	if target is StatusBar.Chip:
		(target as StatusBar.Chip).bump()
	else:
		UITheme.pulse(target, 1.12, 0.35)
	EventBus.sfx.emit(&"click")


## Mint ring expanding from a module's centre on screen.
func burst_on_module(uid: int) -> void:
	if not is_inside_tree():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	for node in get_tree().get_nodes_in_group(&"station_module"):
		var module := node as Module
		if module and module.uid == uid:
			var center: Vector3 = module.get_world_aabb().get_center() if module.has_method(&"get_world_aabb") \
				else module.global_position
			if not cam.is_position_behind(center):
				burst(cam.unproject_position(center))
			return


## Ring burst at a screen point (UI pixels).
func burst(at: Vector2, color: Color = UITheme.SUCCESS) -> void:
	var ring := Control.new()
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.position = at
	add_child(ring)
	var state := {"r": 24.0, "a": 1.0}
	ring.draw.connect(func() -> void:
		ring.draw_arc(Vector2.ZERO, state.r, 0.0, TAU, 48, Color(color, state.a * 0.9), 4.0, true)
		ring.draw_arc(Vector2.ZERO, state.r * 0.62, 0.0, TAU, 40, Color(color, state.a * 0.45), 2.0, true))
	var tw := ring.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(t: float) -> void:
		state.r = lerpf(24.0, 150.0, t)
		state.a = 1.0 - t
		ring.queue_redraw(), 0.0, 1.0, 0.7)
	tw.tween_callback(ring.queue_free)
