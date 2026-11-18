class_name ModuleSheet
extends PanelContainer
## Contextual sheet of the focused module: the ModulePanel (name, state,
## condition, actions, crew) on top, the ObjectPanel (one card per object
## type, room view only) under it.
## - Portrait: full-width bottom sheet with a drag handle. It snaps between
##   PEEK (module only), HALF (+ objects, up to half the screen) and FULL (up
##   to the top bar). Drag the handle (a flick picks the next state), or tap
##   the handle / header to toggle PEEK and HALF.
## - Landscape: docked bottom-left, SHEET_WIDTH wide; the chevron folds it.

## Position or size changed (the HUD moves the dock and the camera's free area).
signal layout_changed

enum Snap { PEEK, HALF, FULL }

const HANDLE_HEIGHT := 36.0
## Release speed (px/s) that counts as a flick.
const FLICK_SPEED := 600.0
const HALF_FRACTION := 0.5
const SNAP_SECONDS := 0.22

var module_panel: ModulePanel
var object_panel: ObjectPanel
var portrait := false
var snap := Snap.HALF
## Tallest the sheet may get (px). The HUD sets it from the screen.
var max_height := 560.0
## Screen height (px), for the HALF state.
var screen_height := 720.0

var _box: VBoxContainer
var _handle: Control
var _tween: Tween
var _drag_y := NAN
var _drag_h := 0.0
var _drag_samples: Array[Vector2] = []  # (msec, y)
var _dragged := false


func _init(p_module_panel: ModulePanel, p_object_panel: ObjectPanel) -> void:
	module_panel = p_module_panel
	object_panel = p_object_panel


func _ready() -> void:
	name = "ModuleSheet"
	mouse_filter = Control.MOUSE_FILTER_STOP
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", UITheme.SPACE_S)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)
	_handle = Control.new()
	_handle.name = "Handle"
	_handle.custom_minimum_size.y = HANDLE_HEIGHT
	_handle.mouse_filter = Control.MOUSE_FILTER_STOP
	_handle.mouse_default_cursor_shape = Control.CURSOR_VSIZE
	_handle.draw.connect(_draw_handle)
	_handle.gui_input.connect(_on_handle_input)
	_box.add_child(_handle)
	module_panel.embedded = true
	_box.add_child(module_panel)
	_box.add_child(object_panel)
	module_panel.fold_requested.connect(_on_fold_requested)
	for c: Control in [module_panel, object_panel]:
		c.visibility_changed.connect(_sync)
	_box.minimum_size_changed.connect(_fit)
	item_rect_changed.connect(layout_changed.emit)
	visibility_changed.connect(layout_changed.emit)
	EventBus.module_focused.connect(func(_m: Module) -> void: _sync.call_deferred())
	EventBus.room_view_changed.connect(func(_room: bool) -> void: _apply_snap.call_deferred(false))
	_style()
	_sync()


## Orientation and room from the HUD (called on every resize).
func apply_layout(p_portrait: bool, p_max_height: float, p_screen_height: float) -> void:
	portrait = p_portrait
	max_height = p_max_height
	screen_height = p_screen_height
	if portrait:
		set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		offset_left = 0.0
		offset_right = 0.0
	else:
		set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		offset_left = 0.0
		offset_right = UITheme.SHEET_WIDTH
	offset_bottom = 0.0
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	_style()
	_apply_snap(false)
	_sync()


## Portrait: snaps to `state` (animated unless `instant`).
func set_snap(state: Snap, instant: bool = false) -> void:
	snap = state
	_apply_snap(not instant)


## Height the object cards get in a snap state (0 = hidden).
func objects_height_for(state: Snap) -> float:
	var fixed := _fixed_height()
	match state:
		Snap.PEEK:
			return 0.0
		Snap.HALF:
			return clampf(screen_height * HALF_FRACTION - fixed, 0.0, maxf(max_height - fixed, 0.0))
	return maxf(max_height - fixed, 0.0)


## Back button: FULL folds to HALF. True if it did something.
func handle_back() -> bool:
	if portrait and visible and snap == Snap.FULL and object_panel.visible:
		set_snap(Snap.HALF)
		return true
	return false


func _style() -> void:
	var sb := UITheme.sheet()
	sb.border_color = Color(UITheme.CYAN, 0.55)
	sb.set_border_width_all(1)
	sb.content_margin_top = 4 if portrait else UITheme.SPACE_M
	sb.content_margin_left = UITheme.SPACE_L
	sb.content_margin_right = UITheme.SPACE_M
	add_theme_stylebox_override("panel", sb)


