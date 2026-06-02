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
const float BLOOM_THRESHOLD = 1.2;
const float BLOOM_EMISSION = 2.5;
const float USE_REINHARD_TONEMAP = 0.0;
const float EMISSION_SOFT_CLIP = 1.0;
const float FAR_FIELD_BOUNDARY_RS = 15.0;
const float BLACKBODY_LUT_MAX_TEMPERATURE_K = 40000.0;
const bool USE_FAR_FIELD_LUT = true;

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
    return fract(sin(dot(input_uv + fract(11.4514 * sin(seed)), vec2(12.9898, 78.233))) * 43758.5453);
}

vec4 HashCorners2D(vec2 cell) {
    vec4 x = vec4(cell.x, cell.x + 1.0, cell.x, cell.x + 1.0);
    vec4 y = vec4(cell.y, cell.y, cell.y + 1.0, cell.y + 1.0);
    vec4 p = fract(x * 0.1031 + y * 0.0973);
    p += dot(p, p.yzwx + 33.33);
    return fract((p + p.yzwx) * p.wxyz);
}

float ValueNoise2D(vec2 p) {
    vec2 cell = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    vec4 h = HashCorners2D(cell);
    return mix(mix(h.x, h.y, u.x), mix(h.z, h.w, u.x), u.y);
}

float Fbm2D(vec2 p) {
    float sum = 0.0;
    float amp = 0.5;
    mat2 rot = mat2(vec2(0.80, -0.60), vec2(0.60, 0.80));
    for (int octave = 0; octave < 4; octave++) {
        sum += amp * ValueNoise2D(p);
        p = rot * p * 2.03 + vec2(11.7, 5.3);
        amp *= 0.5;
    }
    return sum;
}

