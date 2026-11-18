class_name ObjectPanel
extends ScrollContainer
## Accordion of cards in the ModuleSheet, one per object type of the focused module
## (four planters share one "Planter" card). Only one card is open at a time;
## the others fold to a one-line header (icon, name, chevron).
## An open card lists the object's actions as touch tiles (side by side when
## their text fits, "Sleep 1 h | 4 h | 8 h", else one per row); pressing one sends
## the castaway to the nearest such object, and the action runs on arrival
## (Player.interact_with). Tapping a header opens that card (or folds it when
## it's the open one). Tapping an object in the room opens and flashes its card.

## Tallest the stack gets (px) before it scrolls; the ModuleSheet sets it
## (snap state in portrait, free height in landscape).
var max_height := 440.0:
	set(value):
		max_height = value
		if _list:
			_fit()
## Key of the card the player opened last (kept across modules), &"" = first.
var open_key := ""
## Cards the player folded while open, by key (an all-folded accordion stays so).
var folded: Dictionary[String, bool] = {}
## Cards by object scene path, in layout order.
var cards: Dictionary[String, ObjectCard] = {}

## Hidden by the sheet (folded / peeking) without changing the room-view rule.
var suppressed := false:
	set(value):
		suppressed = value
		if _list:
			_update_visibility()
var module: Module
var _list: VBoxContainer
var _player: Player
var _hidden_by_overlay := false
## Object actions only show in room view (the castaway walks to the object).
var _room_view := false
var _refresh_queued := false


## One object type: header (icon, name, fold toggle) and its action buttons.
class ObjectCard:
	extends PanelContainer

	signal action_pressed(card: ObjectCard, action: InteractionAction)
	signal fold_toggled(card: ObjectCard)

	var key: String
	## Every object of this type in the module.
	var targets: Array[Interactable] = []
	var buttons: Array[Button] = []
	var actions: Array[InteractionAction] = []
	var folded := false
	var _header: HBoxContainer
	var _title: Label
	var _fold: Button
	var _list: GridContainer
	var _flash: Tween

	func _init(p_key: String, first: Interactable) -> void:
		key = p_key
		name = "Card_%s" % first.name
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", UITheme.SPACE_M)
		add_child(box)
		_header = HBoxContainer.new()
		_header.add_theme_constant_override("separation", UITheme.SPACE_M)
		_header.custom_minimum_size.y = UITheme.GHOST_SIZE
		_header.mouse_filter = Control.MOUSE_FILTER_STOP
		_header.gui_input.connect(_on_header_input)
		box.add_child(_header)
		_header.add_child(UITheme.icon_rect(first.icon, UITheme.CYAN))
		_title = UITheme.label(first.display_name, false, UITheme.TEXT)
		_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_header.add_child(_title)
		_fold = UITheme.ghost_button(&"chevron_down", func() -> void: fold_toggled.emit(self))
		_fold.name = "Fold"
		_header.add_child(_fold)
		_list = GridContainer.new()
		_list.columns = 1
		_list.add_theme_constant_override("h_separation", UITheme.SPACE_S)
		_list.add_theme_constant_override("v_separation", UITheme.SPACE_S)
		box.add_child(_list)
		resized.connect(_relayout)
		set_folded(false)

	func set_folded(value: bool) -> void:
		folded = value
		_list.visible = not folded
		_fold.icon = UITheme.icon(&"chevron_down" if folded else &"chevron_up")
		# A flat section of the sheet (the sheet is the card).
		# Flat: a faint fill, no border (the tiles inside carry the chrome).
		var sb := UITheme.box(Color(1, 1, 1, 0.025 if folded else 0.045), Color.TRANSPARENT, 0, UITheme.RADIUS_BUTTON)
		sb.content_margin_left = UITheme.SPACE_M
		sb.content_margin_right = 4 if folded else UITheme.SPACE_M
		sb.content_margin_top = 0 if folded else 2
		sb.content_margin_bottom = 0 if folded else UITheme.SPACE_M
		add_theme_stylebox_override("panel", sb)

	## Rebuilds the action buttons from the first object's get_actions().
	func refresh(pending: InteractionAction) -> void:
		actions = targets[0].get_actions()
		while buttons.size() > actions.size():
			buttons.pop_back().queue_free()
		while buttons.size() < actions.size():
			var b := UITheme.action_button("", "")
			b.name = "Action%d" % buttons.size()
			var index := buttons.size()
			b.pressed.connect(func() -> void: action_pressed.emit(self, actions[index]))
			_list.add_child(b)
			buttons.append(b)
		for i in actions.size():
			var a := actions[i]
			var walking := pending != null and pending.label == a.label and pending.detail == a.detail
			UITheme.set_action_text(buttons[i], a.label, "Walking…" if walking else a.subtitle())
			buttons[i].disabled = not a.enabled
		_relayout()

	## Tiles side by side (up to 3) when every action's text fits its share
	## of the width and the rows come out even (4 = 2 x 2); one per row otherwise.
	func _relayout() -> void:
		var n := buttons.size()
		if n == 0 or size.x <= 0.0:
			return
		var need := 0.0
		for b in buttons:
			for l: Label in b.get_node("Lines").get_children():
				var f := l.get_theme_font("font")
				need = maxf(need, f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
					l.get_theme_font_size("font_size")).x)
		need += 2.0 * UITheme.SPACE_M + 4.0
		var avail := size.x - 2.0 * UITheme.SPACE_M
		var sep := float(UITheme.SPACE_S)
		var cols := 1
		for c in range(mini(n, 3), 1, -1):
			if n % c == 0 and (avail - (c - 1) * sep) / c >= need:
				cols = c
				break
		if _list.columns != cols:
			_list.columns = cols
		var pad := UITheme.SPACE_M if cols > 1 else UITheme.SPACE_L
		for b in buttons:
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var lines := b.get_node("Lines") as Control
			lines.offset_left = pad
			lines.offset_right = -pad
			for l: Label in lines.get_children():
				l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if cols > 1 else HORIZONTAL_ALIGNMENT_LEFT

	func flash() -> void:
		if _flash:
			_flash.kill()
		modulate = Color(1.15, 1.25, 1.3)
		_flash = create_tween()
		_flash.tween_property(self, "modulate", Color.WHITE, 0.6)
		UITheme.pulse(self, 1.03, 0.3)

	func _on_header_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb and mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			accept_event()
			EventBus.sfx.emit(&"click")
			fold_toggled.emit(self)


