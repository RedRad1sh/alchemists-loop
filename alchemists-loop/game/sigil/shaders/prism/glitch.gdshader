shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

// Glitch — смягчённые разрывы и RGB-сдвиг ПОВЕРХ карты.
// База (screen_tex) остаётся; сдвиг строк/каналов не заливает фон.

uniform float phase = 0.0;
uniform float speed : hint_range(0.1, 10.0) = 2.4;
uniform float intensity : hint_range(0.0, 1.0) = 0.62;
uniform float block_size : hint_range(0.01, 0.5) = 0.085;
uniform float color_shift : hint_range(0.0, 0.1) = 0.018;

float hash1(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float hash1(float x) {
    return fract(sin(x * 127.1) * 43758.5453);
}

void fragment() {
    vec2 screen_uv = SCREEN_UV;
    vec2 screen_px = 1.0 / vec2(textureSize(screen_tex, 0));
    vec4 base = texture(screen_tex, screen_uv);
    float t = phase * speed;
    float frame_id = floor(t * 24.0);
    float aspect = screen_px.y / screen_px.x;

    float block = floor(screen_uv.y / block_size);
    float row = floor(screen_uv.y * 72.0);
    float trigger = step(0.77, hash1(block + frame_id * 13.7));
    float row_trigger = step(0.86, hash1(row + frame_id * 31.1));
    float random_shift = (hash1(block * 7.1 + frame_id * 5.3) - 0.5) * 0.18;
    float shift = (random_shift * trigger + (hash1(row + frame_id * 2.7) - 0.5) * 0.045 * row_trigger) * intensity;

    float burst = step(0.92, hash1(block * 3.3 + frame_id * 47.0));
    float wave = 0.5 + 0.5 * sin(screen_uv.y * 24.0 + t * 2.3);

    vec2 shifted_uv = screen_uv + vec2(shift * aspect, 0.0);
    vec4 shifted = texture(screen_tex, shifted_uv);

    // RGB-расщепление только на активных строках.
    float r_x = color_shift * (trigger + row_trigger * 0.4 + burst * 0.6);
    float b_x = -r_x * 0.7;
    vec3 col;
    col.r = texture(screen_tex, screen_uv + vec2(r_x * aspect, 0.0)).r;
    col.g = shifted.g;
    col.b = texture(screen_tex, screen_uv + vec2(b_x * aspect, 0.0)).b;

    // Мягкое затухание — разрывы не «выжигают» фон.
    float act = clamp(trigger * 0.6 + row_trigger * 0.5 + burst * 0.8 * wave, 0.0, 1.0) * intensity;
    col = mix(base.rgb, col, act);

    float al = max(base.a, act * 0.7);
    COLOR = vec4(col, clamp(al, 0.0, 1.0));
}