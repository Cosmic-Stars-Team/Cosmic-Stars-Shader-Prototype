extends CanvasLayer
## 黑洞科普标注层：在引力透镜/光子环等特征处显示指示标记 + 名字框，
## 点击名字框展开详细介绍。按 H 切换显隐，Esc 关闭介绍面板。
## 3D 锚定：标记随相机运动跟着特征移动。纯叠加层，不影响渲染。

const MATERIAL_PATH := "res://materials/blackhole_live.tres"

# 黑洞阴影（光子环）的视半径，单位 Rs。理论值 sqrt(27)/2 ≈ 2.6。
const APPARENT_SHADOW_RS := 2.6
# 采样方位数：用于在盘上找“最朝向相机”“最靠近镜头”的点
const AZIMUTH_SAMPLES := 64

# ---- 科普文案（集中在此，随便改）----
# type 决定锚定方式：
#   "center" 黑洞中心（事件视界/阴影）
#   "shadow" 相对阴影边缘的屏幕方向（screen_dir 指向）
#   "disk_near"  盘上离镜头最近的可见点（半径由 radius_ratio 决定，相对内外缘 0~1）
#   "doppler"    盘上轨道速度最朝向相机的点（最亮的多普勒增亮侧，动态换边）
const FEATURES := [
	{
		"id": "event_horizon", "type": "center",
		"name": "事件视界 · 黑洞阴影",
		"desc": "中心这片纯黑不是“洞口”，而是[b]事件视界[/b]：引力强到连光都无法逃离的临界面。我们看到的黑色圆面比视界本身更大，约为 2.6 倍史瓦西半径——因为黑洞把背后与周围的光线弯折、吞没，形成了放大的“阴影”。",
	},
	{
		"id": "photon_ring", "type": "shadow", "screen_dir": Vector2(0.90, -0.44), "radius_mult": 1.0,
		"name": "光子环",
		"desc": "阴影边缘那圈极细极亮的光带是[b]光子环[/b]：光线在这里被引力捕获、绕黑洞转了一圈甚至多圈后才射向我们。它叠加了来自四面八方的光，是整幅画面里最锐利的结构，也是黑洞强引力透镜的直接证据。",
	},
	{
		"id": "lensing_arc", "type": "shadow", "screen_dir": Vector2(0.0, -1.22), "radius_mult": 1.0,
		"name": "引力透镜 · 上方光弧",
		"desc": "黑洞正上方这道横跨的光弧，其实是吸积盘[b]远侧[/b]的像。盘背面发出的光被黑洞的引力弯折、绕到上方再进入镜头，于是本该被挡住的远侧盘被“抬”到了黑洞头顶。这就是[b]引力透镜[/b]：质量弯曲时空，光线随之走弯路。",
	},
	{
		"id": "accretion_disk", "type": "disk_near", "radius_ratio": 0.55, "screen_dir": Vector2(-0.7, 1.0),
		"name": "吸积盘",
		"desc": "环绕黑洞的炽热气体盘。物质被引力拉入时高速旋转、相互摩擦，温度可达数百万度并发出强光。越靠内侧越热越蓝，越外侧越冷越红——画面里的颜色梯度就是温度梯度。",
	},
	{
		"id": "doppler_beaming", "type": "doppler", "radius_ratio": 0.45,
		"name": "相对论集束 · 多普勒增亮",
		"desc": "盘内气体以接近光速绕转。[b]朝向[/b]我们运动的一侧被“相对论集束”效应增亮、并蓝移；[b]远离[/b]的一侧变暗、红移。所以盘的一边明显更亮更蓝——这是狭义相对论的直接体现。绕黑洞转一圈，这个亮侧会随视角换边。",
	},
	{
		"id": "gravitational_redshift", "type": "disk_near", "radius_ratio": 0.04, "screen_dir": Vector2(0.85, 1.0),
		"name": "引力红移 · 内缘",
		"desc": "盘最内侧紧贴视界处，光要从极深的引力势阱里爬出来，损失能量、波长被拉长——即[b]引力红移[/b]。越靠近视界，光越偏红、越暗，最终在视界处趋于无限红移而消失。",
	},
]

# ---- 运行时状态 ----
var _camera: Camera3D
var _rs := 4.0
var _inner_radius := 10.0
var _outer_radius := 24.0
var _disk_normal := Vector3(0, 1, 0)
var _disk_t1 := Vector3(1, 0, 0)   # 盘平面内基向量
var _disk_t2 := Vector3(0, 0, 1)

var _overlay: Control                # 画准星 + 引线
var _labels: Array[Button] = []      # 名字框，逐帧定位
var _markers: Array[Vector2] = []    # 每个特征当前的标记屏幕坐标（x=NAN 表示隐藏）
var _annotations_visible := true

var _panel: PanelContainer           # 详细介绍面板
var _panel_title: Label
var _panel_body: RichTextLabel

