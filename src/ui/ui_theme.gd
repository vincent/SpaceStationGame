class_name UITheme
## Builds the game's UI Theme in code, plus the small component kit the HUD
## is made of. One visual language, used everywhere:
## - dark navy glass surfaces (a faint hairline, no glow) float over the station;
## - cyan = selected / focused / interaction feedback, muted purple = something
##   you can press, warm yellow = resources, notifications and the main action,
##   coral = warnings and draining resources, white = text;
## - three button weights: Primary (yellow fill, the main action), the default
##   secondary button (muted purple fill) and Ghost (icon only: close, fold, steppers).
## The UI has its own colours: `Palette` is the 3D world's and stays untouched.
## System sans-serif font (maximum legibility), touch-sized controls.

# Type scale (px at the 1280x720 base resolution).
const TITLE_FONT_SIZE := 24
const FONT_SIZE := 20
const SMALL_FONT_SIZE := 16
# Spacing scale.
const SPACE_S := 6
const SPACE_M := 10
const SPACE_L := 16
const RADIUS := 14
const RADIUS_BUTTON := 12
## Minimum touch target height in px (at the 1280x720 base resolution).
const TOUCH_SIZE := 56
## Icon-only buttons inside a row (still a comfortable thumb target).
const GHOST_SIZE := 48
## Smallest text anywhere (px at the base resolution).
const MIN_FONT_SIZE := 14
## Width of the module sheet when docked (landscape).
const SHEET_WIDTH := 420
## Base canvas size per orientation (`content_scale_size`): portrait keeps
## the same text size as landscape instead of shrinking everything.
const LANDSCAPE_BASE := Vector2i(1280, 720)
const PORTRAIT_BASE := Vector2i(720, 1280)

## Line icons (white, tinted by the caller) in this folder, by file name.
const ICON_DIR := "res://assets/ui/icons/"
const ICON_SIZE := 24

## Surfaces.
const PANEL := Color(0.055, 0.09, 0.16, 0.88)  # dark navy glass (#0e1729)
const PANEL_SOLID := Color(0.055, 0.09, 0.16, 0.96)  # sheets and dialogs
const RAISED := Color("18233a")  # rows, slots
const RAISED_HI := Color("21304d")  # hovered rows
const HAIRLINE := Color(1, 1, 1, 0.07)  # the only default border
const SHADOW := Color(0, 0, 0, 0.3)
const SCRIM := Color(0.02, 0.027, 0.05, 0.55)
const GLASS := PANEL
const GLASS_RIM := HAIRLINE
## Roles.
const CYAN := Color("5fd4e3")  # selection, focus, interaction
const PURPLE := Color("5d5590")  # buttons, secondary interactive elements
const PURPLE_HI := Color("6c64a0")
const PURPLE_DOWN := Color("4d467c")
const YELLOW := Color("f4c24d")  # resources, notifications, main action
const YELLOW_HI := Color("f8d06e")
const YELLOW_DOWN := Color("dcab3a")
const TEXT := Color("f1f4f9")
const TEXT_DIM := Color("98a3ba")
const INK := Color("111827")  # text on yellow
const DANGER := Color("ff6f7d")
const SUCCESS := Color("6fd9a0")

## Theme type variations (set `theme_type_variation`).
const PRIMARY := &"PrimaryButton"
const GHOST := &"GhostButton"
const ROW := &"RowButton"
## Left-aligned list row with room for a status light on its left.
const LIST_ROW := &"ListRowButton"
const TITLE := &"TitleLabel"
const CAPTION := &"CaptionLabel"

const FOLD_TIME := 0.15

static var _theme: Theme
static var _icons: Dictionary[StringName, Texture2D] = {}


## True when the screen is taller than wide (phone held upright).
static func is_portrait(vp: Viewport) -> bool:
	var size := vp.get_visible_rect().size
	return size.y > size.x


static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme


static func button(text: String, callback: Callable = Callable(), variant: StringName = &"") -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, TOUCH_SIZE)
	b.theme_type_variation = variant
	b.focus_mode = Control.FOCUS_NONE  # touch UI: no keyboard focus rings
	if callback.is_valid():
		b.pressed.connect(callback)
	b.pressed.connect(func() -> void: EventBus.sfx.emit(&"click"))
	# Press feedback: a small squash while held, a spring back on release.
	b.button_down.connect(func() -> void: _squash(b, 0.95, 0.06))
	b.button_up.connect(func() -> void: _squash(b, 1.0, 0.14))
	return b


static func _squash(c: Control, to: float, seconds: float) -> void:
	if not c.is_inside_tree():
		return
	c.pivot_offset = c.size * 0.5
	var tw := c.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "scale", Vector2(to, to), seconds)


