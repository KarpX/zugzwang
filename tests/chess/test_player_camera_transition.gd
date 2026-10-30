extends SceneTree

func _init() -> void:
	print("--- [Player Camera Transition Test] Запуск теста взаимодействия со столом ---")
	
	var scene = load("res://scenes/room.tscn")
	var room = scene.instantiate()
	root.add_child(room)
	
	var player = room.find_child("player", true)
	var board = room.find_child("ChessBoard", true)
	player._chess_board_node = board
	
	assert(player != null, "Игрок должен присутствовать в сцене")
	assert(board != null, "Шахматная доска должна присутствовать в сцене")
	
	# 1. Позиционируем игрока около стола (Z = 22)
	player.position = Vector3(16.0, 5.18, 22.0)
	var horiz_dist: float = Vector2(player.position.x, player.position.z).distance_to(Vector2(player.table_world_center.x, player.table_world_center.z))
	player.is_near_table = (horiz_dist <= player.table_interact_distance)
	
	assert(player.is_near_table == true, "Игрок около стола должен распознавать близость к столу")
	print("[PASS] Тест 1: Игрок распознает близость к шахматному столу")
	
	# 2. Садимся за стол
	player.enter_board_mode()
	assert(player.is_board_mode == true, "is_board_mode должен стать true")
	assert(player.can_walk == false, "can_walk должен быть false за столом")
	assert(player.can_move == false, "can_move должен быть false за столом")
	assert(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Курсор мыши должен быть видимым для игры в шахматы")
	assert(board.is_active == true, "Доска должна стать активной для кликов")
	print("[PASS] Тест 2: Режим игры за столом успешно активирован, камера переходит к доске")
	
	# 3. Встаем из-за стола
	player.exit_board_mode()
	assert(player.is_board_mode == false, "is_board_mode должен стать false")
	if player._cam_tween and player._cam_tween.is_valid():
		player._cam_tween.custom_step(1.0) # Завершаем анимацию возврата камеры
	assert(player.can_walk == true, "Ходьба должна снова быть разрешена после завершения твина")
	assert(player.can_move == true, "Вращение камеры должно снова быть разрешено")
	assert(board.is_active == false, "Доска должна деактивироваться")
	print("[PASS] Тест 3: Выход из-за стола успешно деактивирует режим доски и возвращает управление")
	
	room.free()
	print("--- [Player Camera Transition Test] ВСЕ ТЕСТЫ УСПЕШНО ПРОЙДЕНЫ ---")
	quit(0)
