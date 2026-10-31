extends SceneTree

const SecurityCameraScript = preload("res://scripts/world/security_camera.gd")

func _init() -> void:
	_run_tests.call_deferred()

func _run_tests() -> void:
	print("--- [Security Camera Test] Запуск теста слежения камеры ---")
	
	var room_scene = load("res://scenes/room.tscn")
	assert(room_scene != null, "Сцена res://scenes/room.tscn должна успешно загружаться")
	
	var room = room_scene.instantiate()
	assert(room != null, "Инстанцирование room.tscn должно проходить успешно")
	root.add_child(room)
	
	# Ждем 1 кадр для обновления transforms и inside_tree
	await process_frame
	
	# Проверяем наличие узлов камеры
	var base = room.get_node_or_null("walls/CameraBase")
	assert(base != null, "walls/CameraBase должен существовать")
	
	var pivot = base.get_node_or_null("CameraPivot")
	assert(pivot != null, "CameraPivot должен существовать внутри CameraBase")
	assert(pivot.get_script() == SecurityCameraScript, "CameraPivot должен использовать security_camera.gd")
	
	var spotlight: SpotLight3D = pivot.get_node_or_null("NightVisionSpotLight") as SpotLight3D
	assert(spotlight != null, "NightVisionSpotLight должен существовать")
	assert(spotlight.spot_angle <= 20.0, "spot_angle должен быть сфокусированным (<= 20°)")
	assert(spotlight.light_energy <= 2.5, "light_energy должен быть умеренным (<= 2.5)")
	print("[PASS] Тест 1: Сфокусированное освещение (spot_angle = %s, light_energy = %s)" % [spotlight.spot_angle, spotlight.light_energy])
	
	# Проверяем цель слежения
	var player = room.get_node_or_null("player")
	assert(player != null, "Игрок должен существовать в комнате")
	assert(player.is_in_group("player"), "Игрок должен быть в группе 'player'")
	
	pivot._resolve_target()
	assert(pivot.target == player, "Камера должна автоматически обнаружить игрока как цель")
	print("[PASS] Тест 2: Камера автоматически захватывает игрока как цель")
	
	# Тестируем шаг слежения в кадре
	for i in range(10):
		pivot._process(0.1)
		
	var dir_to_player = ((player.global_position + Vector3(0, pivot.vertical_offset, 0)) - pivot.global_position).normalized()
	var forward_cam = -pivot.global_basis.z
	
	# Проверяем, что вектор взгляда камеры направлен на игрока
	var dot_product = forward_cam.dot(dir_to_player)
	assert(dot_product > 0.85, "Камера должна направлять свой передний вектор (-Z) в сторону игрока (dot = %.3f)" % dot_product)
	print("[PASS] Тест 3: Шаг слежения плавно направляет камеру на игрока (dot = %.3f)" % dot_product)
	
	room.free()
	print("--- [Security Camera Test] ВСЕ ТЕСТЫ УСПЕШНО ПРОЙДЕНЫ ---")
	quit(0)
