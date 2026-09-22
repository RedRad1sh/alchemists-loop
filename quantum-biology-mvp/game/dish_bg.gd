extends Control
# Слой фона: шейдер каустик + стеклянный декор.
# Цвет среды меняется по стадии эволюции (set_stage) — плавный tween.

const W := 720.0
const H := 1280.0

# [base, caustic] по стадиям 0..7
const STAGE_BASE := [
	Color(0.012, 0.030, 0.065),   # 0 глубоководье
	Color(0.014, 0.038, 0.070),   # 1
	Color(0.018, 0.060, 0.078),   # 2 прибрежное
	Color(0.020, 0.068, 0.080),   # 3
	Color(0.024, 0.085, 0.088),   # 4 светлая лагуна
	Color(0.026, 0.090, 0.084),   # 5
	Color(0.045, 0.070, 0.075),   # 6 «венец» (золотой отлив)
	Color(0.050, 0.028, 0.105)    # 7 квантовая жизнь (фиолет)
]
const STAGE_CAUSTIC := [
	Color(0.05, 0.20, 0.42),
	Color(0.06, 0.24, 0.45),
	Color(0.10, 0.42, 0.36),
	Color(0.12, 0.48, 0.38),
	Color(0.18, 0.55, 0.38),
	Color(0.22, 0.58, 0.34),
	Color(0.55, 0.42, 0.18),
	Color(0.45, 0.22, 0.62)
]

var _shader_rect: ColorRect
var _deco: Node2D
var _mat: ShaderMaterial
var _tw: Tween

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_shader_rect = ColorRect.new()
	_shader_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shader_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://assets/shaders/dish_bg.gdshader")
	_shader_rect.material = _mat
	add_child(_shader_rect)

	_deco = DishDeco.new()
	add_child(_deco)

func set_stage(idx: int, instant: bool = false) -> void:
	idx = clampi(idx, 0, 7)
	var base: Color = STAGE_BASE[idx]
	var caustic: Color = STAGE_CAUSTIC[idx]
	if _mat == null:
		return
	if instant:
		_mat.set_shader_parameter("base_col", base)
		_mat.set_shader_parameter("caustic_col", caustic)
		return
	if _tw != null and _tw.is_valid():
		_tw.kill()
	_tw = create_tween().set_parallel(true)
	_tw.tween_property(_mat, "shader_parameter/base_col", base, 2.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tw.tween_property(_mat, "shader_parameter/caustic_col", caustic, 2.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
