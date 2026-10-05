shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

// Oil Slick — тонкоплёночная интерференция ПОВЕРХ карты.
// Семплирует уже отрисованное (screen_tex): карта остаётся видимой,
// сверху ложатся цветные разводы с сохранением её альфы.

uniform float phase = 0.0;
uniform float speed : hint_range(0.01, 1.0) = 0.42;
uniform float intensity : hint_range(0.0, 1.0) = 0.88;
uniform float scale : hint_range(1.0, 20.0) = 5.0;
uniform float bands : hint_range(1.0, 30.0) = 8.0;

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
    vec2 p = (screen_uv - vec2(0.5)) * vec2(aspect, 1.0) * scale;

    float distortion = (value_noise(p * 2.6 + vec2(t * 0.17, -t * 0.11)) - 0.5) * 1.8;
    distortion += sin(p.x * 2.4 + t) * cos(p.y * 2.1 - t * 0.8) * 0.22;
    float radius = length(p * vec2(1.0, 0.82)) + distortion;
    float film = radius * bands * 1.55 + t * 1.7;

    vec3 interference = 0.5 + 0.5 * cos(film + vec3(0.0, 2.094, 4.189));
    float ring_glint = pow(max(0.0, cos(film * 0.5 + 0.4)), 9.0);
    float broad_sheen = 0.5 + 0.5 * sin(film * 0.42 + p.x * 1.5 - t);
    vec3 oil = interference * (0.55 + 0.45 * broad_sheen);
    oil += vec3(0.42, 0.56, 0.8) * ring_glint * 0.72;
    oil *= 0.72 + 0.28 * value_noise(p * 7.0 + vec2(0.0, t * 0.4));

    // Микс с базой: разводы как цветная дымка поверх, не заливка фона.
    vec3 effect = mix(base.rgb, mix(base.rgb, oil, 0.55), intensity);
    COLOR = vec4(effect, base.a);
}