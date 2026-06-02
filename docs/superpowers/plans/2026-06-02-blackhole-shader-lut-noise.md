# Black Hole Shader LUT and Noise Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the Godot black hole shader to use the existing blackbody and far-field deflection LUTs, replace expensive real-time noise, and reduce the material tuning surface to about ten parameters.

**Architecture:** Keep the shader as a single Godot full-screen spatial shader for this pass, but split responsibilities inside it into small helper functions: LUT mapping, far-field boundary state transfer, disk noise, and disk shading. The material binds the three texture resources and exposes only the core artist-facing controls; constants handle the rest.

**Tech Stack:** Godot 4.6 shader language, Godot ShaderMaterial `.tres`, EXR Texture2D resources, PowerShell, git.

---

## Scope Check

This is one shader/material refactor, not multiple independent subsystems. The LUT baker code in `D:/Development/Cosmic-Stars/Cosmic-Stars-Prototype` is reference material only; this plan does not modify that separate repository.

## File Structure

- Modify `BlackHole.gdshader`: add LUT uniforms, reduce exposed uniforms, replace Kelvin color conversion, replace procedural noise helpers, and add far-field boundary transfer before near-field RK tracing.
- Modify `materials/blackhole_live.tres`: bind `sky_texture`, `blackbody_lut`, and `far_field_deflection_lut`; keep only the reduced public shader parameter set.
- Create or regenerate `lud/blackbody_1d_lut_4k.exr.import`: Godot import metadata for the blackbody LUT.
- Create or regenerate `lud/far_field_ray_deflection_lut_rs1_4096.exr.import`: Godot import metadata for the far-field deflection LUT.
- Do not commit `.superpowers/brainstorm/` browser companion files.
- Do not revert the existing uncommitted edits in `BlackHole.gdshader`; inspect and work with the current file contents.

## Task 1: Bind LUT Resources and Reduce Public Parameters

**Files:**
- Modify: `BlackHole.gdshader`
- Modify: `materials/blackhole_live.tres`
- Create or regenerate: `lud/blackbody_1d_lut_4k.exr.import`
- Create or regenerate: `lud/far_field_ray_deflection_lut_rs1_4096.exr.import`

- [ ] **Step 1: Inspect current dirty shader state**

Run:

```powershell
git diff -- BlackHole.gdshader
```

Expected: Output shows pre-existing comment/formatting edits. Keep those edits unless they conflict with this refactor.

- [ ] **Step 2: Add the reduced shader parameter surface**

In `BlackHole.gdshader`, replace the existing long uniform block with this public tuning block and internal constants. Keep `shader_type` and `render_mode` unchanged.

```glsl
uniform float Rs = 4.0;
uniform float gravity_strength = 1.0;
uniform int steps = 256;
uniform float disk_tilt = -0.3;
uniform float disk_inner_radius_ratio = 2.5;
uniform float disk_outer_radius_ratio = 7.6;
uniform float disk_thickness_ratio = 0.62;
uniform float disk_noise_amount = 1.0;
uniform float disk_temperature_scale = 0.71;
uniform float output_exposure = 0.9;

uniform sampler2D sky_texture : filter_nearest;
uniform sampler2D blackbody_lut : filter_linear;
uniform sampler2D far_field_deflection_lut : filter_linear;

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
const float DISK_TEMP_KELVIN_MAX = 40000.0;
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
const float FAR_FIELD_BLEND_WIDTH_RS = 1.0;
const float BLACKBODY_LUT_MAX_TEMPERATURE_K = 40000.0;
const bool USE_BLACKBODY_LUT = true;
const bool USE_FAR_FIELD_LUT = true;
const bool USE_FAST_NOISE = true;
```

- [ ] **Step 3: Update material resource bindings**

Replace `materials/blackhole_live.tres` with this resource shape, preserving the existing material UID:

```text
[gd_resource type="ShaderMaterial" format=3 uid="uid://qxooc2475gd5"]

[ext_resource type="Shader" uid="uid://gd3gu4hc0c3m" path="res://BlackHole.gdshader" id="1_sjfy6"]
[ext_resource type="Texture2D" uid="uid://cdjuddtyvblls" path="res://starmap_2020_8k.exr" id="2_q56d7"]
[ext_resource type="Texture2D" path="res://lud/blackbody_1d_lut_4k.exr" id="3_bbody"]
[ext_resource type="Texture2D" path="res://lud/far_field_ray_deflection_lut_rs1_4096.exr" id="4_farfield"]

[resource]
render_priority = 0
shader = ExtResource("1_sjfy6")
shader_parameter/Rs = 4.0
shader_parameter/gravity_strength = 1.0
shader_parameter/steps = 256
shader_parameter/disk_tilt = -0.3
shader_parameter/disk_inner_radius_ratio = 2.5
shader_parameter/disk_outer_radius_ratio = 7.6
shader_parameter/disk_thickness_ratio = 0.62
shader_parameter/disk_noise_amount = 1.0
shader_parameter/disk_temperature_scale = 0.71
shader_parameter/output_exposure = 0.9
shader_parameter/sky_texture = ExtResource("2_q56d7")
shader_parameter/blackbody_lut = ExtResource("3_bbody")
shader_parameter/far_field_deflection_lut = ExtResource("4_farfield")
```

