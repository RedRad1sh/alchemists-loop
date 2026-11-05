extends Node3D
class_name FurnitureItem
# Порт PlayerHouse/scripts/furniture_item.gd: спрайт проецируется в габарит бокса
# через projection_rect/alpha_rect_uv, вариант правится grade-цепочкой из .asset,
# отражение — отдельный зеркальный меш с *_reflection.png. Без yaw: в игре только
# flip X, поэтому yaw_basis = IDENTITY, а разворот стенного предмета делает
# _geometry_size().

const ISO_ROTATION_DEG := Vector3(-35.264, 45.0, 0.0)
const BOX_SHADER := preload("res://assets/house/shaders/furniture_box.gdshader")
const REFLECTION_SHADER := preload("res://assets/house/shaders/furniture_box_reflection.gdshader")
const SHADOW_TEX_PATH := "res://assets/house/shadows/blob_soft.png"

const SPRITE_PRIORITY := 5
const WALL_SPRITE_PRIORITY := 4
const REFLECTION_PRIORITY := -5
const SHADOW_PRIORITY := 1
# В исходника reflection-текстура уже затемнена в bake, поэтому opacity 1.0.
const REFLECTION_OPACITY := 1.0
const REFLECTION_FADE := 0.0
const REFLECTION_BLUR := 2.5
const SHADOW_OPACITY := 0.55
const GHOST_OPACITY := 0.55
const SHADOW_MARGIN := 0.22
const GHOST_OK_TINT := Color(0.45, 1.0, 0.5)
const GHOST_BAD_TINT := Color(1.0, 0.35, 0.3)
const SELECTED_TINT := Color(1.0, 0.92, 0.72)

## Слой отражения, как в оригинале: ReflectionBlur перекладывает его на свой слой,
## чтобы SubViewport-камера рисовала зеркало отдельно от основного прохода.
@export var reflection_layers := 2

var item_id := ""
var def := {}
var placement := {}
var _sprite: MeshInstance3D
var _reflection: MeshInstance3D
var _shadow: MeshInstance3D
var _sprite_mat: ShaderMaterial
var _reflection_mat: ShaderMaterial
var _shadow_mat: StandardMaterial3D
var _box := Vector3.ONE
var _ghost := false
var _ghost_valid := true
var _selected := false


func setup(id: String, p: Dictionary) -> void:
	item_id = id
	def = HouseItems.get_item(id)
	placement = p.duplicate(true)
	_build()


func apply(p: Dictionary) -> void:
	var size_before := _geometry_size()
	placement = p.duplicate(true)
	if size_before != _geometry_size() and _sprite != null:
		var mesh := _build_projected_box_mesh(_geometry_size(), false)
		_sprite.mesh = mesh
		# Прямоугольник проекции снимается с габарита в осях стены: при переезде на
		# другую стену бокс меняет местами X и Z, и прежняя UV-прямоуголка легла бы
		# картинкой поперёк нового меша.
		_set_projected_shader_parameters(_sprite_mat, _sprite_texture())
		if _reflection != null:
			_reflection.mesh = _build_projected_box_mesh(_geometry_size(), true)
			_set_projected_shader_parameters(_reflection_mat, _reflection_texture())
	else:
		var flip := _picture_flip()
		if _sprite_mat != null:
			_sprite_mat.set_shader_parameter("flip_x", flip)
		if _reflection_mat != null:
			_reflection_mat.set_shader_parameter("flip_x", flip)
	_update_sprite_priority()
	_update_transform()


## Порт `_set_wall_orientation` и `effective_picture_flip` из PlayerHouse: картинка
## ассета нарисована под одну стену (`wall_view`), на противоположной её нужно
## отзеркалить. Ручное «Отразить» игрока XOR-ится с этим разворотом, поэтому в
## сейве живёт прежний один флаг и контракт `_house_json` не меняется.
func _picture_flip() -> bool:
	var manual := bool(placement.get("flip", false))
	var wall := int(placement.get("wall", -1))
	if wall < 0 or not bool(def.get("flip_ok", false)):
		return manual
	return manual != (wall != int(def.get("wall_view", -1)))


func set_ghost(on: bool, valid := true) -> void:
	_ghost = on
	_ghost_valid = valid
	_apply_visual_state()


func set_selected(on: bool) -> void:
	_selected = on
	_apply_visual_state()


