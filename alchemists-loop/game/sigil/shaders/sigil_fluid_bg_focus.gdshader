shader_type canvas_item;
render_mode blend_mix, unshaded;

// Seedable, restrained material field for the card background only.
// The transmutation circle, frame, aura and central icon stay on their own layers.
uniform vec2 card_size = vec2(512.0, 704.0);
uniform vec4 color_deep : source_color = vec4(0.025, 0.040, 0.060, 1.0);
uniform vec4 color_mid : source_color = vec4(0.075, 0.125, 0.155, 1.0);
uniform vec4 color_hot : source_color = vec4(0.235, 0.365, 0.455, 1.0);

uniform float noise_scale = 1.65;
uniform float warp_amount = 0.38;
uniform float phase = 0.0;
uniform float contrast = 1.0;
// Slow, continuous procedural advection; set to 0.0 to freeze the field.
uniform float flow_speed = 0.075;

// -1 = infer from palette; 0 = flowing alchemical/metal; 1 = earth/sediment.
// Prefer setting this from result_family when that context is available.
uniform float material_mode = -1.0;

// A broad, low-strength lift near the circle's center; deliberately not a bloom.
uniform vec2 focus_uv = vec2(0.5, 0.39);
uniform float focus_radius = 0.58;
uniform float focus_strength = 0.065;

// Optional faint card-edge separation. Keep this weaker than the actual frame.
uniform float rim_offset_px = 16.0;
uniform float rim_width_px = 7.0;
uniform float rim_strength = 0.06;

uniform float vignette = 0.22;
uniform float edge_softness = 0.20;
uniform float shape_amount = 0.52;
uniform float grain = 0.009;

float hash21(vec2 p) {
	p = fract(p * vec2(233.34, 851.73));
	p += dot(p, p + 23.45);
	return fract(p.x * p.y);
}

vec2 hash22(vec2 p) {
	float n = hash21(p);
	return vec2(n, hash21(p + n));
}

float gnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = dot(hash22(i) * 2.0 - 1.0, f);
	float b = dot(hash22(i + vec2(1.0, 0.0)) * 2.0 - 1.0, f - vec2(1.0, 0.0));
	float c = dot(hash22(i + vec2(0.0, 1.0)) * 2.0 - 1.0, f - vec2(0.0, 1.0));
	float d = dot(hash22(i + vec2(1.0, 1.0)) * 2.0 - 1.0, f - vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 1.45;
}

float fbm(vec2 p, int octaves) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 6; i++) {
		if (i >= octaves) { break; }
		v += amp * gnoise(p);
		p = p * 2.03 + vec2(17.3, 9.1);
		amp *= 0.5;
	}
	return v;
}

