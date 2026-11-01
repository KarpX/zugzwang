extends SceneTree

# Тест-сьют: Блокировка ходов игрока и ИИ во время активного текста радиоприёмника
func _init() -> void:
	print("--- [Radio Text Blocking Test Suite] Запуск тестов ---")
	_run_tests()

func _run_tests() -> void:
	var board_scene = load("res://scenes/chess/chess_board.tscn")
	assert(board_scene != null, "Сцена res://scenes/chess/chess_board.tscn должна успешно загружаться")
	
	var board: ChessBoardView = board_scene.instantiate()
	root.add_child(board)
	await process_frame
	
	var bus = root.get_node_or_null("EventBus")
	assert(bus != null, "EventBus должен существовать в сцене/дереве")
	
	board.is_active = true
	board.white_move_duration = 0.0
	board.black_move_duration = 0.0
	
	# ТЕСТ 1: is_effect_active() возвращает true, если виден текст радио
	bus.is_radio_text_visible = false
	assert(board.is_effect_active() == false, "При is_radio_text_visible == false is_effect_active() должен быть false")
	
	bus.is_radio_text_visible = true
	assert(board.is_effect_active() == true, "При is_radio_text_visible == true is_effect_active() должен возвращать true!")
	print("[PASS] Тест 1: is_effect_active() корректно возвращает true при активном тексте радио")
	
	# ТЕСТ 2: Клик игрока по фигуре блокируется при активном тексте радио
	board.clear_selection()
	board._on_cell_clicked(Vector2i(4, 1)) # e2 пешка
	assert(board.selected_pos == Vector2i(-1, -1), "Клик по фигуре не должен выбирать фигуру, пока висит текст радио")
	print("[PASS] Тест 2: Выбор фигуры игроком блокируется при активном тексте радио")
	
	# ТЕСТ 3: make_random_player_move() отклоняется при активном тексте радио
	var move_res: bool = board.make_random_player_move()
	assert(move_res == false, "make_random_player_move() должен вернуть false при активном тексте радио")
	assert(board.logic.move_count == 0, "Ход не должен совершаться в логике при активном тексте радио")
	print("[PASS] Тест 3: make_random_player_move() возвращает false при активном тексте радио")
	
	# ТЕСТ 4: Попытка совершения хода при уже выбранной фигуре также блокируется
	bus.is_radio_text_visible = false
	board._on_cell_clicked(Vector2i(4, 1)) # e2 пешка выбрана
	assert(board.selected_pos == Vector2i(4, 1), "Пешка должна быть выбрана при отключенном радио")
	
	bus.is_radio_text_visible = true # Радио включилось
	board._on_cell_clicked(Vector2i(4, 3)) # попытка пойти e2-e4
	assert(board.logic.move_count == 0, "Ход не должен совершиться при клике на целевую клетку, пока активно радио")
	assert(board.logic.is_white_turn == true, "Очередь хода должна оставаться у белых")
	print("[PASS] Тест 4: Перемещение уже выбранной фигуры блокируется при начале радио-сообщения")
	
	# ТЕСТ 5: Ход черных (ИИ) блокируется при активном тексте радио
	# Завершаем ход белых при выключенном радио
	bus.is_radio_text_visible = false
	board._on_cell_clicked(Vector2i(4, 3)) # e2-e4 совершается
	assert(board.logic.move_count == 1, "Ход e2-e4 должен успешно выполниться")
	assert(board.logic.is_white_turn == false, "Сейчас должен быть ход черных")
	
	# Включаем текст радио перед вызовом _check_execute_ai_turn
	bus.is_radio_text_visible = true
	board._white_animation_finished = true
	board._ai_turn_delay_finished = true
	board._is_ai_calculating = false
	
	var moves_before_ai = board.logic.move_count
	board._check_execute_ai_turn()
	assert(board.logic.move_count == moves_before_ai, "ИИ не должен совершать ход, пока висит текст радио!")
	assert(board.logic.is_white_turn == false, "Ход всё еще должен принадлежать черным")
	print("[PASS] Тест 5: _check_execute_ai_turn() блокирует ход черных (ИИ) при активном тексте радио")
	
	# ТЕСТ 6: Завершение радиопередачи (radio_transmission_finished) инициирует ход черных
	bus.is_radio_text_visible = false
	bus.radio_transmission_finished.emit()
	assert(board.logic.move_count == moves_before_ai + 1, "Сигнал radio_transmission_finished должен запустить ход черных")
	assert(board.logic.is_white_turn == true, "Ход должен вернуться к белым после ответа черных")
	print("[PASS] Тест 6: radio_transmission_finished разблокирует и выполняет отложенный ход ИИ черных")
	
	# ТЕСТ 7: После завершения радиопередачи игрок снова может свободно совершать ходы
	assert(board.is_effect_active() == false, "is_effect_active() должен быть false после радиопередачи")
	var white_move_ok = board.make_random_player_move()
	assert(white_move_ok == true, "Игрок должен мочь совершить ход после окончания текста радио")
	print("[PASS] Тест 7: Игрок может совершать ходы после исчезновения текста радио")
	
	board.free()
	bus.reset_game_state()
	print("--- [Radio Text Blocking Test Suite] ВСЕ ТЕСТЫ УСПЕШНО ПРОЙДЕНЫ ---")
	quit(0)
