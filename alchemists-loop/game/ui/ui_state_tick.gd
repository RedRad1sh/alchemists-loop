class_name UiStateTick
extends Node
## UX-31: disabled-состояние должно быть отличимо от активного.
## Кнопки игры используют текстуры Kenney без disabled-варианта, поэтому
## раз в 0.25 c обходим кнопки и приглушаем modulate у disabled.
## Изолировано: удаление ноды полностью отключает поведение.

const DIM := Color(0.60, 0.65, 0.72, 0.85)

var _acc := 0.0


func _process(delta: float) -> void:
	_acc += delta
	if _acc < 0.25:
		return
	_acc = 0.0
	var host := get_parent()
	if host == null:
		return
	for b in host.find_children("*", "Button", true, false):
		var btn := b as Button
		if btn == null or btn.has_meta("ui_keep_modulate"):
			continue
		var want := DIM if btn.disabled else Color.WHITE
		if btn.modulate != want:
			btn.modulate = want
