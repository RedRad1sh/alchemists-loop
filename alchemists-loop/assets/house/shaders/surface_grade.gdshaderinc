// Room surface math shared by every override shader: `floor_setup.gdshader`,
// `surface_back.gdshader` and `surface_double.gdshader`. It is functions only -
// each shader declares its own uniforms and calls these - so the grade chain and
// the corner occlusion exist in one place and cannot drift apart between the
// floor and the walls.
//
// Godot's shader parser takes no global `const`, so the luminance weights live
// in _luma(), and there is no `not` keyword - every boolean test below uses `!`.
//
// These bodies are the ones `floor_setup.gdshader` shipped with since the grade
// sliders were introduced; moving them here changed no line of arithmetic, and
// the identity probe re-measures the floor against the imported material after
// the move to prove it.

float _luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}


vec3 _rgb_to_hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}


vec3 _hsv_to_rgb(vec3 c) {
	vec4 k = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + k.xyz) * 6.0 - k.www);
	return c.z * mix(k.xxx, clamp(p - k.xxx, vec3(0.0), vec3(1.0)), c.y);
}


/// The one grade chain, in this order: brightness, contrast about mid grey,
/// saturation about the luminance, then a hue turn. Identity is (1,1,1,0). The
/// parameters carry an `f_` prefix because each shader also declares a uniform of
/// the same name, and a function parameter shadowing a global is driver-fragile.
vec3 _grade(vec3 c, float f_brightness, float f_contrast, float f_saturation, float f_hue) {
	c *= f_brightness;
	c = (c - vec3(0.5, 0.5, 0.5)) * f_contrast + vec3(0.5, 0.5, 0.5);
	c = mix(vec3(_luma(c)), c, f_saturation);
	if (abs(f_hue) > 0.0001) {
		vec3 hsv = _rgb_to_hsv(clamp(c, vec3(0.0), vec3(1.0)));
		hsv.x = fract(hsv.x + f_hue);
		c = _hsv_to_rgb(hsv);
	}
	return c;
}


/// Distance from `uv` to the nearest edge of the quad, in UV units. Every room
/// surface is one quad whose UVs run 0..1 across the whole face - measured on the
/// live room, all six of them - so the border of the UV square *is* the seam with
/// the neighbouring surfaces: the floor's border is the four wall bases, a wall's
/// border is the floor line, the ceiling line and the two vertical corners, and
/// the ceiling's border is the four wall tops. One term therefore fits all of
/// them, it needs no second UV channel, and it cannot disturb a map the artist
/// tiled differently: the shading reads `UV` itself, while the colour keeps
/// reading the tiled coordinate.
float _border(vec2 uv) {
	return min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
}


/// Ambient occlusion, approximated analytically instead of from a baked map.
/// 1.0 away from the seams, `1 - strength` exactly on one, reached over
/// `radius` of UV space. Only ever multiplied into ALBEDO - never into ALPHA -
/// so an occluded corner cannot turn opaque and cover the reflection space.
float _ao(vec2 uv, bool enabled, float strength, float radius) {
	if (!enabled || strength <= 0.0 || radius <= 0.0) {
		return 1.0;
	}
	float b = clamp(_border(uv) / radius, 0.0, 1.0);
	return mix(1.0 - strength, 1.0, smoothstep(0.0, 1.0, b));
}
