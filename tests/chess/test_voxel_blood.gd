extends SceneTree

const VoxelBloodStain = preload("res://scripts/chess/voxel_blood_stain.gd")

func _init() -> void:
	print("--- [Voxel Blood Test Suite] Запуск тестов ---")
	_run_tests.call_deferred()

func _run_tests() -> void:
	_test_voxel_stain_generation()
	_test_board_blood_stain_spawn()
	_test_blood_accumulation()
	await _test_clear_blood_stains()
	_test_capture_triggers_blood_stain()
	_test_camera_shake_on_capture()
	await _test_camera_no_tilt_on_enter()
	
	print("--- [Voxel Blood Test Suite] ВСЕ ТЕСТЫ УСПЕШНО ПРОЙДЕНЫ ---")
	quit(0)

## Тест 1: Процедурная генерация воксельного пятна
func _test_voxel_stain_generation() -> void:
	var stain: VoxelBloodStain = VoxelBloodStain.new()
	root.add_child(stain)
	
	var test_pos: Vector3 = Vector3(1.0, 0.405, -2.0)
	stain.create_stain(test_pos, 0, false)
	
	assert(stain.multimesh_instance != null, "MultiMeshInstance3D должен быть создан")
	var mm: MultiMesh = stain.multimesh_instance.multimesh
	assert(mm != null, "MultiMesh должен быть назначен")
	assert(mm.instance_count >= 15, "Пятно должно состоять из достаточного количества вокселей (>=15)")
	assert(mm.use_colors == true, "MultiMesh должен иметь включенную поддержку цветов вокселей")
	
	var mat: StandardMaterial3D = stain.multimesh_instance.material_override as StandardMaterial3D
	assert(mat != null, "Материал крови должен быть назначен")
	assert(mat.vertex_color_use_as_albedo == true, "Материал должен использовать цвета вершин для разнообразия вокселей")
	assert(mat.albedo_color.r > mat.albedo_color.g and mat.albedo_color.r > mat.albedo_color.b, "Базовый цвет материала должен быть красным")
	assert(mat.roughness < 0.25, "Кровь должна иметь влажный блеск (низкий roughness)")
	assert(mat.clearcoat_enabled == true, "Clearcoat должен быть включен для эффекта мокрой пленки")
	
	stain.free()
	print("[PASS] Тест 1: Процедурная генерация воксельного пятна корректна")

## Тест 2: Спавн пятна крови через ChessBoardView
func _test_board_blood_stain_spawn() -> void:
	var board_scene = load("res://scenes/chess/chess_board.tscn")
	assert(board_scene != null, "chess_board.tscn должен загружаться")
	var board = board_scene.instantiate()
	root.add_child(board)
	
	var target_cell: Vector2i = Vector2i(3, 4)
	var stain = board.spawn_blood_stain(target_cell)
	
	assert(stain != null and is_instance_valid(stain), "spawn_blood_stain должен вернуть валидный объект")
	assert(board.blood_container != null, "blood_container должен существовать")
	assert(stain.get_parent() == board.blood_container, "Пятно крови должно находиться в blood_container")
	
	var expected_pos: Vector3 = board.cell_to_local_pos(target_cell)
	assert(is_equal_approx(stain.position.x, expected_pos.x), "Координата X пятна должна соответствовать клетке")
	assert(is_equal_approx(stain.position.z, expected_pos.z), "Координата Z пятна должна соответствовать клетке")
	
	board.free()
	print("[PASS] Тест 2: Спавн пятна крови на доске работает корректно")

## Тест 3: Накопление слоев крови при повторном взятии на одной клетке
func _test_blood_accumulation() -> void:
	var board_scene = load("res://scenes/chess/chess_board.tscn")
	var board = board_scene.instantiate()
	root.add_child(board)
	
	var target_cell: Vector2i = Vector2i(4, 4)
	board.spawn_blood_stain(target_cell)
	assert(board.blood_layers[target_cell] == 1, "Первое взятие: слой 1")
	
	board.spawn_blood_stain(target_cell)
	assert(board.blood_layers[target_cell] == 2, "Второе взятие: слой 2 (накопление)")
	assert(board.blood_container.get_child_count() == 2, "На клетке должно быть 2 слоя пятен")
	
	board.free()
	print("[PASS] Тест 3: Накопление слоев крови при повторных взятиях работает")

## Тест 4: Очистка пятен крови
func _test_clear_blood_stains() -> void:
	var board_scene = load("res://scenes/chess/chess_board.tscn")
	var board = board_scene.instantiate()
	root.add_child(board)
	
	board.spawn_blood_stain(Vector2i(2, 2))
	board.spawn_blood_stain(Vector2i(5, 5))
	assert(board.blood_container.get_child_count() == 2, "Должно быть 2 пятна")
	
	board.clear_blood_stains()
	assert(board.blood_layers.is_empty(), "Словарь слоев должен быть очищен")
	
	# Ожидаем queue_free
	await process_frame
	for child in board.blood_container.get_children():
		assert(child.is_queued_for_deletion(), "Все пятна должны быть помечены на удаление")
		
	board.free()
	print("[PASS] Тест 4: Очистка пятен крови clear_blood_stains работает")