func _ready() -> void:
	layer = 130   # 在后处理(128)之上，画质 UI(200)之下
	_load_params()
	_build_overlay()
	_build_labels()
	_build_panel()
	_markers.resize(FEATURES.size())
	set_process(true)

func _load_params() -> void:
	var mat := load(MATERIAL_PATH) as ShaderMaterial
	if mat:
		_rs = float(mat.get_shader_parameter("Rs"))
		var inner_ratio := float(mat.get_shader_parameter("disk_inner_radius_ratio"))
		var outer_ratio := float(mat.get_shader_parameter("disk_outer_radius_ratio"))
		var tilt := float(mat.get_shader_parameter("disk_tilt"))
		_inner_radius = inner_ratio * _rs
		_outer_radius = outer_ratio * _rs
		_disk_normal = Vector3(tilt, 1.0, 0.0).normalized()
	# 盘平面内的两条正交基（仅用于采样方位）
	var seed := Vector3(0, 0, 1)
	if abs(_disk_normal.dot(seed)) > 0.95:
		seed = Vector3(1, 0, 0)
	_disk_t1 = _disk_normal.cross(seed).normalized()
	_disk_t2 = _disk_normal.cross(_disk_t1).normalized()

# ---- UI 构建 ----

func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_on_overlay_draw)
	add_child(_overlay)

func _build_labels() -> void:
	for i in FEATURES.size():
		var f: Dictionary = FEATURES[i]
		var btn := Button.new()
		btn.text = f["name"]
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 15)
		btn.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
		btn.add_theme_color_override("font_hover_color", Color(1, 1, 1))
		_style_label_box(btn)
		btn.pressed.connect(_on_label_pressed.bind(i))
		add_child(btn)
		_labels.append(btn)

func _style_label_box(btn: Button) -> void:
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.04, 0.06, 0.10, 0.74)
		sb.border_color = Color(0.55, 0.78, 1.0, 0.85)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(4)
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		sb.content_margin_top = 3
		sb.content_margin_bottom = 3
		if state == "hover" or state == "pressed":
			sb.bg_color = Color(0.10, 0.16, 0.24, 0.88)
			sb.border_color = Color(0.75, 0.90, 1.0, 1.0)
		btn.add_theme_stylebox_override(state, sb)

func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(440, 0)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.05, 0.09, 0.94)
	sb.border_color = Color(0.55, 0.78, 1.0, 0.9)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(18)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_panel.add_child(vbox)

	_panel_title = Label.new()
	_panel_title.add_theme_font_size_override("font_size", 22)
	_panel_title.add_theme_color_override("font_color", Color(0.85, 0.93, 1.0))
	vbox.add_child(_panel_title)

	_panel_body = RichTextLabel.new()
	_panel_body.bbcode_enabled = true
	_panel_body.fit_content = true
	_panel_body.custom_minimum_size = Vector2(404, 0)
	_panel_body.add_theme_font_size_override("normal_font_size", 16)
	vbox.add_child(_panel_body)

	var close_btn := Button.new()
	close_btn.text = "关闭"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(_close_panel)
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_END
	hbox.add_child(close_btn)
	vbox.add_child(hbox)

# ---- 每帧更新 ----

func _process(_delta: float) -> void:
	if not _annotations_visible:
		return
	if _camera == null or not is_instance_valid(_camera):
		_camera = get_viewport().get_camera_3d()
		if _camera == null:
			return

	var center_screen := _project(Vector3.ZERO)
	var shadow_px := _apparent_shadow_px(center_screen)

	for i in FEATURES.size():
		var f: Dictionary = FEATURES[i]
		var marker := _feature_marker(f, center_screen, shadow_px)
		_markers[i] = marker
		var btn: Button = _labels[i]
		if is_nan(marker.x):
			btn.visible = false
			continue
		btn.visible = true
		# 名字框放在标记的外侧（远离中心方向），避免压住特征本身
		var out_dir := (marker - center_screen)
		out_dir = out_dir.normalized() if out_dir.length() > 1.0 else Vector2(1, -1).normalized()
		var anchor := marker + out_dir * 26.0
		var sz := btn.get_combined_minimum_size()
		# 若在中心右/下侧，框朝右展开；左/上侧朝左，尽量不出屏
		var pos := anchor
		if out_dir.x < 0:
			pos.x = anchor.x - sz.x
		if out_dir.y < 0:
			pos.y = anchor.y - sz.y
		var vp := get_viewport().get_visible_rect().size
		pos.x = clampf(pos.x, 4.0, vp.x - sz.x - 4.0)
		pos.y = clampf(pos.y, 4.0, vp.y - sz.y - 4.0)
		btn.position = pos
		btn.set_meta("anchor", anchor)   # 引线终点
	_overlay.queue_redraw()

