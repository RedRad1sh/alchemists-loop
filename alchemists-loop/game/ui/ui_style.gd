class_name UiStyle
extends RefCounted
## StyleBox-фабрики меню вкладок «Atheneum» (pill-сегмент). Всё остальное
## оформление откатано к исходному виду до следующей итерации редизайна.

## Алиас через preload: `const T := DesignTokens` — Parse Error в Godot 4.7.2
## (не constant expression), см. комментарий в ui_theme.gd.
const T := preload("res://game/ui/design_tokens.gd")

static func _box(bg: Color, radius: int, border: Color = Color(0, 0, 0, 0), bw: int = 0,
		pad: Vector4 = Vector4(4, 6, 4, 6)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if bw > 0:
		sb.set_border_width_all(bw)
		sb.border_color = border
	sb.content_margin_left = pad.x
	sb.content_margin_top = pad.y
	sb.content_margin_right = pad.z
	sb.content_margin_bottom = pad.w
	return sb

# Активная вкладка: accent-soft заливка + акцентный контур (пилюля).
static func tab(selected: bool) -> StyleBoxFlat:
	if selected:
		return _box(T.accent_soft(0.18), T.R_PILL, T.c(T.ACCENT, 0.7), 1)
	return _box(Color(0, 0, 0, 0), T.R_PILL)

static func tab_hover() -> StyleBoxFlat:
	return _box(T.c(T.BG2, 0.8), T.R_PILL)

# Дорожка меню: пилюля-подложка с тонкой рамкой.
static func tab_bar() -> StyleBoxFlat:
	return _box(T.c(T.BG1, 0.85), T.R_PILL, T.c(T.LINE), 1, Vector4(3, 3, 3, 3))
