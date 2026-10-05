shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

// Galaxy / Cosmic — фоновая надстройка ПОД центральным объектом.
// Туманность видна постоянно (не «проявляется»), плавно дрейфует по фазе.

uniform float phase = 0.0;
uniform float speed : hint_range(0.01, 1.0) = 0.65;
uniform float intensity : hint_range(0.0, 1.0) = 0.9;
uniform vec4 nebula_a : source_color = vec4(0.45, 0.10, 0.80, 1.0);
uniform vec4 nebula_b : source_color = vec4(0.10, 0.55, 0.95, 1.0);
uniform vec4 nebula_c : source_color = vec4(0.95, 0.45, 0.20, 1.0);
uniform float star_density : hint_range(10.0, 100.0) = 42.0;
uniform float star_size : hint_range(0.5, 4.0) = 1.5;

float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec2 hash22(vec2 p) {
    return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
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

float fbm(vec2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 5; i++) {
        value += amplitude * value_noise(p);
        p *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

void fragment() {
    vec2 screen_uv = SCREEN_UV;
    vec2 screen_px = 1.0 / vec2(textureSize(screen_tex, 0));
    vec4 base = texture(screen_tex, screen_uv);
    float aspect = screen_px.y / screen_px.x;
    float t = phase * speed;

    vec2 p = (screen_uv - vec2(0.5)) * vec2(aspect, 1.0) * 3.0;
    vec2 flow_a = vec2(cos(t * 0.40), sin(t * 0.40)) * 0.34;
    vec2 flow_b = vec2(cos(t * 0.31 + 2.1), sin(t * 0.31 + 2.1)) * 0.28;
    vec2 warp = vec2(
        fbm(p * 1.05 + flow_a + vec2(2.1, 7.4)),
        fbm(p * 1.05 + flow_b + vec2(-3.8, 1.7))
    ) - vec2(0.5);

    float cloud_base = fbm(p * 1.15 + warp * 1.35 + flow_a * 0.62);
    float cloud_detail = fbm(p * 2.35 + warp * 0.78 - flow_b * 0.52);
    float field = cloud_base * 0.66 + cloud_detail * 0.34;
    float cloud_haze = smoothstep(0.18, 0.72, field);
    float cloud_body = smoothstep(0.38, 0.80, field);
    float cloud = clamp(cloud_haze * 0.55 + cloud_body * 0.45, 0.0, 1.0);
    float filament_noise = fbm(p * 4.7 + warp * 1.2 + flow_b * 0.44);
    float filament_region = cloud_haze * smoothstep(0.32, 0.78, field);
    float filament = (1.0 - smoothstep(0.035, 0.14, abs(filament_noise - 0.5))) * filament_region;

    // Три цветовых пятна тумана: фиолетовое, голубое, тёплое.
    float n1 = fbm(p * 1.6 + vec2(0.0, t * 0.12) + warp * 0.6);
    float n2 = fbm(p * 1.9 + vec2(t * 0.09, 3.1) + warp * 0.5);
    float n3 = fbm(p * 2.2 + vec2(-t * 0.07, 6.2) + warp * 0.4);
    vec3 nebula = mix(nebula_a.rgb, nebula_b.rgb, n1);
    nebula = mix(nebula, nebula_c.rgb, n2 * 0.55);
    nebula *= 0.75 + 0.45 * n3;   // пятнистость

    // Основа: туман виден ВСЕГДА (не зависит от cloud), но его плотность
    // модулируется пятнами — так космос видно в каждом кадре.
    float density = 0.30 + 0.55 * cloud * intensity;
    vec3 col = mix(base.rgb, nebula, density);
    col += nebula * filament * 0.30 * intensity;

    // Звёзды: редкие, мелкие, мерцают от фазы.
    vec2 sp = p * 2.1;
    vec2 cell = floor(sp);
    vec2 lpos = hash22(cell) * 0.55 + 0.45;
    float star_h = hash21(cell);
    float star = step(1.0 - star_density * 0.006, star_h) * step(0.02, hash21(cell + 9.1));
    float twinkle = 0.5 + 0.5 * sin(t * 3.0 + hash21(cell + 3.7) * 12.0);
    float d2 = length(fract(sp) - lpos);
    float star_glow = smoothstep(star_size * 0.05, 0.0, d2) * star * twinkle * 0.8;

    vec3 out_col = col + vec3(1.0) * star_glow * intensity;
    // Альфа: туман полупрозрачен, фон (base.a) всегда проходит.
    float out_alpha = max(base.a, 0.35 + cloud * 0.45 * intensity);
    COLOR = vec4(out_col, out_alpha);
}