extends Node
## 画质设置单例：两档预设 + 独立分辨率选项。
## 运行时切换、套用到材质/视口/窗口，并记忆到 user://settings.cfg。
## 按 Esc 打开/关闭设置面板；首次运行自动弹出。

const CONFIG_PATH := "user://settings.cfg"
const MATERIAL_PATH := "res://materials/blackhole_live.tres"

# 两档画质。噪声相关：
#   noise_mode            1=启用混合(低频贴图+高频程序化), 0=全贴图(最省, 但糊)
#   noise_hybrid_split    fBm 里 >=此 level 的高频octave走程序化(清晰), 以下查贴图(便宜)
#   noise_detail_footprint 高频 LOD：越大越淡掉最高octave以消 FSR2 缩放下的闪烁; 高画质=0 保细节
const QUALITY_PRESETS := [
	{ "name": "高画质（独显 4060+/台式）", "steps": 512, "fsr2_scale": 0.85,
		"noise_mode": 1, "noise_hybrid_split": 2, "noise_detail_footprint": 0.0 },
	{ "name": "流畅（入门独显~5060 笔记本）", "steps": 320, "fsr2_scale": 0.77,
		"noise_mode": 1, "noise_hybrid_split": 3, "noise_detail_footprint": 0.0015 },
]

# 分辨率：窗口内容尺寸；size 为 ZERO 表示全屏
const RESOLUTIONS := [
	{ "name": "1280 x 720", "size": Vector2i(1280, 720) },
	{ "name": "1920 x 1080", "size": Vector2i(1920, 1080) },
	{ "name": "2560 x 1440", "size": Vector2i(2560, 1440) },
	{ "name": "全屏", "size": Vector2i.ZERO },
]

# 吸积盘温度档。scale 套到材质 disk_temperature_scale。
#   标准暖盘 0.84：与原效果一致（warm_keep≈1，保留暖/红艺术补光）
#   高温蓝盘 5.0：温度顶到 40000K 黑体蓝，且 warm_keep→0 自动关掉红/暖染色，物理正确的纯蓝
const DISK_TEMP_PRESETS := [
	{ "name": "标准暖盘", "scale": 0.84 },
	{ "name": "高温蓝盘（~40000K）", "scale": 5.0 },
]

var quality_index := 1    # 默认“流畅”
var resolution_index := 1 # 默认 1080p
var disk_temp_index := 0  # 默认标准暖盘
var vsync_on := true

var _material: ShaderMaterial
var _ui: CanvasLayer
var _panel: Control
var _quality_option: OptionButton
var _resolution_option: OptionButton
var _disk_temp_option: OptionButton
var _vsync_check: CheckBox

func _ready() -> void:
	_material = load(MATERIAL_PATH) as ShaderMaterial
	var had_config := _load_config()
	_build_ui()
	_apply_all()
	# 首次运行（没有配置文件）弹出面板让用户选；否则静默套用
	_set_panel_visible(not had_config)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_set_panel_visible(not _panel.visible)
		get_viewport().set_input_as_handled()

# ---- 套用 ----

func _apply_all() -> void:
	_apply_quality()
	_apply_resolution()
	_apply_disk_temp()
	_apply_vsync()

func _apply_disk_temp() -> void:
	if _material:
		var t: Dictionary = DISK_TEMP_PRESETS[disk_temp_index]
		_material.set_shader_parameter("disk_temperature_scale", float(t["scale"]))

func _apply_quality() -> void:
	var p: Dictionary = QUALITY_PRESETS[quality_index]
	if _material:
		_material.set_shader_parameter("steps", int(p["steps"]))
		_material.set_shader_parameter("noise_mode", int(p["noise_mode"]))
		_material.set_shader_parameter("noise_hybrid_split", int(p["noise_hybrid_split"]))
		_material.set_shader_parameter("noise_detail_footprint", float(p["noise_detail_footprint"]))
	get_viewport().scaling_3d_scale = float(p["fsr2_scale"])

