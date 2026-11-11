class_name Avatar
extends Control

const Portrait = preload("res://game/ui/avatar_portrait.gd")
const CACHE_LIMIT := 128
static var _textures: Dictionary = {}
var _texture: Texture2D
var _spec: Dictionary = {}

static func spec_for(seed: String, gender: String = "male") -> Dictionary:
	return Portrait.spec_for(seed, gender)

static func portrait_svg(spec: Dictionary) -> String:
	return Portrait.render(spec)

func setup(seed: String, size_px: float, gender: String = "male") -> void:
	setup_spec(spec_for(seed, gender), size_px)

func setup_spec(spec: Dictionary, size_px: float) -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_spec = {"kind": "spirit"} if spec.get("kind") == "spirit" else Portrait.normalized(spec)
	var key := JSON.stringify(_spec)
	if not _textures.has(key):
		var image := Image.new()
		if _spec.get("kind") == "spirit":
			image = (preload("res://game/spirits/idle.png") as Texture2D).get_image()
		else:
			var err := image.load_svg_from_string(Portrait.render(_spec), 2.0)
			if err != OK:
				return
		image.generate_mipmaps()
		if _textures.size() >= CACHE_LIMIT:
			_textures.erase(_textures.keys()[0])
		_textures[key] = ImageTexture.create_from_image(image)
	_texture = _textures[key]
	custom_minimum_size = Vector2(size_px, size_px)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	queue_redraw()

func _draw() -> void:
	if _texture == null:
		return
	var d := minf(size.x, size.y)
	var fitted := Vector2(d, d)
	if _spec.get("kind") == "spirit":
		fitted = _texture.get_size() * (d / maxf(_texture.get_width(), _texture.get_height()))
	draw_texture_rect(_texture, Rect2((size - fitted) * 0.5, fitted), false)
