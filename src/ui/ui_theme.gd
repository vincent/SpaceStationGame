class_name UITheme
## Builds the game's UI Theme in code: synthwave colors, system sans-serif
## font (no typographic personality, maximum legibility), touch-sized buttons.

const FONT_SIZE := 22
const SMALL_FONT_SIZE := 17
## Minimum touch target height in px (at the 1280x720 base resolution).
const TOUCH_SIZE := 56

static var _theme: Theme


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
	return b


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

	var panel := box(Color(Palette.NIGHT, 0.92), Palette.NEON_CYAN, 2)
	theme.set_stylebox("panel", "PanelContainer", panel)
	theme.set_stylebox("panel", "Panel", panel)

	theme.set_color("font_color", "Label", Palette.TEXT)

	theme.set_stylebox("normal", "Button", box(Palette.DEEP_BLUE, Palette.VIOLET, 2))
	theme.set_stylebox("hover", "Button", box(Palette.VIOLET, Palette.NEON_PINK, 2))
	theme.set_stylebox("pressed", "Button", box(Palette.NEON_PINK, Palette.YELLOW, 2))
	theme.set_stylebox("disabled", "Button", box(Color(Palette.ANTHRACITE, 0.8), Palette.ANTHRACITE, 2))
	theme.set_stylebox("focus", "Button", box(Color.TRANSPARENT, Palette.YELLOW, 2))
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