func _build() -> void:
	_box = def.get("box", Vector3.ONE)
	_sprite = MeshInstance3D.new()
	_sprite.name = "Sprite"
	_sprite.mesh = _build_projected_box_mesh(_geometry_size(), false)
	_sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sprite_mat = ShaderMaterial.new()
	_sprite_mat.shader = BOX_SHADER
	_update_sprite_priority()
	_sprite.material_override = _sprite_mat
	_set_projected_shader_parameters(_sprite_mat, _sprite_texture())
	add_child(_sprite)
	_reflection = MeshInstance3D.new()
	_reflection.name = "Reflection"
	_reflection.mesh = _build_projected_box_mesh(_geometry_size(), true)
	_reflection.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_reflection_mat = ShaderMaterial.new()
	_reflection_mat.shader = REFLECTION_SHADER
	_reflection_mat.render_priority = REFLECTION_PRIORITY
	_reflection.material_override = _reflection_mat
	_reflection.visible = _has_reflection()
	if _reflection.visible:
		_reflection.layers = reflection_layers
	_set_projected_shader_parameters(_reflection_mat, _reflection_texture())
	add_child(_reflection)
	_shadow = MeshInstance3D.new()
	_shadow.name = "BlobShadow"
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow_mat = StandardMaterial3D.new()
	_shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shadow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shadow_mat.albedo_texture = load(SHADOW_TEX_PATH)
	_shadow_mat.render_priority = SHADOW_PRIORITY
	_shadow.material_override = _shadow_mat
	add_child(_shadow)
	_apply_visual_state()
	_update_transform()


func _update_sprite_priority() -> void:
	if _sprite_mat == null:
		return
	# Стенные и напольные спрайты прозрачны и при равном приоритете сортируются
	# view-глубиной начала узла: высокое окно на стене выходит «ближе» витрины,
	# стоящей у той же стены, и рисуется поверх неё. Пониженный приоритет
	# выводит стену из этого соревнования: пол всегда поверх стен.
	_sprite_mat.render_priority = WALL_SPRITE_PRIORITY \
		if int(placement.get("wall", -1)) >= 0 else SPRITE_PRIORITY


func _sprite_texture() -> Texture2D:
	return load(String(def.get("sprite", "")))


func _has_reflection() -> bool:
	return String(def.get("refl", "")) != "" \
		and String(def.get("refl_mode", "regular")) != "none"


func _reflection_texture() -> Texture2D:
	var path := String(def.get("refl", ""))
	if path == "":
		return _sprite_texture()
	return load(path)