## Quick scale bounce (1 → `amount` → 1): "this just changed".
static func pulse(c: Control, amount: float = 1.15, seconds: float = 0.35) -> void:
	if not c.is_inside_tree():
		return
	c.pivot_offset = c.size * 0.5
	var tw := c.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "scale", Vector2(amount, amount), seconds * 0.35)
	tw.tween_property(c, "scale", Vector2.ONE, seconds * 0.65)


## Tints `c` towards `color` and fades back (success / attention flash).
static func flash(c: CanvasItem, color: Color = SUCCESS, seconds: float = 0.7) -> void:
	if not c.is_inside_tree():
		return
	c.modulate = Color.WHITE.lerp(color, 0.55) * 1.25
	c.modulate.a = 1.0
	var tw := c.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate", Color.WHITE, seconds)


## Slim rounded bar (wear, staffing, timers): `color` fill on a faint track.
static func bar(color: Color, height: int = 6, max_value: float = 1.0) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.max_value = max_value
	b.step = 0.0
	b.custom_minimum_size.y = height
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_bar_color(b, color)
	return b


static func set_bar_color(b: ProgressBar, color: Color) -> void:
	var fill := box(color, Color.TRANSPARENT, 0, 3)
	fill.set_content_margin_all(0)
	b.add_theme_stylebox_override("fill", fill)


## Icon `name` from ICON_DIR, or null when there is none.
static func icon(icon_name: StringName) -> Texture2D:
	if icon_name == &"":
		return null
	if not _icons.has(icon_name):
		var path := ICON_DIR + String(icon_name) + ".svg"
		_icons[icon_name] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _icons[icon_name]


## Button with an icon left of the text (or above it when `vertical`).
static func icon_button(text: String, icon_name: StringName, callback: Callable = Callable(),
		vertical: bool = false, variant: StringName = &"") -> Button:
	var b := button(text, callback, variant)
	b.icon = icon(icon_name)
	b.expand_icon = false
	b.add_theme_constant_override("icon_max_width", ICON_SIZE)
	if vertical:
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.custom_minimum_size.y = 72
	return b


## Square icon-only button without chrome (close, fold, steppers).
static func ghost_button(icon_name: StringName, callback: Callable = Callable()) -> Button:
	var b := icon_button("", icon_name, callback, false, GHOST)
	b.custom_minimum_size = Vector2(GHOST_SIZE, GHOST_SIZE)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b


## Compact action row: `title` and a smaller dim `detail` under it, left
## aligned. Change the lines later through `set_action_text()`.
static func action_button(title: String, detail: String, callback: Callable = Callable(),
		variant: StringName = ROW) -> Button:
	var b := button("", callback, variant)
	var box := VBoxContainer.new()
	box.name = "Lines"
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = SPACE_L
	box.offset_right = -SPACE_L
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", -2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(box)
	for i in 2:
		var l := label("", i == 1, TEXT if i == 0 else TEXT_DIM)
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(l)
	set_action_text(b, title, detail)
	if variant == PRIMARY:  # dark text on yellow, light again once disabled
		b.draw.connect(func() -> void:
			for i in 2:
				var l := box.get_child(i) as Label
				var c := INK if not b.disabled else TEXT if i == 0 else TEXT_DIM
				if l.get_theme_color("font_color") != c:
					l.add_theme_color_override("font_color", c))
	return b


static func set_action_text(b: Button, title: String, detail: String) -> void:
	var lines := b.get_node("Lines")
	(lines.get_child(0) as Label).text = title
	var d := lines.get_child(1) as Label
	d.text = detail
	d.visible = detail != ""
	# The labels don't size the button: keep it tall enough for both lines.
	b.custom_minimum_size.y = 60 if detail != "" else TOUCH_SIZE
	b.tooltip_text = detail


## Icon as a fixed-size TextureRect tinted `color`.
static func icon_rect(icon_name: StringName, color: Color = TEXT, px: int = ICON_SIZE) -> TextureRect:
	var r := TextureRect.new()
	r.texture = icon(icon_name)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(px, px)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.modulate = color
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Small round colour dot (status lights).
static func dot(color: Color, px: int = 10) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(px, px)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := box(color, Color.TRANSPARENT, 0, px)
	sb.set_content_margin_all(0)
	p.add_theme_stylebox_override("panel", sb)
	return p


## Floating glass surface: dark navy, faint hairline, soft shadow.
static func glass(radius: int = RADIUS) -> StyleBoxFlat:
	var sb := box(PANEL, HAIRLINE, 1, radius)
	sb.shadow_color = SHADOW
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 3)
	sb.set_content_margin_all(SPACE_L - 2)
	return sb


