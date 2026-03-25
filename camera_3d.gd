extends Camera3D

# 黑洞中心坐标 (默认在世界原点)
var target_pos := Vector3.ZERO 

# --- 目标参数 (滚轮和拖拽改变这些) ---
var target_distance := 15.0 
var target_yaw := 0.0
var target_pitch := 0.0

# --- 渲染当前参数 (Lerp让这些追赶目标) ---
var current_distance := 15.0 
var current_yaw := 0.0
var current_pitch := 0.0

# --- 平滑控制系数 (调节平滑度，越低越柔和) ---
var smoothing_factor := 0.1 # 值越小，平滑过渡越长。建议0.05-0.15

# --- 物理限制和速度 (大幅降低数值以保护眼睛) ---
var min_distance := 1.5   # 最小距离
var max_distance := 200.0 # 最大距离

var zoom_speed := 0.2     # 大幅降低滚轮速度 (从原本的1.5降到0.2)
var mouse_sensitivity := 0.001 # 大幅降低鼠标灵敏度 (从原本的0.005降到0.001)

var is_dragging := false

func _ready():
	# 初始化
	current_distance = target_distance
	current_yaw = target_yaw
	current_pitch = target_pitch
	update_camera()

# 【关键修复】：将鼠标操作与 P 键截图全部合并进同一个输入生命周期函数
func _input(event):
	# 1. 鼠标左键拖拽 (改变目标旋转)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			is_dragging = event.pressed
			
		# 2. 鼠标滚轮缩放 (改变目标距离)
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				target_distance -= zoom_speed
				target_distance = max(target_distance, min_distance)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				target_distance += zoom_speed
				target_distance = min(target_distance, max_distance)

	# 3. 鼠标移动控制目标偏航和俯仰
	if event is InputEventMouseMotion and is_dragging:
		target_yaw -= event.relative.x * mouse_sensitivity
		target_pitch -= event.relative.y * mouse_sensitivity
		
		# 限制俯仰目标角度，防止万向节死锁 (Gimbal Lock)
		target_pitch = clamp(target_pitch, -PI/2 + 0.01, PI/2 - 0.01)

	# 4. P 键截图逻辑
	if event is InputEventKey and event.pressed and event.keycode == KEY_P:
		take_screenshot()

# 每帧运行，进行平滑插值追赶
func _process(delta):
	# 使用 Lerp 进行平滑追赶
	# 距离插值
	current_distance = lerp(current_distance, target_distance, smoothing_factor)
	
	# 旋转插值 (在接近黑洞时，偏离一像素UV采样跳跃极大，必须柔化)
	current_yaw = lerp(current_yaw, target_yaw, smoothing_factor)
	current_pitch = lerp(current_pitch, target_pitch, smoothing_factor)
	
	# 强制每帧更新相机位置，实现无缝过渡
	update_camera()

# 使用插值后的 current 参数计算相机位置
func update_camera():
	# 使用球坐标系
	var x = current_distance * cos(current_pitch) * sin(current_yaw)
	var y = current_distance * sin(current_pitch)
	var z = current_distance * cos(current_pitch) * cos(current_yaw)
	
	position = target_pos + Vector3(x, y, z)
	
	# 强制盯住中心
	look_at(target_pos, Vector3.UP)

# 【关键修复】：补全了截断的代码
func take_screenshot():
	# 获取视口渲染的无损像素数据
	var img = get_viewport().get_texture().get_image()
	
	# 获取 UNIX 时间戳并转为字符串，绝对不会包含非法路径字符
	var time_stamp = str(Time.get_unix_time_from_system()).replace(".", "")
	var file_path = "res://BH_Shot_" + time_stamp + ".png"
	
	# 执行保存并获取底层错误码 (Godot 中 OK 的枚举值为 0)
	var err = img.save_png(file_path)
	
	# 打印精确的执行结果到控制台
	if err == OK:
		print("【截图成功】文件已写入硬盘 -> ", file_path)
	else:
		print("【截图失败】Godot 底层 I/O 错误码 -> ", err)