# Порт _build_projected_box_mesh: те же три видимые изо-камере грани для спрайта;
# для отражения — две вертикальные грани зеркального бокса плюс грань пола, когда
# у ассета advanced-рефлексия (её bake дотягивает картинку до линии контакта).
func _build_projected_box_mesh(box_size: Vector3, reflected: bool) -> ArrayMesh:
	var iso_basis := Basis.from_euler(Vector3(
		deg_to_rad(ISO_ROTATION_DEG.x), deg_to_rad(ISO_ROTATION_DEG.y), 0.0))
	var h := box_size.y
	var hx := box_size.x * 0.5
	var hz := box_size.z * 0.5
	var corners := [
		Vector3(-hx, 0.0, -hz), Vector3(hx, 0.0, -hz),
		Vector3(hx, 0.0, hz), Vector3(-hx, 0.0, hz),
		Vector3(-hx, h, -hz), Vector3(hx, h, -hz),
		Vector3(hx, h, hz), Vector3(-hx, h, hz)]
	var screen_min := Vector2(1e30, 1e30)
	var screen_max := Vector2(-1e30, -1e30)
	for corner in corners:
		var screen_point := Vector2(corner.dot(iso_basis.x), corner.dot(iso_basis.y))
		screen_min.x = minf(screen_min.x, screen_point.x)
		screen_min.y = minf(screen_min.y, screen_point.y)
		screen_max.x = maxf(screen_max.x, screen_point.x)
		screen_max.y = maxf(screen_max.y, screen_point.y)
	var screen_width := maxf(screen_max.x - screen_min.x, 0.001)
	var screen_height := maxf(screen_max.y - screen_min.y, 0.001)
	var faces := [[4, 5, 6, 7], [1, 2, 6, 5], [2, 3, 7, 6]]
	var mirror_basis := Basis.IDENTITY.scaled(Vector3(1.0, -1.0, 1.0))
	if reflected:
		faces = [[1, 2, 6, 5], [2, 3, 7, 6]]
		if String(def.get("refl_mode", "regular")) == "advanced":
			faces.append([0, 1, 2, 3])
	var triangle_order := [0, 1, 2, 0, 2, 3]
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var projected_uvs := PackedVector2Array()
	for face in faces:
		var face_indices: Array = face
		for tri in range(0, triangle_order.size(), 3):
			var source_a: Vector3 = corners[face_indices[triangle_order[tri]]]
			var source_b: Vector3 = corners[face_indices[triangle_order[tri + 1]]]
			var source_c: Vector3 = corners[face_indices[triangle_order[tri + 2]]]
			var a := mirror_basis * source_a if reflected else source_a
			var b := mirror_basis * source_b if reflected else source_b
			var c := mirror_basis * source_c if reflected else source_c
			var normal := (b - a).cross(c - a).normalized()
			for point in [a, b, c]:
				vertices.append(point)
				normals.append(normal)
				# UV всегда снимается с незеркальной точки: alpha-прямоугольник
				# привязан к исходному боксу, а не к его отражению.
				var source_point: Vector3 = mirror_basis * point if reflected else point
				var screen_x: float = source_point.dot(iso_basis.x)
				var screen_y: float = source_point.dot(iso_basis.y)
				var tx := clampf((screen_x - screen_min.x) / screen_width, 0.0, 1.0)
				var ty := clampf((screen_max.y - screen_y) / screen_height, 0.0, 1.0)
				projected_uvs.append(Vector2(tx, ty))
				uvs.append(Vector2(tx, ty))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = projected_uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _screen_bounds(size: Vector3, iso_basis: Basis) -> Rect2:
	var lo := Vector2(1e30, 1e30)
	var hi := Vector2(-1e30, -1e30)
	for corner in _static_corners(size):
		var p := Vector2(corner.dot(iso_basis.x), corner.dot(iso_basis.y))
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	return Rect2(lo, hi - lo)


static func _static_corners(size: Vector3) -> Array:
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	return [
		Vector3(-hx, 0.0, -hz), Vector3(hx, 0.0, -hz),
		Vector3(hx, 0.0, hz), Vector3(-hx, 0.0, hz),
		Vector3(-hx, size.y, -hz), Vector3(hx, size.y, -hz),
		Vector3(hx, size.y, hz), Vector3(-hx, size.y, hz)]


# Порт _projection_rect_for_box: в нормализованном квадрате бокса спрайт занимает
# прямоугольник проекции ВИЗИУАЛЬНОГО бокса, смещённый на sprite_offset_world.
# Без этого перекоса нарисованный изометрический стол ложится на хитбокс стола.
func _projection_rect_for_box() -> Rect2:
	var iso_basis := Basis.from_euler(Vector3(
		deg_to_rad(ISO_ROTATION_DEG.x), deg_to_rad(ISO_ROTATION_DEG.y), 0.0))
	var box_rect := _screen_bounds(_geometry_size(), iso_basis)
	var visual := _swap_xz(def.get("vbox", _box))
	var sprite_rect := _screen_bounds(visual, iso_basis)
	if box_rect.size.x <= 0.001 or box_rect.size.y <= 0.001:
		return Rect2(Vector2.ZERO, Vector2.ONE)
	var off := _swap_xz(def.get("off", Vector3.ZERO))
	var offset_screen := Vector2(off.dot(iso_basis.x), off.dot(iso_basis.y))
	var center := Vector2(0.5, 0.5) + Vector2(
		offset_screen.x / box_rect.size.x,
		-offset_screen.y / box_rect.size.y)
	var normalized := Vector2(
		sprite_rect.size.x / box_rect.size.x,
		sprite_rect.size.y / box_rect.size.y)
	return Rect2(center - normalized * 0.5, normalized)


