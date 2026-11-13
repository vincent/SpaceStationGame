class_name UITheme
## Builds the game's UI Theme in code: synthwave colors, system sans-serif
## font (no typographic personality, maximum legibility), touch-sized buttons.

const FONT_SIZE := 22
const SMALL_FONT_SIZE := 17
## Minimum touch target height in px (at the 1280x720 base resolution).
const TOUCH_SIZE := 56

## Line icons (white, tinted by the caller) in this folder, by file name.
const ICON_DIR := "res://assets/ui/icons/"
const ICON_SIZE := 26

static var _theme: Theme
static var _icons: Dictionary[StringName, Texture2D] = {}


static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme


static func button(text: String, callback: Callable = Callable()) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, TOUCH_SIZE)
	if callback.is_valid():
		b.pressed.connect(callback)
	b.pressed.connect(func() -> void: EventBus.sfx.emit(&"click"))
	return b


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
		vertical: bool = false) -> Button:
	var b := button(text, callback)
	b.icon = icon(icon_name)
	b.expand_icon = false
	b.add_theme_constant_override("icon_max_width", ICON_SIZE)
	if vertical:
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.custom_minimum_size.y = 84
	return b


## Big two-line button: `title` and a smaller dim `detail` under it.
## Change the lines later through `set_action_text()`.
static func action_button(title: String, detail: String, callback: Callable = Callable()) -> Button:
	var b := button("", callback)
	b.custom_minimum_size.y = 72
	var box := VBoxContainer.new()
	box.name = "Lines"
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(box)
	for i in 2:
		var l := label("", i == 1, Palette.TEXT if i == 0 else Palette.TEXT_DIM)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(l)
	set_action_text(b, title, detail)
	return b


static func set_action_text(b: Button, title: String, detail: String) -> void:
	var lines := b.get_node("Lines")
	(lines.get_child(0) as Label).text = title
	var d := lines.get_child(1) as Label
	d.text = detail
	d.visible = detail != ""
	# Keeps the button tall enough for both lines (the labels don't size it).
	b.custom_minimum_size.y = 72 if detail != "" else UITheme.TOUCH_SIZE + 4


## Icon as a fixed-size TextureRect tinted `color`.
static func icon_rect(icon_name: StringName, color: Color = Palette.TEXT, px: int = ICON_SIZE) -> TextureRect:
	var r := TextureRect.new()
	r.texture = icon(icon_name)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(px, px)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.modulate = color
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Floating card style (cyan frame, rounded) used by the HUD panels.
static func card(border: Color = Palette.NEON_CYAN) -> StyleBoxFlat:
	var sb := box(Color(Palette.NIGHT, 0.92), border, 2, 14)
	sb.set_content_margin_all(14)
	return sb


static func label(text: String = "", small: bool = false, color: Color = Palette.TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	if small:
		l.add_theme_font_size_override("font_size", SMALL_FONT_SIZE)
	return l


static func box(
		color: Color, border: Color = Color.TRANSPARENT, border_width: int = 0, radius: int = 6
) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(12)
	return sb


static func _build() -> Theme:
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["sans-serif"])
	theme.default_font = font
	theme.default_font_size = FONT_SIZE

	var panel := card()
	theme.set_stylebox("panel", "PanelContainer", panel)
	theme.set_stylebox("panel", "Panel", panel)

	theme.set_color("font_color", "Label", Palette.TEXT)

	theme.set_stylebox("normal", "Button", box(Palette.DEEP_BLUE, Palette.VIOLET, 2, 10))
	theme.set_stylebox("hover", "Button", box(Palette.VIOLET, Palette.NEON_PINK, 2, 10))
	theme.set_stylebox("pressed", "Button", box(Palette.NEON_PINK, Palette.YELLOW, 2, 10))
	theme.set_stylebox("disabled", "Button", box(Color(Palette.ANTHRACITE, 0.8), Palette.ANTHRACITE, 2, 10))
	theme.set_stylebox("focus", "Button", box(Color.TRANSPARENT, Palette.YELLOW, 2, 10))
	theme.set_color("icon_normal_color", "Button", Palette.TEXT)
	theme.set_color("icon_hover_color", "Button", Palette.TEXT)
	theme.set_color("icon_pressed_color", "Button", Palette.NIGHT)
	theme.set_color("icon_disabled_color", "Button", Palette.TEXT_DIM)
	theme.set_color("font_color", "Button", Palette.TEXT)
	theme.set_color("font_hover_color", "Button", Palette.TEXT)
	theme.set_color("font_pressed_color", "Button", Palette.NIGHT)
	theme.set_color("font_disabled_color", "Button", Palette.TEXT_DIM)

	var bar_bg := box(Palette.ANTHRACITE, Color.TRANSPARENT, 0, 4)
	bar_bg.set_content_margin_all(0)
	theme.set_stylebox("background", "ProgressBar", bar_bg)
	var bar_fill := box(Palette.NEON_CYAN, Color.TRANSPARENT, 0, 4)
	bar_fill.set_content_margin_all(0)
	theme.set_stylebox("fill", "ProgressBar", bar_fill)
	theme.set_color("font_color", "ProgressBar", Palette.TEXT)
	return theme
