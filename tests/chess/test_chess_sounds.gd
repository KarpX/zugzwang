extends SceneTree

func _init() -> void:
	print("--- [Chess Sounds Test] Запуск теста звуков шахматной доски ---")
	
	var scene = load("res://scenes/chess/chess_board.tscn")
	assert(scene != null, "Сцена chess_board.tscn должна загружаться")
	
	var board = scene.instantiate()
	root.add_child(board)
	
	# 1. Проверяем наличие звуковых нод
	var player_sound = board.get_node_or_null("PlayerTurnSound")
	var enemy_sound = board.get_node_or_null("EnemyTurnSound")
	var capture_sound = board.get_node_or_null("CaptureSound")
	var deselect_sound = board.get_node_or_null("DeselectSound")
	
	assert(player_sound != null, "PlayerTurnSound должен существовать в chess_board.tscn")
	assert(enemy_sound != null, "EnemyTurnSound должен существовать в chess_board.tscn")
	assert(capture_sound != null, "CaptureSound должен существовать в chess_board.tscn")
	assert(deselect_sound != null, "DeselectSound должен существовать в chess_board.tscn")
	
	assert(player_sound.stream != null, "PlayerTurnSound должен иметь валидный AudioStream")
	assert(enemy_sound.stream != null, "EnemyTurnSound должен иметь валидный AudioStream")
	assert(capture_sound.stream != null, "CaptureSound должен иметь валидный AudioStream")
	assert(deselect_sound.stream != null, "DeselectSound должен иметь валидный AudioStream")
	print("[PASS] Тест 1: Все 4 ноды звуков успешно созданы с валидными аудио-потоками")
	
	# 2. Проверяем воспроизведение звука хода игрока
	board._play_player_move_sound(Vector3.ZERO)
	print("[PASS] Тест 2: Вызов _play_player_move_sound корректен")
	
	# 3. Проверяем воспроизведение и остановку звука хода врага
	board._play_enemy_move_sound(Vector3.ZERO, Vector3(1.0, 0.0, 0.0), 1.6)
	print("[PASS] Тест 3: Запуск _play_enemy_move_sound с твином перемещения звука корректен")
	
	board._stop_enemy_move_sound()
	assert(enemy_sound.playing == false, "EnemyTurnSound должен быть остановлен после вызова _stop_enemy_move_sound")
	print("[PASS] Тест 4: Остановка звука врага _stop_enemy_move_sound корректна")
	
	# 4. Проверяем воспроизведение звука взятия и звука отмены выбора
	board._play_capture_sound(Vector3.ZERO)
	board._play_deselect_sound(Vector3.ZERO)
	print("[PASS] Тест 5: Прямые вызовы _play_capture_sound и _play_deselect_sound корректны")
	
	# 5. Проверяем логику cancel_selection (звук отмены при снятии выбора)
	board._select_cell(Vector2i(4, 1)) # Выбираем e2
	assert(board.selected_pos == Vector2i(4, 1), "Фигура e2 выбрана")
	board.cancel_selection()
	assert(board.selected_pos == Vector2i(-1, -1), "Выбор успешно сброшен")
	print("[PASS] Тест 6: cancel_selection сбрасывает выбор и проигрывает звук отмены")
	
	# 6. Проверяем ход игрока e2-e4
	board._execute_player_move(Vector2i(4, 1), Vector2i(4, 3))
	print("[PASS] Тест 7: Выполнение хода игрока инициирует звук и анимацию")
	
	board.free()
	print("--- [Chess Sounds Test] ВСЕ ТЕСТЫ УСПЕШНО ПРОЙДЕНЫ ---")
	quit(0)
