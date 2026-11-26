extends Control
class_name CircleRankSymbol
# Символ-ранг Круга: геральдический щит с латунной рамой, полем цвета ранга,
# пламенем о трёх языках и звездой сверху — композиция просмотренного рефа
# (щит-бейдж ранга), матово, без glow. Без анимации.

var level := 0


func setup(lvl: int) -> void:
	level = lvl
	queue_redraw()


static func emblem_glyph(lvl: int) -> String:
	if lvl < 1:
		return ""
	return "shield_flame"


func _draw() -> void:
	if level < 1:
		return
	var rk := {}
	for r in Game.CIRCLE_RANKS:
		if int(r["level"]) == level:
			rk = r
	if rk.is_empty():
		return
	var col := Color(String(rk["color"]))
	var shield := [Vector2(0.16, 0.14), Vector2(0.84, 0.14), Vector2(0.86, 0.44),
		Vector2(0.72, 0.72), Vector2(0.50, 0.94), Vector2(0.28, 0.72),
		Vector2(0.14, 0.44)]
	# Рама: тёмный обод, латунная фаска со сдвигом вниз, светлая латунь.
	draw_colored_polygon(_sp(shield, 1.0), Color("5c3a1e"))
	draw_colored_polygon(_sp(shield, 0.93, 0.015), Color("8a6c42"))
	draw_colored_polygon(_sp(shield, 0.93), Color("d9b36a"))
	# Поле цвета ранга: тёмная основа + основной тон + светлый верх для глубины.
	draw_colored_polygon(_sp(shield, 0.78), col.darkened(0.35))
	draw_colored_polygon(_sp(shield, 0.72), col)
	draw_colored_polygon(_sp(shield, 0.72, -0.02),
		Color(col.r, col.g, col.b, 0.30).lightened(0.2))
	# Пламя о трёх языках с тенью и светлым ядром.
	var flame := [Vector2(0.50, 0.28), Vector2(0.56, 0.38), Vector2(0.63, 0.33),
		Vector2(0.60, 0.46), Vector2(0.66, 0.53), Vector2(0.61, 0.65),
		Vector2(0.50, 0.74), Vector2(0.39, 0.65), Vector2(0.34, 0.53),
		Vector2(0.40, 0.46), Vector2(0.37, 0.33), Vector2(0.44, 0.38)]
	draw_colored_polygon(_sp(flame, 1.0, 0.015), Color(0.05, 0.02, 0.01, 0.35))
	draw_colored_polygon(_sp(flame, 1.0), Color("ffd98a"))
	draw_colored_polygon(_sp([Vector2(0.50, 0.44), Vector2(0.55, 0.55),
		Vector2(0.50, 0.66), Vector2(0.45, 0.55)], 1.0), Color(1.0, 0.95, 0.82, 0.9))
	# Звезда-венец над щитом.
	var star := PackedVector2Array()
	for k in 10:
		var a := TAU * float(k) / 10.0 - PI / 2.0
		var rad := 0.08 if k % 2 == 0 else 0.034
		star.append(Vector2(0.5 + cos(a) * rad, 0.09 + sin(a) * rad))
	draw_colored_polygon(_sp(star, 1.0, 0.012), Color(0.05, 0.02, 0.01, 0.35))
	draw_colored_polygon(_sp(star, 1.0), Color("ffd21f"))


## Доли силуэта → пиксели: масштаб k вокруг центра и сдвиг dy по вертикали.
func _sp(pts, k: float, dy: float = 0.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		var v := p as Vector2
		out.append(Vector2((v.x - 0.5) * k + 0.5, (v.y - 0.5) * k + 0.5 + dy) * size)
	return out