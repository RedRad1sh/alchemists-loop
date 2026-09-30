class_name SigilPalette
extends RefCounted

## Палитра карточки. База задаётся редкостью, конкретные оттенки — seed'ом,
## поэтому две легендарки одного рецепта не выглядят как копии.

var rarity: StringName = &"common"
var bg_deep: Color = Color(0.03, 0.04, 0.07)
var bg_mid: Color = Color(0.10, 0.14, 0.24)
var bg_hot: Color = Color(0.35, 0.50, 0.78)
var aura_color: Color = Color(0.45, 0.50, 0.58)
var ink: Color = Color(0.91, 0.88, 0.79)
var ink_dim: Color = Color(0.55, 0.56, 0.62)
var accent: Color = Color(0.85, 0.72, 0.42)
var aura_intensity: float = 0.12
var aura_layers: int = 1
var aura_pulse: float = 0.0
var noise_scale: float = 2.2
var warp: float = 0.85
var contrast: float = 1.0
var ink_width: float = 1.0


static func preset(rarity_name: StringName) -> Dictionary:
	match rarity_name:
		&"uncommon":
			return {"h": 0.33, "aura": Color(0.35, 0.78, 0.44), "i": 0.20, "l": 2, "p": 0.0}
		&"rare":
			return {"h": 0.58, "aura": Color(0.28, 0.58, 0.92), "i": 0.34, "l": 3, "p": 0.0}
		&"epic":
			return {"h": 0.76, "aura": Color(0.62, 0.36, 0.92), "i": 0.50, "l": 4, "p": 0.05}
		&"legendary":
			return {"h": 0.10, "aura": Color(0.98, 0.70, 0.22), "i": 0.74, "l": 5, "p": 0.35}
		&"mythic":
			return {"h": 0.98, "aura": Color(0.92, 0.24, 0.36), "i": 0.95, "l": 6, "p": 0.55}
		_:
			return {"h": 0.60, "aura": Color(0.48, 0.54, 0.62), "i": 0.11, "l": 1, "p": 0.0}


static func rarity_names() -> PackedStringArray:
	return PackedStringArray(["common", "uncommon", "rare", "epic", "legendary", "mythic"])


static func make(seed_value: int, rarity_name: StringName) -> SigilPalette:
	var rng := SigilRng.new(seed_value).fork("palette")
	var p := new()
	p.rarity = rarity_name
	var pr := preset(rarity_name)

	var base_h := float(pr["h"])
	var hue := fposmod(base_h + rng.gauss(0.0, 0.035), 1.0)
	var sat := clampf(float(pr["aura"].s) * rng.randf_range(0.92, 1.10), 0.0, 1.0)
	var val := clampf(float(pr["aura"].v) * rng.randf_range(0.94, 1.06), 0.0, 1.0)
	var aura := Color.from_hsv(hue, sat, val)

	p.aura_color = aura
	p.aura_intensity = float(pr["i"])
	p.aura_layers = int(pr["l"])
	p.aura_pulse = float(pr["p"])

	# Фон: холодный и тёмный, чтобы кольцо и иконка читались поверх.
	var bg_hue := fposmod(hue + rng.randf_range(-0.09, 0.09), 1.0)
	var deep_v := rng.randf_range(0.030, 0.060)
	var mid_v := rng.randf_range(0.090, 0.165)
	var hot_v := rng.randf_range(0.260, 0.420)
	p.bg_deep = Color.from_hsv(bg_hue, 0.55, deep_v)
	p.bg_mid = Color.from_hsv(fposmod(bg_hue + 0.03, 1.0), 0.46, mid_v)
	p.bg_hot = Color.from_hsv(fposmod(bg_hue + 0.07, 1.0), 0.38, hot_v)

	# Чернила (линии круга) — тёплый пергамент, подсвеченный цветом ауры.
	p.ink = Color.from_hsv(fposmod(hue + 0.02, 1.0), 0.18, rng.randf_range(0.88, 0.97))
	p.ink_dim = Color(p.ink.r, p.ink.g, p.ink.b, 0.42)
	p.accent = aura.lerp(Color(1, 0.95, 0.82), 0.25)

	p.noise_scale = rng.randf_range(1.7, 3.1)
	p.warp = rng.randf_range(0.6, 1.25)
	p.contrast = rng.randf_range(0.85, 1.30)
	p.ink_width = 1.0 + float(p.aura_layers) * 0.06
	return p


func to_shader_uniforms() -> Dictionary:
	return {
		"color_deep": bg_deep,
		"color_mid": bg_mid,
		"color_hot": bg_hot,
		"noise_scale": noise_scale,
		"warp_amount": warp,
		"phase": 0.0,
		"contrast": contrast,
	}


func to_glow_uniforms(center_ratio: float, glow: float) -> Dictionary:
	return {
		"center_uv": Vector2(0.5, center_ratio),
		"glow_color": aura_color,
		"intensity": aura_intensity,
		"pulse": aura_pulse,
		"ring_radius": glow,
	}