# 返回某特征的标记屏幕坐标；x=NAN 表示不可见
func _feature_marker(f: Dictionary, center_screen: Vector2, shadow_px: float) -> Vector2:
	var hidden := Vector2(NAN, NAN)
	match f["type"]:
		"center":
			if _camera.is_position_behind(Vector3.ZERO):
				return hidden
			return center_screen
		"shadow":
			if is_nan(center_screen.x):
				return hidden
			var d: Vector2 = f["screen_dir"]
			return center_screen + d.normalized() * shadow_px * float(f["radius_mult"]) * d.length()
		"disk_near":
			var r := lerpf(_inner_radius, _outer_radius, float(f["radius_ratio"]))
			return _project_disk_biased(r, f["screen_dir"], center_screen)
		"doppler":
			var r := lerpf(_inner_radius, _outer_radius, float(f["radius_ratio"]))
			return _project_disk_doppler(r)
	return hidden

# ---- 几何辅助 ----

func _project(world: Vector3) -> Vector2:
	if _camera.is_position_behind(world):
		return Vector2(NAN, NAN)
	return _camera.unproject_position(world)

func _disk_point(radius: float, azimuth: float) -> Vector3:
	return radius * (cos(azimuth) * _disk_t1 + sin(azimuth) * _disk_t2)

# 在给定半径的盘环上采样，挑屏幕上最偏向 screen_dir 方向（相对中心）的可见点。
# 这样不同特征用不同方向就能确定性地散开，不会全堆在底部。
func _project_disk_biased(radius: float, screen_dir: Vector2, center_screen: Vector2) -> Vector2:
	var dir := screen_dir.normalized()
	var best := Vector2(NAN, NAN)
	var best_score := -INF
	for k in AZIMUTH_SAMPLES:
		var az := TAU * float(k) / float(AZIMUTH_SAMPLES)
		var wp := _disk_point(radius, az)
		if _camera.is_position_behind(wp):
			continue
		var sp := _camera.unproject_position(wp)
		var score := (sp - center_screen).dot(dir)
		if score > best_score:
			best_score = score
			best = sp
	return best

# 盘环上轨道速度最朝向相机的点（最强多普勒增亮/蓝移侧）
func _project_disk_doppler(radius: float) -> Vector2:
	var best := Vector2(NAN, NAN)
	var best_dot := -INF
	for k in AZIMUTH_SAMPLES:
		var az := TAU * float(k) / float(AZIMUTH_SAMPLES)
		var wp := _disk_point(radius, az)
		# 开普勒轨道速度方向：n × r̂（与 shader 中 cloud_velocity 取向一致）
		var vel_dir := _disk_normal.cross(wp.normalized())
		var to_cam := (_camera.global_position - wp).normalized()
		var d := vel_dir.dot(to_cam)
		if d > best_dot and not _camera.is_position_behind(wp):
			best_dot = d
			best = _camera.unproject_position(wp)
	return best

# 阴影（光子环）的视半径，单位像素。用一个垂直于视线、距中心 2.6Rs 的点标定。
func _apparent_shadow_px(center_screen: Vector2) -> float:
	if is_nan(center_screen.x):
		return 0.0
	var right := _camera.global_transform.basis.x.normalized()
	var edge := right * (APPARENT_SHADOW_RS * _rs)
	if _camera.is_position_behind(edge):
		return 0.0
	return _camera.unproject_position(edge).distance_to(center_screen)

# ---- 输入 / 绘制 / 面板 ----

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_H:
			_toggle_visible()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and _panel.visible:
			_close_panel()
			get_viewport().set_input_as_handled()

func _toggle_visible() -> void:
	_annotations_visible = not _annotations_visible
	for btn in _labels:
		btn.visible = false   # _process 下一帧会按需恢复
	if not _annotations_visible:
		_close_panel()
	_overlay.queue_redraw()

func _on_overlay_draw() -> void:
	if not _annotations_visible:
		return
	var line_col := Color(0.62, 0.82, 1.0, 0.8)
	for i in FEATURES.size():
		var m: Vector2 = _markers[i]
		if is_nan(m.x) or not _labels[i].visible:
			continue
		var r := 7.0
		_overlay.draw_arc(m, r, 0, TAU, 24, line_col, 1.5, true)
		_overlay.draw_line(m - Vector2(r + 4, 0), m - Vector2(r - 2, 0), line_col, 1.5, true)
		_overlay.draw_line(m + Vector2(r - 2, 0), m + Vector2(r + 4, 0), line_col, 1.5, true)
		_overlay.draw_line(m - Vector2(0, r + 4), m - Vector2(0, r - 2), line_col, 1.5, true)
		_overlay.draw_line(m + Vector2(0, r - 2), m + Vector2(0, r + 4), line_col, 1.5, true)
		if _labels[i].has_meta("anchor"):
			var a: Vector2 = _labels[i].get_meta("anchor")
			_overlay.draw_line(m, a, line_col, 1.2, true)

func _on_label_pressed(index: int) -> void:
	var f: Dictionary = FEATURES[index]
	_panel_title.text = f["name"]
	_panel_body.text = f["desc"]
	_panel.visible = true

func _close_panel() -> void:
	_panel.visible = false