## Тест 5: Взятие фигуры в партии автоматически спавнит пятно крови
func _test_capture_triggers_blood_stain() -> void:
	var board_scene = load("res://scenes/chess/chess_board.tscn")
	var board = board_scene.instantiate()
	root.add_child(board)
	board.is_active = true
	board.white_move_duration = 0.01
	
	# Подготавливаем ситуацию взятия: белая пешка на (3, 3), черная на (4, 4)
	var white_pawn = board.piece_nodes.get(Vector2i(3, 1))
	assert(white_pawn != null, "Белая пешка на (3, 1) должна быть")
	board.piece_nodes.erase(Vector2i(3, 1))
	board.piece_nodes[Vector2i(3, 3)] = white_pawn
	white_pawn.board_pos = Vector2i(3, 3)
	board.logic.grid[3][1] = null
	board.logic.grid[3][3] = { "type": "pawn", "is_white": true, "has_moved": true }
	
	var black_pawn = board.piece_nodes.get(Vector2i(4, 6))
	assert(black_pawn != null, "Черная пешка на (4, 6) должна быть")
	board.piece_nodes.erase(Vector2i(4, 6))
	board.piece_nodes[Vector2i(4, 4)] = black_pawn
	black_pawn.board_pos = Vector2i(4, 4)
	board.logic.grid[4][6] = null
	board.logic.grid[4][4] = { "type": "pawn", "is_white": false, "has_moved": true }
	
	# Белые берут пешку на (4, 4)
	board._execute_player_move(Vector2i(3, 3), Vector2i(4, 4))
	
	assert(board.blood_layers.has(Vector2i(4, 4)), "На клетке (4, 4) должно зарегистрироваться пятно крови")
	assert(board.blood_container.get_child_count() > 0, "В blood_container должен появиться объект вокселей")
	assert(white_pawn.kill_count == 1, "Фигура-убийца должна получить kill_count = 1")
	assert(white_pawn.get_node_or_null("BloodDroplets") != null, "На фигуре должны появиться воксели крови")
	assert(white_pawn.get_node("BloodDroplets").get_child_count() > 0, "К фигуре должны быть прикреплены партиклы крови")
	assert(white_pawn.mesh_instance.material_override == board.white_mat, "Цвет и материал самой фигуры не изменяются")
	
	board.free()
	print("[PASS] Тест 5: Реальное взятие фигуры в игре создает воксельное пятно крови и окрашивает убийцу")

## Тест 6: Тряска камеры при взятии фигуры
func _test_camera_shake_on_capture() -> void:
	var room_scene = load("res://scenes/room.tscn")
	assert(room_scene != null, "room.tscn должен загружаться")
	var room = room_scene.instantiate()
	root.add_child(room)
	
	var player = room.find_child("player", true)
	assert(player != null, "Игрок должен присутствовать в комнате")
	assert(player._trauma == 0.0, "Начальная травма камеры должна быть 0")
	
	# Эмулируем сигнал piece_captured
	player._on_piece_captured("pawn", false)
	assert(player._trauma > 0.5, "После взятия фигуры должна появиться сильная травма тряски")
	
	# Обновляем тряску в процессе
	player._update_camera_shake(0.016)
	assert(player.camera != null, "Камера игрока должна существовать")
	
	# Проверяем, что смещение камеры или крен активированы
	var has_shake: bool = (player.camera.h_offset != 0.0 or player.camera.v_offset != 0.0 or player.camera.rotation.z != 0.0)
	assert(has_shake, "Камера должна получить смещение или крен от тряски")
	
	room.free()
	print("[PASS] Тест 6: Тряска камеры (Screen Shake) при взятии фигуры корректно работает")

## Тест 7: Отсутствие наклона горизонта при подходе к столу сбоку
func _test_camera_no_tilt_on_enter() -> void:
	var room_scene = load("res://scenes/room.tscn")
	var room = room_scene.instantiate()
	root.add_child(room)
	await process_frame
	
	var player = room.find_child("player", true)
	var board = room.find_child("ChessBoard", true)
	player._chess_board_node = board
	
	# Подход игрока сбоку (поворот на 50° и наклон головы)
	player.rotation_degrees.y = 50.0
	player.head.rotation_degrees.x = -20.0
	
	player.enter_board_mode()
	
	# Проверяем крен камеры на середине перехода (t = 0.375)
	if player._cam_tween and player._cam_tween.is_valid():
		player._cam_tween.custom_step(0.375)
		var mid_euler = player.camera.global_transform.basis.orthonormalized().get_euler(EULER_ORDER_YXZ)
		assert(is_zero_approx(mid_euler.z), "Крен камеры (roll) во время перехода должен быть строго 0")
		
		# Завершаем переход
		player._cam_tween.custom_step(0.375)
		var end_euler = player.camera.global_transform.basis.orthonormalized().get_euler(EULER_ORDER_YXZ)
		assert(is_zero_approx(end_euler.z), "Крен камеры (roll) в финальной точке должен быть строго 0")
		
	room.free()
	print("[PASS] Тест 7: Камера не наклоняется вбок при переходе в режим шахмат")