- [ ] **Step 4: Generate or refresh Godot import metadata**

Run:

```powershell
godot --headless --path . --import
```

Expected: Godot exits without shader/resource import errors and creates or refreshes these files:

```text
lud/blackbody_1d_lut_4k.exr.import
lud/far_field_ray_deflection_lut_rs1_4096.exr.import
```

If the `godot` command is unavailable, skip only this import-generation step and record that verification is blocked by the missing executable. Do not invent `.ctex` paths by hand.

- [ ] **Step 5: Verify the parameter surface is reduced**

Run:

```powershell
rg -n "shader_parameter/(base_step|noise_scale|noise_contrast|time_rate|time_override|shift_max|disk_visual|disk_temperature_argument|peak_temperature|disk_temp_kelvin|disk_white_mix|disk_brightness_floor|disk_rgb_floor|beaming_|bloom_|emission_soft_clip|use_reinhard)" materials/blackhole_live.tres
```

Expected: No matches.

- [ ] **Step 6: Commit the resource and parameter binding change**

Run:

```powershell
git add -- BlackHole.gdshader materials/blackhole_live.tres lud/blackbody_1d_lut_4k.exr lud/far_field_ray_deflection_lut_rs1_4096.exr lud/blackbody_1d_lut_4k.exr.import lud/far_field_ray_deflection_lut_rs1_4096.exr.import
git commit -m "Bind black hole shader LUT resources"
```

Expected: Commit succeeds. If import metadata was not generated, omit the missing `.import` paths from `git add` and mention that in the task summary.

## Task 2: Replace Kelvin Color Math With Blackbody LUT Sampling

**Files:**
- Modify: `BlackHole.gdshader`

- [ ] **Step 1: Confirm the old Kelvin path is still present**

Run:

```powershell
rg -n "KelvinToRgb|disk_temp_to_rgb_scale|disk_temp_kelvin" BlackHole.gdshader
```

Expected: Matches exist before this task starts.

- [ ] **Step 2: Add blackbody LUT mapping helpers**

Insert these helpers after `Vec2ToTheta()` and before the disk color function:

```glsl
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
    vec3 thermal_rgb = USE_BLACKBODY_LUT ? SampleBlackbodyColor(temperature_k) : KelvinToRgb(temperature_k);
    return mix(thermal_rgb, vec3(1.0, 0.97, 0.92), DISK_WHITE_MIX);
}
```

- [ ] **Step 3: Replace the thermal RGB calculation**

In `calculate_disk_color()`, replace the current thermal color block:

```glsl
thermal_kelvin *= disk_temp_to_rgb_scale;
thermal_kelvin = clamp(thermal_kelvin, disk_temp_kelvin_min, disk_temp_kelvin_max);
vec3 thermal_rgb = KelvinToRgb(thermal_kelvin);
thermal_rgb = mix(thermal_rgb, vec3(1.0, 0.97, 0.92), clamp(disk_white_mix, 0.0, 1.0));
```

with:

```glsl
thermal_kelvin *= disk_temperature_scale;
thermal_kelvin = clamp(thermal_kelvin, DISK_TEMP_KELVIN_MIN, DISK_TEMP_KELVIN_MAX);
vec3 thermal_rgb = DiskTemperatureToRgb(thermal_kelvin);
```

- [ ] **Step 4: Replace remaining constant references in disk brightness**

In `calculate_disk_color()`, replace these names:

```text
peak_temp_pow4_local -> PEAK_TEMPERATURE_POW4
shift_max_local -> SHIFT_MAX
disk_brightness_floor -> DISK_BRIGHTNESS_FLOOR
disk_rgb_floor -> DISK_RGB_FLOOR
beaming_spectral_index -> BEAMING_SPECTRAL_INDEX
beaming_strength -> BEAMING_STRENGTH
beaming_clamp -> BEAMING_CLAMP
```

Then remove the corresponding parameters from the `calculate_disk_color()` signature and call site.

- [ ] **Step 5: Verify removed uniforms are not referenced**

Run:

