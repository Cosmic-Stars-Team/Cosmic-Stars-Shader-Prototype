shader_type spatial;

render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never;

uniform float Rs = 4.0;
uniform float gravity_strength = 1.0;
uniform int steps = 512;
uniform float disk_tilt = -0.3;
uniform float disk_inner_radius_ratio = 2.5;
uniform float disk_outer_radius_ratio = 7.6;
uniform float disk_thickness_ratio = 0.62;
uniform float disk_noise_amount = 1.1;
uniform float disk_temperature_scale = 0.71;
uniform float output_exposure = 0.9;

uniform sampler2D sky_texture : filter_nearest;
uniform sampler2D blackbody_lut : filter_linear, repeat_disable;
uniform sampler2D far_field_deflection_lut : filter_linear, repeat_disable;
// (b) Quick perf-validation: a tiling 3D noise texture (NoiseTexture3D / FastNoiseLite).
// PerlinNoise() samples this instead of computing the 8-corner hash, to measure how
// much the texture fetch saves. Visual will differ from the procedural noise until we
// bake a pixel-identical version.
uniform sampler3D noise_texture : filter_linear, repeat_enable;
uniform float noise_texture_scale = 0.15;

const float BASE_STEP = 0.02;
const float TIME_RATE = 8.0;
const float TIME_OVERRIDE = -1.0;
const float SHIFT_MAX = 2.6;
const float DISK_VISUAL_ROTATE_SPEED = 0.18;
const float DISK_OUTER_SPIN_RATIO = 0.6;
const float DISK_VISUAL_TIME_SCALE = 0.02;
const float DISK_NOISE_SCALE = 1.1;
const float DISK_NOISE_CONTRAST = 80.0;
const float DISK_TEMPERATURE_ARGUMENT = 1.4e19;
const float PEAK_TEMPERATURE_POW4 = 5.665278e18;
const float DISK_TEMP_KELVIN_MIN = 1200.0;
const float DISK_TEMP_KELVIN_MAX = 22000.0;
const float DISK_WHITE_MIX = 0.002;
const float DISK_BRIGHTNESS_FLOOR = 0.0045;
const float DISK_RGB_FLOOR = 0.0025;
const float BEAMING_SPECTRAL_INDEX = 0.1;
const float BEAMING_STRENGTH = 0.58;
const float BEAMING_CLAMP = 15.0;
const float BLOOM_THRESHOLD = 0.92;
const float BLOOM_EMISSION = 4.05;
const float HDR_BLOOM_KNEE = 0.62;
const float HDR_EMISSION_GAIN = 1.26;
const float USE_REINHARD_TONEMAP = 0.0;
const float EMISSION_SOFT_CLIP = 0.72;
const float DISK_HAZE_CONTRAST = 0.66;
const float DISK_OPACITY_GAIN = 0.88;
const float DISK_CORE_OPACITY_GAIN = 1.28;
const float DISK_GLOBAL_BRIGHTNESS = 1.62;
// A: scales the hand-tuned artistic emission additions. 1.0 = current Godot look;
// lower toward 0.0 to let the example's physical T^4 * KelvinToRgb core dominate.
const float DISK_ARTISTIC_EMISSION = 0.35;
const float DISK_BLUE_SIDE_BOOST = 2.10;
const float DISK_RED_SIDE_FILL = 1.55;
const float DISK_RADIAL_LAYER_STRENGTH = 0.52;
const float DISK_FINE_LAYER_STRENGTH = 0.36;
const float DISK_MICRO_LAYER_STRENGTH = 0.20;
const float DISK_MICRO_FILAMENT_STRENGTH = 0.48;
const float DISK_MIDLINE_SHADOW_STRENGTH = 0.20;
const float DISK_LAYER_SHADOW_STRENGTH = 0.28;
const float DISK_EDGE_SOFTNESS_RS = 0.12;
const float DISK_VERTICAL_EDGE_SOFTNESS = 0.22;
const float DISK_LENSED_ARC_DETAIL = 0.72;
const float DISK_LENSED_ARC_DUST_SUPPRESS = 0.42;
const float LENS_SKY_BOOST = 0.25;
const float LENS_STAR_BOOST = 5.0;
const float FAR_FIELD_BOUNDARY_RS = 15.0;
const float BLACKBODY_LUT_MAX_TEMPERATURE_K = 40000.0;
const bool USE_FAR_FIELD_LUT = true;

const vec3 DISK_WARM_TINT = vec3(1.00, 0.84, 0.58);
const vec3 DISK_HOT_TINT = vec3(0.52, 0.94, 1.96);
const vec3 DISK_RIM_TINT = vec3(0.58, 1.02, 2.08);
const vec3 DISK_WHITE_TINT = vec3(1.16, 1.14, 1.04);
const vec3 DISK_BLUE_RIM_EMISSION = vec3(0.58, 1.18, 3.05);
const vec3 DISK_RED_FILL_EMISSION = vec3(3.10, 0.055, 0.010);
const vec3 DISK_DUST_TINT = vec3(0.86, 0.38, 0.13);
const vec3 DISK_SHADOW_TINT = vec3(0.58, 0.40, 0.26);
const vec3 DISK_FILAMENT_WARM_TINT = vec3(1.24, 0.78, 0.44);
const vec3 DISK_FILAMENT_HOT_TINT = vec3(0.46, 0.94, 2.08);
const vec3 DISK_KEY_LIGHT_TINT = vec3(1.10, 0.96, 0.74);
const vec3 DISK_BACK_LIGHT_TINT = vec3(1.10, 0.10, 0.035);
const vec3 DISK_COLD_EDGE_TINT = vec3(0.48, 0.78, 1.52);
const vec3 DISK_RING_CORE_TINT = vec3(0.90, 1.03, 1.42);
const vec3 DISK_RING_HALO_TINT = vec3(1.95, 0.22, 0.055);
const vec3 DISK_RING_SHADOW_TINT = vec3(0.42, 0.28, 0.20);

const int MAX_STEPS = 512;

const float kPi = 3.141592653589;
const float kSpeedOfLight = 299792458.0;
const float kLightYear = 9460730472580800.0;

