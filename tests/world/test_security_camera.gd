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
	
	# Тестируем шаг слежения в кадре: приведение цели к границе видимости
	for i in range(10):
		pivot._process(0.1)
		
	var dir_to_player = ((player.global_position + Vector3(0, pivot.vertical_offset, 0)) - pivot.global_position).normalized()
	var forward_cam = -pivot.global_basis.z
	
	# Проверяем, что вектор взгляда камеры удерживает игрока в поле зрения
	var dot_product = forward_cam.dot(dir_to_player)
	assert(dot_product > 0.85, "Камера должна направлять свой передний вектор (-Z) в сторону игрока (dot = %.3f)" % dot_product)
	print("[PASS] Тест 3: Шаг слежения направляет камеру к границе поля зрения игрока (dot = %.3f)" % dot_product)
	
	# Тест 4: Неподвижность камеры при перемещениях игрока ВНУТРИ поля зрения
	var player_center_target = player.global_position + Vector3(0.0, pivot.vertical_offset, 0.0)
	var direct_look = pivot.global_transform.looking_at(player_center_target, Vector3.UP)
	pivot.global_basis = direct_look.basis
	
	var initial_basis = pivot.global_basis
	# Делаем небольшой шаг игроком внутри поля зрения (смещение на 0.3 метра)
	player.global_position += Vector3(0.0, 0.0, 0.3)
	pivot._process(0.05)
	
	var angle_diff = initial_basis.get_rotation_quaternion().angle_to(pivot.global_basis.get_rotation_quaternion())
	assert(angle_diff < 0.001, "Камера не должна двигаться, пока игрок внутри поля зрения (angle_diff = %.4f)" % angle_diff)
	assert(pivot.camera_sound == null or not pivot.camera_sound.playing, "Звук сервопривода не должен играть при шагах внутри поля зрения")
	print("[PASS] Тест 4: Камера неподвижна, пока игрок перемещается внутри поля зрения")
	
	# Тест 5: Движение камеры только при выходе игрока за границу поля зрения
	# Смещаем игрока перпендикулярно лучу зрения на 12 метров (угол станет около 40°)
	player.global_position += Vector3(0.0, 0.0, 12.0)
	var basis_before_push = pivot.global_basis
	pivot._process(0.1)
	
	var angle_moved = basis_before_push.get_rotation_quaternion().angle_to(pivot.global_basis.get_rotation_quaternion())
	assert(angle_moved > 0.01, "Камера должна повернуться, когда игрок смещает границу поля зрения (angle_moved = %.4f)" % angle_moved)
	print("[PASS] Тест 5: Камера поворачивается при выходе игрока за границу поля зрения (angle_moved = %.4f)" % angle_moved)
	
	# Тест 6: Остановка камеры, когда игрок прекращает движение и доворачивает до границы
	for i in range(25):
		pivot._process(0.1)
	
	# Теперь игрок стоит на месте, проверяем следующий кадр
	var basis_at_rest = pivot.global_basis
	pivot._process(0.016)
	var angle_at_rest = basis_at_rest.get_rotation_quaternion().angle_to(pivot.global_basis.get_rotation_quaternion())
	assert(angle_at_rest < 0.001, "Камера должна немедленно остановиться, когда игрок перестал двигать границу (angle_at_rest = %.4f)" % angle_at_rest)
	assert(pivot.camera_sound == null or not pivot.camera_sound.playing, "Звук должен выключаться при остановке движения границы")
	print("[PASS] Тест 6: Камера немедленно останавливается, когда игрок перестает двигать границу")
	
	room.free()
	print("--- [Security Camera Test] ВСЕ ТЕСТЫ УСПЕШНО ПРОЙДЕНЫ ---")
	quit(0)
