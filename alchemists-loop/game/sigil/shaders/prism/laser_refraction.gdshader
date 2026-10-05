shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

// Laser / Refraction — два мягких спектральных луча ПОВЕРХ карты.
// База (screen_tex) остаётся; лучи — полупрозрачные засветки.

uniform float phase = 0.0;
uniform float speed : hint_range(0.01, 2.0) = 0.65;
uniform float intensity : hint_range(0.0, 1.0) = 0.5;
uniform float frequency : hint_range(1.0, 50.0) = 20.0;

void fragment() {
    vec2 screen_uv = SCREEN_UV;
    vec2 screen_px = 1.0 / vec2(textureSize(screen_tex, 0));
    vec4 base = texture(screen_tex, screen_uv);
    float aspect = screen_px.y / screen_px.x;
    float t = phase * speed;
    vec2 p = vec2((screen_uv.x - 0.5) * aspect, screen_uv.y - 0.5);
    vec2 beam_axis = normalize(vec2(0.68, 0.73));
    float coordinate = dot(p, beam_axis);

    float sweep_orbit = sin(t * 0.72 + 0.68);
    float sweep_a = 0.39 * sweep_orbit;
    float sweep_b = -0.39 * sweep_orbit;
    float signed_a = coordinate - sweep_a;
    float signed_b = coordinate - sweep_b;
    float distance_a = abs(signed_a);
    float distance_b = abs(signed_b);

    float glow_a = exp(-distance_a * distance_a * 2.2) * 0.55;
    float glow_b = exp(-distance_b * distance_b * 2.2) * 0.55;
    float transverse = sin(t * frequency * 0.05) * 0.5;
    float ripple_a = (0.5 + 0.5 * sin(signed_a * frequency * 4.0 + transverse * 9.0)) * glow_a;
    float ripple_b = (0.5 + 0.5 * sin(signed_b * frequency * 4.0 - transverse * 9.0)) * glow_b;

    // Спектральный градиент луча: от голубого к фиолетовому/оранжевому.
    vec3 beam_a = vec3(0.35, 0.62, 1.0);
    vec3 beam_b = vec3(0.85, 0.35, 0.95);
    vec3 col = base.rgb;
    col += beam_a * (glow_a * 0.6 + ripple_a * 0.4) * intensity;
    col += beam_b * (glow_b * 0.6 + ripple_b * 0.4) * intensity;
    float al = max(base.a, (glow_a + glow_b) * intensity * 0.55);
    COLOR = vec4(col, clamp(al, 0.0, 1.0));
}