func _apply_resolution() -> void:
	var r: Dictionary = RESOLUTIONS[resolution_index]
	var size: Vector2i = r["size"]
	if size == Vector2i.ZERO:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(size)
		# 居中
		var screen := DisplayServer.screen_get_size()
		DisplayServer.window_set_position((screen - size) / 2)

func _apply_vsync() -> void:
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync_on else DisplayServer.VSYNC_DISABLED
	)

# ---- 配置存取 ----

func _load_config() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return false
	quality_index = clampi(cfg.get_value("graphics", "quality", quality_index), 0, QUALITY_PRESETS.size() - 1)
	resolution_index = clampi(cfg.get_value("graphics", "resolution", resolution_index), 0, RESOLUTIONS.size() - 1)
	disk_temp_index = clampi(cfg.get_value("graphics", "disk_temp", disk_temp_index), 0, DISK_TEMP_PRESETS.size() - 1)
	vsync_on = bool(cfg.get_value("graphics", "vsync", vsync_on))
	return true

func _save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "quality", quality_index)
	cfg.set_value("graphics", "resolution", resolution_index)
	cfg.set_value("graphics", "disk_temp", disk_temp_index)
	cfg.set_value("graphics", "vsync", vsync_on)
	cfg.save(CONFIG_PATH)

# ---- UI ----

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 200
	add_child(_ui)

	# 半透明遮罩，挡住背景点击
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_ui.add_child(dim)
	_panel = dim

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)

	var panel := PanelContainer.new()
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(420, 0)
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "画质设置"
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)

	# 画质档位
	vbox.add_child(_make_row_label("画质档位"))
	_quality_option = OptionButton.new()
	for p in QUALITY_PRESETS:
		_quality_option.add_item(p["name"])
	_quality_option.selected = quality_index
	vbox.add_child(_quality_option)

	# 分辨率
	vbox.add_child(_make_row_label("分辨率"))
	_resolution_option = OptionButton.new()
	for r in RESOLUTIONS:
		_resolution_option.add_item(r["name"])
	_resolution_option.selected = resolution_index
	vbox.add_child(_resolution_option)

	# 吸积盘温度
	vbox.add_child(_make_row_label("吸积盘温度"))
	_disk_temp_option = OptionButton.new()
	for t in DISK_TEMP_PRESETS:
		_disk_temp_option.add_item(t["name"])
	_disk_temp_option.selected = disk_temp_index
	vbox.add_child(_disk_temp_option)

	# 垂直同步
	_vsync_check = CheckBox.new()
	_vsync_check.text = "垂直同步（防撕裂，建议开）"
	_vsync_check.button_pressed = vsync_on
	vbox.add_child(_vsync_check)

	# 按钮行
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_END
	hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(hbox)

	var apply_btn := Button.new()
	apply_btn.text = "应用"
	apply_btn.pressed.connect(_on_apply_pressed)
	hbox.add_child(apply_btn)

	var close_btn := Button.new()
	close_btn.text = "关闭"
	close_btn.pressed.connect(func(): _set_panel_visible(false))
	hbox.add_child(close_btn)

	var hint := Label.new()
	hint.text = "按 Esc 随时打开/关闭此面板"
	hint.modulate = Color(1, 1, 1, 0.55)
	vbox.add_child(hint)

func _make_row_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l

func _on_apply_pressed() -> void:
	quality_index = _quality_option.selected
	resolution_index = _resolution_option.selected
	disk_temp_index = _disk_temp_option.selected
	vsync_on = _vsync_check.button_pressed
	_apply_all()
	_save_config()
	_set_panel_visible(false)

func _set_panel_visible(v: bool) -> void:
	if _panel:
		_panel.visible = v
		# 打开时同步控件到当前值
		if v:
			_quality_option.selected = quality_index
			_resolution_option.selected = resolution_index
			_disk_temp_option.selected = disk_temp_index
			_vsync_check.button_pressed = vsync_on