func _ready() -> void:
	name = "ObjectPanel"
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	custom_minimum_size.x = 0
	# Sized to its cards (up to max_height), so it never covers empty screen.
	mouse_filter = Control.MOUSE_FILTER_PASS
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", UITheme.SPACE_S)
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list.minimum_size_changed.connect(_fit)
	add_child(_list)
	_player = get_tree().get_first_node_in_group(&"player") as Player
	if _player:
		_player.pending_changed.connect(func(_t: Interactable, _a: InteractionAction) -> void: queue_refresh())
	EventBus.module_focused.connect(func(m: Module) -> void:
		module = m
		rebuild())
	EventBus.interactable_tapped.connect(highlight)
	EventBus.upgrade_view_requested.connect(func(_m: Module) -> void:
		_hidden_by_overlay = true
		_update_visibility())
	EventBus.upgrade_view_closed.connect(func() -> void:
		_hidden_by_overlay = false
		rebuild())
	EventBus.room_view_changed.connect(func(room: bool) -> void:
		_room_view = room
		_update_visibility())
	EventBus.game_reset.connect(rebuild)
	GameState.station.module_changed.connect(func(_uid: int, _r: StringName) -> void: queue_refresh())
	GameState.station.crew.changed.connect(queue_refresh)
	GameState.inventory.changed.connect(queue_refresh)
	GameState.stock.count_changed.connect(func(_id: StringName, _n: int) -> void: queue_refresh())
	GameState.needs.changed.connect(func(_n: StringName, _v: float) -> void: queue_refresh())
	rebuild()


## Recollects the focused module's objects (new module, layout rebuilt...).
func rebuild() -> void:
	for card in cards.values():
		card.queue_free()
	cards.clear()
	if module != null and is_instance_valid(module):
		for it in objects_of(module):
			var key := it.scene_file_path if it.scene_file_path != "" else it.display_name
			if not cards.has(key):
				var card := ObjectCard.new(key, it)
				card.action_pressed.connect(_on_action_pressed)
				card.fold_toggled.connect(_on_fold_toggled)
				_list.add_child(card)
				cards[key] = card
			cards[key].targets.append(it)
	_apply_accordion()
	refresh()


## Opens one card (the last opened, or the first) unless the player folded it.
func _apply_accordion() -> void:
	if cards.is_empty():
		return
	var key: String = open_key if cards.has(open_key) else cards.keys()[0]
	for card: ObjectCard in cards.values():
		card.set_folded(card.key != key or folded.has(card.key))


## Interactables inside `m` (its furniture), in scene order.
static func objects_of(m: Module) -> Array[Interactable]:
	var out: Array[Interactable] = []
	for node in m.find_children("*", "Area3D", true, false):
		if node is Interactable:
			out.append(node)
	return out


## Batches the many change signals into one refresh per frame.
func queue_refresh() -> void:
	if not _refresh_queued:
		_refresh_queued = true
		refresh.call_deferred()


func refresh() -> void:
	_refresh_queued = false
	var pending := _player.pending_action() if _player else null
	for key in cards.keys():
		var card := cards[key]
		card.targets = card.targets.filter(func(t: Interactable) -> bool: return is_instance_valid(t))
		if card.targets.is_empty():
			cards.erase(key)
			card.queue_free()
			continue
		card.refresh(pending)
	_update_visibility()


## Card of `target`'s type, or null.
func card_of(target: Interactable) -> ObjectCard:
	for card: ObjectCard in cards.values():
		if card.targets.has(target):
			return card
	return null


## Unfolds and flashes the card of a tapped object.
func highlight(target: Interactable) -> void:
	var card := card_of(target)
	if card == null:
		return
	_open(card)
	card.flash()
	ensure_control_visible.call_deferred(card)


## The castaway walks to the nearest object of the card's type and acts there.
func press(card: ObjectCard, action: InteractionAction) -> void:
	var index := card.actions.find(action)
	if _player == null or index < 0 or not action.enabled:
		return
	var best: Interactable = null
	var best_d := INF
	for t in card.targets:
		var d := t.get_approach_position().distance_to(_player.global_position)
		if d < best_d:
			best = t
			best_d = d
	# The same action, but bound to the object the castaway will use.
	var own := best.get_actions()
	_player.interact_with(best, own[index] if index < own.size() else action)


func _on_action_pressed(card: ObjectCard, action: InteractionAction) -> void:
	press(card, action)


func _on_fold_toggled(card: ObjectCard) -> void:
	if card.folded:
		_open(card)
	else:
		folded[card.key] = true
		card.set_folded(true)


## Opens `card` and folds the others (one open at a time).
func _open(card: ObjectCard) -> void:
	open_key = card.key
	folded.erase(card.key)
	for other: ObjectCard in cards.values():
		other.set_folded(other != card)


func _fit() -> void:
	custom_minimum_size.y = minf(_list.get_combined_minimum_size().y, max_height)


func _update_visibility() -> void:
	visible = _room_view and not _hidden_by_overlay and not suppressed and not cards.is_empty()
