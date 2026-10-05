shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

// Shattered Glass — преломляющие фасетки и трещины ПОВЕРХ карты.
// База (screen_tex) остаётся; осколки дают блики/фаски, не заливку.

uniform float phase = 0.0;
uniform float speed : hint_range(0.01, 1.0) = 0.55;
uniform float intensity : hint_range(0.0, 1.0) = 0.92;
uniform float scale : hint_range(2.0, 20.0) = 7.0;
uniform vec4 crack_color : source_color = vec4(0.78, 0.96, 1.0, 1.0);

float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec2 hash22(vec2 p) {
    return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}

vec4 voronoi_data(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    float min_d = 8.0;
    vec2 min_site = vec2(0.0);
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 cell = vec2(float(x), float(y));
            vec2 site = hash22(i + cell);
            vec2 r = cell + site - f;
            float d = dot(r, r);
            if (d < min_d) {
                min_d = d;
                min_site = i + cell + site;
            }
        }
    }
    return vec4(sqrt(min_d), min_site.x, min_site.y, 1.0);
}

void fragment() {
    vec2 screen_uv = SCREEN_UV;
    vec2 screen_px = 1.0 / vec2(textureSize(screen_tex, 0));
    vec4 base = texture(screen_tex, screen_uv);
    float aspect = screen_px.y / screen_px.x;
    float t = phase * speed;

    vec2 p = vec2(screen_uv.x * aspect, screen_uv.y) * scale;
    vec4 cell = voronoi_data(p);
    float edge_distance = cell.x;
    vec2 cell_id = floor(cell.yz);
    float cell_hash = hash21(cell_id);
    vec2 random_normal = hash22(cell_id + vec2(5.2, 2.9)) * 2.0 - 1.0;
    vec2 facet_normal = normalize(random_normal + vec2(0.001, 0.002));

    vec2 light_dir = normalize(vec2(cos(t * 0.75), sin(t * 0.75)));
    float diffuse = max(0.0, dot(facet_normal, light_dir));
    float rim = pow(1.0 - abs(dot(facet_normal, light_dir)), 3.0);

    float edge = 1.0 - smoothstep(0.0, 0.055, edge_distance);
    float crack = edge * 0.35 + pow(edge, 2.0) * 0.65;

    vec3 glass_col = base.rgb + crack_color.rgb * crack * 0.35 * intensity;
    glass_col += (diffuse * 0.4 + rim * 0.5) * intensity;
    float al = max(base.a, crack * 0.6 * intensity);
    COLOR = vec4(glass_col, clamp(al, 0.0, 1.0));
}