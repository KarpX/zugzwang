extends SceneTree

# Тест-сьют: Случайный ход белых по сигналу EventBus и отсутствие блокировок при перебое света / радио
func _init() -> void:
	print("--- [Random Player Move & Unblocked Board Test Suite] Запуск тестов ---")
	
	_run_tests()

func _run_tests() -> void:
	var board_scene = load("res://scenes/chess/chess_board.tscn")
	assert(board_scene != null, "Сцена res://scenes/chess/chess_board.tscn должна загружаться")
	
	var board: ChessBoardView = board_scene.instantiate()
	root.add_child(board)
	await process_frame
	
	var bus = root.get_node_or_null("EventBus")
	board.is_active = true
	board.white_move_duration = 0.0
	board.black_move_duration = 0.0
	
	# ТЕСТ 1: Проверка get_all_legal_moves
	var moves: Array[Dictionary] = board.logic.get_all_legal_moves(true)
	# В начальной позиции у белых 20 легальных ходов (16 пешечных + 4 конных)
	assert(moves.size() == 20, "В начальной позиции должно быть ровно 20 легальных ходов за белых, получено: %d" % moves.size())
	for m in moves:
		assert(m.has("from") and m.has("to"), "Каждый ход должен содержать ключи 'from' и 'to'")
		assert(board.logic.get_piece(m["from"]) != null, "Клетка отправления должна содержать фигуру")
		assert(board.logic.get_piece(m["from"])["is_white"] == true, "Фигура должна принадлежать белым")
	print("[PASS] Тест 1: logic.get_all_legal_moves(true) возвращает все 20 легальных ходов белых в дебюте")
	
	# ТЕСТ 2: Перебой света НЕ блокирует ввод игрока (is_effect_active == false)
	board._is_light_trouble_active = true
	if bus:
		bus.is_lamp_trouble_active = true
	assert(board.is_effect_active() == false, "is_effect_active() не должен быть true из-за перебоя света")
	
	# Клик по клетке белой фигуры работает во время перебоя
	board._on_cell_clicked(Vector2i(4, 1)) # e2 пешка
	assert(board.selected_pos == Vector2i(4, 1), "Игрок может выбрать фигуру во время перебоя света")
	print("[PASS] Тест 2: Перебой света не блокирует ввод игрока (клик и выбор фигуры работают)")
	
	# ТЕСТ 3: make_random_player_move сбрасывает выбранную клетку и делает случайный ход
	var initial_move_count: int = board.logic.move_count
	var move_success: bool = board.make_random_player_move()
	assert(move_success == true, "make_random_player_move() должен вернуть true")
	assert(board.selected_pos == Vector2i(-1, -1), "Выбор фигуры должен быть сброшен после случайного хода")
	assert(board.logic.move_count == initial_move_count + 1, "move_count должен увеличиться на 1")
	assert(board.logic.is_white_turn == false, "Ход должен перейти к черным")
	print("[PASS] Тест 3: make_random_player_move() сбрасывает выбор и успешно совершает случайный легальный ход")
	
	# ТЕСТ 4: make_random_player_move возвращает false, если сейчас ход черных
	var cannot_move: bool = board.make_random_player_move()
	assert(cannot_move == false, "make_random_player_move() должен вернуть false на ходе черных")
	print("[PASS] Тест 4: make_random_player_move() отклоняется, если сейчас не ход белых")
	
	# ТЕСТ 5: Ход черных (ИИ) не блокируется перебоем света
	board._is_light_trouble_active = true
	if bus:
		bus.is_lamp_trouble_active = true
	var moves_before_ai = board.logic.move_count
	board._execute_ai_turn()
	assert(board.logic.move_count == moves_before_ai + 1, "Бот должен сразу совершить ход, не откладывая из-за перебоя света")
	assert(board.logic.is_white_turn == true, "Ход должен вернуться к белым")
	print("[PASS] Тест 5: Ход ИИ не блокируется и не откладывается при перебое света")
	
	# ТЕСТ 6: Срабатывание по сигналу EventBus bus.random_player_move_requested
	if bus:
		board.selected_pos = Vector2i(0, 1) # Выберем фигуру
		var moves_before_signal = board.logic.move_count
		bus.random_player_move_requested.emit()
		assert(board.logic.move_count == moves_before_signal + 1, "Сигнал EventBus должен запустить случайный ход белых")
		assert(board.selected_pos == Vector2i(-1, -1), "Выбор фигуры должен быть сброшен")
		print("[PASS] Тест 6: Сигнал bus.random_player_move_requested корректно инициирует случайный ход")
	
	board.free()
	if bus:
		bus.reset_game_state()
	print("--- [Random Player Move & Unblocked Board Test Suite] ВСЕ ТЕСТЫ УСПЕШНО ПРОЙДЕНЫ ---")
	quit(0)