void vertex() {
    POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

vec3 calc_acceleration(vec3 x, float L2) {
    float r2 = dot(x, x);
    float r = sqrt(r2);
    float r5 = max(r2 * r2 * r, 1e-6);
    return -(1.5 * Rs * gravity_strength * L2 / r5) * x;
}

void rk4_step(inout vec3 x, inout vec3 v, float dl, float L2) {
    vec3 k1_x = v;
    vec3 k1_v = calc_acceleration(x, L2);

    vec3 k2_x = v + k1_v * (dl * 0.5);
    vec3 k2_v = calc_acceleration(x + k1_x * (dl * 0.5), L2);

    vec3 k3_x = v + k2_v * (dl * 0.5);
    vec3 k3_v = calc_acceleration(x + k2_x * (dl * 0.5), L2);

    vec3 k4_x = v + k3_v * dl;
    vec3 k4_v = calc_acceleration(x + k3_x * dl, L2);

    x += (k1_x + 2.0 * k2_x + 2.0 * k3_x + k4_x) * (dl / 6.0);
    v += (k1_v + 2.0 * k2_v + 2.0 * k3_v + k4_v) * (dl / 6.0);
}

// Velocity Verlet: 2nd-order accurate but only ONE acceleration eval per step
// (the previous step's acceleration is cached in `accel`), vs RK4's four.
// Ideal here because the force depends only on position, and it stays stable
// for the tightly-winding photon-ring rays. `accel` MUST be seeded with
// calc_acceleration(x, L2) once before the first call.
void verlet_step(inout vec3 x, inout vec3 v, inout vec3 accel, float dl, float L2) {
    x += v * dl + (0.5 * dl * dl) * accel;
    vec3 accel_new = calc_acceleration(x, L2);
    v += (0.5 * dl) * (accel + accel_new);
    accel = accel_new;
}

float RandomStep(vec2 input_uv, float seed) {
    vec3 p = fract(vec3(input_uv, seed) * vec3(0.1031, 0.0973, 0.1099));
    p += dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}

float CubicInterpolate(float x) {
    return 3.0 * x * x - 2.0 * x * x * x;
}

void HashCorners3D(vec3 cell, out vec4 z0, out vec4 z1) {
    vec4 x = vec4(cell.x, cell.x + 1.0, cell.x, cell.x + 1.0);
    vec4 y = vec4(cell.y, cell.y, cell.y + 1.0, cell.y + 1.0);
    vec4 p0 = fract(vec4(cell.z) * 0.1099 + x * 0.1031 + y * 0.0973);
    vec4 p1 = fract(vec4(cell.z + 1.0) * 0.1099 + x * 0.1031 + y * 0.0973);

    p0 += dot(p0, p0.yzwx + 33.33);
    p1 += dot(p1, p1.yzwx + 33.33);

    z0 = fract((p0 + p0.yzwx) * p0.wxyz) * 2.0 - 1.0;
    z1 = fract((p1 + p1.yzwx) * p1.wxyz) * 2.0 - 1.0;
}

float PerlinNoise(vec3 position) {
    // (b) Texture-fetch path: hardware trilinear filtering + tiling replaces the
    // 8-corner hash. repeat_enable lets any position wrap into the texture.
    // *2-1 remaps the texture's [0,1] back to the procedural noise's ~[-1,1].
    return texture(noise_texture, position * noise_texture_scale).r * 2.0 - 1.0;
}

float PerlinNoiseProcedural(vec3 position) {
    vec3 pos_int = floor(position);
    vec3 pos_float = fract(position);

    vec4 z0;
    vec4 z1;
    HashCorners3D(pos_int, z0, z1);

    vec3 u = pos_float * pos_float * (3.0 - 2.0 * pos_float);
    vec4 z_mix = mix(z0, z1, u.z);
    vec2 y_mix = mix(z_mix.xy, z_mix.zw, u.y);
    return mix(y_mix.x, y_mix.y, u.x);
}

float SoftSaturate(float x) {
    return 1.0 - 1.0 / (max(x, 0.0) + 1.0);
}

float GenerateAccretionDiskNoise(vec3 position, int noise_start_level, int noise_end_level, float contrast_level) {
    float noise_accumulator = 10.0;
    // Running frequency multiply replaces a pow(3.0, level) per octave — this is
    // the hottest loop in the shader, so dropping the per-octave exp/log matters.
    float noise_frequency = pow(3.0, float(noise_start_level));
    for (int level = noise_start_level; level < noise_end_level; ++level) {
        noise_accumulator *= (1.0 + 0.1 * PerlinNoise(noise_frequency * position));
        noise_frequency *= 3.0;
    }
    return log(1.0 + pow(max(0.1 * noise_accumulator, 1e-6), contrast_level));
}

float Vec2ToTheta(vec2 v1, vec2 v2) {
    float dp = dot(v1, v2);
    float crossp = v1.x * v2.y - v1.y * v2.x;
    float lenp = max(length(v1) * length(v2), 1e-6);
    float angle = asin(clamp(0.999999 * crossp / lenp, -1.0, 1.0));

    if (dp > 0.0) {
        return angle;
    } else if (dp < 0.0 && (-crossp) < 0.0) {
        return kPi - angle;
    } else if (dp < 0.0 && (-crossp) > 0.0) {
        return -kPi - angle;
    }

    return angle;
}

float WrapToPi(float angle) {
    return angle - 2.0 * kPi * floor((angle + kPi) / (2.0 * kPi));
}

vec3 OffsetNoiseAxis(vec3 domain, int axis, float delta) {
    if (axis == 0) {
        domain.x += delta;
    } else if (axis == 1) {
        domain.y += delta;
    } else {
        domain.z += delta;
    }
    return domain;
}

float GenerateAngularAccretionDiskNoise(
    vec3 domain,
    int theta_axis,
    float theta,
    float theta_scale,
    int noise_start_level,
    int noise_end_level,
    float contrast_level
) {
    float base_noise = GenerateAccretionDiskNoise(
        DISK_NOISE_SCALE * domain,
        noise_start_level,
        noise_end_level,
        contrast_level
    );

    float wrapped_theta = WrapToPi(theta);
    float seam_distance = min(wrapped_theta + kPi, kPi - wrapped_theta);
    float seam_blend = 1.0 - smoothstep(0.0, 0.16 * kPi, seam_distance);
    if (seam_blend <= 0.0) {
        return base_noise;
    }

    float wrap_delta = (wrapped_theta < 0.0) ? 2.0 * kPi : -2.0 * kPi;
    vec3 wrapped_domain = OffsetNoiseAxis(domain, theta_axis, wrap_delta * theta_scale);
    float wrapped_noise = GenerateAccretionDiskNoise(
        DISK_NOISE_SCALE * wrapped_domain,
        noise_start_level,
        noise_end_level,
        contrast_level
    );
    return mix(base_noise, wrapped_noise, seam_blend);
}

float Ridge(float phase, float sharpness) {
    return pow(clamp(0.5 + 0.5 * cos(phase), 0.0, 1.0), sharpness);
}

float MapTemperatureToBlackbodyUv(float temperature_k) {
    float t = clamp(temperature_k, 0.0, BLACKBODY_LUT_MAX_TEMPERATURE_K);
    if (t <= 12000.0) {
        return 0.85 * (t / 12000.0);
    }
    if (t <= 20000.0) {
        return 0.85 + 0.10 * ((t - 12000.0) / 8000.0);
    }
    return 0.95 + 0.05 * ((t - 20000.0) / 20000.0);
}

vec3 SampleBlackbodyColor(float temperature_k) {
    float uv_x = MapTemperatureToBlackbodyUv(temperature_k);
    vec3 rgb = texture(blackbody_lut, vec2(uv_x, 0.5)).rgb;
    return max(rgb, vec3(0.0));
}

vec3 DiskTemperatureToRgb(float temperature_k) {
    vec3 thermal_rgb = SampleBlackbodyColor(temperature_k);
    return mix(thermal_rgb, vec3(1.0, 0.97, 0.92), DISK_WHITE_MIX);
}

float Luminance(vec3 color) {
    return dot(color, vec3(0.299, 0.587, 0.114));
}

vec3 FilmicDisplay(vec3 color) {
    vec3 safe_color = max(color, vec3(0.0));
    return 1.0 - exp(-safe_color * 0.82);
}

vec3 HdrBloomSource(vec3 hdr_color) {
    vec3 safe_color = max(hdr_color, vec3(0.0));
    float luma = Luminance(safe_color);
    float response = smoothstep(BLOOM_THRESHOLD, BLOOM_THRESHOLD + HDR_BLOOM_KNEE, luma);
    return safe_color * response * HDR_EMISSION_GAIN;
}

// Faithful port of the reference Shadertoy bloom "inverse tonemap":
// it expands a near-LDR color back into HDR so bright pixels explode
// (0.5 -> ~1.0, 0.9 -> ~6.3, 0.99 -> clamped to BLOOM_EXPAND_MAX), while a
// per-channel hue factor keeps the original color ratio. The expanded value
// drives EMISSION so Godot's glow blurs it into the signature bleed.
const float BLOOM_EXPAND_MAX = 12.0;
vec3 BloomExpand(vec3 c) {
    c = clamp(c, vec3(0.0), vec3(0.999));
    float denom = max(c.g + c.g + c.b, 1e-4);
    vec3 hue_factor = 3.0 * c / denom;
    vec3 e;
    e.r = min(-4.0 * log(1.0 - pow(c.r, 2.2)), BLOOM_EXPAND_MAX * hue_factor.r);
    e.g = min(-4.0 * log(1.0 - pow(c.g, 2.2)), BLOOM_EXPAND_MAX * hue_factor.g);
    e.b = min(-4.0 * log(1.0 - pow(c.b, 2.2)), BLOOM_EXPAND_MAX * hue_factor.b);
    return max(e, vec3(0.0));
}

float FarFieldImpactUv(float impact_parameter, float rs) {
    float b_crit = 1.5 * sqrt(3.0) * rs;
    float b_min = b_crit + 1e-6 * rs;
    float b_max = FAR_FIELD_BOUNDARY_RS * rs;
    return (impact_parameter - b_min) / max(b_max - b_min, 1e-6);
}

bool TryApplyFarFieldBoundary(inout vec3 ray_pos, inout vec3 ray_dir, float rs) {
    if (!USE_FAR_FIELD_LUT || rs <= 0.0 || abs(gravity_strength - 1.0) > 0.05) {
        return false;
    }

    float boundary_radius = FAR_FIELD_BOUNDARY_RS * rs;
    float r = length(ray_pos);
    if (r <= boundary_radius) {
        return false;
    }

    vec3 er0 = ray_pos / max(r, 1e-6);
    float vr0 = dot(ray_dir, er0);
    if (vr0 >= 0.0) {
        return false;
    }

    vec3 vt_vec = ray_dir - er0 * vr0;
    float vt0 = length(vt_vec);
    if (vt0 <= 1e-6) {
        return false;
    }

    vec3 et0 = vt_vec / vt0;
    float b = r * vt0;
    float b_crit = 1.5 * sqrt(3.0) * rs;
    float b_min = b_crit + 1e-6 * rs;
    float b_max = boundary_radius;
    if (b < b_min || b > b_max) {
        return false;
    }

    float u = 1.0 / r;
    vec2 lut_uv = vec2(FarFieldImpactUv(b, rs), u * boundary_radius);
    float deflection = texture(far_field_deflection_lut, lut_uv).r;

    float boundary_u = 1.0 / boundary_radius;
    float vt_boundary = b * boundary_u;
    float vr_boundary_sq = max(1.0 - b * b * boundary_u * boundary_u + rs * b * b * boundary_u * boundary_u * boundary_u, 0.0);
    float vr_boundary = -sqrt(vr_boundary_sq);

    float alpha0 = atan(vt0, vr0);
    float alpha_boundary = atan(vt_boundary, vr_boundary);
    float radial_delta = deflection + alpha0 - alpha_boundary;

    float c = cos(radial_delta);
    float s = sin(radial_delta);
    vec3 er_boundary = normalize(er0 * c + et0 * s);
    vec3 et_boundary = normalize(-er0 * s + et0 * c);

    ray_pos = er_boundary * boundary_radius;
    ray_dir = normalize(er_boundary * vr_boundary + et_boundary * vt_boundary);
    return true;
}

float GetKeplerianAngularVelocity(float radius, float rs) {
    return sqrt(kSpeedOfLight / kLightYear * kSpeedOfLight * rs / kLightYear / ((2.0 * radius - 3.0 * rs) * radius * radius));
}

float Shape(float x, float alpha, float beta) {
    float xc = clamp(x, 0.0, 1.0);
    float k = pow(alpha + beta, alpha + beta) / (pow(alpha, alpha) * pow(beta, beta));
    return k * pow(xc, alpha) * pow(1.0 - xc, beta);
}

void BuildDiskBasis(vec3 disk_normal, vec3 world_up, out vec3 bx, out vec3 by, out vec3 bz) {
    by = normalize(disk_normal);
    bz = cross(world_up, by);
    if (length(bz) < 1e-6) {
        bz = cross(vec3(1.0, 0.0, 0.0), by);
    }
    bz = normalize(bz);
    bx = normalize(cross(by, bz));
}

vec3 WorldToBlackHoleSpace(vec3 position, vec3 black_hole_pos, vec3 disk_normal, vec3 world_up) {
    vec3 bx;
    vec3 by;
    vec3 bz;
    BuildDiskBasis(disk_normal, world_up, bx, by, bz);

    vec3 p = position - black_hole_pos;
    return vec3(dot(p, bx), dot(p, by), dot(p, bz));
}

vec3 ApplyBlackHoleRotation(vec3 direction, vec3 disk_normal, vec3 world_up) {
    vec3 bx;
    vec3 by;
    vec3 bz;
    BuildDiskBasis(disk_normal, world_up, bx, by, bz);

    return vec3(dot(direction, bx), dot(direction, by), dot(direction, bz));
}

vec4 calculate_disk_color(
    vec4 base_color,
    float animated_time,
    float step_length,
    vec3 camera_pos,
    vec3 ray_pos,
    vec3 last_ray_pos,
    vec3 ray_dir,
    vec3 bx,
    vec3 by,
    vec3 bz,
    vec3 black_hole_pos,
    float rs,
    float inter_radius,
    float outer_radius,
    float thin
) {
    vec3 p_pos = ray_pos - black_hole_pos;
    vec3 pos_on_disk = vec3(dot(p_pos, bx), dot(p_pos, by), dot(p_pos, bz));
    float pos_r = length(pos_on_disk.zx);
    float pos_y = pos_on_disk.y;

    vec3 p_last = last_ray_pos - black_hole_pos;
    float last_pos_y = dot(p_last, by);

    float radial_edge_softness = max(rs * DISK_EDGE_SOFTNESS_RS, 1e-6);
    bool crossing = (last_pos_y * pos_y < 0.0);

    // Cheap early-out: a segment that neither crosses the disk midplane nor lies
    // within the vertical/radial band can never shade -> identical to the
    // visibility gate below failing. Skips dir transform + all noise sampling.
    if (!crossing &&
        (abs(pos_y) >= thin ||
         pos_r >= outer_radius + radial_edge_softness ||
         pos_r <= inter_radius - radial_edge_softness)) {
        return base_color;
    }

    vec3 dir_on_disk = vec3(dot(ray_dir, bx), dot(ray_dir, by), dot(ray_dir, bz));
    float crossed_midplane = 0.0;

    if (crossing) {
        vec3 last_pos_on_disk = vec3(dot(p_last, bx), dot(p_last, by), dot(p_last, bz));
        float denom = pos_y - last_pos_y;
        if (abs(denom) > 1e-6) {
            vec3 c_point = (-pos_on_disk * last_pos_y + last_pos_on_disk * pos_y) / denom;
            crossed_midplane = 1.0;
            vec3 disk_plane_jitter_dir = vec3(dir_on_disk.x, 0.0, dir_on_disk.z);
            if (length(disk_plane_jitter_dir) < 1e-6) {
                disk_plane_jitter_dir = vec3(-c_point.z, 0.0, c_point.x);
            }
            if (length(disk_plane_jitter_dir) < 1e-6) {
                disk_plane_jitter_dir = vec3(1.0, 0.0, 0.0);
            }
            disk_plane_jitter_dir = normalize(disk_plane_jitter_dir);
            float disk_normal_view = abs(dir_on_disk.y);
            float plane_jitter_mix = smoothstep(0.35, 0.95, disk_normal_view);
            vec3 jitter_dir = normalize(mix(dir_on_disk, disk_plane_jitter_dir, plane_jitter_mix));
            vec2 jitter_uv = c_point.zx / max(rs, 1e-6);
            float jitter_noise = PerlinNoise(vec3(jitter_uv.x * 2.1, jitter_uv.y * 2.1, 0.37)) * 2.0 - 1.0;
            float jitter_scale = mix(0.36, 0.14, plane_jitter_mix);
            pos_on_disk = c_point + min(thin, length(c_point - last_pos_on_disk)) *
                jitter_dir * jitter_noise * jitter_scale;

            step_length = length(pos_on_disk - last_pos_on_disk);
            pos_r = length(pos_on_disk.zx);
            pos_y = pos_on_disk.y;
        }
    }

    vec4 color = vec4(0.0);

    if (abs(pos_y) < thin && pos_r < outer_radius + radial_edge_softness && pos_r > inter_radius - radial_edge_softness) {
        float effective_radius = 1.0 - ((pos_r - inter_radius) / max(outer_radius - inter_radius, 1e-6) * 0.5);

        if ((outer_radius - inter_radius) > 9.0 * rs) {
            if (pos_r < 5.0 * rs + inter_radius) {
                effective_radius = 1.0 - ((pos_r - inter_radius) / max(9.0 * rs, 1e-6) * 0.5);
            } else {
                float denom2 = 1.0 - 5.0 * rs / max(outer_radius - inter_radius, 1e-6);
                effective_radius = 1.0 - (
                    0.5 / 0.9 * 0.5 +
                    (
                        (pos_r - inter_radius) / max(outer_radius - inter_radius, 1e-6) -
                        5.0 * rs / max(outer_radius - inter_radius, 1e-6)
                    ) / max(denom2, 1e-6) * 0.5
                );
            }
        }

        float disk_shape = Shape(effective_radius, 4.0, 0.9);
        float lower_sheet_shape = 1.0 - 5.0 * pow(2.0 * (1.0 - effective_radius), 2.0);
        float radial_edge_fade = smoothstep(inter_radius - radial_edge_softness, inter_radius + radial_edge_softness, pos_r) *
            (1.0 - smoothstep(outer_radius - radial_edge_softness, outer_radius + radial_edge_softness, pos_r));
        float vertical_edge_fade = 1.0 - smoothstep(
            thin * disk_shape * (1.0 - DISK_VERTICAL_EDGE_SOFTNESS),
            thin * disk_shape,
            abs(pos_y)
        );
        float disk_edge_fade = clamp(radial_edge_fade * mix(0.35, 1.0, vertical_edge_fade), 0.0, 1.0);

        if (
            (abs(pos_y) < thin * disk_shape) ||
            (pos_y < thin * lower_sheet_shape)
        ) {
            float angular_velocity = GetKeplerianAngularVelocity(pos_r, rs);
            float half_pi_time_inside = kPi / max(GetKeplerianAngularVelocity(3.0 * rs, rs), 1e-6);

            float spiral_theta = 12.0 * 2.0 / sqrt(3.0) * atan(sqrt(max(0.6666666 * (pos_r / max(rs, 1e-6)) - 1.0, 0.0)));
            float inner_theta = kPi / max(half_pi_time_inside, 1e-6) * animated_time;
            float pos_theta_for_inner_cloud = Vec2ToTheta(pos_on_disk.zx, vec2(cos(0.666666 * inner_theta), sin(0.666666 * inner_theta)));
            float pos_theta = Vec2ToTheta(pos_on_disk.zx, vec2(cos(-spiral_theta), sin(-spiral_theta)));

            float disk_temperature = pow(
                DISK_TEMPERATURE_ARGUMENT * pow(max(rs / max(pos_r, 1e-6), 0.10), 3.0) * max(1.0 - sqrt(inter_radius / max(pos_r, 1e-6)), 0.000001),
                0.25
            );

            vec3 cloud_velocity = kLightYear / kSpeedOfLight * angular_velocity * cross(vec3(0.0, 1.0, 0.0), pos_on_disk);
            vec3 n_to_observer = normalize(-dir_on_disk);
            float beta2 = clamp(dot(cloud_velocity, cloud_velocity), 0.0, 0.9999);
            float gamma = 1.0 / sqrt(max(1.0 - beta2, 1e-6));
            float beta_los = clamp(dot(cloud_velocity, n_to_observer), -0.9999, 0.9999);
            float dopler = 1.0 / max(gamma * (1.0 - beta_los), 1e-6); // delta
            float grav_shift = sqrt(max(1.0 - rs / max(pos_r, 1e-6), 0.000001)) /
                               sqrt(max(1.0 - rs / max(length(camera_pos), 1e-6), 0.000001));
            float red_shift = dopler * grav_shift;
            float beaming = pow(max(dopler, 1e-4), 3.0 + BEAMING_SPECTRAL_INDEX);
            beaming = mix(1.0, min(beaming, BEAMING_CLAMP), clamp(BEAMING_STRENGTH, 0.0, 1.0));

            float density = Shape(effective_radius, 4.0, 0.9);
            float noise_amount = clamp(disk_noise_amount / 1.1, 0.25, 2.5);
            float thick = 0.0;
            float vertical_mix_factor = 0.0;
            float dust_color = 0.0;

            // Make outer disk visibly rotate as well; keep inner ring faster.
            float radius_ratio = clamp(inter_radius / max(pos_r, 1e-6), 0.0, 1.0);
            float radius_spin_mix = mix(DISK_OUTER_SPIN_RATIO, 1.0, radius_ratio);
            float visual_phase = animated_time * DISK_VISUAL_ROTATE_SPEED * DISK_VISUAL_TIME_SCALE * radius_spin_mix;
            float cloud_theta = pos_theta + visual_phase * 0.70;
            float strand_theta = pos_theta + visual_phase;

            float rot_pos_r = pos_r / max(rs, 1e-6) +
                0.3 * sqrt(3.0) * kSpeedOfLight / kLightYear / 3.0 / sqrt(3.0) / max(rs, 1e-6) * animated_time;
            float vertical_domain = pos_y / max(min(rs, thin / 0.1), 1e-6);
            float radial01 = clamp((pos_r - inter_radius) / max(outer_radius - inter_radius, 1e-6), 0.0, 1.0);
            float disk_edge_view = sqrt(max(1.0 - dir_on_disk.y * dir_on_disk.y, 0.0));
            vec2 camera_disk_dir = camera_pos.zx / max(length(camera_pos.zx), 1e-6);
            vec2 surface_disk_dir = pos_on_disk.zx / max(length(pos_on_disk.zx), 1e-6);
            float far_side = 1.0 - smoothstep(-0.18, 0.22, dot(surface_disk_dir, camera_disk_dir));
            float lensed_arc = far_side * smoothstep(0.50, 0.96, disk_edge_view) * smoothstep(0.06, 0.82, radial01);
            float layer_warp = PerlinNoise(vec3(
                rot_pos_r * 0.55 + 0.06 * visual_phase,
                0.34 * pos_theta,
                vertical_domain * 0.28
            ));
            float layer_phase = rot_pos_r * 20.0 + layer_warp * 1.30 + pos_theta * 0.10 + visual_phase * 0.85;
            float radial_layer = Ridge(layer_phase, 7.0);
            float radial_gap = Ridge(layer_phase + kPi, 5.0);
            float fine_layer = Ridge(rot_pos_r * 58.0 + layer_warp * 2.6 + pos_theta * 0.28, 17.0);
            float micro_layer = Ridge(rot_pos_r * 108.0 + layer_warp * 4.0 + pos_theta * 0.52, 28.0);
            float disk_layers = clamp(
                radial_layer * DISK_RADIAL_LAYER_STRENGTH +
                    fine_layer * DISK_FINE_LAYER_STRENGTH +
                    micro_layer * DISK_MICRO_LAYER_STRENGTH,
                0.0,
                1.0
            );
            disk_layers = clamp(disk_layers * (1.0 + DISK_LENSED_ARC_DETAIL * lensed_arc), 0.0, 1.0);
            float midline_shadow = exp(-pow(pos_y / max(thin * 0.11, 1e-6), 2.0)) * disk_edge_view;

            vec4 color0 = vec4(0.0);

            if (abs(pos_y) < thin * density) {
                float thickness_noise = SoftSaturate(GenerateAngularAccretionDiskNoise(
                    vec3(1.5 * cloud_theta, rot_pos_r, 1.0),
                    0,
                    cloud_theta,
                    1.5,
                    1,
                    3,
                    DISK_NOISE_CONTRAST
                ));
                thick = thin * density * (0.36 + 0.54 * thickness_noise);
                vertical_mix_factor = max(0.0, 1.0 - abs(pos_y) / max(thick, 1e-6));
                float vertical_core = pow(vertical_mix_factor, 1.08);
                density *= 0.70 * vertical_core * density;

                float cloud_value = GenerateAngularAccretionDiskNoise(
                    vec3(rot_pos_r, vertical_domain, 0.5 * cloud_theta),
                    2,
                    cloud_theta,
                    0.5,
                    3,
                    6,
                    DISK_NOISE_CONTRAST
                );

                float strand_detail = GenerateAngularAccretionDiskNoise(
                    vec3(rot_pos_r, 1.5 * strand_theta, vertical_domain),
                    1,
                    strand_theta,
                    1.5,
                    1,
                    3,
                    DISK_NOISE_CONTRAST
                );
                float cloud_soft = SoftSaturate(cloud_value);
                float strand_soft = SoftSaturate(strand_detail);
                float cloud_gate = smoothstep(0.12, 0.68, cloud_soft);
                float strand_gate = smoothstep(0.15, 0.78, strand_soft);
                float continuity_fill = 0.22 + 0.24 * radial_layer + 0.18 * fine_layer;
                float structured_cloud = mix(continuity_fill * cloud_soft, cloud_value, cloud_gate);
                color0 = vec4(vec3(structured_cloud), structured_cloud * (0.56 + 0.44 * strand_gate));
                float micro_strand = SoftSaturate(GenerateAngularAccretionDiskNoise(
                    vec3(rot_pos_r * 1.75 + 0.08 * layer_warp, 3.0 * strand_theta, vertical_domain * 1.35),
                    1,
                    strand_theta,
                    3.0,
                    2,
                    4,
                    46.0
                ));
                micro_strand *= strand_gate * (0.35 + 0.65 * vertical_core) * (1.0 + 0.45 * lensed_arc);
                float structure_gate = clamp(0.38 + 0.50 * strand_gate + 0.38 * disk_layers + 0.16 * micro_strand, 0.28, 1.0);
                float layer_gain = 1.0 + disk_layers * (0.48 + 0.34 * vertical_core);
                float layer_shadow = 1.0 - DISK_LAYER_SHADOW_STRENGTH * radial_gap *
                    (0.35 + 0.65 * strand_gate) * (1.0 - 0.22 * micro_layer);
                color0.xyz *= density * 1.4 * (
                    0.14 + 0.76 * vertical_core +
                    (0.82 - 0.58 * vertical_core) * strand_gate +
                    DISK_MICRO_FILAMENT_STRENGTH * micro_strand * (1.0 + 0.35 * lensed_arc)
                ) * noise_amount * layer_gain * layer_shadow;
                color0.a *= density * structure_gate * clamp(noise_amount, 0.35, 1.45) *
                    mix(0.90, 1.14, radial_layer) * mix(1.0, 0.86, radial_gap) *
                    mix(1.0, 1.08, micro_strand);
            }

            if (abs(pos_y) < thin * (1.0 - 5.0 * pow(2.0 * (1.0 - effective_radius), 2.0))) {
                float denom3 = thin * max(1.0 - 5.0 * pow(2.0 * (1.0 - effective_radius), 2.0), 0.0001);
                float dust_phase = kPi / max(half_pi_time_inside, 1e-6) * animated_time;
                float dust_noise = GenerateAngularAccretionDiskNoise(
                    vec3(
                        1.5 * (pos_theta_for_inner_cloud + dust_phase),
                        pos_r / max(rs, 1e-6),
                        vertical_domain
                    ),
                    0,
                    pos_theta_for_inner_cloud,
                    1.5,
                    0,
                    4,
                    DISK_NOISE_CONTRAST
                );
                dust_color = max(1.0 - pow(pos_y / max(denom3, 1e-6), 2.0), 0.0) * dust_noise;
                float dust_layer_gate = clamp(0.44 + 0.56 * disk_layers - 0.42 * radial_gap, 0.14, 1.0);
                float dust_filament_gate = smoothstep(0.12, 0.72, radial_layer + 0.65 * fine_layer + 0.35 * micro_layer);
                float layered_dust = dust_color * (0.12 + 0.70 * radial_layer + 0.36 * fine_layer + 0.22 * micro_layer) *
                    dust_layer_gate * dust_filament_gate * mix(1.0, DISK_LENSED_ARC_DUST_SUPPRESS, lensed_arc);

                float disk_normal_view = abs(dir_on_disk.y);
                float dust_view = max(sqrt(max(1.0001 - dir_on_disk.y * dir_on_disk.y, 0.0)), 0.28 * smoothstep(0.35, 1.0, disk_normal_view));
                color0 += 0.0024 * vec4(DISK_DUST_TINT * layered_dust, 0.034 * layered_dust) *
                    dust_view * min(1.0, dopler * dopler);
            }

            color = color0;
            color *= 1.0 + 20.0 * exp(-10.0 * (pos_r - inter_radius) / max(outer_radius - inter_radius, 1e-6));

            float bright_without_redshift = 4.5 * disk_temperature * disk_temperature * disk_temperature * disk_temperature / max(PEAK_TEMPERATURE_POW4, 1e-6);
            if (disk_temperature > 1000.0) {
                // Standard shift for blackbody temperature uses frequency shift once.
                disk_temperature = max(1000.0, disk_temperature * red_shift);
            }

            disk_temperature = min(100000.0, disk_temperature);
            bright_without_redshift = max(bright_without_redshift, DISK_BRIGHTNESS_FLOOR);

            float thermal_kelvin = disk_temperature / exp((pos_r - inter_radius) / (0.6 * max(outer_radius - inter_radius, 1e-6)));
            thermal_kelvin *= disk_temperature_scale;
            thermal_kelvin = clamp(thermal_kelvin, DISK_TEMP_KELVIN_MIN, DISK_TEMP_KELVIN_MAX);
            vec3 thermal_rgb = DiskTemperatureToRgb(thermal_kelvin);
            float hot_side = smoothstep(0.90, 1.68, dopler);
            float inner_rim = exp(-9.0 * radial01);
            float ring_core = exp(-44.0 * radial01);
            float ring_halo = max(exp(-8.0 * radial01) - 0.58 * ring_core, 0.0);
            float ring_shadow_band = smoothstep(0.045, 0.14, radial01) * (1.0 - smoothstep(0.18, 0.42, radial01));
            float grazing_view = smoothstep(0.18, 0.95, sqrt(max(1.0 - dir_on_disk.y * dir_on_disk.y, 0.0)));
            float rim_light = inner_rim * (0.32 + 0.68 * grazing_view) * (0.36 + 0.64 * hot_side);

            thermal_rgb *= mix(DISK_WARM_TINT, DISK_HOT_TINT, hot_side);
            thermal_rgb = mix(thermal_rgb, DISK_RIM_TINT, 0.30 * inner_rim * hot_side);
            thermal_rgb = mix(thermal_rgb, DISK_RING_CORE_TINT, 0.22 * ring_core * (0.45 + 0.55 * hot_side));
            float white_heat = clamp(0.20 * hot_side + 0.12 * inner_rim + 0.06 * ring_core, 0.0, 0.34);
            thermal_rgb = mix(thermal_rgb, DISK_WHITE_TINT, white_heat);

            color.xyz *= bright_without_redshift * min(1.0, 1.8 * (outer_radius - pos_r) / max(outer_radius - inter_radius, 1e-6)) * thermal_rgb;
            color.xyz *= min(SHIFT_MAX, red_shift);
            color.xyz *= beaming;

            red_shift = min(red_shift, SHIFT_MAX);
            color.xyz *= pow(abs(1.0 - (1.0 - min(1.0, red_shift)) * (pos_r - inter_radius) / max(outer_radius - inter_radius, 1e-6)), 9.0);
            color.xyz *= min(1.0, 1.0 + 0.5 * ((pos_r - inter_radius) / max(inter_radius, 1e-6) + inter_radius / max(pos_r - inter_radius, 1e-6)) - max(1.0, red_shift));

            float path_length_weight = step_length / max(rs, 1e-6);
            color *= path_length_weight;
            color *= disk_edge_fade;
            float local_luma = Luminance(color.rgb);
            float strand_mask = smoothstep(0.010, 0.115, local_luma);
            float opacity_core_gate = smoothstep(0.08, 0.32, color.a);
            float filament_core = smoothstep(0.080, 0.270, local_luma) * opacity_core_gate;
            float highlight_luma = local_luma / (1.0 + local_luma * 0.85);
            float cold_side = 1.0 - hot_side;
            float volume_shadow = smoothstep(0.16, 0.72, color.a) * (1.0 - 0.55 * filament_core) * (0.28 + 0.72 * cold_side);
            float optical_depth = color.a * DISK_OPACITY_GAIN *
                (1.0 + DISK_CORE_OPACITY_GAIN * filament_core + 0.35 * inner_rim) *
                mix(0.92, 1.08, disk_layers) * mix(1.0, 0.90, radial_gap);
            vec3 disk_tangent = vec3(-pos_on_disk.z, 0.0, pos_on_disk.x);
            if (length(disk_tangent) > 1e-6) {
                disk_tangent = normalize(disk_tangent);
            } else {
                disk_tangent = vec3(1.0, 0.0, 0.0);
            }
            float tangent_view = smoothstep(0.18, 0.92, abs(dot(disk_tangent, n_to_observer)));
            float anisotropic_filament = filament_core * strand_mask * tangent_view *
                (0.32 + 0.68 * hot_side) * (0.45 + 0.55 * grazing_view);
            vec3 filament_tint = mix(DISK_FILAMENT_WARM_TINT, DISK_FILAMENT_HOT_TINT, hot_side);
            float inner_key = exp(-2.25 * radial01);
            float key_light = smoothstep(0.70, 1.50, dopler) * (0.42 + 0.58 * inner_key) *
                (0.38 + 0.62 * filament_core);
            float back_shadow = (1.0 - smoothstep(0.82, 1.18, dopler)) *
                smoothstep(0.10, 0.82, color.a) * (0.45 + 0.55 * radial01);
            float cold_edge = rim_light * hot_side * grazing_view * (0.35 + 0.65 * filament_core);
            float ring_core_light = ring_core * (0.35 + 0.65 * grazing_view) * (0.42 + 0.58 * hot_side) *
                (1.0 + 0.55 * lensed_arc);
            float ring_halo_light = ring_halo * (0.30 + 0.70 * strand_mask) * (0.32 + 0.68 * hot_side) *
                (1.0 + 0.72 * lensed_arc);
            vec3 key_tint = mix(DISK_KEY_LIGHT_TINT, DISK_COLD_EDGE_TINT, hot_side);
            float layer_visibility = (0.28 + 0.72 * grazing_view) * (0.25 + 0.75 * strand_mask) *
                (1.0 + 0.65 * lensed_arc);
            color.rgb *= mix(DISK_HAZE_CONTRAST, 1.16, strand_mask);
            color.rgb *= mix(0.94, 1.18, filament_core);
            color.rgb *= mix(vec3(1.0), vec3(0.55, 0.94, 1.72), hot_side * (0.22 + 0.78 * strand_mask));
            color.rgb *= mix(vec3(1.0), vec3(1.46, 0.34, 0.16), cold_side * (0.14 + 0.86 * strand_mask));
            color.rgb *= mix(vec3(1.0), DISK_SHADOW_TINT, clamp(volume_shadow * 0.36, 0.0, 0.72));
            color.rgb *= mix(vec3(1.0), DISK_RING_SHADOW_TINT, clamp(ring_shadow_band * cold_side * (1.0 - 0.55 * filament_core) * 0.34, 0.0, 0.55));
            color.rgb *= 1.0 + disk_layers * layer_visibility * (0.48 + 0.24 * hot_side + 0.20 * lensed_arc);
            color.rgb *= 1.0 - clamp(radial_gap * DISK_LAYER_SHADOW_STRENGTH *
                (0.35 + 0.65 * grazing_view) * (0.55 + 0.45 * cold_side) * (1.0 + 0.55 * lensed_arc), 0.0, 0.60);
            color.rgb *= 1.0 - clamp(midline_shadow * DISK_MIDLINE_SHADOW_STRENGTH *
                (0.55 + 0.45 * cold_side), 0.0, 0.38);
            color.rgb *= 1.0 + 0.48 * key_light;
            color.rgb *= mix(vec3(1.0), DISK_BACK_LIGHT_TINT, clamp(back_shadow * 0.42, 0.0, 0.68));
            float emission_luma = max(highlight_luma, color.a * (0.010 + 0.018 * disk_layers));
            vec3 artistic_emission = vec3(0.0);
            artistic_emission += key_tint * emission_luma * key_light * 0.62;
            artistic_emission += filament_tint * emission_luma * anisotropic_filament * 0.66;
            artistic_emission += mix(DISK_RING_HALO_TINT, DISK_COLD_EDGE_TINT, hot_side) *
                emission_luma * disk_layers * layer_visibility * (0.24 + 0.18 * lensed_arc);
            artistic_emission += DISK_RING_HALO_TINT * emission_luma * ring_halo_light * 0.32;
            artistic_emission += DISK_RING_CORE_TINT * emission_luma * ring_core_light * 0.46;
            artistic_emission += DISK_COLD_EDGE_TINT * emission_luma * cold_edge * 0.30;
            float hot_white_core = hot_side * smoothstep(0.10, 0.68, color.a) *
                (0.42 + 0.58 * inner_key) * (0.38 + 0.62 * strand_mask);
            artistic_emission += DISK_WHITE_TINT * emission_luma * hot_white_core * 0.92;
            artistic_emission += DISK_BLUE_RIM_EMISSION * emission_luma * hot_white_core * 0.22;
            float blue_side = rim_light * hot_side * (0.35 + 0.65 * strand_mask) * (0.45 + 0.55 * grazing_view);
            artistic_emission += DISK_BLUE_RIM_EMISSION * emission_luma * blue_side * DISK_BLUE_SIDE_BOOST;
            float red_side = cold_side * smoothstep(0.08, 0.70, color.a) *
                (0.28 + 0.72 * radial01) * strand_mask *
                clamp(0.92 * ring_halo + 0.30 * inner_key, 0.0, 1.0);
            float red_body_light = cold_side * smoothstep(0.06, 0.62, color.a) *
                (0.28 + 0.72 * radial01) * (0.32 + 0.68 * grazing_view) *
                (0.30 + 0.70 * disk_layers);
            artistic_emission += DISK_RED_FILL_EMISSION * emission_luma * red_body_light * 0.32;
            artistic_emission += DISK_RED_FILL_EMISSION * emission_luma * red_side * DISK_RED_SIDE_FILL;
            color.rgb += artistic_emission * DISK_ARTISTIC_EMISSION;
            color.rgb *= DISK_GLOBAL_BRIGHTNESS;
            float lit_optical_depth = optical_depth * (1.0 + 0.10 * key_light + 0.18 * back_shadow);
            color.a = clamp(1.0 - exp(-lit_optical_depth), 0.0, 1.0);
            color.a = clamp(color.a + 0.020 * anisotropic_filament + 0.008 * ring_core + 0.004 * ring_halo, 0.0, 1.0);
            float alpha_luma_gate = smoothstep(0.002, 0.035, Luminance(color.rgb));
            color.a *= mix(0.42, 1.0, alpha_luma_gate);
            color.rgb += DISK_RIM_TINT * max(highlight_luma, DISK_RGB_FLOOR * color.a) * rim_light * 0.58;
            float blue_rim = rim_light * hot_side * strand_mask;
            color.rgb += DISK_BLUE_RIM_EMISSION * max(highlight_luma, DISK_RGB_FLOOR * color.a) * blue_rim * 0.34;
            color.rgb = max(color.rgb, vec3(DISK_RGB_FLOOR) * color.a * thermal_rgb);
        }
    }
	
    return base_color + color * (1.0 - base_color.a);
}

void fragment() {
    vec2 ndc = SCREEN_UV * 2.0 - 1.0;
    float aspect = VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;

    vec3 fwd = -INV_VIEW_MATRIX[2].xyz;
    vec3 rgt = INV_VIEW_MATRIX[0].xyz;
    vec3 up = INV_VIEW_MATRIX[1].xyz;

    vec3 rd = normalize(fwd * 1.5 + rgt * ndc.x * aspect + up * ndc.y);

    vec3 camera_world_pos = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
    vec3 x = camera_world_pos;
    vec3 v = rd;

    if (disk_outer_radius_ratio <= FAR_FIELD_BOUNDARY_RS) {
        TryApplyFarFieldBoundary(x, v, Rs);
    }

    vec3 L_vec = cross(x, v);
    float L2 = dot(L_vec, L_vec);
    float impact_parameter = sqrt(max(L2, 0.0));
    float capture_impact = 1.5 * sqrt(3.0) * Rs;
    bool captured_by_impact = dot(x, v) < 0.0 && impact_parameter <= capture_impact * 1.0005;

    bool hit_hole = false;
    bool escaped = false;
    float real_escape_radius = 500.0;
    float min_ray_radius = length(x);

    float anim_time = (TIME_OVERRIDE >= 0.0) ? TIME_OVERRIDE : (TIME * TIME_RATE);
    vec4 disk_col_accum = vec4(0.0);
    vec2 pixel_coord = floor(SCREEN_UV * VIEWPORT_SIZE);
    float dither = mix(0.18, 0.82, RandomStep(pixel_coord, 0.371));

    float initial_dl = BASE_STEP * (max(length(x), Rs * 0.5) + 0.01 * length(x) * length(x));
    // Re-test Velocity Verlet now that texturing freed up the hash registers.
    vec3 accel = calc_acceleration(x, L2);
    verlet_step(x, v, accel, initial_dl * dither, L2);

    float inter_radius = disk_inner_radius_ratio * Rs;
    float outer_radius = disk_outer_radius_ratio * Rs;
    float thin = disk_thickness_ratio * Rs;

    vec3 last_ray_pos = x;
    float step_length = 0.0;

    vec3 disk_normal = normalize(vec3(disk_tilt, 1.0, 0.0));
    vec3 world_up = vec3(0.0, 1.0, 0.0);

    // Disk-space basis and camera position are constant for the whole ray:
    // build once here instead of rebuilding inside the per-step disk function.
    vec3 disk_bx;
    vec3 disk_by;
    vec3 disk_bz;
    BuildDiskBasis(disk_normal, world_up, disk_bx, disk_by, disk_bz);
    vec3 camera_disk_pos = vec3(
        dot(camera_world_pos, disk_bx),
        dot(camera_world_pos, disk_by),
        dot(camera_world_pos, disk_bz)
    );

    for (int i = 0; i < MAX_STEPS; i++) {
        if (i >= steps) {
            break;
        }

        float r = length(x);
        min_ray_radius = min(min_ray_radius, r);

        disk_col_accum = calculate_disk_color(
            disk_col_accum,
            anim_time,
            step_length,
            camera_disk_pos,
            x,
            last_ray_pos,
            v,
            disk_bx,
            disk_by,
            disk_bz,
            vec3(0.0),
            Rs,
            inter_radius,
            outer_radius,
            thin
        );

        if (disk_col_accum.a >= 0.99 && Luminance(disk_col_accum.rgb) > 0.08) {
            break;
        }

        if (r <= Rs) {
            hit_hole = true;
            break;
        }
        if (r >= real_escape_radius && dot(x, v) > 0.0) {
            escaped = true;
            break;
        }

        float dl = BASE_STEP * (max(r, Rs * 0.5) + 0.01 * r * r);

        last_ray_pos = x;

        verlet_step(x, v, accel, dl, L2);
        step_length = dl;
    }

    float final_r = length(x);
    if (!hit_hole && !captured_by_impact && !escaped && final_r > FAR_FIELD_BOUNDARY_RS * Rs && dot(x, v) > 0.0) {
        escaped = true;
    }


    vec3 out_col = vec3(0.0);
    if (escaped && !hit_hole && !captured_by_impact) {
        vec3 ray_dir = normalize(v);
        float phi = atan(ray_dir.x, -ray_dir.z);
        float theta = acos(clamp(ray_dir.y, -1.0, 1.0));
        vec2 uv = vec2(phi / (2.0 * PI) + 0.5, theta / PI);
        out_col = texture(sky_texture, uv).rgb;

        float lens_radius = min_ray_radius / max(Rs, 1e-6);
        float lens_strength = smoothstep(1.05, 1.55, lens_radius) * (1.0 - smoothstep(2.2, 8.5, lens_radius));
        float sky_luma = Luminance(out_col);
        float star_mask = smoothstep(0.015, 0.22, sky_luma);
        out_col *= 1.0 + lens_strength * (LENS_SKY_BOOST + LENS_STAR_BOOST * star_mask);
        out_col += vec3(0.012, 0.018, 0.030) * lens_strength * star_mask;
    }
    // Keep already-accumulated foreground disk emission even if the ray later falls into the hole.
    // The black hole only removes the sky background for that ray.

    float visible_disk = smoothstep(0.006, 0.050, Luminance(disk_col_accum.rgb));
    float disk_a = clamp(disk_col_accum.a * mix(0.35, 1.0, visible_disk), 0.0, 1.0);
    vec3 composite = (out_col * (1.0 - disk_a) + disk_col_accum.rgb) * output_exposure;
	if (any(isnan(composite)) || any(isinf(composite))) {
        composite = vec3(0.0); 
    }
	composite = clamp(composite, vec3(0.0), vec3(128.0));
	
    vec3 display_col = composite;
    if (USE_REINHARD_TONEMAP > 0.5) {
        display_col = composite / (vec3(1.0) + composite);
    }
	
    ALBEDO = clamp(FilmicDisplay(display_col), vec3(0.0), vec3(1.0));

    // A: reference-style bloom. Expand the displayed LDR image back into HDR with
    // the inverse-tonemap so bright disk/photon-ring pixels bleed strongly through
    // Godot's glow, instead of the gentle thresholded EMISSION used before.
    vec3 bloom_src = BloomExpand(ALBEDO);
    EMISSION = clamp(bloom_src, vec3(0.0), vec3(128.0));
}
