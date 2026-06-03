shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

const float BLOOM_THRESHOLD = 0.68;
const float BLOOM_STRENGTH = 0.15;
const float DETAIL_STRENGTH = 0.16;
const float SHADOW_CRUSH = 0.12;
const float MID_CONTRAST = 1.12;
const float GRADE_STRENGTH = 0.72;
const float HIGHLIGHT_DETAIL_KEEP = 0.22;

float Luminance(vec3 color) {
    return dot(color, vec3(0.299, 0.587, 0.114));
}

vec3 Saturate(vec3 color) {
    return clamp(color, vec3(0.0), vec3(1.0));
}

vec3 AcesFitted(vec3 color) {
    vec3 a = color * (2.51 * color + vec3(0.03));
    vec3 b = color * (2.43 * color + vec3(0.59)) + vec3(0.14);
    return Saturate(a / b);
}

vec3 BloomLod(vec2 uv, float lod) {
    vec3 color = textureLod(screen_texture, uv, lod).rgb;
    float luma = Luminance(color);
    return color * smoothstep(BLOOM_THRESHOLD, 1.0, luma);
}

void fragment() {
    vec2 uv = SCREEN_UV;
    vec3 source = texture(screen_texture, uv).rgb;

    vec3 bloom =
        BloomLod(uv, 1.8) * 0.55 +
        BloomLod(uv, 3.2) * 0.32 +
        BloomLod(uv, 5.0) * 0.18;

    vec3 soft = textureLod(screen_texture, uv, 2.2).rgb;
    float source_luma = Luminance(source);
    vec3 detail = source - soft;

    vec3 color = source;
    color += bloom * BLOOM_STRENGTH;
    color += detail * DETAIL_STRENGTH * smoothstep(0.08, 0.80, source_luma);

    float shadow = 1.0 - smoothstep(0.02, 0.22, source_luma);
    color *= 1.0 - SHADOW_CRUSH * shadow;

    float mid = smoothstep(0.10, 0.72, source_luma) * (1.0 - smoothstep(0.78, 1.0, source_luma));
    color = mix(color, (color - vec3(0.5)) * MID_CONTRAST + vec3(0.5), mid);

    float warm_mid = smoothstep(0.10, 0.58, source_luma) * (1.0 - smoothstep(0.66, 0.94, source_luma));
    float cool_high = smoothstep(0.62, 1.0, source_luma);
    color *= mix(vec3(1.0), vec3(1.05, 0.97, 0.86), warm_mid * 0.28);
    color *= mix(vec3(1.0), vec3(0.90, 0.98, 1.16), cool_high * 0.24);

    vec3 graded = AcesFitted(max(color * 1.08, vec3(0.0)));
    float highlight_keep = smoothstep(0.72, 1.0, source_luma) * HIGHLIGHT_DETAIL_KEEP;
    color = mix(color, graded, GRADE_STRENGTH);
    color = mix(color, Saturate(source + detail * 0.18), highlight_keep);

    COLOR = vec4(Saturate(color), 1.0);
}
