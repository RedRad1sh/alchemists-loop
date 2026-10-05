shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

// Textured Foil — микротекстура волокон/зерна со спектральной засветкой
// ПОВЕРХ карты. База (screen_tex) остаётся, сверху глянец фольги.

uniform float phase = 0.0;
uniform float speed : hint_range(0.01, 1.0) = 0.55;
uniform float intensity : hint_range(0.0, 1.0) = 0.3;
uniform vec4 foil_color : source_color = vec4(0.79, 0.91, 1.0, 1.0);
uniform float line_density : hint_range(20.0, 500.0) = 112.0;
uniform float noise_amt : hint_range(0.0, 1.0) = 0.38;

float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + vec2(1.0, 0.0));
    float c = hash21(i + vec2(0.0, 1.0));
    float d = hash21(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
    vec2 screen_uv = SCREEN_UV;
    vec2 screen_px = 1.0 / vec2(textureSize(screen_tex, 0));
    vec4 base = texture(screen_tex, screen_uv);
    float aspect = screen_px.y / screen_px.x;
    float t = phase * speed;
    vec2 p = vec2(screen_uv.x * aspect, screen_uv.y);
    float carrier = dot(p, normalize(vec2(0.92, 0.39)));

    float grain = value_noise(p * line_density * 0.22 + vec2(13.2, 7.4));
    float fleck = hash21(floor(p * line_density * 0.62));
    float surface = mix(grain, fleck, noise_amt);
    float fiber_wave = sin(carrier * line_density + (grain - 0.5) * 0.72);
    float fiber = 0.5 + 0.5 * fiber_wave;
    float ridge = pow(max(0.0, sin(carrier * line_density + (grain - 0.5) * 1.2)), 3.0);

    // Спектральная засветка движется по карте.
    float sheen_pos = fract(carrier * 0.6 + t * 0.35);
    vec3 spectral = 0.5 + 0.5 * cos(sheen_pos * 6.2831 + vec3(0.0, 2.094, 4.189));
    float sheen = smoothstep(0.30, 0.70, sheen_pos) * (1.0 - smoothstep(0.70, 1.05, sheen_pos));

    vec3 foil = mix(base.rgb, foil_color.rgb * (0.55 + 0.45 * fiber), 
                    (0.18 * surface + 0.30 * ridge) * intensity);
    foil += spectral * sheen * 0.35 * intensity;
    float al = max(base.a, (grain * 0.12 + ridge * 0.30 + sheen * 0.4) * intensity);
    COLOR = vec4(foil, clamp(al, 0.0, 1.0));
}