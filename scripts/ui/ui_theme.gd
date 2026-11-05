class_name UiTheme
extends RefCounted
## One warm, readable theme for every menu. Large fonts and touch targets
## because most players will be on a phone.

const PANEL_COLOR := Color(0.13, 0.1, 0.08, 0.86)
const ACCENT := Color(0.96, 0.78, 0.42)
const TEXT := Color(0.97, 0.93, 0.85)
const MUTED := Color(0.78, 0.72, 0.62)


static func create() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 22

	var panel := _box(PANEL_COLOR, 14)
	theme.set_stylebox("panel", "PanelContainer", panel)
	theme.set_stylebox("panel", "Panel", panel)

	theme.set_stylebox("normal", "Button", _box(Color(0.3, 0.22, 0.15, 0.95), 10))
	theme.set_stylebox("hover", "Button", _box(Color(0.4, 0.3, 0.2, 0.98), 10))
	theme.set_stylebox("pressed", "Button", _box(Color(0.55, 0.4, 0.22, 1.0), 10))
	theme.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), 10))
	theme.set_stylebox("disabled", "Button", _box(Color(0.22, 0.2, 0.18, 0.8), 10))
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_pressed_color", "Button", Color(1, 0.95, 0.8))
	theme.set_color("font_hover_color", "Button", Color(1, 0.95, 0.8))
	theme.set_color("font_color", "Label", TEXT)
	theme.set_constant("outline_size", "Label", 0)
	return theme


static func _box(color: Color, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	return box


static func label(text: String, size: int = 22, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, min_width: float = 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, 56)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): Sounds.play("click", null, -6.0))
	return b
