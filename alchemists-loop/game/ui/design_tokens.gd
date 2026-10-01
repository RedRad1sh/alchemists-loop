class_name DesignTokens
extends RefCounted
## Дизайн-токены UI «Atheneum» (v2). Единственный источник правды о цвете,
## типографике, отступах, радиусах и тач-размерах. Новые UI-файлы не содержат
## хардкода Color(): берут всё отсюда. См. docs/ui-ux/2026-10-01-*.md.

# ---------- цвет ----------
# Поверхности (снизу вверх): экран → панель → карточка → поле ввода.
const BG0 := "#0A0F16"
const BG1 := "#121A24"
const BG2 := "#18222E"
const BG3 := "#0D141D"
# Линии: разделитель и акцентный контур.
const LINE := "#24313F"
const LINE_STRONG := "#35485C"
# Текст: три роли вместо четырёх «почти-серых».
const INK1 := "#EAF2F7"
const INK2 := "#A9B8C6"
const INK3 := "#7E8D9C"
# Акценты: эфир/действие и награда/престиж.
const ACCENT := "#3AD6C6"
const ACCENT_INK := "#052622"   # текст НА акценте (контраст ≈ 9:1)
const GOLD := "#E9B44C"
const GOLD_INK := "#241A05"
# Семантика состояний.
const DANGER := "#E5705F"
const SUCCESS := "#6FCF8E"
const VIOLET := "#B49AFF"
# Скрим модалок.
const SCRIM := "#04080C"

static func c(hex: String, alpha := 1.0) -> Color:
	var col := Color(hex)
	col.a = alpha
	return col

static func accent_soft(a := 0.16) -> Color:
	return Color(ACCENT, a)

static func gold_soft(a := 0.16) -> Color:
	return Color(GOLD, a)

# ---------- типографика (Manrope) ----------
# Роль: [кегль, индекс начертания, межстрочный px, трекинг px]
const FONT_PATHS := [
	"res://assets/fonts/Manrope-Regular.ttf",   # 0
	"res://assets/fonts/Manrope-Medium.ttf",    # 1
	"res://assets/fonts/Manrope-SemiBold.ttf",  # 2
	"res://assets/fonts/Manrope-Bold.ttf",      # 3
	"res://assets/fonts/Manrope-ExtraBold.ttf", # 4
]
const T_DISPLAY := [26, 4, 32, 0.6]  # бренд (капс)
const T_H1 := [21, 4, 27, 0.2]      # заголовок экрана
const T_H2 := [17, 3, 23, 0.0]      # заголовок секции
const T_H3 := [15, 2, 21, 0.0]      # подзаголовок/карточка
const T_BODY := [15, 0, 22, 0.0]    # основной текст
const T_SMALL := [13, 1, 18, 0.0]   # вторичный текст
const T_CAPTION := [11, 2, 15, 0.6] # капс-подписи (трекинг обязателен)
const T_BTN := [15, 2, 20, 0.1]     # кнопки
const T_BTN_SM := [13, 2, 18, 0.1]  # компактные кнопки/чипы
const T_TAB := [13, 2, 18, 0.2]     # вкладки

# ---------- геометрия ----------
const SP_1 := 4
const SP_2 := 8
const SP_3 := 12
const SP_4 := 16
const SP_5 := 20
const SP_6 := 24
const SP_7 := 32
const R_CTRL := 10   # кнопки, поля
const R_CARD := 14   # карточки/панели
const R_SHEET := 18  # попапы/шторы
const R_PILL := 999  # пилюли, бейджи
const HIT_MIN := 44  # минимальный тач-таргет
const HIT_HEAD := 44 # кнопки шапки
# Тени (elevation): [offset_y, blur, alpha]
const E1 := [2, 8, 0.35]
const E2 := [6, 18, 0.45]
const E3 := [12, 32, 0.55]

# ---------- проверка контраста (WCAG) ----------
static func _lin(v: float) -> float:
	return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)

static func luminance(col: Color) -> float:
	return 0.2126 * _lin(col.r) + 0.7152 * _lin(col.g) + 0.0722 * _lin(col.b)

static func contrast(a: Color, b: Color) -> float:
	var la := luminance(a)
	var lb := luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)
