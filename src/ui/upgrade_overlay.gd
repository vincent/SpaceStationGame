class_name UpgradeOverlay
extends CanvasLayer
## Labels of the exploded view, drawn like a technical diagram: one card per
## part (name, state, cost, install button) linked to the part by an ink
## leader line. Owned by ExplodedView. Landscape: two columns beside the
## model; portrait: two columns under it (the HUD frames the model in the
## top half, see HUD._update_free_rect).

## Card width range; the actual width follows the screen (26 % of it).
const CARD_WIDTH := 300.0
const MIN_CARD_WIDTH := 190.0
const MARGIN := 20.0
## Screen space kept free above (title, needs) and below (Done button) the cards.
const TOP := 150.0
const BOTTOM := 110.0
const GAP := 8.0
## Portrait: the cards start at this share of the screen height.
const PORTRAIT_TOP := 0.5
## Columns that don't fit shrink down to this scale.
const MIN_SCALE := 0.5
const LINE_COLOR := Color(UITheme.CYAN, 0.7)
## Built-in parts: quieter lines, they have nothing to buy.
const LINE_COLOR_BUILT_IN := Color(UITheme.CYAN, 0.25)

var view: ExplodedView

var _root: Control
var _lines: Control
var _title: Label
var _cards: Dictionary[ModulePart, Control] = {}


func _ready() -> void:
	layer = 20
	_root = Control.new()
	_root.theme = UITheme.get_theme()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_lines = Control.new()
	_lines.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lines.draw.connect(_draw_lines)
	_root.add_child(_lines)

	var top := PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.position.y = 12
	var top_sb := UITheme.pill()
	top_sb.content_margin_left = 24
	top_sb.content_margin_right = 24
	top_sb.content_margin_top = 10
	top_sb.content_margin_bottom = 10
	top.add_theme_stylebox_override("panel", top_sb)
	_title = UITheme.title_label("")
	top.add_child(_title)  # display font via the TITLE variation
	_root.add_child(top)

	var done := UITheme.button("Done", func() -> void: view.exit())
	done.custom_minimum_size = Vector2(200, 64)
	done.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	done.grow_horizontal = Control.GROW_DIRECTION_BOTH
	done.grow_vertical = Control.GROW_DIRECTION_BEGIN
	done.position.y -= 16
	_root.add_child(done)
	hide()


func open() -> void:
	_title.text = "%s — upgrades" % view.module.display_name()
	_rebuild_cards()
	show()


func close() -> void:
	for card: Control in _cards.values():
		card.queue_free()
	_cards.clear()
	hide()


func _rebuild_cards() -> void:
	for card: Control in _cards.values():
		card.queue_free()
	_cards.clear()
	var by_part := {}
	for up in GameState.module_db.upgrades_for(view.module.def.id):
		by_part[up.part_node] = up
	for part in view.module.get_parts():
		var card := _make_card(part, by_part.get(StringName(part.name)))
		_root.add_child(card)
		_cards[part] = card


