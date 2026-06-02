# Black Hole Shader LUT and Noise Refactor Design

## Goal

Refactor `BlackHole.gdshader` so the expensive and hard-to-maintain parts are replaced with explicit lookup-table contracts and cheaper real-time noise:

- Use `lud/blackbody_1d_lut_4k.exr` for blackbody color lookup instead of `KelvinToRgb()`.
- Use `lud/far_field_ray_deflection_lut_rs1_4096.exr` for far-field ray deflection outside the 15Rs boundary.
- Replace the current scalar `sin(dot())` 3D noise path with cheaper vectorized value-FBM and analytic spiral structure.

The first implementation should preserve the existing look as much as possible. It should make the fast paths optional through shader parameters so visual comparisons against the current shader are straightforward.

The public tuning surface should be reduced to about ten artist-facing parameters for now. The current shader exposes too many controls, which makes later tuning and debugging painful. Implementation may keep additional constants internally, but the material inspector should only expose the small set that a user is expected to adjust.

## Current Context

The shader is a full-screen Godot spatial shader. It currently does all work inline:

- Builds a camera ray from the screen quad.
- Integrates ray bending with RK4 in `fragment()`.
- Samples and shades the accretion disk during integration.
- Computes procedural disk density through repeated scalar hash noise.
- Approximates blackbody color with `KelvinToRgb()`.
- Applies redshift, beaming, exposure, tonemapping, and bloom output.

The project already contains the two LUT assets needed for this refactor:

- `lud/far_field_ray_deflection_lut_rs1_4096.exr`
- `lud/blackbody_1d_lut_4k.exr`

Both files are present, but the current material does not bind them and the shader does not sample them.

## Approaches Considered

### 1. Preserve visuals first, add fast paths behind toggles

This approach adds LUT sampling and optimized noise while keeping fallback paths for the current calculations.

Pros:
- Easier visual A/B testing.
- Lower risk of breaking the current shot.
- Lets the far-field boundary blend be tuned independently.

Cons:
- The shader remains somewhat larger during the transition.
- Some old functions stay until comparison passes.

### 2. Rewrite the shader around LUTs immediately

This approach removes the current Kelvin function, most far-field RK work, and old noise in one pass.

Pros:
- Cleaner end state faster.
- Less duplicate shader code.

Cons:
- Higher regression risk.
- Harder to identify whether a change in look came from LUT mapping, boundary blending, or noise.

### 3. Split into multiple shaders or materials

This approach separates lensing, disk shading, and output into different shader/material resources.

Pros:
- Stronger long-term separation.
- Easier to reason about each module.

Cons:
- More Godot material wiring.
- Not necessary for the current prototype.

## Selected Design

Use approach 1.

Add LUT and optimized-noise paths behind parameters, compare against the current look with `time_override`, then remove or de-emphasize old helpers after the new paths are validated.

## Blackbody 1D LUT Contract

`lud/blackbody_1d_lut_4k.exr` is a `4096 x 1` RGB EXR. It stores normalized linear sRGB blackbody color.

The texture X coordinate maps to temperature with the baker's piecewise-linear curve:

- `0K` to `12000K` uses `85%` of the texture.
- `12000K` to `20000K` uses `10%` of the texture.
- `20000K` to `40000K` uses `5%` of the texture.

Shader-side behavior:

- Compute the disk's base temperature exactly where the shader currently does.
- Apply redshift once to the temperature, matching the current blackbody shift behavior.
- Apply `disk_temp_to_rgb_scale`.
- Clamp the lookup temperature to `[0K, 40000K]`.
- Map that temperature through the same piecewise curve and sample the LUT.
- Keep brightness in the shader through the current brightness chain: `T^4` normalization, radial falloff, redshift multiplier, beaming, exposure, and bloom source.

Do not bake physical brightness into this LUT for the first implementation. The existing LUT is chromaticity-style color. Baking direct `T^4` intensity would make the high-temperature end dominate and would make the current artistic brightness controls much harder to preserve.

## Far-Field Deflection LUT Contract

`lud/far_field_ray_deflection_lut_rs1_4096.exr` is a `4096 x 4096` single-channel EXR with channel `Y`. It stores angular deflection in radians.

The baker is `D:/Development/Cosmic-Stars/Cosmic-Stars-Prototype/src/far_field_lut_baker.py`.

The baker uses REBOUND IAS15 and the same core acceleration model as the shader at `gravity_strength = 1`:

```text
a = -1.5 * Rs * L2 / r^5 * x
```

The LUT domain is:

```text
boundary_radius = 15Rs
b_crit = 1.5 * sqrt(3) * Rs
b_min = b_crit + 1e-6 * Rs
b_max = 15Rs
u = 1 / r
```

Texture mapping:

```text
uv.x = (b - b_min) / (b_max - b_min)
uv.y = u / (1 / (15Rs))
```

Shader-side behavior:

- Compute impact parameter from the current ray state as `b = length(cross(x, v))`.
- Use the LUT only when the ray is outside the near-field boundary and `b` is in the LUT domain.
- Treat the LUT value as a 2D-plane angular bend toward the black hole center.
- Keep RK4 for near-field tracing, disk crossing, event-horizon hit tests, and rays that fall outside the LUT domain.
- Add a configurable transition band around `15Rs` to blend between RK and LUT behavior.