vec3 SampleFastDiskNoise(float radius_rs, float theta, float y_norm, float animated_time) {
    float spiral = theta + 4.5 * log(max(radius_rs, 1.001)) - animated_time * 0.025;
    vec2 base_uv = vec2(radius_rs * 0.33, spiral * 1.15);
    float density = Fbm2D(base_uv);
    float detail = Fbm2D(base_uv * 2.4 + vec2(17.0, animated_time * 0.015));
    float dust = Fbm2D(vec2(fract(spiral / (2.0 * kPi)) * 8.0, radius_rs * 0.75 + y_norm * 0.35));
    return clamp(mix(vec3(0.5), vec3(density, detail, dust), clamp(disk_noise_amount, 0.0, 2.0)), vec3(0.0), vec3(1.0));
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

    if (last_pos_y * pos_y < 0.0) {
        float denom = pos_y - last_pos_y;
        if (abs(denom) > 1e-6) {
            vec3 c_point = (-pos_on_disk * last_pos_y + last_pos_on_disk * pos_y) / denom;
            pos_on_disk = c_point + min(thin, length(c_point - last_pos_on_disk)) * dir_on_disk *
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

            float spiral_theta = 12.0 * 2.0 / sqrt(3.0) * atan(sqrt(max(0.6666666 * (pos_r / max(rs, 1e-6)) - 1.0, 0.0)));
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
            float thick = 0.0;
            float vertical_mix_factor = 0.0;
            float dust_color = 0.0;

            // Make outer disk visibly rotate as well; keep inner ring faster.
            float radius_ratio = clamp(inter_radius / max(pos_r, 1e-6), 0.0, 1.0);
            float radius_spin_mix = mix(DISK_OUTER_SPIN_RATIO, 1.0, radius_ratio);
            float visual_phase = animated_time * DISK_VISUAL_ROTATE_SPEED * DISK_VISUAL_TIME_SCALE * radius_spin_mix;

            float radius_rs = pos_r / max(rs, 1e-6);
            float y_norm = pos_y / max(thin, 1e-6);
            vec3 fast_noise = SampleFastDiskNoise(radius_rs, pos_theta + visual_phase, y_norm, animated_time);
            float density_noise = fast_noise.x;
            float detail_noise = fast_noise.y;
            float dust_noise_sample = fast_noise.z;

            vec4 color0 = vec4(0.0);

            if (abs(pos_y) < thin * density) {
                thick = thin * density * mix(0.45, 1.05, density_noise);
                vertical_mix_factor = max(0.0, 1.0 - abs(pos_y) / max(thick, 1e-6));
                density *= 0.7 * vertical_mix_factor * density;

                float cloud_value = mix(density_noise, detail_noise, 0.55);
                color0 = vec4(vec3(cloud_value), cloud_value);

                color0.xyz *= density * 1.4 * (
                    0.2 + 0.8 * vertical_mix_factor +
                    (0.8 - 0.8 * vertical_mix_factor) * detail_noise
                );
                color0.a *= density;
            }

            if (abs(pos_y) < thin * (1.0 - 5.0 * pow(2.0 * (1.0 - effective_radius), 2.0))) {
                float denom3 = thin * max(1.0 - 5.0 * pow(2.0 * (1.0 - effective_radius), 2.0), 0.0001);
                dust_color = max(1.0 - pow(pos_y / max(denom3, 1e-6), 2.0), 0.0) * dust_noise_sample;

                color0 += 0.02 * vec4(vec3(dust_color), 0.2 * dust_color) *
                    sqrt(max(1.0001 - dir_on_disk.y * dir_on_disk.y, 0.0)) * min(1.0, dopler * dopler);
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

            color.xyz *= bright_without_redshift * min(1.0, 1.8 * (outer_radius - pos_r) / max(outer_radius - inter_radius, 1e-6)) * thermal_rgb;
            color.xyz *= min(SHIFT_MAX, red_shift);
            color.xyz *= beaming;

            red_shift = min(red_shift, SHIFT_MAX);
            color.xyz *= pow(abs(1.0 - (1.0 - min(1.0, red_shift)) * (pos_r - inter_radius) / max(outer_radius - inter_radius, 1e-6)), 9.0);
            color.xyz *= min(1.0, 1.0 + 0.5 * ((pos_r - inter_radius) / max(inter_radius, 1e-6) + inter_radius / max(pos_r - inter_radius, 1e-6)) - max(1.0, red_shift));

            color *= step_length / max(rs, 1e-6);
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
    }
	if (hit_hole) {
        // 既然这根光线最终跌入了黑洞，那无论它在路上穿过了多亮的前景气体，
        // 我们都强行剥夺它的亮度，或者对其进行极大的衰减。
        // 乘以 0.0 代表完全抹除前景气体，黑球将呈现绝对的纯黑和完美边缘；
        // 乘以 0.05 代表保留极微弱的前景气体质感。你可以自己权衡这个艺术值。
        disk_col_accum.rgb *= 0.0; 
        disk_col_accum.a *= 0.0; 
    }

    float disk_a = clamp(disk_col_accum.a, 0.0, 1.0);
    vec3 composite = mix(out_col, disk_col_accum.rgb, disk_a) * output_exposure;
	if (any(isnan(composite)) || any(isinf(composite))) {
        composite = vec3(0.0); 
    }
	composite = clamp(composite, vec3(0.0), vec3(128.0));
	
    vec3 display_col = composite;
    if (USE_REINHARD_TONEMAP > 0.5) {
        display_col = composite / (vec3(1.0) + composite);
    }
	
    ALBEDO = clamp(display_col, vec3(0.0), vec3(1.0));

    // Bloom source from display-space color to avoid HDR blow-up.
    vec3 bloom_src = max(display_col - vec3(BLOOM_THRESHOLD), vec3(0.0));
    if (EMISSION_SOFT_CLIP > 0.0) {
        bloom_src = bloom_src / (vec3(EMISSION_SOFT_CLIP) + bloom_src);
    }
EMISSION = clamp(bloom_src * BLOOM_EMISSION, vec3(0.0), vec3(128.0));
}
