extends Button
class_name AlphaHitButton
# Кнопка-предмет, которая ловит ввод только по непрозрачным пикселям вырезки:
# прозрачные поля квадрата не должны перекрывать соседние кнопки (стрелку
# «назад» в Мастерской закрывал угол верстака).

const ALPHA_MIN := 0.2

var _mask: BitMap = null
var _mask_size := Vector2.ZERO


func set_hit_texture(tex: Texture2D) -> void:
	if tex == null:
		return
	var img := tex.get_image()
	if img == null:
		return
	if img.is_compressed():
		img.decompress()
	_mask = BitMap.new()
	_mask.create_from_image_alpha(img, ALPHA_MIN)
	_mask_size = Vector2(img.get_size())


func _has_point(point: Vector2) -> bool:
	if _mask == null or size.x <= 0.0 or size.y <= 0.0:
		return Rect2(Vector2.ZERO, size).has_point(point)
	# Спрайт вписан KEEP_ASPECT_CENTERED — та же проекция, что у картинки.
	var k := minf(size.x / _mask_size.x, size.y / _mask_size.y)
	var off := (size - _mask_size * k) * 0.5
	var p := (point - off) / k
	if p.x < 0.0 or p.y < 0.0 or p.x >= _mask_size.x or p.y >= _mask_size.y:
		return false
	return _mask.get_bitv(Vector2i(p))
