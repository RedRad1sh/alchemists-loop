// Frosted floor: a screen-aligned nine-tap blur of the reflection-only
// SubViewport texture, painted on the quad that sits just under the room floor.
// The viewport camera clones the main one, so SCREEN_UV addresses both images.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never,
		shadows_disabled, specular_disabled, fog_disabled;

// source_color matters: the viewport texture already left the mirror camera with
// tonemapping and sRGB encoding applied. Without the hint the main pass would
// encode those values a second time and the frosted floor would be far too bright.
uniform sampler2D refl_tex : source_color, filter_linear;
// blur_pixels is the radius in main-viewport pixels; texel converts it to UV.
uniform float blur_pixels = 3.5;
uniform float texel = 0.001;
uniform float intensity = 1.0;

// The floor footprint as it lands on the screen, pushed every frame by
// scripts/reflection_blur.gd. `clip_to_floor` makes this quad exactly the room's
// floor, so its projection is the diamond the floor draws: the two half-axes are
// that diamond's diagonals, and the two weight vectors are the rows of their
// inverse. All-zero weights mean "nothing measured yet" and switch the clamp off,
// so a first frame without a camera cannot pull every tap to the middle of the
// screen.
uniform bool clamp_to_footprint = false;
uniform vec2 quad_center_uv = vec2(0.5, 0.5);
uniform vec2 quad_axis_x_uv = vec2(0.25, 0.0);
uniform vec2 quad_axis_z_uv = vec2(0.0, 0.25);
uniform vec2 axis_weights_x = vec2(0.0, 0.0);
uniform vec2 axis_weights_z = vec2(0.0, 0.0);
// Where the footprint's own border sits in `st`. `quad_axis_x_uv` is the UV from
// the quad centre to one edge, so a unit offset along it lands exactly on that
// edge and the border is at +/-1. The value this shipped with before
// scripts/reflection_blur.gd's `clamp_at_room_edge` existed is 0.5, which folds
// every fragment beyond half the floor onto its mid-line: see the export.
uniform float footprint_border = 1.0;

// The last half of the same seam, one pixel wide. `clamp_to_footprint` keeps the
// nine taps inside the room, and scripts/reflection_blur.gd's `screen_edge_match`
// lands the quad's outline on the floor's outline, but the floor map is only about
// 69 % opaque, so its own anti-aliased edge pixels still let the film through at
// nearly full strength: that thin bright ring on the two near edges (the ones whose
// walls the camera culls, meeting at the bottom corner) is the line the user reads
// as garbage at floor brightness 0. `edge_fade` ramps the film's own alpha to 0
// across the outer `edge_fade_st` of the footprint, so those edge pixels reveal the
// black void behind the floor instead of the mirror, and the line blends into the
// void rather than standing out against it. All-zero `edge_fade_st` (or the weights
// being all-zero, i.e. nothing measured yet) leaves the film's edge hard, exactly as
// before this existed.
uniform bool edge_fade = false;
uniform vec2 edge_fade_st = vec2(0.0, 0.0);


// The fragment's position in footprint space: (0,0) is the quad centre, each axis
// runs -0.5..0.5 from one floor edge to the other. Same two dot products the tap
// clamp uses, but without the clamp so the distance to the border is measurable.
vec2 _st_of(vec2 u) {
	vec2 d = u - quad_center_uv;
	return vec2(dot(d, axis_weights_x), dot(d, axis_weights_z));
}


// The tap position folded back to the nearest point of the projected footprint.
//
// Nine taps reach `blur_pixels` in every direction, and nothing stops them leaving
// the floor's own footprint: the innermost few pixels of the floor along its four
// edges then average in what the mirror texture holds outside the room - the black
// background and the black closure masks. That is the band the user reads as
// garbage along the bottom edge of the floor, where the two walls the camera culls
// leave the floor's edge uncovered: at floor brightness 1 the graded texture swamps
// it, at 0 the floor is mostly the mirror behind it and the band is the edge.
// Clamped taps take the footprint's own border value instead of the void, which is
// what a blur kernel is supposed to do at an edge.
vec2 _footprint_uv(vec2 u) {
	if (!clamp_to_footprint
			|| abs(axis_weights_x.x) + abs(axis_weights_x.y)
					+ abs(axis_weights_z.x) + abs(axis_weights_z.y) <= 0.0) {
		return u;
	}
	vec2 st = _st_of(u);
	// The footprint's own border, i.e. the quad's edge.
	st = clamp(st, vec2(-footprint_border, -footprint_border),
			vec2(footprint_border, footprint_border));
	return quad_center_uv + st.x * quad_axis_x_uv + st.y * quad_axis_z_uv;
}


void fragment() {
	vec2 offs = vec2(blur_pixels * texel);
	vec2 u = _footprint_uv(SCREEN_UV);
	// Nine taps: centre, four axis neighbours, four diagonals (x0.7071 keeps the
	// radius isotropic). Unrolled because Godot's shading language has no const
	// array literal, and a loop would only re-add index cost to a 9-tap kernel.
	// Each tap goes through _footprint_uv separately, so it is the kernel that is
	// clamped: a tap one pixel past the floor edge contributes the edge's value.
	vec4 sum = texture(refl_tex, u);
	sum += texture(refl_tex, _footprint_uv(u + vec2(offs.x, 0.0)));
	sum += texture(refl_tex, _footprint_uv(u + vec2(-offs.x, 0.0)));
	sum += texture(refl_tex, _footprint_uv(u + vec2(0.0, offs.y)));
	sum += texture(refl_tex, _footprint_uv(u - vec2(0.0, offs.y)));
	sum += texture(refl_tex, _footprint_uv(u + vec2(offs.x, offs.y) * 0.7071));
	sum += texture(refl_tex, _footprint_uv(u + vec2(-offs.x, offs.y) * 0.7071));
	sum += texture(refl_tex, _footprint_uv(u + vec2(offs.x, -offs.y) * 0.7071));
	sum += texture(refl_tex, _footprint_uv(u + vec2(-offs.x, -offs.y) * 0.7071));
	vec4 avg = sum / 9.0;
	float a = avg.a * intensity;
	// Ramp the film's own alpha to 0 across the outer edge of the footprint so the
	// floor's semi-transparent edge pixels reveal the void, not the mirror. The
	// footprint's own border sits at st = +/-1 (a unit offset along an axis lands on
	// the quad's edge), the same place `footprint_border` clamps the taps to.
	if (edge_fade) {
		vec2 st = _st_of(SCREEN_UV);
		vec2 border = vec2(1.0) - abs(st);
		vec2 f = clamp(border / max(edge_fade_st, vec2(1.0e-5)), vec2(0.0), vec2(1.0));
		a *= min(f.x, f.y);
	}
	ALBEDO = avg.rgb;
	ALPHA = a;
}
