extends RefCounted

const DIR := "res://assets/ui/kit_01b/"
static var _padded: Dictionary = {}

static func texture(file: String) -> Texture2D:
	return load(DIR + file) as Texture2D

static func artwork(parent: Control, file: String, node_name: String = "Artwork") -> TextureRect:
	var rect := TextureRect.new()
	rect.name = node_name
	rect.texture = texture(file)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return rect

static func clear_button(button: Button) -> void:
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	button.add_theme_stylebox_override("focus", UIStyle.focus_ring())

static func frame_button(button: Button, file: String) -> void:
	clear_button(button)
	artwork(button, file)

static func glow_artwork(parent: Control, file: String) -> TextureRect:
	const PAD := 24
	var source := texture(file)
	if not _padded.has(file):
		var image := source.get_image()
		var padded := Image.create(image.get_width() + PAD * 2, image.get_height() + PAD * 2, false, Image.FORMAT_RGBA8)
		padded.fill(Color.TRANSPARENT)
		padded.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i(PAD, PAD))
		_padded[file] = ImageTexture.create_from_image(padded)
	var rect := TextureRect.new()
	rect.name = "TabArtwork"
	rect.texture = _padded[file]
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := ShaderMaterial.new()
	shader.shader = load(DIR + "godot_active_glow.gdshader")
	shader.set_shader_parameter("active_amount", 0.0)
	rect.material = shader
	parent.add_child(rect)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var fit := func() -> void:
		var extra := Vector2(PAD, PAD) * parent.size / source.get_size()
		rect.offset_left = -extra.x
		rect.offset_top = -extra.y
		rect.offset_right = extra.x
		rect.offset_bottom = extra.y
	parent.resized.connect(fit)
	fit.call()
	return rect

static func modal_corners(panel: Control) -> void:
	var overlay := Node2D.new()
	overlay.name = "MicroCorners"
	panel.add_child(overlay, false, Node.INTERNAL_MODE_BACK)
	for i in 4:
		var corner := TextureRect.new()
		corner.texture = texture("14b_modal_micro_corner_tri.png")
		corner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		corner.size = Vector2(18, 18)
		corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		corner.flip_h = (i & 1) != 0
		corner.flip_v = (i & 2) != 0
		overlay.add_child(corner)
		var place := func() -> void:
			corner.position = Vector2(panel.size.x - 18 if (i & 1) != 0 else 0, panel.size.y - 18 if (i & 2) != 0 else 0)
		panel.resized.connect(place)
		place.call()

static func avatar_ring(avatar: Control) -> void:
	var ring := artwork(avatar, "15_avatar_brass_ring.png", "BrassRing")
	ring.offset_left = -2
	ring.offset_top = -2
	ring.offset_right = 2
	ring.offset_bottom = 2

static func cta(button: Button) -> void:
	var normal := StyleBoxTexture.new()
	normal.texture = texture("16_cta_button_brass_9slice.png")
	normal.set_texture_margin_all(14)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := normal.duplicate() as StyleBoxTexture
		style.modulate_color = Color(1.08, 1.08, 1.08) if state == "hover" else (Color(0.8, 0.8, 0.8) if state in ["pressed", "disabled"] else Color.WHITE)
		button.add_theme_stylebox_override(state, style)
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(state, Color("2b1d12"))

static func wax_badge() -> Label:
	var badge := UIStyle.count_badge()
	var style := StyleBoxTexture.new()
	style.texture = texture("08_wax_seal_badge.png")
	style.set_content_margin_all(4)
	badge.add_theme_stylebox_override("normal", style)
	badge.custom_minimum_size = Vector2(28, 28)
	return badge