## Everything but the object cards (handle, module card, separations, chrome).
func _fixed_height() -> float:
	var sb := get_theme_stylebox("panel")
	var h := sb.get_minimum_size().y if sb else 0.0
	if _handle.visible:
		h += HANDLE_HEIGHT + UITheme.SPACE_S
	if module_panel.visible:
		h += module_panel.get_combined_minimum_size().y + UITheme.SPACE_S
	return h


func _sync() -> void:
	visible = module_panel.visible or object_panel.visible or _objects_available()
	_handle.visible = portrait and _objects_available()
	_fit.call_deferred()


## The object cards would show (room view, cards) if the sheet let them.
func _objects_available() -> bool:
	return object_panel._room_view and not object_panel._hidden_by_overlay and not object_panel.cards.is_empty()


func _apply_snap(animate: bool) -> void:
	if not is_inside_tree():
		return
	if _tween:
		_tween.kill()
	if not portrait:
		module_panel.set_fold_icon(module_panel.collapsed)
		object_panel.suppressed = module_panel.collapsed
		object_panel.max_height = maxf(max_height - _fixed_height(), 120.0)
		_sync()
		return
	var target := objects_height_for(snap)
	module_panel.set_fold_icon(snap == Snap.PEEK)
	if target > 0.0:
		object_panel.suppressed = false
	if animate:
		var from := object_panel.size.y if object_panel.visible else 0.0
		object_panel.max_height = from
		_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_tween.tween_property(object_panel, "max_height", target, SNAP_SECONDS)
		_tween.tween_callback(_end_snap)
	else:
		object_panel.max_height = target
		_end_snap()


func _end_snap() -> void:
	object_panel.suppressed = portrait and snap == Snap.PEEK
	_sync()


## Shrinks / grows to the content, keeping the bottom edge in place.
func _fit() -> void:
	if not is_inside_tree():
		return
	var min_size := get_combined_minimum_size()
	offset_top = offset_bottom - min_size.y
	if not portrait:
		offset_right = offset_left + UITheme.SHEET_WIDTH
	layout_changed.emit()


func _on_fold_requested() -> void:
	if portrait and _objects_available():
		set_snap(Snap.HALF if snap == Snap.PEEK else Snap.PEEK)
	else:
		module_panel.toggle_collapsed()
		_apply_snap(false)


func _draw_handle() -> void:
	var w := 44.0
	var r := Rect2((_handle.size.x - w) * 0.5, 12.0, w, 5.0)
	_handle.draw_style_box(UITheme.box(Color(UITheme.TEXT_DIM, 0.6), Color.TRANSPARENT, 0, 3), r)


func _on_handle_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if mb.pressed:
			if _tween:
				_tween.kill()
			_drag_y = mb.global_position.y
			_drag_h = object_panel.size.y if object_panel.visible else 0.0
			_drag_samples = [Vector2(Time.get_ticks_msec(), _drag_y)]
			_dragged = false
		elif not is_nan(_drag_y):
			_release(mb.global_position.y)
		return
	var mm := event as InputEventMouseMotion
	if mm and not is_nan(_drag_y):
		accept_event()
		var dy := mm.global_position.y - _drag_y
		if absf(dy) > 8.0:
			_dragged = true
		if _dragged:
			object_panel.suppressed = false
			object_panel.max_height = clampf(_drag_h - dy, 0.0, objects_height_for(Snap.FULL))
		_drag_samples.append(Vector2(Time.get_ticks_msec(), mm.global_position.y))
		if _drag_samples.size() > 6:
			_drag_samples.pop_front()


## Picks the snap state after a drag: a flick goes one step its way, a slow
## release goes to the nearest state. A tap toggles PEEK / HALF.
func _release(y: float) -> void:
	_drag_y = NAN
	if not _dragged:
		EventBus.sfx.emit(&"click")
		_on_fold_requested()
		return
	var h := object_panel.max_height
	var velocity := 0.0
	if _drag_samples.size() >= 2:
		var a := _drag_samples[0]
		var dt := maxf((Time.get_ticks_msec() - a.x) / 1000.0, 0.001)
		velocity = (y - a.y) / dt  # > 0 = down = smaller
	var states: Array[Snap] = [Snap.PEEK, Snap.HALF, Snap.FULL]
	var best := snap
	if velocity < -FLICK_SPEED:  # flick up: the next taller state
		best = Snap.FULL
		for s in states:
			if objects_height_for(s) > h + 1.0:
				best = s
				break
	elif velocity > FLICK_SPEED:  # flick down: the next shorter state
		best = Snap.PEEK
		for s in states:
			if objects_height_for(s) < h - 1.0:
				best = s
	else:
		var best_d := INF
		for s in states:
			var d := absf(objects_height_for(s) - h)
			if d < best_d:
				best_d = d
				best = s
	set_snap(best)
