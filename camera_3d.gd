extends Camera3D

# 黑洞中心
var target_pos := Vector3.ZERO

# 目标参数（输入直接改这些）
var target_distance := 15.0
var target_yaw := 0.0
var target_pitch := 0.0
var target_aim_offset := Vector2(1.5, 0.2) # 非中心注视偏移：x左右 y上下

# 当前参数（平滑追赶）
var current_distance := 15.0
var current_yaw := 0.0
var current_pitch := 0.0
var current_aim_offset := Vector2(1.5, 0.2)

# 控制项
var smoothing_factor := 0.1
var min_distance := 1.5
var max_distance := 200.0
var zoom_speed := 0.2
var mouse_sensitivity := 0.001
var aim_sensitivity := 0.003
var lock_center := false

var is_dragging := false
var is_aim_dragging := false

const EPS := 0.00001

# FPS 标题栏显示
var _fps_accum := 0.0
var _fps_frames := 0
var _fps_timer := 0.0

func _ready() -> void:
	current_distance = target_distance
	current_yaw = target_yaw
	current_pitch = target_pitch
	current_aim_offset = target_aim_offset
	update_camera()

func _input(event: InputEvent) -> void:
	# 鼠标按键
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			is_dragging = event.pressed
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			is_aim_dragging = event.pressed

		if event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				target_distance = max(target_distance - zoom_speed, min_distance)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				target_distance = min(target_distance + zoom_speed, max_distance)

	# 鼠标移动
	if event is InputEventMouseMotion:
		if is_dragging:
			target_yaw -= event.relative.x * mouse_sensitivity
			target_pitch -= event.relative.y * mouse_sensitivity
			target_pitch = clamp(target_pitch, -PI / 2.0 + 0.01, PI / 2.0 - 0.01)

		if is_aim_dragging:
			target_aim_offset.x += event.relative.x * aim_sensitivity
			target_aim_offset.y -= event.relative.y * aim_sensitivity
			target_aim_offset.x = clamp(target_aim_offset.x, -4.0, 4.0)
			target_aim_offset.y = clamp(target_aim_offset.y, -2.0, 2.0)

	# 快捷键
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_P:
			take_screenshot()
		elif event.keycode == KEY_C:
			lock_center = !lock_center

func _process(delta: float) -> void:
	var t: float = 1.0 - exp(-8.0 * delta) # 帧率无关平滑

	current_distance = _smooth_snap(current_distance, target_distance, t)
	current_yaw = _smooth_snap(current_yaw, target_yaw, t)
	current_pitch = _smooth_snap(current_pitch, target_pitch, t)
	current_aim_offset = current_aim_offset.lerp(target_aim_offset, t)

	update_camera()
	_update_fps_title(delta)

func _update_fps_title(delta: float) -> void:
	# 累积 0.5 秒求平均帧时间，避免标题数字乱跳
	_fps_accum += delta
	_fps_frames += 1
	_fps_timer += delta
	if _fps_timer >= 0.5:
		var avg_ms: float = (_fps_accum / float(_fps_frames)) * 1000.0
		var fps: float = 1000.0 / max(avg_ms, EPS)
		var size := get_viewport().get_visible_rect().size
		DisplayServer.window_set_title(
			"BlackHole  |  %.1f FPS  |  %.2f ms  |  %dx%d"
			% [fps, avg_ms, int(size.x), int(size.y)]
		)
		_fps_accum = 0.0
		_fps_frames = 0
		_fps_timer = 0.0

func _smooth_snap(current: float, target: float, t: float) -> float:
	var v: float = lerpf(current, target, t)
	if abs(v - target) < EPS:
		return target
	return v

func update_camera() -> void:
	# 球坐标 -> 世界位置
	var x := current_distance * cos(current_pitch) * sin(current_yaw)
	var y := current_distance * sin(current_pitch)
	var z := current_distance * cos(current_pitch) * cos(current_yaw)
	position = target_pos + Vector3(x, y, z)

	# 注视点：支持偏移，不再永远锁中心
	var to_center := (target_pos - position).normalized()
	var right := to_center.cross(Vector3.UP)
	if right.length_squared() < 1e-8:
		right = Vector3.RIGHT
	right = right.normalized()
	var up_local := right.cross(to_center).normalized()

	var aim_scale := current_distance * 0.2
	var look_target := target_pos \
		+ right * current_aim_offset.x * aim_scale \
		+ up_local * current_aim_offset.y * aim_scale

	if lock_center:
		look_at(target_pos, Vector3.UP)
	else:
		look_at(look_target, Vector3.UP)

func take_screenshot() -> void:
	var img: Image = get_viewport().get_texture().get_image()
	var time_stamp: String = str(Time.get_unix_time_from_system()).replace(".", "")
	# 存到 user://（系统用户数据目录），不污染工程目录
	var file_path: String = "user://BH_Shot_" + time_stamp + ".png"
	var err: int = img.save_png(file_path)

	if err == OK:
		print("【截图成功】", ProjectSettings.globalize_path(file_path))
	else:
		print("【截图失败】错误码 -> ", err)
		