```powershell
rg -n "disk_temp_to_rgb_scale|disk_temp_kelvin_min|disk_temp_kelvin_max|disk_white_mix|disk_brightness_floor|disk_rgb_floor|beaming_spectral_index|beaming_strength|beaming_clamp|peak_temp_pow4_local|shift_max_local" BlackHole.gdshader
```

Expected: No matches.

- [ ] **Step 6: Compile or parse-check the shader through Godot**

Run:

```powershell
godot --headless --path . --quit
```

Expected: Godot starts and exits without shader compile errors. If `godot` is unavailable, run the search checks from Step 5 and record that shader compilation is blocked.

- [ ] **Step 7: Commit the blackbody LUT change**

Run:

```powershell
git add -- BlackHole.gdshader materials/blackhole_live.tres
git commit -m "Use blackbody LUT for disk color"
```

Expected: Commit succeeds.

## Task 3: Replace Scalar 3D Noise With Fast Disk Noise

**Files:**
- Modify: `BlackHole.gdshader`

- [ ] **Step 1: Confirm the old scalar noise path is present**

Run:

```powershell
rg -n "PerlinNoise|GenerateAccretionDiskNoise|sin\\(dot" BlackHole.gdshader
```

Expected: Matches exist before this task starts.

- [ ] **Step 2: Add vectorized value-noise helpers**

Insert these helpers after `SoftSaturate()`:

```glsl
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
    return mix(vec3(0.5), vec3(density, detail, dust), clamp(disk_noise_amount, 0.0, 2.0));
}
```

- [ ] **Step 3: Reuse one fast noise sample inside disk shading**

Inside the disk-volume branch in `calculate_disk_color()`, after `visual_phase` and `rot_pos_r` are computed, add:

```glsl
float radius_rs = pos_r / max(rs, 1e-6);
float y_norm = pos_y / max(thin, 1e-6);
vec3 fast_noise = SampleFastDiskNoise(radius_rs, pos_theta + visual_phase, y_norm, animated_time);
float density_noise = fast_noise.x;
float detail_noise = fast_noise.y;
float dust_noise_sample = fast_noise.z;
```

- [ ] **Step 4: Replace the thick/density noise expression**

Replace:

```glsl
thick = thin * density * (0.4 + 0.6 * SoftSaturate(GenerateAccretionDiskNoise(noise_scale * vec3(1.5 * (pos_theta + visual_phase), rot_pos_r + 0.18 * visual_phase, 1.0), 1, 3, noise_contrast)));
```

with:

```glsl
thick = thin * density * mix(0.45, 1.05, density_noise);
```

- [ ] **Step 5: Replace the main cloud color noise expression**

Replace the `color0 = vec4(GenerateAccretionDiskNoise(...))` block and the wraparound blend that follows it with:

```glsl
float cloud_value = mix(density_noise, detail_noise, 0.55);
color0 = vec4(vec3(cloud_value), cloud_value);
```

Then replace the later multiplier containing another `GenerateAccretionDiskNoise(...)` call with:

```glsl
color0.xyz *= density * 1.4 * (
    0.2 + 0.8 * vertical_mix_factor +
    (0.8 - 0.8 * vertical_mix_factor) * detail_noise
);
```

- [ ] **Step 6: Replace the dust noise expression**

Replace the `dust_color = ... GenerateAccretionDiskNoise(...)` expression with:

```glsl
dust_color = max(1.0 - pow(pos_y / max(denom3, 1e-6), 2.0), 0.0) * dust_noise_sample;
```

- [ ] **Step 7: Remove old scalar noise helpers**

Delete these functions from `BlackHole.gdshader`:

```text
RandomStep must stay because dithering still uses it.
CubicInterpolate
PerlinNoise
GenerateAccretionDiskNoise
```

Keep `RandomStep()` unchanged.

- [ ] **Step 8: Verify old noise is gone**

Run:

```powershell
rg -n "PerlinNoise|GenerateAccretionDiskNoise|CubicInterpolate|noise_scale|noise_contrast|sin\\(dot" BlackHole.gdshader
```

Expected: No matches.

- [ ] **Step 9: Compile or parse-check the shader through Godot**

Run:

```powershell
godot --headless --path . --quit
```

Expected: Godot exits without shader compile errors. If `godot` is unavailable, rely on the search checks and record the missing executable.

- [ ] **Step 10: Commit the fast noise change**

Run:

```powershell
git add -- BlackHole.gdshader
git commit -m "Replace accretion disk noise with fast value noise"
```

Expected: Commit succeeds.

## Task 4: Add Far-Field LUT Boundary Transfer

**Files:**
- Modify: `BlackHole.gdshader`

- [ ] **Step 1: Add far-field LUT helper functions**

Insert these helpers after the blackbody LUT helpers:

```glsl
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
```

- [ ] **Step 2: Apply the far-field transfer before near-field RK**

