class_name AlchemyModalStyle
extends RefCounted

## Единый набор лёгких StyleBoxFlat для внутренних окон игры (Godot 4):
## 1) Окно «Друзья» (Вариант 2 — микро-уголки + Glow-таб)
## 2) «Контрактная доска» (Вариант 3 — аптекарский пергамент + тёмные скошенные кнопки)
##
## Примечание: corner_detail = 1 превращает радиус скругления в чистую фаску под 45° без текстур!

static func _set_chamfer(sb: StyleBoxFlat, radius: int = 6) -> void:
	sb.corner_detail = 1
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius

# ==============================================================================
# ОКНО «ДРУЗЬЯ» (Вариант 2)
# Поверх 4 внешних углов окна положите TextureRect со спрайтом
# 14b_modal_micro_corner_tri.png (или 14a_modal_micro_corner_L.png) + flip_h / flip_v.
# ==============================================================================

## Основная матовая подложка окна «Друзья»
static func make_modal_panel() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#221B14")
	sb.border_color = Color("#8D6E42")
	sb.set_border_width_all(1)
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	sb.shadow_size = 18
	return sb

## Активная вкладка со свечением («Друзья (1)»)
static func make_tab_active() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#2C2218")
	sb.border_color = Color("#E5BC70")
	sb.set_border_width_all(1)
	sb.border_width_bottom = 2
	_set_chamfer(sb, 6)
	sb.shadow_color = Color(1.0, 0.72, 0.26, 0.28)
	sb.shadow_size = 6
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb

## Неактивная вкладка («Заявки (0)»)
static func make_tab_inactive() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#1B150F")
	sb.border_color = Color("#57442E")
	sb.set_border_width_all(1)
	_set_chamfer(sb, 6)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb

## Поле поиска («Ник игрока» — LineEdit)
static func make_search_input() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#16110C")
	sb.border_color = Color("#4D3C28")
	sb.set_border_width_all(1)
	_set_chamfer(sb, 5)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	return sb

## Строка списка друзей («Светик»)
static func make_friend_row() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.88, 0.72, 0.44, 0.045)
	sb.border_color = Color(0.85, 0.68, 0.40, 0.16)
	sb.border_width_bottom = 1
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb

# ==============================================================================
# «КОНТРАКТНАЯ ДОСКА» (Вариант 3 — аптекарский бланк + тёмные кнопки)
# Фон доски: 17_contract_board_frame.png, листки: 18a / 18b, гвоздик: 19,
# печати: 20a / 20b / 20c, закрытие в правом верхнем углу: 21_close_icon_x_brass.png.
# ==============================================================================

## Тёмная скошенная кнопка действия на доске («Полешко: +10 ⚡»)
static func make_board_action_button(hovered: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#241B13") if hovered else Color("#1B140E")
	sb.border_color = Color("#E5BC70") if hovered else Color("#B89252")
	sb.set_border_width_all(1)
	_set_chamfer(sb, 6)
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.40)
	sb.shadow_size = 4
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb

## Нижние контурные плашки вех («Вехи дней: 7·30·100·365», «Вехи очков: 50·150·500»)
static func make_board_milestone_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.07, 0.05, 0.88)
	sb.border_color = Color("#6E5637")
	sb.set_border_width_all(1)
	_set_chamfer(sb, 6)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	return sb
