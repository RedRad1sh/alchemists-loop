extends RefCounted
class_name UiGestures
# Чистые предикаты жестов: покрыты selftest без ввода (headless).

static func swipe_closes(drag: Vector2) -> bool:
	# §2.3: свайп вниз по карточке — резкий, вертикальный (порог 80 px, dx < dy/2)
	return drag.y > 80.0 and absf(drag.x) < drag.y * 0.5