In `fragment()`, after `vec3 x = camera_world_pos; vec3 v = rd;`, call the helper and then compute angular momentum:

```glsl
TryApplyFarFieldBoundary(x, v, Rs);

vec3 L_vec = cross(x, v);
float L2 = dot(L_vec, L_vec);
```

Remove the older `L_vec` and `L2` declarations that happened before this point.

- [ ] **Step 3: Update integration constants and radius ratios**

In `fragment()`, replace uses of removed uniforms:

```text
base_step -> BASE_STEP
time_rate -> TIME_RATE
time_override -> TIME_OVERRIDE
inter_radius_ratio -> disk_inner_radius_ratio
outer_radius_ratio -> disk_outer_radius_ratio
thin_ratio -> disk_thickness_ratio
```

The animation time line should become:

```glsl
float anim_time = (TIME_OVERRIDE >= 0.0) ? TIME_OVERRIDE : (TIME * TIME_RATE);
```

Build disk normal from the reduced tilt parameter:

```glsl
vec3 disk_normal = normalize(vec3(disk_tilt, 1.0, 0.0));
```

- [ ] **Step 4: Update the disk color call signature**

Pass only the values still needed by `calculate_disk_color()`:

```glsl
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
```

The function signature should no longer include `last_ray_dir`, `disk_temperature_argument_local`, `peak_temp_pow4_local`, or `shift_max_local`.

- [ ] **Step 5: Replace output constants**

At the end of `fragment()`, replace removed uniform names:

```text
use_reinhard_tonemap -> USE_REINHARD_TONEMAP
bloom_threshold -> BLOOM_THRESHOLD
emission_soft_clip -> EMISSION_SOFT_CLIP
bloom_emission -> BLOOM_EMISSION
```

- [ ] **Step 6: Verify removed shader parameters are gone**

Run:

```powershell
rg -n "base_step|time_rate|time_override|inter_radius_ratio|outer_radius_ratio|thin_ratio|disk_normal_world|last_ray_dir|disk_temperature_argument_local|peak_temp_pow4_local|shift_max_local|use_reinhard_tonemap|bloom_threshold|bloom_emission|emission_soft_clip" BlackHole.gdshader
```

Expected: No matches.

- [ ] **Step 7: Compile or parse-check the shader through Godot**

Run:

```powershell
godot --headless --path . --quit
```

Expected: Godot exits without shader compile errors. If Godot reports shader errors, fix those exact lines before committing.

- [ ] **Step 8: Commit the far-field LUT change**

Run:

```powershell
git add -- BlackHole.gdshader materials/blackhole_live.tres
git commit -m "Use far-field LUT for black hole ray entry"
```

Expected: Commit succeeds.

## Task 5: Final Verification and Cleanup

**Files:**
- Modify only if needed: `BlackHole.gdshader`
- Modify only if needed: `materials/blackhole_live.tres`

- [ ] **Step 1: Verify the reduced public material parameters**

Run:

```powershell
rg -n "shader_parameter/" materials/blackhole_live.tres
```

Expected output contains only:

```text
shader_parameter/Rs
shader_parameter/gravity_strength
shader_parameter/steps
shader_parameter/disk_tilt
shader_parameter/disk_inner_radius_ratio
shader_parameter/disk_outer_radius_ratio
shader_parameter/disk_thickness_ratio
shader_parameter/disk_noise_amount
shader_parameter/disk_temperature_scale
shader_parameter/output_exposure
shader_parameter/sky_texture
shader_parameter/blackbody_lut
shader_parameter/far_field_deflection_lut
```

- [ ] **Step 2: Verify no obsolete shader uniforms remain**

Run:

```powershell
rg -n "uniform (float|int|vec3) (base_step|noise_scale|noise_contrast|time_rate|time_override|shift_max|disk_visual|disk_temperature_argument|peak_temperature|disk_temp|beaming_|bloom_|use_reinhard|emission_soft)" BlackHole.gdshader
```

Expected: No matches.

- [ ] **Step 3: Verify project compiles**

Run:

```powershell
godot --headless --path . --quit
```

Expected: Godot exits without shader or resource errors.

- [ ] **Step 4: Verify git only contains intended changes**

Run:

```powershell
git status --short
```

Expected: Modified or staged files are limited to this refactor. Pre-existing unrelated untracked files may remain, but they must not be included in commits.

- [ ] **Step 5: Commit final cleanup if any changes were needed**

If Step 1 through Step 3 required cleanup edits, run:

```powershell
git add -- BlackHole.gdshader materials/blackhole_live.tres
git commit -m "Clean up black hole shader parameters"
```

Expected: Commit succeeds. If no cleanup edits were needed, do not create an empty commit.
