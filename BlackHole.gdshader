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

const float BASE_STEP = 0.02;
const float TIME_RATE = 8.0;
const float TIME_OVERRIDE = -1.0;
const float SHIFT_MAX = 2.6;
const float DISK_VISUAL_ROTATE_SPEED = 0.18;
const float DISK_OUTER_SPIN_RATIO = 0.6;
const float DISK_VISUAL_TIME_SCALE = 0.02;
const float DISK_NOISE_SCALE = 1.1;
const float DISK_NOISE_CONTRAST = 72.0;
const float DISK_TEMPERATURE_ARGUMENT = 1.4e19;
const float PEAK_TEMPERATURE_POW4 = 5.665278e18;
const float DISK_TEMP_KELVIN_MIN = 1200.0;
const float DISK_TEMP_KELVIN_MAX = 18000.0;
const float DISK_WHITE_MIX = 0.002;
const float DISK_BRIGHTNESS_FLOOR = 0.0045;
const float DISK_RGB_FLOOR = 0.0025;
const float BEAMING_SPECTRAL_INDEX = 0.1;
const float BEAMING_STRENGTH = 0.5;
const float BEAMING_CLAMP = 15.0;
const float BLOOM_THRESHOLD = 1.18;
const float BLOOM_EMISSION = 3.0;
const float USE_REINHARD_TONEMAP = 0.0;
const float EMISSION_SOFT_CLIP = 0.90;
const float DISK_HAZE_CONTRAST = 0.66;
const float DISK_OPACITY_GAIN = 1.42;
const float DISK_CORE_OPACITY_GAIN = 1.35;
const float LENS_SKY_BOOST = 0.25;
const float LENS_STAR_BOOST = 5.0;
const float FAR_FIELD_BOUNDARY_RS = 15.0;
const float BLACKBODY_LUT_MAX_TEMPERATURE_K = 40000.0;
const bool USE_FAR_FIELD_LUT = true;

