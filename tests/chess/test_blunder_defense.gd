extends SceneTree

func _init() -> void:
	print("--- [Blunder Defense Test Suite] Запуск тестов защиты фигур ---")
	
	# Тест 1: Слон под боем пешки белых (d4 атакует Bc5) -> бот не отдает слона!
	var logic = ChessLogic.new()
	logic.reset_board(1)
	logic.make_move(Vector2i(4, 1), Vector2i(4, 3)) # 1. e4
	logic.make_move(Vector2i(4, 6), Vector2i(4, 4)) # 1... e5
	logic.make_move(Vector2i(6, 0), Vector2i(5, 2)) # 2. Nf3
	logic.make_move(Vector2i(5, 7), Vector2i(2, 4)) # 2... Bc5
	logic.make_move(Vector2i(3, 1), Vector2i(3, 3)) # 3. d4 (атакует Bc5!)
	
	var grid = logic.clone_grid()
	var b_move = ChessBot.choose_best_move(grid, 1, 0, logic.en_passant_target)
	var p = logic.get_piece(b_move["from"])
	
	# Бот должен ликвидировать угрозу (e5xd4) или увести/закрыть слона, но НЕ играть случайный ход пешкой h7
	assert(b_move["from"] == Vector2i(4, 4) or b_move["from"] == Vector2i(2, 4), 
		"Бот должен защитить слона или устранить атакующую пешку, получен ход: %s" % str(b_move))
	print("[PASS] Тест 1: Бот защитил слона под атакой пешки: %s с %s на %s" % [p["type"], b_move["from"], b_move["to"]])
	
	# Тест 2: Слон под атакой пешки a3 (Bb4 под боем a3) -> бот не отдает слона
	logic.reset_board(1)
	logic.make_move(Vector2i(4, 1), Vector2i(4, 3)) # 1. e4
	logic.make_move(Vector2i(4, 6), Vector2i(4, 4)) # 1... e5
	logic.make_move(Vector2i(6, 0), Vector2i(5, 2)) # 2. Nf3
	logic.make_move(Vector2i(5, 7), Vector2i(1, 3)) # 2... Bb4
	logic.make_move(Vector2i(0, 1), Vector2i(0, 2)) # 3. a3 (атакует Bb4!)
	
	grid = logic.clone_grid()
	b_move = ChessBot.choose_best_move(grid, 1, 0, logic.en_passant_target)
	p = logic.get_piece(b_move["from"])
	# Слон должен уйти, разменяться (Bxc3) или контратаковать по центру (d5)
	assert(b_move["from"] == Vector2i(1, 3) or b_move["to"] == Vector2i(3, 4),
		"Бот не должен игнорировать прямую атаку на слона: %s" % str(b_move))
	print("[PASS] Тест 2: Бот адекватно ответил на атаку слона пешкой a3: %s" % str(b_move))
	
	# Тест 3: SEE и защита фигуры своими фигурами
	var board = ChessBot.make_light_board(logic.grid)
	assert(ChessBot.is_square_attacked(board, Vector2i(3, 0), true), "Белый ферзь на d1 защищает/атакует свое поле")
	assert(ChessBot.is_square_attacked(board, Vector2i(5, 2), true), "Белый конь на f3 защищает свои клетки")
	print("[PASS] Тест 3: Защита фигур союзными нодами корректно определяется движком")
	
	print("--- [Blunder Defense Test Suite] ВСЕ ТЕСТЫ ПРОЙДЕНЫ УСПЕШНО ---")
	quit()

