shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform sampler2D screen_mip_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

// 辉光：自带 WorldEnvironment glow 已关闭（省 ~10ms），辉光全交给这里。
// 这几项做成 uniform 可在 Inspector 实时调，且全程免费（不进光线步进循环）。
uniform float bloom_strength = 0.16;   // 辉光强度（提高补回被关掉的 glow + 填丝间暗隙）
uniform float bloom_threshold = 0.32;  // 发光阈值（调低让更多盘面发光，填亮丝间暗隙）
uniform float scene_exposure = 1.0;    // 整体曝光乘子（>1 更亮）
const float BLOOM_KNEE = 0.48;
const float DETAIL_STRENGTH = 0.22;
const float HIGHLIGHT_DETAIL_KEEP = 0.24;
// 负向锐化（挖暗隙）的保留比例。亮丝间的缝被全力压黑会在多普勒过曝侧戳出黑点，
// 所以正向锐化全留、负向只留这点。
const float DETAIL_NEG_KEEP = 0.10;
// 局部暗点填充：盘内像素不得暗于邻域均值的此比例（堵黑点）；填充混合强度。
const float SPECKLE_FLOOR_RATIO = 0.5;
const float SPECKLE_FILL_STRENGTH = 0.7;
const float REFERENCE_GRADE_STRENGTH = 0.86;

float Luminance(vec3 color) {
    return dot(color, vec3(0.299, 0.587, 0.114));
}

vec3 Saturate(vec3 color) {
    return clamp(color, vec3(0.0), vec3(1.0));
}

vec3 BloomLod(vec2 uv, float lod, float weight) {
    vec3 color = textureLod(screen_mip_texture, uv, lod).rgb;
    float luma = Luminance(color);
    float gate = smoothstep(bloom_threshold, bloom_threshold + BLOOM_KNEE, luma);
    return color * gate * weight;
}

vec3 GetReferenceBloom(vec2 uv) {
    vec3 bloom = vec3(0.0);
    bloom += BloomLod(uv, 1.0, 1.0);
    bloom += BloomLod(uv, 2.0, 1.5);
    bloom += BloomLod(uv, 3.0, 1.0);
    bloom += BloomLod(uv, 4.0, 1.5);
    bloom += BloomLod(uv, 5.0, 1.8);
    bloom += BloomLod(uv, 6.0, 1.0);
    bloom += BloomLod(uv, 7.0, 1.0);
    bloom += BloomLod(uv, 8.0, 1.0);
    return bloom;
}

vec3 ReferenceTonemap(vec3 color) {
    color = max(color, vec3(0.0));
    color = pow(color, vec3(1.5));
    color = color / (vec3(1.0) + color);
    color = pow(color, vec3(1.0 / 1.5));
    color = color * color * (vec3(3.0) - 2.0 * color);
    color = pow(max(color, vec3(0.0)), vec3(1.3, 1.20, 1.0));
    color = Saturate(color * 1.01);
    color = pow(color, vec3(0.7 / 2.2));
    return Saturate(color);
}

void fragment() {
    vec2 uv = SCREEN_UV;
    vec3 source = texture(screen_texture, uv).rgb * scene_exposure;
    float source_luma = Luminance(source);

    vec3 bloom = GetReferenceBloom(uv) * bloom_strength;
    vec3 soft = textureLod(screen_mip_texture, uv, 1.2).rgb;
    vec3 detail = source - soft;
    // 削弱负向锐化（暗隙），保留正向（亮丝核心），避免在过曝侧把缝挖成黑点。
    vec3 detail_shaped = max(detail, vec3(0.0)) + min(detail, vec3(0.0)) * DETAIL_NEG_KEEP;
    // 锐化在中间调最强，过曝高光处收手（黑点正是在高光区被挖出来的）。
    float detail_gate = smoothstep(0.06, 0.40, source_luma) * (1.0 - 0.9 * smoothstep(0.62, 0.98, source_luma));

    vec3 color = source + bloom;
    color += detail_shaped * DETAIL_STRENGTH * detail_gate;

    // 局部暗点填充：邻域越亮（= 盘内），就不允许像素暗于邻域均值的一定比例，
    // 直接堵死被亮丝包围的黑点；邻域暗（空旷星空）则完全不动，保住黑背景。
    float neighborhood = Luminance(soft);
    float speckle_fill = smoothstep(0.22, 0.62, neighborhood) * SPECKLE_FILL_STRENGTH;
    color = mix(color, max(color, soft * SPECKLE_FLOOR_RATIO), speckle_fill);

    vec3 graded = ReferenceTonemap(color);
    color = mix(color, graded, REFERENCE_GRADE_STRENGTH);

    float highlight_keep = smoothstep(0.66, 1.0, source_luma) * HIGHLIGHT_DETAIL_KEEP;
    color = mix(color, Saturate(source + detail_shaped * 0.34 + bloom * 0.28), highlight_keep);

    COLOR = vec4(Saturate(color), 1.0);
}
