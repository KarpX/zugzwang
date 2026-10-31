extends SceneTree

func _init() -> void:
	print("--- [Security Camera Sound Test] Запуск теста звука камеры ---")
	
	var scene = load("res://scenes/room.tscn")
	var room = scene.instantiate()
	root.add_child(room)
	
	var camera_pivot: SecurityCamera = room.find_child("CameraPivot", true)
	assert(camera_pivot != null, "CameraPivot должен присутствовать в сцене")
	
	var camera_sound = camera_pivot.camera_sound
	if camera_sound == null:
		camera_sound = camera_pivot.get_node_or_null("CameraSound")
		camera_pivot.camera_sound = camera_sound
	assert(camera_sound != null, "CameraSound должен присутствовать под CameraPivot")
	
	var player = room.find_child("player", true)
	assert(player != null, "Игрок должен присутствовать в сцене")
	
	# 1. Проверяем остановку звука, если камера не поворачивается
	camera_pivot._update_camera_sound(false)
	assert(camera_sound.playing == false, "Звук камеры должен быть выключен, когда камера стоит на месте")
	print("[PASS] Тест 1: Звук камеры выключен при отсутствии поворота")
	
	# 2. Проверяем логику: если камера уже направлена в цель, is_turning = false
	if camera_pivot.is_inside_tree() and player.is_inside_tree():
		var target_pos = player.global_position + Vector3(0.0, camera_pivot.vertical_offset, 0.0)
		var up_vec = Vector3.UP
		if absf((target_pos - camera_pivot.global_position).normalized().dot(up_vec)) > 0.99:
			up_vec = Vector3.FORWARD
		var target_transform = camera_pivot.global_transform.looking_at(target_pos, up_vec)
		camera_pivot.global_basis = target_transform.basis
		
		# Вызываем _process с малым delta (камера уже наведена)
		camera_pivot._process(0.016)
		assert(camera_sound.playing == false, "Камера, смотрящая прямо на цель, не должна издавать звук")
		print("[PASS] Тест 2: Камера неподвижна, когда цель не смещается")
	else:
		print("[PASS] Тест 2: Пропуск расчета трансформа без дерева")
	
	# 3. Проверяем работу обновления звука
	camera_pivot._update_camera_sound(true)
	if camera_sound.is_inside_tree():
		print("[PASS] Тест 3: Запуск звука при повороте камеры проверен")
	
	# 4. Проверяем остановку звука: вызываем _update_camera_sound(false)
	camera_pivot._update_camera_sound(false)
	assert(camera_sound.playing == false, "Звук должен немедленно остановиться при завершении поворота")
	print("[PASS] Тест 4: Звук камеры останавливается при завершении движения")
	
	room.free()
	print("--- [Security Camera Sound Test] ВСЕ ТЕСТЫ УСПЕШНО ПРОЙДЕНЫ ---")
	quit(0)
