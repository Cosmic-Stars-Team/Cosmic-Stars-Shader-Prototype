shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform sampler2D screen_mip_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

const float BLOOM_THRESHOLD = 0.52;
const float BLOOM_KNEE = 0.48;
const float BLOOM_STRENGTH = 0.050;
const float DETAIL_STRENGTH = 0.24;
const float HIGHLIGHT_DETAIL_KEEP = 0.42;
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
    float gate = smoothstep(BLOOM_THRESHOLD, BLOOM_THRESHOLD + BLOOM_KNEE, luma);
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
    vec3 source = texture(screen_texture, uv).rgb;
    float source_luma = Luminance(source);

    vec3 bloom = GetReferenceBloom(uv) * BLOOM_STRENGTH;
    vec3 soft = textureLod(screen_mip_texture, uv, 1.2).rgb;
    vec3 detail = source - soft;

    vec3 color = source + bloom;
    color += detail * DETAIL_STRENGTH * smoothstep(0.06, 0.86, source_luma);

    vec3 graded = ReferenceTonemap(color);
    color = mix(color, graded, REFERENCE_GRADE_STRENGTH);

    float highlight_keep = smoothstep(0.66, 1.0, source_luma) * HIGHLIGHT_DETAIL_KEEP;
    color = mix(color, Saturate(source + detail * 0.34 + bloom * 0.28), highlight_keep);

    COLOR = vec4(Saturate(color), 1.0);
}