Because the existing LUT is baked for `gravity_strength = 1`, the first shader implementation should either:

- Only enable far-field LUT behavior when `gravity_strength` is close to `1`, or
- Document that non-1 values use an approximate artistic path.

The safer first implementation is to gate the LUT with a `use_far_field_lut` parameter and leave `gravity_strength = 1` for validated comparisons.

## 15Rs Boundary Handling

The boundary must not create visible jumps in the lensed background or disk silhouette.

The shader should use:

- `far_field_boundary_rs = 15.0`
- `far_field_blend_width_rs`, initially around `1.0`

For rays well outside the boundary, the LUT can bend the direction before sky sampling.

For rays near the boundary, the shader should blend between:

- The current RK-integrated direction.
- The direction produced by applying the LUT deflection.

For rays inside the boundary, RK remains authoritative.

The accretion disk should still be sampled through near-field tracing. The LUT is a far-field lensing accelerator, not a replacement for local disk intersection and emission.

## Real-Time Noise Refactor

The current noise stack is expensive because `PerlinNoise()` evaluates eight scalar `sin(dot())` hashes per sample, and `GenerateAccretionDiskNoise()` is called many times with multiple octaves.

Replace it with a real-time noise path built from:

- A vectorized hash function that returns multiple values per call.
- 2D value noise in disk coordinates where possible.
- A small FBM stack, typically 2 to 4 octaves.
- Analytic spiral phase for the dominant disk structure.
- Reused noise samples for density, detail, and dust terms.

Recommended shader helpers:

- `hash42(vec2 p)` or equivalent: returns four hash values for the corners of a 2D cell.
- `value_noise_2d(vec2 p)`: smooth bilinear interpolation across the four hashed corners.
- `fbm_2d(vec2 p, int octaves)`: low octave stack.
- `disk_spiral_phase(float radius_rs, float theta, float time)`: analytic spiral coordinate.

Sampling strategy:

- Use disk-plane coordinates for most noise: radius, theta, and animated spiral phase.
- Use vertical height only as a cheap modulation term, not as a full 3D noise dimension.
- Compute at most three reusable noise values per disk sample:
  - `density_noise`
  - `detail_noise`
  - `dust_noise`
- Keep branch checks before noise work so samples outside the disk volume do not evaluate noise.

The new path should be controlled by `use_fast_noise`. The current noise path can remain temporarily as a fallback until visual comparison is complete.

## Shader Parameters

Expose only the core tuning parameters in the material inspector. Target public parameters:

```text
uniform float Rs;
uniform float gravity_strength;
uniform int steps;
uniform float disk_tilt;
uniform float disk_inner_radius_ratio;
uniform float disk_outer_radius_ratio;
uniform float disk_thickness_ratio;
uniform float disk_noise_amount;
uniform float disk_temperature_scale;
uniform float output_exposure;
```

The two LUT samplers remain shader parameters because they must be bound by the material, but they are resource bindings rather than regular tuning knobs:

```text
uniform sampler2D blackbody_lut : filter_linear;
uniform sampler2D far_field_deflection_lut : filter_linear;
uniform sampler2D sky_texture : filter_nearest;
```

The following values should be internal constants or hidden implementation parameters unless debugging requires temporarily exposing them:

```text
use_blackbody_lut = 1.0
use_far_field_lut = 1.0
use_fast_noise = 1.0
far_field_boundary_rs = 15.0
far_field_blend_width_rs = 1.0
blackbody_lut_max_temperature_k = 40000.0
disk_white_mix
disk_brightness_floor
disk_rgb_floor
beaming_spectral_index
beaming_strength
beaming_clamp
bloom_threshold
bloom_emission
emission_soft_clip
```

The implementation should remove or stop exposing redundant parameters from `materials/blackhole_live.tres` after the new shader compiles. This is part of the refactor, not a separate cleanup pass.

## Material and Import Requirements

The material `materials/blackhole_live.tres` should bind:

- `blackbody_lut = res://lud/blackbody_1d_lut_4k.exr`
- `far_field_deflection_lut = res://lud/far_field_ray_deflection_lut_rs1_4096.exr`

The LUT imports should avoid destructive color processing:

- No sRGB conversion for numeric LUTs.
- No mipmap-dependent value drift for the far-field deflection LUT unless tested.
- Linear filtering is acceptable for both LUTs because the baker is continuous over the sampled domains.

If Godot creates `.import` files for these LUTs, commit them with the shader change so the resource contract is reproducible.

## Testing and Verification

Use visual and numeric checks:

- Fix `time_override` so before/after screenshots are comparable.
- Compare `use_blackbody_lut = 0` vs `1` for color shifts.
- Compare `use_fast_noise = 0` vs `1` for disk texture continuity and performance.
- Compare `use_far_field_lut = 0` vs `1` at `gravity_strength = 1`.
- Test camera distances that cross the 15Rs boundary.
- Check that horizon hits remain black and that foreground disk emission is not accidentally erased except by the existing hit-hole policy.
- Run Godot shader compilation by opening or launching the project after edits.

## Scope Boundaries

This design does not require regenerating either LUT.

This design does not replace the near-field RK path.

This design does not add a noise texture.

This design does not bake physical brightness into the blackbody LUT in the first implementation.

This design does not support accurate far-field LUT behavior for arbitrary `gravity_strength` values without either rebaking or accepting approximation.