void fragment() {
	float aspect = card_size.x / max(card_size.y, 1.0);
	vec2 aspect_scale = vec2(aspect, 1.0);
	// Older palettes may send noise_scale 1.7–3.1 and warp_amount up to 1.25;
	// cap both so a preset cannot restore the harsh static/wobble being removed.
	float stable_scale = clamp(noise_scale, 1.2, 1.8);
	float stable_warp = clamp(warp_amount, 0.15, 0.45);
	vec2 p = (UV - vec2(0.5)) * aspect_scale * stable_scale;

	// Slowly advect broad noise domains so the field reads as drifting fog,
	// not scrolling wallpaper. TIME is built in; no per-frame script update needed.
	float drift_time = TIME * clamp(flow_speed, 0.0, 0.16);
	vec2 drift_a = vec2(drift_time * 0.80, -drift_time * 0.48);
	vec2 drift_b = vec2(-drift_time * 0.56, drift_time * 0.76);

	// Slow, broad domain warp. Keep the movement low-frequency and restrained.
	vec2 q = vec2(
		fbm(p * 0.72 + drift_a + vec2(phase, 3.1), 3),
		fbm(p * 0.72 + drift_b + vec2(8.2, phase + 1.7), 3));
	vec2 warped = p + q * stable_warp;
	float macro_field = fbm(warped * 0.88 + vec2(2.4, phase * 0.7) + drift_b * 0.72, 4) * 0.5 + 0.5;
	float detail_field = fbm(warped * 1.55 + vec2(11.8, 5.6 + phase) + drift_a * 0.86, 3) * 0.5 + 0.5;
	float shape = clamp(shape_amount, 0.0, 1.0);
	float detail_mix = clamp(0.24 + 0.42 * shape, 0.24, 0.62);
	float field = clamp(mix(macro_field, detail_field, detail_mix), 0.0, 1.0);
	field = clamp(0.5 + (field - 0.5) * 2.90, 0.0, 1.0);
	float t = pow(field, 1.0 / clamp(contrast, 0.90, 1.10));

	// Broad color pools should read at card scale, not collapse into black static.
	float mid_mix = smoothstep(0.23, 0.77, t);
	vec3 col = mix(color_deep.rgb, color_mid.rgb, mid_mix);
	float pigment = smoothstep(0.62, 0.88, t) * 0.14;
	col = mix(col, color_hot.rgb, pigment);

	// Fine flowing traces for metal/alchemy; soft warped strata for raw earth.
	float inferred_mode = clamp(0.5 + (color_mid.r - color_mid.b) * 3.5, 0.0, 1.0);
	float mode = material_mode < -0.5 ? inferred_mode : clamp(material_mode, 0.0, 1.0);
	float flow_phase = p.x * 1.35 + p.y * 0.55 + q.x * 0.65 + phase * 0.30 + drift_time * 0.22;
	float flow_wave = 0.5 + 0.5 * sin(flow_phase * 3.14159);
	float flow_wash = smoothstep(0.22, 0.78, flow_wave);
	vec3 flow_tint = mix(color_mid.rgb, color_hot.rgb, 0.18 + 0.42 * flow_wash);
	col = mix(col, flow_tint, (1.0 - mode) * 0.22);
	float strata_phase = p.y * 3.0 + p.x * 0.36 + q.y * 0.92 + phase * 0.22 + drift_time * 0.16;
	float strata = 0.5 + 0.5 * sin(strata_phase * 3.14159);
	float sediment = smoothstep(0.23, 0.77, strata);
	sediment *= smoothstep(0.12, 0.92, macro_field);
	vec3 strata_tint = mix(color_deep.rgb, color_mid.rgb, 0.34 + 0.48 * sediment);
	col = mix(col, strata_tint, mode * 0.28);

	// A small, diffuse focus keeps the center legible without a saturated halo.
	float focus_d = length((UV - focus_uv) * aspect_scale);
	float focus = exp(-0.5 * pow(focus_d / max(focus_radius, 0.001), 2.0));
	vec3 focus_tint = mix(color_mid.rgb, color_hot.rgb, 0.18);
	col = mix(col, max(col, focus_tint), focus * clamp(focus_strength, 0.0, 0.08));

	float d = length((UV - vec2(0.5)) * aspect_scale);
	float vignette_mask = 1.0 - smoothstep(0.30, 0.88, d);
	col *= mix(1.0, vignette_mask, clamp(vignette, 0.0, 0.32));

	float ex = min(min(UV.x, 1.0 - UV.x) * card_size.x,
				   min(UV.y, 1.0 - UV.y) * card_size.y);
	float edge = smoothstep(0.0, max(edge_softness, 0.001) * 56.0, ex);
	col = mix(color_deep.rgb * 0.54, col, edge);

	float rim_sigma = max(rim_width_px, 0.75);
	float rim = exp(-0.5 * pow((ex - rim_offset_px) / rim_sigma, 2.0));
	col = mix(col, max(col, color_hot.rgb), clamp(rim * min(rim_strength, 0.10), 0.0, 0.12));

	// Cap values from older callers too: texture should read as material, not static.
	col += (hash21(UV * card_size + vec2(phase * 13.0)) - 0.5) * clamp(grain, 0.0, 0.010);
	COLOR = vec4(clamp(col, vec3(0.0), vec3(1.0)), 1.0);
}