func _make_card(part: ModulePart, up: UpgradeDef) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size.x = CARD_WIDTH
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)
	if up == null:  # built-in part: a slim tag, nothing to buy
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.set_meta(&"built_in", true)
		var sb := UITheme.glass(UITheme.RADIUS_BUTTON)
		sb.bg_color = Color(UITheme.PANEL, 0.6)
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		card.add_theme_stylebox_override("panel", sb)
		var tag := UITheme.label("%s · built in" % String(part.name).trim_prefix("part_").capitalize(),
			true, UITheme.TEXT_DIM)
		tag.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		box.add_child(tag)
		return card
	var name_label := UITheme.label(up.display_name, false, UITheme.TEXT)
	name_label.add_theme_font_override("font", UITheme.font(UITheme.FONT_UI_BOLD))
	box.add_child(name_label)
	var desc := UITheme.label(up.description, true, UITheme.TEXT_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(desc)
	var uid := view.module.uid
	if GameState.station.is_installed(uid, up.id):
		var done := HBoxContainer.new()
		done.add_theme_constant_override("separation", 4)
		done.add_child(UITheme.icon_rect(&"check", UITheme.SUCCESS, 18))
		done.add_child(UITheme.label("Installed", true, UITheme.SUCCESS))
		box.add_child(done)
		return card
	var err := GameState.upgrade_error(uid, up.id)
	var locked := err != "" and not err.begins_with("Needs %s" % GameState.format_cost(up.cost))
	var b := UITheme.cta_button("Install", &"lock" if locked else &"upgrade", up.cost, _buy.bind(up.id))
	b.disabled = err != ""
	box.add_child(b)
	if locked:  # waiting on another part: not an error, just "later"
		box.modulate.a = 0.7  # dim the content, keep the panel opaque
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		row.add_child(UITheme.icon_rect(&"lock", UITheme.TEXT_DIM, 16))
		var why := UITheme.label(err, true, UITheme.TEXT_DIM)
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		why.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(why)
		box.add_child(row)
	return card


func _buy(upgrade_id: StringName) -> void:
	if view.buy(upgrade_id):
		_rebuild_cards()
		# The freshly installed card flashes mint.
		var up := GameState.module_db.get_upgrade(upgrade_id)
		for part: ModulePart in _cards:
			if up and StringName(part.name) == up.part_node:
				UITheme.flash(_cards[part], UITheme.SUCCESS, 0.9)


func _process(_delta: float) -> void:
	if not visible or view == null or not view.active:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var screen := _root.size
	var width := clampf(screen.x * 0.26, MIN_CARD_WIDTH, CARD_WIDTH)
	if _portrait():
		width = (screen.x - 3.0 * MARGIN) * 0.5
	var left: Array[ModulePart] = []
	var right: Array[ModulePart] = []
	for part: ModulePart in _cards:
		if not is_instance_valid(part):
			continue
		_cards[part].custom_minimum_size.x = width
		var p := cam.unproject_position(part.global_position)
		(left if p.x < screen.x * 0.5 else right).append(part)
	_balance(left, right, cam)
	_stack(left, false, width, cam)
	_stack(right, true, width, cam)
	_lines.queue_redraw()


## Moves the cards nearest the screen centre to the shorter column until the
## two columns are about the same height (less shrinking on small screens).
func _balance(left: Array[ModulePart], right: Array[ModulePart], cam: Camera3D) -> void:
	var h := func(col: Array[ModulePart]) -> float:
		var sum := 0.0
		for part in col:
			sum += _cards[part].size.y + GAP
		return sum
	var sx := func(part: ModulePart) -> float: return cam.unproject_position(part.global_position).x
	for _i in _cards.size():
		var hl: float = h.call(left)
		var hr: float = h.call(right)
		var tall := right if hr > hl else left
		var short := left if hr > hl else right
		if tall.is_empty():
			return
		# The tall column's card closest to the centre line.
		var pick: ModulePart = tall[0]
		for part in tall:
			if (tall == right and sx.call(part) < sx.call(pick)) or (tall == left and sx.call(part) > sx.call(pick)):
				pick = part
		var move := _cards[pick].size.y + GAP
		if absf(hr - hl) <= move:  # moving it would not make the columns more even
			return
		tall.erase(pick)
		short.append(pick)


## Stacks one column of cards, sorted by their part's height on screen. A
## column taller than the free space shrinks (down to MIN_SCALE) to fit.
func _stack(parts: Array[ModulePart], right_side: bool, width: float, cam: Camera3D) -> void:
	parts.sort_custom(func(a: ModulePart, b: ModulePart) -> bool:
		return cam.unproject_position(a.global_position).y < cam.unproject_position(b.global_position).y)
	var screen := _root.size
	var total := 0.0
	for part in parts:
		total += _cards[part].size.y + GAP
	var top := screen.y * PORTRAIT_TOP if _portrait() else TOP
	var avail := maxf(screen.y - top - BOTTOM, 1.0)
	var s := clampf(avail / total, MIN_SCALE, 1.0) if total > 0.0 else 1.0
	var y := top
	for part in parts:
		var card := _cards[part]
		card.scale = Vector2(s, s)
		var w := maxf(card.size.x, width) * s
		card.position = Vector2(screen.x - w - MARGIN if right_side else MARGIN, y)
		y += (card.size.y + GAP) * s


func _portrait() -> bool:
	return _root.size.y > _root.size.x


func _draw_lines() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	for part: ModulePart in _cards:
		if not is_instance_valid(part):
			continue
		var card := _cards[part]
		var anchor := cam.unproject_position(part.global_position)
		var on_left := card.position.x < _root.size.x * 0.5
		var shown := card.size * card.scale
		var edge := card.position + Vector2(shown.x if on_left else 0.0, minf(28.0, shown.y * 0.5))
		var elbow := Vector2(lerpf(edge.x, anchor.x, 0.35), edge.y)
		if _portrait():  # cards under the model: leave from the card's inner top corner
			edge = card.position + Vector2(shown.x - 24.0 if on_left else 24.0, 0.0)
			elbow = Vector2(edge.x, lerpf(edge.y, anchor.y, 0.4))
		var color := LINE_COLOR_BUILT_IN if card.has_meta(&"built_in") else LINE_COLOR
		_lines.draw_polyline(PackedVector2Array([edge, elbow, anchor]), color, 2.0, true)
		_lines.draw_circle(anchor, 5.0 if color == LINE_COLOR else 3.5, color)