## HUD card: glass, with a cyan rim when it's the selected / focused thing.
static func card(selected: bool = false) -> StyleBoxFlat:
	var sb := glass()
	if selected:
		sb.border_color = Color(CYAN, 0.85)
		sb.set_border_width_all(2)
	return sb


## Opaque-ish glass for sheets and dialogs (nothing busy shows through).
static func sheet() -> StyleBoxFlat:
	var sb := glass()
	sb.bg_color = PANEL_SOLID
	return sb


## Rounded pill (chips, clusters of the top row).
static func pill(color: Color = PANEL, border: Color = HAIRLINE) -> StyleBoxFlat:
	var sb := box(color, border, 1 if border.a > 0.0 else 0, 24)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


static func label(text: String = "", small: bool = false, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	if small:
		l.theme_type_variation = CAPTION
	return l


## Card / sheet title: semi-bold, white.
static func title_label(text: String = "", color: Color = TEXT) -> Label:
	var l := label(text, false, color)
	l.theme_type_variation = TITLE
	return l


## A cost as a row of small chips ("⚙ 6", "💧 2"): item icon (or colour dot
## and name), amount in pink when the castaway doesn't have enough.
static func cost_chips(cost: Dictionary) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", SPACE_S)
	flow.add_theme_constant_override("v_separation", 4)
	flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if cost.is_empty():
		flow.add_child(label("Free", true, SUCCESS))
		return flow
	for id: StringName in cost:
		var item := GameState.item_db.get_item(id)
		var n := int(cost[id])
		var short := GameState.count(id) < n
		var chip := PanelContainer.new()
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := pill(Color(RAISED, 0.8), Color(DANGER, 0.8) if short else Color.TRANSPARENT)
		sb.content_margin_left = 8
		sb.content_margin_right = 10
		sb.content_margin_top = 2
		sb.content_margin_bottom = 2
		chip.add_theme_stylebox_override("panel", sb)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		chip.add_child(row)
		var color: Color = item.color if item and item.color.a > 0.0 else TEXT_DIM
		var text := str(n)
		if icon(id):
			row.add_child(icon_rect(id, color, 18))
		else:
			row.add_child(dot(color, 8))
			text = "%d %s" % [n, item.display_name.to_lower() if item else String(id)]
		row.add_child(label(text, true, DANGER if short else TEXT))
		chip.tooltip_text = item.display_name if item else String(id)
		flow.add_child(chip)
	return flow


## Sheet header: title on the left, ghost ✕ on the right.
static func sheet_header(title: Label, on_close: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", SPACE_M)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(title)
	var close := ghost_button(&"close", on_close)
	close.name = "Close"
	row.add_child(close)
	return row


## Full-screen dim layer behind modal sheets. Visual only: taps still reach
## the world (which closes menus), so it doesn't change how input works.
static func scrim() -> ColorRect:
	var r := ColorRect.new()
	r.name = "Scrim"
	r.color = SCRIM
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.hide()
	return r


## Shows / hides `c` with a short fade (and a small slide from `offset`).
static func fade(c: CanvasItem, show_it: bool, offset: Vector2 = Vector2.ZERO) -> void:
	if not show_it:
		c.hide()
		return
	if c.visible and c.modulate.a >= 1.0:
		return
	var tw := c.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	c.modulate.a = 0.0
	c.show()
	tw.tween_property(c, "modulate:a", 1.0, FOLD_TIME)
	if c is Control and offset != Vector2.ZERO:
		var ctrl := c as Control
		var end := ctrl.position
		ctrl.position = end + offset
		tw.parallel().tween_property(ctrl, "position", end, FOLD_TIME * 1.5)


static func box(
		color: Color, border: Color = Color.TRANSPARENT, border_width: int = 0, radius: int = 6
) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(radius)
	sb.corner_detail = 6
	sb.anti_aliasing = true
	sb.set_content_margin_all(12)
	return sb


static func _button_box(color: Color, border: Color, border_width: int = 1, h_margin: int = 14) -> StyleBoxFlat:
	var sb := box(color, border, border_width, RADIUS_BUTTON)
	sb.content_margin_left = h_margin
	sb.content_margin_right = h_margin
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


static func _set_button_styles(theme: Theme, type: StringName, styles: Array[StyleBox]) -> void:
	for i in 4:
		theme.set_stylebox(["normal", "hover", "pressed", "disabled"][i], type, styles[i])
	theme.set_stylebox("hover_pressed", type, styles[2])
	theme.set_stylebox("focus", type, StyleBoxEmpty.new())


static func _build() -> Theme:
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["sans-serif"])
	theme.default_font = font
	theme.default_font_size = FONT_SIZE
	var bold := SystemFont.new()
	bold.font_names = PackedStringArray(["sans-serif"])
	bold.font_weight = 600

	var panel := glass()
	theme.set_stylebox("panel", "PanelContainer", panel)
	theme.set_stylebox("panel", "Panel", panel)

	theme.set_color("font_color", "Label", TEXT)
	theme.set_type_variation(TITLE, "Label")
	theme.set_font("font", TITLE, bold)
	theme.set_font_size("font_size", TITLE, TITLE_FONT_SIZE)
	theme.set_type_variation(CAPTION, "Label")
	theme.set_font_size("font_size", CAPTION, SMALL_FONT_SIZE)
	theme.set_color("font_color", CAPTION, TEXT_DIM)

	var disabled := _button_box(Color(1, 1, 1, 0.05), Color.TRANSPARENT, 0)

	# Secondary (default): muted purple fill, no border.
	_set_button_styles(theme, &"Button", [
		_button_box(PURPLE, Color.TRANSPARENT, 0),
		_button_box(PURPLE_HI, Color.TRANSPARENT, 0),
		_button_box(PURPLE_DOWN, Color.TRANSPARENT, 0),
		disabled,
	])
	_set_text_colors(theme, &"Button", TEXT, TEXT)
	theme.set_constant("h_separation", "Button", 10)

	# Primary: the main action of a card (warm yellow, dark text).
	theme.set_type_variation(PRIMARY, "Button")
	_set_button_styles(theme, PRIMARY, [
		_button_box(YELLOW, Color.TRANSPARENT, 0),
		_button_box(YELLOW_HI, Color.TRANSPARENT, 0),
		_button_box(YELLOW_DOWN, Color.TRANSPARENT, 0),
		disabled,
	])
	_set_text_colors(theme, PRIMARY, INK, INK)

	# Ghost: icon only, no chrome until pressed.
	theme.set_type_variation(GHOST, "Button")
	var none := _button_box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 8)
	none.set_content_margin_all(8)
	var ghost_down := _button_box(Color(CYAN, 0.18), Color.TRANSPARENT, 0, 8)
	ghost_down.set_content_margin_all(8)
	var ghost_off := none.duplicate() as StyleBoxFlat
	_set_button_styles(theme, GHOST, [none, none, ghost_down, ghost_off])
	theme.set_color("icon_normal_color", GHOST, TEXT_DIM)
	theme.set_color("icon_hover_color", GHOST, TEXT)
	theme.set_color("icon_pressed_color", GHOST, CYAN)
	theme.set_color("icon_hover_pressed_color", GHOST, CYAN)
	theme.set_color("icon_disabled_color", GHOST, Color(TEXT_DIM, 0.35))

	# Row: action lines inside a card (text drawn by the "Lines" labels).
	theme.set_type_variation(ROW, "Button")
	_set_button_styles(theme, ROW, [
		_button_box(RAISED, HAIRLINE),
		_button_box(RAISED_HI, Color(1, 1, 1, 0.12)),
		_button_box(Color(CYAN, 0.16), CYAN),
		_button_box(Color(1, 1, 1, 0.03), Color.TRANSPARENT, 0),
	])

	theme.set_type_variation(LIST_ROW, "Button")
	var list_styles: Array[StyleBox] = []
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := (theme.get_stylebox(state, ROW) as StyleBoxFlat).duplicate() as StyleBoxFlat
		sb.content_margin_left = 32
		list_styles.append(sb)
	_set_button_styles(theme, LIST_ROW, list_styles)

	# Progress bars (needs) and thin scroll bars.
	var bar_bg := box(Color(1, 1, 1, 0.08), Color.TRANSPARENT, 0, 4)
	bar_bg.set_content_margin_all(0)
	theme.set_stylebox("background", "ProgressBar", bar_bg)
	var bar_fill := box(CYAN, Color.TRANSPARENT, 0, 4)
	bar_fill.set_content_margin_all(0)
	theme.set_stylebox("fill", "ProgressBar", bar_fill)
	theme.set_color("font_color", "ProgressBar", TEXT)
	var track := box(Color(1, 1, 1, 0.04), Color.TRANSPARENT, 0, 3)
	track.set_content_margin_all(3)
	var grab := box(Color(TEXT_DIM, 0.35), Color.TRANSPARENT, 0, 3)
	grab.set_content_margin_all(3)
	theme.set_stylebox("scroll", "VScrollBar", track)
	for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
		theme.set_stylebox(state, "VScrollBar", grab)
	return theme


static func _set_text_colors(theme: Theme, type: StringName, text: Color, icon_color: Color) -> void:
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		theme.set_color(state, type, text)
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color"]:
		theme.set_color(state, type, icon_color)
	theme.set_color("font_disabled_color", type, TEXT_DIM)
	theme.set_color("icon_disabled_color", type, TEXT_DIM)