func _set_projected_shader_parameters(mat: ShaderMaterial, tex: Texture2D) -> void:
	mat.set_shader_parameter("sprite_tex", tex)
	var projection := _projection_rect_for_box()
	mat.set_shader_parameter("projection_rect", Vector4(
		projection.position.x, projection.position.y,
		projection.size.x, projection.size.y))
	if tex == null:
		return
	var tex_size := tex.get_size()
	var alpha: Rect2 = def.get("alpha", Rect2(Vector2.ZERO, tex_size))
	if alpha.size.x <= 0.0 or alpha.size.y <= 0.0:
		alpha = Rect2(Vector2.ZERO, tex_size)
	mat.set_shader_parameter("alpha_rect_uv", Vector4(
		alpha.position.x / maxf(tex_size.x, 1.0),
		alpha.position.y / maxf(tex_size.y, 1.0),
		alpha.end.x / maxf(tex_size.x, 1.0),
		alpha.end.y / maxf(tex_size.y, 1.0)))
	mat.set_shader_parameter("flip_x", _picture_flip())
	mat.set_shader_parameter("grade", def.get("grade", Vector4(1.0, 1.0, 1.0, 0.0)))
	mat.set_shader_parameter("grade_alpha", float(def.get("grade_alpha", 1.0)))


# Wall 0 (плоскость x = -ROOM_HALF) разворачивает box на 90°: вдоль стены
# лежит box.x, в глубину — box.z. Placement.clamp_record/footprint предполагают
# ровно этот разворот; в исходнике его делал yaw_basis, здесь — подмена осей.
func _geometry_size() -> Vector3:
	return _swap_xz(_box)


# Wall 0 и отражённый напольный предмет (mirrored_xz донора) меняют местами X и Z.
func _axes_swapped() -> bool:
	if int(placement.get("wall", -1)) == 0:
		return true
	return Placement.floor_box(def, placement) != _box


func _swap_xz(v: Vector3) -> Vector3:
	return Vector3(v.z, v.y, v.x) if _axes_swapped() else v


func _update_transform() -> void:
	var wall := int(placement.get("wall", -1))
	var y := 0.0
	if wall >= 0:
		y = float(placement.get("y", _box.y * 0.5)) - _box.y * 0.5
	position = Vector3(float(placement.get("x", 0.0)), y, float(placement.get("z", 0.0)))
	if _reflection != null:
		# Отражение зеркалит относительно world y = 0 (плоскость пола), а не
		# вокруг origin узла: для стенных предметов узел поднят над полом.
		_reflection.position = Vector3(0.0, -y, 0.0)
	_update_shadow()


func _update_shadow() -> void:
	if _shadow == null:
		return
	var wall := int(placement.get("wall", -1))
	# Меш тени создаётся один раз и переиспользуется: apply() вызывается на каждом
	# кадре перетаскивания, аллоцировать PlaneMesh каждый раз расточительно.
	var plane := _shadow.mesh as PlaneMesh
	if plane == null:
		plane = PlaneMesh.new()
		_shadow.mesh = plane
	if wall == 0:
		plane.size = Vector2(_box.y + SHADOW_MARGIN, _box.x + SHADOW_MARGIN)
		_shadow.rotation_degrees = Vector3(0.0, 0.0, -90.0)
		_shadow.position = Vector3(0.01 - _box.z * 0.5, _box.y * 0.5, 0.0)
	elif wall == 1:
		plane.size = Vector2(_box.x + SHADOW_MARGIN, _box.y + SHADOW_MARGIN)
		_shadow.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		_shadow.position = Vector3(0.0, _box.y * 0.5, 0.01 - _box.z * 0.5)
	else:
		var fp := Placement.footprint(placement)
		plane.size = Vector2(fp.size.x + SHADOW_MARGIN, fp.size.y + SHADOW_MARGIN)
		_shadow.rotation_degrees = Vector3.ZERO
		_shadow.position = Vector3(0.0, 0.01, 0.0)


func _current_tint() -> Color:
	if _ghost:
		return GHOST_OK_TINT if _ghost_valid else GHOST_BAD_TINT
	if _selected:
		return SELECTED_TINT
	return Color.WHITE


func _apply_visual_state() -> void:
	var tint := _current_tint()
	var opacity := GHOST_OPACITY if _ghost else 1.0
	if _sprite_mat != null:
		_sprite_mat.set_shader_parameter("tint_color", tint)
		_sprite_mat.set_shader_parameter("opacity", opacity)
	if _reflection_mat != null:
		_reflection_mat.set_shader_parameter("tint_color", tint)
		_reflection_mat.set_shader_parameter("opacity", REFLECTION_OPACITY * opacity)
		_reflection_mat.set_shader_parameter("fade_power", REFLECTION_FADE)
		_reflection_mat.set_shader_parameter("blur_mips", REFLECTION_BLUR)
	if _shadow_mat != null:
		_shadow_mat.albedo_color = Color(0.0, 0.0, 0.0, SHADOW_OPACITY * opacity)
