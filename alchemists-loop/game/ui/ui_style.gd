class_name UiStyle
extends RefCounted
## Фабрики StyleBox из токенов DesignTokens. Все поверхности UI строятся здесь,
## чтобы кнопки/панели/поля в любом модуле выглядели одинаково.

const T := DesignTokens

static func _box(bg: Color, radius: int, border: Color = Color(0, 0, 0, 0), bw: int = 0,
		pad: Vector4 = Vector4(12, 10, 12, 10)) -> StyleBoxFlat:
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
	sb.shadow_color = Color(0, 0, 0, 0.35)
	return sb

# ---------- поверхности ----------
static func card() -> StyleBoxFlat:
	return _box(T.c(T.BG1), T.R_CARD, T.c(T.LINE), 1, Vector4(14, 12, 14, 12))

static func card_raised() -> StyleBoxFlat:
	var sb := _box(T.c(T.BG2), T.R_CARD, T.c(T.LINE), 1, Vector4(14, 12, 14, 12))
	sb.shadow_color = Color(0, 0, 0, T.E2[2])
	sb.shadow_size = int(T.E2[1]) * 0.5
	sb.shadow_offset = Vector2(0, T.E2[0])
	return sb

static func sheet() -> StyleBoxFlat:
	var sb := _box(T.c(T.BG1, 0.98), T.R_SHEET, T.c(T.LINE_STRONG), 1, Vector4(18, 16, 18, 16))
	sb.shadow_color = Color(0, 0, 0, T.E3[2])
	sb.shadow_size = int(T.E3[1]) * 0.5
	sb.shadow_offset = Vector2(0, T.E3[0])
	return sb

static func input() -> StyleBoxFlat:
	return _box(T.c(T.BG3), T.R_CTRL, T.c(T.LINE_STRONG), 1, Vector4(12, 10, 12, 10))

static func input_focus() -> StyleBoxFlat:
	return _box(T.c(T.BG3), T.R_CTRL, T.c(T.ACCENT, 0.9), 2, Vector4(12, 10, 12, 10))

static func scrim() -> StyleBoxFlat:
	return _box(T.c(T.SCRIM, 0.66), 0)

# ---------- кнопки: kind 0 ghost/secondary, 1 accent, 2 gold ----------
static func button(kind: int, state: String) -> StyleBoxFlat:
	match kind:
		1:
			match state:
				"hover": return _box(T.c(T.ACCENT).lightened(0.08), T.R_CTRL)
				"pressed": return _box(T.c(T.ACCENT).darkened(0.12), T.R_CTRL)
				"disabled": return _box(T.c(T.ACCENT, 0.28), T.R_CTRL)
				_: return _box(T.c(T.ACCENT), T.R_CTRL)
		2:
			match state:
				"hover": return _box(T.c(T.GOLD).lightened(0.08), T.R_CTRL)
				"pressed": return _box(T.c(T.GOLD).darkened(0.12), T.R_CTRL)
				"disabled": return _box(T.c(T.GOLD, 0.30), T.R_CTRL)
				_: return _box(T.c(T.GOLD), T.R_CTRL)
		_:
			match state:
				"hover": return _box(T.c(T.BG2).lightened(0.10), T.R_CTRL, T.c(T.LINE_STRONG), 1)
				"pressed": return _box(T.c(T.BG3), T.R_CTRL, T.c(T.LINE_STRONG), 1)
				"disabled": return _box(T.c(T.BG1, 0.6), T.R_CTRL, T.c(T.LINE, 0.6), 1)
				_: return _box(T.c(T.BG2, 0.92), T.R_CTRL, T.c(T.LINE), 1)

static func button_focus() -> StyleBoxFlat:
	var sb := _box(Color(0, 0, 0, 0), T.R_CTRL, T.c(T.ACCENT, 0.95), 2)
	sb.set_expand_margin_all(2.0)
	return sb

# ---------- чипы/сегменты ----------
static func chip(selected: bool) -> StyleBoxFlat:
	if selected:
		return _box(T.accent_soft(0.18), T.R_PILL, T.c(T.ACCENT, 0.75), 1, Vector4(14, 8, 14, 8))
	return _box(Color(0, 0, 0, 0), T.R_PILL, T.c(T.LINE_STRONG), 1, Vector4(14, 8, 14, 8))

# ---------- пилюля-бейдж ----------
static func badge() -> StyleBoxFlat:
	return _box(T.c(T.GOLD), T.R_PILL, Color(0, 0, 0, 0), 0, Vector4(6, 2, 6, 2))

# ---------- прогресс ----------
static func bar_bg() -> StyleBoxFlat:
	return _box(T.c(T.BG3), 6, T.c(T.LINE), 1, Vector4(0, 0, 0, 0))

static func bar_fill() -> StyleBoxFlat:
	return _box(T.c(T.ACCENT), 6)

# ---------- вкладки (pill-сегмент) ----------
static func tab(selected: bool) -> StyleBoxFlat:
	if selected:
		return _box(T.accent_soft(0.18), T.R_PILL, T.c(T.ACCENT, 0.7), 1, Vector4(12, 6, 12, 6))
	return _box(Color(0, 0, 0, 0), T.R_PILL, Color(0, 0, 0, 0), 0, Vector4(12, 6, 12, 6))

static func tab_hover() -> StyleBoxFlat:
	return _box(T.c(T.BG2, 0.8), T.R_PILL, Color(0, 0, 0, 0), 0, Vector4(12, 6, 12, 6))

static func tab_bar() -> StyleBoxFlat:
	return _box(T.c(T.BG1, 0.85), T.R_PILL, T.c(T.LINE), 1, Vector4(4, 4, 4, 4))
