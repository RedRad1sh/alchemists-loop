extends SceneTree
## Headless-проба UI-статики для CI (запуск: godot --headless --script
## res://tools/ui_probe.gd). Цепочка вызовов повторяет игровую: UiBootstrap
## -> UiTheme.build() -> UiStyle.* -> UiIcon.badge(). Любой SCRIPT ERROR или
## нулевой результат даёт exit != 0 — джоба падает ДО селфтеста и в аннотации
## попадает точная причина (в селфтесте такие ошибки тонут в 725 проверках).
##
## Зачем: прогон 2026-10-04 показал "Nonexistent function 'font' in base
## 'GDScript'" на UiTheme.font() без видимой причины — проба локализует класс
## ошибки (файл/шаг) за секунды.

func _init() -> void:
	var fails := 0

	# 1. Theme-фабрика (в игре — UiBootstrap.apply).
	var th = UiTheme.build()
	if th == null:
		print("PROBE FAIL: UiTheme.build() вернул null")
		fails += 1
	else:
		print("PROBE OK: UiTheme.build()")

	# 2. Прямые статические вызовы (точка старого падения — UiTheme.font).
	var f = UiTheme.font(2)
	if f == null:
		print("PROBE FAIL: UiTheme.font(2) -> null (шрифт SemiBold не загрузился)")
		fails += 1
	else:
		print("PROBE OK: UiTheme.font(2)")
	var box = UiStyle.tab(true)
	if box == null:
		print("PROBE FAIL: UiStyle.tab(true) -> null")
		fails += 1
	else:
		print("PROBE OK: UiStyle.tab(true)")

	# 3. Иконки: текстуры SVG и бейдж на кнопке.
	if UiIcon.texture("flask") == null:
		print("PROBE FAIL: UiIcon.texture('flask') -> null (SVG не импортирован?)")
		fails += 1
	else:
		print("PROBE OK: UiIcon.texture('flask')")
	var btn := Button.new()
	UiIcon.badge(btn, 7)
	var holder := btn.get_node_or_null("CountBadge")
	if holder == null:
		print("PROBE FAIL: UiIcon.badge не создал CountBadge")
		fails += 1
	else:
		print("PROBE OK: UiIcon.badge -> ", holder.get_class())
	UiIcon.badge(btn, 0)
	if btn.get_node_or_null("CountBadge") != null:
		print("PROBE FAIL: UiIcon.badge(0) не удалил пилюлю")
		fails += 1
	else:
		print("PROBE OK: UiIcon.badge(0) снял пилюлю")
	btn.free()

	if fails == 0:
		print("PROBE PASS")
	quit(0 if fails == 0 else 1)
