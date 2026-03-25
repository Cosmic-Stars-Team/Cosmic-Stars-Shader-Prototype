extends Camera3D
func _input(event):
	# 改用普通的 P 键，避开 F12 的系统冲突
	if event is InputEventKey and event.pressed and event.keycode == KEY_P:
		take_screenshot()

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