const vec3 DISK_WARM_TINT = vec3(1.00, 0.84, 0.58);
const vec3 DISK_HOT_TINT = vec3(0.88, 0.98, 1.24);
const vec3 DISK_RIM_TINT = vec3(0.92, 1.02, 1.30);
const vec3 DISK_WHITE_TINT = vec3(1.04, 1.04, 1.00);
const vec3 DISK_BLUE_RIM_EMISSION = vec3(0.26, 0.52, 1.35);
const vec3 DISK_DUST_TINT = vec3(0.92, 0.46, 0.18);
const vec3 DISK_SHADOW_TINT = vec3(0.58, 0.40, 0.26);
const vec3 DISK_FILAMENT_WARM_TINT = vec3(1.16, 0.86, 0.52);
const vec3 DISK_FILAMENT_HOT_TINT = vec3(0.78, 0.96, 1.32);
const vec3 DISK_KEY_LIGHT_TINT = vec3(1.10, 0.96, 0.74);
const vec3 DISK_BACK_LIGHT_TINT = vec3(0.50, 0.34, 0.24);
const vec3 DISK_COLD_EDGE_TINT = vec3(0.54, 0.78, 1.36);

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
    for (int level = noise_start_level; level < noise_end_level; ++level) {
        float noise_frequency = pow(3.0, float(level));
        vec3 scaled_position = noise_frequency * position;
        noise_accumulator *= (1.0 + 0.1 * PerlinNoise(scaled_position));
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
    vec3 camera_world_pos,
    vec3 ray_pos,
    vec3 last_ray_pos,
    vec3 ray_dir,
    vec3 world_up,
    vec3 black_hole_pos,
    vec3 disk_normal,
    float rs,
    float inter_radius,
    float outer_radius,
    float thin
) {
    vec3 camera_pos = WorldToBlackHoleSpace(camera_world_pos, black_hole_pos, disk_normal, world_up);
    vec3 pos_on_disk = WorldToBlackHoleSpace(ray_pos, black_hole_pos, disk_normal, world_up);
    vec3 last_pos_on_disk = WorldToBlackHoleSpace(last_ray_pos, black_hole_pos, disk_normal, world_up);
    vec3 dir_on_disk = ApplyBlackHoleRotation(ray_dir, disk_normal, world_up);
    float pos_r = length(pos_on_disk.zx);
    float pos_y = pos_on_disk.y;
    float last_pos_y = last_pos_on_disk.y;
    float crossed_midplane = 0.0;

    if (last_pos_y * pos_y < 0.0) {
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
            float plane_jitter_mix = smoothstep(0.35, 0.95, abs(dir_on_disk.y));
            vec3 jitter_dir = normalize(mix(dir_on_disk, disk_plane_jitter_dir, plane_jitter_mix));
            pos_on_disk = c_point + min(thin, length(c_point - last_pos_on_disk)) * jitter_dir *
                (-1.0 + 2.0 * RandomStep(10000000000.0 * pos_on_disk.zx, fract(animated_time + 0.5)));

            step_length = length(pos_on_disk - last_pos_on_disk);
            pos_r = length(pos_on_disk.zx);
            pos_y = pos_on_disk.y;
        }
    }

    vec4 color = vec4(0.0);

    if (abs(pos_y) < thin && pos_r < outer_radius && pos_r > inter_radius) {
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

        if (
            (abs(pos_y) < thin * Shape(effective_radius, 4.0, 0.9)) ||
            (pos_y < thin * (1.0 - 5.0 * pow(2.0 * (1.0 - effective_radius), 2.0)))
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

            float rot_pos_r = pos_r / max(rs, 1e-6) +
                0.3 * sqrt(3.0) * kSpeedOfLight / kLightYear / 3.0 / sqrt(3.0) / max(rs, 1e-6) * animated_time;
            float vertical_domain = pos_y / max(min(rs, thin / 0.1), 1e-6);

            vec4 color0 = vec4(0.0);

            if (abs(pos_y) < thin * density) {
                float thickness_noise = SoftSaturate(GenerateAccretionDiskNoise(
                    DISK_NOISE_SCALE * vec3(1.5 * (pos_theta + visual_phase), rot_pos_r + 0.18 * visual_phase, 1.0),
                    1,
                    3,
                    DISK_NOISE_CONTRAST
                ));
                thick = thin * density * (0.4 + 0.6 * thickness_noise);
                vertical_mix_factor = max(0.0, 1.0 - abs(pos_y) / max(thick, 1e-6));
                density *= 0.7 * vertical_mix_factor * density;

                float cloud_value = GenerateAccretionDiskNoise(
                    DISK_NOISE_SCALE * vec3(rot_pos_r + 0.22 * visual_phase, vertical_domain, 0.5 * (pos_theta + 0.7 * visual_phase)),
                    3,
                    6,
                    DISK_NOISE_CONTRAST
                );

                if (pos_theta + kPi < 0.1 * kPi) {
                    float blend = (pos_theta + kPi) / (0.1 * kPi);
                    float wrapped_cloud = GenerateAccretionDiskNoise(
                        DISK_NOISE_SCALE * vec3(rot_pos_r + 0.22 * visual_phase, vertical_domain, 0.5 * (2.0 * kPi + pos_theta + 0.7 * visual_phase)),
                        3,
                        6,
                        DISK_NOISE_CONTRAST
                    );
                    cloud_value = mix(wrapped_cloud, cloud_value, blend);
                }

                color0 = vec4(vec3(cloud_value), cloud_value);

                float strand_detail = GenerateAccretionDiskNoise(
                    DISK_NOISE_SCALE * vec3(rot_pos_r + 0.12 * visual_phase, 1.5 * (pos_theta + visual_phase), vertical_domain),
                    1,
                    3,
                    DISK_NOISE_CONTRAST
                );
                color0.xyz *= density * 1.4 * (
                    0.2 + 0.8 * vertical_mix_factor +
                    (0.8 - 0.8 * vertical_mix_factor) * strand_detail
                ) * noise_amount;
                color0.a *= density * clamp(noise_amount, 0.35, 1.45);
            }

            if (abs(pos_y) < thin * (1.0 - 5.0 * pow(2.0 * (1.0 - effective_radius), 2.0))) {
                float denom3 = thin * max(1.0 - 5.0 * pow(2.0 * (1.0 - effective_radius), 2.0), 0.0001);
                float dust_noise = GenerateAccretionDiskNoise(
                    DISK_NOISE_SCALE * vec3(
                        1.5 * fract((1.5 * pos_theta_for_inner_cloud + kPi / max(half_pi_time_inside, 1e-6) * animated_time + visual_phase) / (2.0 * kPi)) * 2.0 * kPi,
                        pos_r / max(rs, 1e-6),
                        vertical_domain
                    ),
                    0,
                    6,
                    DISK_NOISE_CONTRAST
                );
                dust_color = max(1.0 - pow(pos_y / max(denom3, 1e-6), 2.0), 0.0) * dust_noise;

                float disk_normal_view = abs(dir_on_disk.y);
                float dust_view = max(sqrt(max(1.0001 - dir_on_disk.y * dir_on_disk.y, 0.0)), 0.28 * smoothstep(0.35, 1.0, disk_normal_view));
                color0 += 0.018 * vec4(DISK_DUST_TINT * dust_color, 0.35 * dust_color) *
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
            float radial01 = clamp((pos_r - inter_radius) / max(outer_radius - inter_radius, 1e-6), 0.0, 1.0);
            float hot_side = smoothstep(0.98, 1.85, dopler);
            float inner_rim = exp(-9.0 * radial01);
            float grazing_view = smoothstep(0.18, 0.95, sqrt(max(1.0 - dir_on_disk.y * dir_on_disk.y, 0.0)));
            float rim_light = inner_rim * (0.32 + 0.68 * grazing_view) * (0.36 + 0.64 * hot_side);

            thermal_rgb *= mix(DISK_WARM_TINT, DISK_HOT_TINT, hot_side);
            thermal_rgb = mix(thermal_rgb, DISK_RIM_TINT, 0.30 * inner_rim * hot_side);
            float white_heat = clamp(0.18 * hot_side + 0.10 * inner_rim, 0.0, 0.28);
            thermal_rgb = mix(thermal_rgb, DISK_WHITE_TINT, white_heat);

            color.xyz *= bright_without_redshift * min(1.0, 1.8 * (outer_radius - pos_r) / max(outer_radius - inter_radius, 1e-6)) * thermal_rgb;
            color.xyz *= min(SHIFT_MAX, red_shift);
            color.xyz *= beaming;

            red_shift = min(red_shift, SHIFT_MAX);
            color.xyz *= pow(abs(1.0 - (1.0 - min(1.0, red_shift)) * (pos_r - inter_radius) / max(outer_radius - inter_radius, 1e-6)), 9.0);
            color.xyz *= min(1.0, 1.0 + 0.5 * ((pos_r - inter_radius) / max(inter_radius, 1e-6) + inter_radius / max(pos_r - inter_radius, 1e-6)) - max(1.0, red_shift));

            float surface_path_weight = crossed_midplane * 0.12 * smoothstep(0.35, 1.0, abs(dir_on_disk.y));
            color *= max(step_length / max(rs, 1e-6), surface_path_weight);
            float local_luma = Luminance(color.rgb);
            float strand_mask = smoothstep(0.0015, 0.080, local_luma);
            float filament_core = smoothstep(0.055, 0.220, local_luma);
            float highlight_luma = local_luma / (1.0 + local_luma * 0.85);
            float cold_side = 1.0 - hot_side;
            float volume_shadow = smoothstep(0.16, 0.72, color.a) * (1.0 - 0.55 * filament_core) * (0.28 + 0.72 * cold_side);
            float optical_depth = color.a * DISK_OPACITY_GAIN * (1.0 + DISK_CORE_OPACITY_GAIN * filament_core + 0.35 * inner_rim);
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
            float key_light = smoothstep(0.78, 1.62, dopler) * (0.36 + 0.64 * inner_key) *
                (0.48 + 0.52 * strand_mask);
            float back_shadow = (1.0 - smoothstep(0.82, 1.18, dopler)) *
                smoothstep(0.10, 0.82, color.a) * (0.45 + 0.55 * radial01);
            float cold_edge = rim_light * hot_side * grazing_view * (0.35 + 0.65 * filament_core);
            vec3 key_tint = mix(DISK_KEY_LIGHT_TINT, DISK_COLD_EDGE_TINT, hot_side);
            color.rgb *= mix(DISK_HAZE_CONTRAST, 1.16, strand_mask);
            color.rgb *= mix(0.92, 1.18, filament_core);
            color.rgb *= mix(vec3(1.0), DISK_SHADOW_TINT, clamp(volume_shadow * 0.36, 0.0, 0.72));
            color.rgb *= 1.0 + 0.34 * key_light;
            color.rgb *= mix(vec3(1.0), DISK_BACK_LIGHT_TINT, clamp(back_shadow * 0.34, 0.0, 0.58));
            color.rgb += key_tint * max(highlight_luma, DISK_RGB_FLOOR * color.a) * key_light * 0.62;
            color.rgb += filament_tint * max(highlight_luma, DISK_RGB_FLOOR * color.a) * anisotropic_filament * 1.05;
            color.rgb += DISK_COLD_EDGE_TINT * max(highlight_luma, DISK_RGB_FLOOR * color.a) * cold_edge * 0.40;
            float lit_optical_depth = optical_depth * (1.0 + 0.10 * key_light + 0.18 * back_shadow);
            color.a = clamp(1.0 - exp(-lit_optical_depth), 0.0, 1.0);
            color.a = clamp(color.a + 0.045 * anisotropic_filament, 0.0, 1.0);
            color.rgb += DISK_RIM_TINT * max(highlight_luma, DISK_RGB_FLOOR * color.a) * rim_light * 0.95;
            float blue_rim = rim_light * hot_side * strand_mask;
            color.rgb += DISK_BLUE_RIM_EMISSION * max(highlight_luma, DISK_RGB_FLOOR * color.a) * blue_rim * 0.82;
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

    bool hit_hole = false;
    float real_escape_radius = 500.0;
    float min_ray_radius = length(x);

    float anim_time = (TIME_OVERRIDE >= 0.0) ? TIME_OVERRIDE : (TIME * TIME_RATE);
    vec4 disk_col_accum = vec4(0.0);
    float dither = RandomStep(SCREEN_UV, fract(anim_time));

    float initial_dl = BASE_STEP * (max(length(x), Rs * 0.5) + 0.01 * length(x) * length(x));
    rk4_step(x, v, initial_dl * dither, L2);

    float inter_radius = disk_inner_radius_ratio * Rs;
    float outer_radius = disk_outer_radius_ratio * Rs;
    float thin = disk_thickness_ratio * Rs;

    vec3 last_ray_pos = x;
    float step_length = 0.0;

    vec3 disk_normal = normalize(vec3(disk_tilt, 1.0, 0.0));
    vec3 world_up = vec3(0.0, 1.0, 0.0);

    for (int i = 0; i < MAX_STEPS; i++) {
        if (i >= steps) {
            break;
        }

        float r = length(x);
        min_ray_radius = min(min_ray_radius, r);
        if (r <= Rs) {
            hit_hole = true;
            break;
        }
        if (r >= real_escape_radius) {
            break;
        }

        float dl = BASE_STEP * (max(r, Rs * 0.5) + 0.01 * r * r);

        disk_col_accum = calculate_disk_color(
            disk_col_accum,
            anim_time,
            step_length,
            camera_world_pos,
            x,
            last_ray_pos,
            v,
            world_up,
            vec3(0.0),
            disk_normal,
            Rs,
            inter_radius,
            outer_radius,
            thin
        );

        if (disk_col_accum.a >= 0.99) {
            break;
        }

        last_ray_pos = x;

        rk4_step(x, v, dl, L2);
        step_length = dl;
    }



    vec3 out_col = vec3(0.0);
    if (!hit_hole) {
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

    float disk_a = clamp(disk_col_accum.a, 0.0, 1.0);
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

    // Use the unclamped HDR composite for selective glow; ALBEDO stays filmic to avoid flat white clipping.
    vec3 bloom_src = max(composite - vec3(BLOOM_THRESHOLD), vec3(0.0));
    if (EMISSION_SOFT_CLIP > 0.0) {
        bloom_src = bloom_src / (vec3(EMISSION_SOFT_CLIP) + bloom_src * 0.35);
    }
    EMISSION = clamp(bloom_src * BLOOM_EMISSION, vec3(0.0), vec3(128.0));
}
