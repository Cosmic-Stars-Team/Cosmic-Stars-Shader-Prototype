# 黑洞参数使用说明（BlackHole.gdshader）

本说明对应材质文件 `res://materials/blackhole_live.tres`，用于调节 `res://BlackHole.gdshader`。

## 1. 使用流程

1. 打开 `black_hole.tscn`。
2. 选中黑洞网格节点（`MeshInstance3D`）。
3. 在 Inspector 中修改 `surface_material_override/0` 对应的参数。
4. 一次只改一组参数，便于定位效果变化。

## 2. 核心引力透镜参数

### `Rs`
- 作用：史瓦西半径，决定黑洞尺度。
- 调大：黑洞阴影和整体结构变大。
- 调小：整体缩小。
- 建议范围：`0.5 ~ 8.0`。

### `gravity_strength`
- 作用：引力偏折强度倍率。
- 调大：透镜效应更强、扭曲更明显。
- 调小：扭曲减弱。
- 建议范围：`0.6 ~ 2.5`。

### `steps`
- 作用：RK4 积分步数。
- 调大：画面更稳定、更精细，但更耗性能。
- 调小：性能更好，但容易出现误差和伪影。
- 建议范围：`64 ~ 512`。

### `base_step`
- 作用：基础步长。
- 调大：更快但精度下降，可能漏过细节。
- 调小：更准但更慢。
- 建议范围：`0.01 ~ 0.08`。

### `sky_texture`
- 作用：背景天空纹理（透镜采样源）。
- 建议：使用高动态范围全景图（例如 `.exr`）。

## 3. 吸积盘形状与朝向

### `disk_normal_world`
- 作用：吸积盘法线（世界坐标）。
- 用法：改盘面倾角和朝向。
- 示例：`Vector3(0.2, 1, 0)`。

### `inter_radius_ratio`
- 作用：内半径比例，实际内半径 = `inter_radius_ratio * Rs`。
- 调大：内圈向外移动。
- 调小：内圈更靠近黑洞。
- 建议范围：`2.0 ~ 4.0`。

### `outer_radius_ratio`
- 作用：外半径比例，实际外半径 = `outer_radius_ratio * Rs`。
- 调大：盘面更宽。
- 调小：盘面更紧凑。
- 建议范围：`8.0 ~ 20.0`。

### `thin_ratio`
- 作用：厚度比例，实际厚度 = `thin_ratio * Rs`。
- 调大：盘更厚。
- 调小：盘更薄、更锐利。
- 建议范围：`0.2 ~ 1.2`。

## 4. 噪声与动态参数

### `noise_scale`
- 作用：噪声细节尺度。
- 调大：纹理更细密。
- 调小：纹理更块状、更平滑。
- 建议范围：`0.5 ~ 3.0`。

### `noise_contrast`
- 作用：噪声对比度。
- 调大：条纹/断裂更明显。
- 调小：纹理更柔和。
- 建议范围：`20 ~ 120`。

### `time_rate`
- 作用：动画速度。
- 调大：运动更快。
- 调小：运动更慢。
- 建议范围：`0 ~ 60`。

### `time_override`
- 作用：手动时间覆盖。
- 规则：`< 0` 使用引擎 `TIME`；`>= 0` 固定在该时间帧。
- 用途：做静态截图、对比测试。

### `disk_visual_rotate_speed`
- 作用：盘面视觉旋转速度。
- 建议范围：`0.02 ~ 0.5`。

### `disk_outer_spin_ratio`
- 作用：外盘相对旋转比例。
- 调大：外圈更跟随内圈旋转。
- 调小：外圈转得更慢。
- 建议范围：`0.0 ~ 1.0`。

### `disk_visual_time_scale`
- 作用：盘面视觉时间缩放。
- 建议范围：`0.005 ~ 0.08`。

## 5. 颜色、频移与亮度

### `shift_max`
- 作用：频移效果上限。
- 调大：红移/蓝移更强。
- 调小：颜色更克制。
- 建议范围：`1.0 ~ 1.6`。

### `disk_temperature_argument`
- 作用：温度模型主控参数。
- 调大：整体更“热”（偏亮偏蓝白）。
- 调小：整体更“冷”（偏暗偏红）。
- 建议范围：`1e18 ~ 1e20`。

### `peak_temperature_pow4`
- 作用：温度亮度归一化项（T^4）。
- 调大：整体会偏暗。
- 调小：整体会偏亮。
- 建议范围：`1e18 ~ 1e19`。

### `disk_temp_to_rgb_scale`
- 作用：温度映射到 RGB 的缩放。
- 调大：颜色更偏高温。
- 调小：颜色更偏低温。
- 建议范围：`0.3 ~ 1.5`。

### `disk_white_mix`
- 作用：向白色混合比例。
- 调大：高亮区域更白。
- 调小：保留更多原始热辐射色。
- 建议范围：`0.0 ~ 0.3`。

### `disk_brightness_floor`
- 作用：最低亮度保底。
- 调大：暗部抬高，可能发灰。
- 调小：暗部更深。
- 建议范围：`0.0 ~ 0.03`。

### `disk_rgb_floor`
- 作用：最低 RGB 保底。
- 调大：避免纯黑死区。
- 调小：黑位更干净。
- 建议范围：`0.0 ~ 0.01`。

### `output_exposure`
- 作用：最终曝光倍率。
- 调大：整体更亮。
- 调小：整体更暗。
- 建议范围：`0.7 ~ 1.8`。

### `bloom_threshold`
- 作用：泛光阈值。
- 调大：更少区域触发泛光。
- 调小：更多区域产生泛光。
- 建议范围：`0.6 ~ 2.0`。

### `bloom_emission`
- 作用：送入 Godot bloom 的发光强度。
- 调大：辉光更强。
- 调小：辉光更弱。
- 建议范围：`0.5 ~ 8.0`。

## 6. 实用预设

### 快速预览（省性能）
- `steps = 96`
- `base_step = 0.05`
- `noise_contrast = 45`
- `bloom_emission = 1.0`

### 电影质感（高质量）
- `steps = 256`
- `base_step = 0.03`
- `noise_contrast = 65`
- `output_exposure = 1.2`
- `bloom_threshold = 0.9`
- `bloom_emission = 3.0`

### 只看透镜（弱化盘）
- `thin_ratio = 0.0`
- `bloom_emission = 0.0`
- `disk_brightness_floor = 0.0`

## 7. 常见问题排查

- 现象：改参数没反应。
- 检查：确认你改的是 `surface_material_override/0` 绑定的材质文件。

- 现象：画面闪烁或噪声太脏。
- 处理：提高 `steps`，降低 `base_step`，降低 `noise_contrast`。

- 现象：画面过曝、发白。
- 处理：降低 `output_exposure`，提高 `bloom_threshold`，降低 `bloom_emission`。

- 现象：盘面太暗。
- 处理：提高 `disk_temperature_argument` 或 `disk_brightness_floor`。
