extends SceneTree

const ChessLogic = preload("res://scripts/chess/chess_logic.gd")

func _init() -> void:
	print("--- [Chess Logic Test Suite] Запуск тестов шахматных правил ---")
	
	var logic = ChessLogic.new()
	assert(logic != null, "ChessLogic должен создаваться")
	
	# Тест 1: Начальная расстановка
	var white_pawn = logic.get_piece(Vector2i(0, 1))
	assert(white_pawn != null and white_pawn["type"] == "pawn" and white_pawn["is_white"] == true, "Белая пешка на (0, 1)")
	var black_king = logic.get_piece(Vector2i(4, 7))
	assert(black_king != null and black_king["type"] == "king" and black_king["is_white"] == false, "Черный король на (4, 7)")
	print("[PASS] Тест 1: Начальная расстановка корректна")
	
	# Тест 2: Ходы пешки на 1 и 2 клетки вперед
	var pawn_moves = logic.get_legal_moves(Vector2i(4, 1))
	assert(Vector2i(4, 2) in pawn_moves, "Пешка может пойти на e3")
	assert(Vector2i(4, 3) in pawn_moves, "Пешка может пойти на e4")
	print("[PASS] Тест 2: Ходы пешки (1 и 2 клетки)")
	
	# Тест 3: Ход пешкой e2-e4
	var res = logic.make_move(Vector2i(4, 1), Vector2i(4, 3))
	assert(res["success"] == true, "Ход e2-e4 успешен")
	assert(logic.is_white_turn == false, "Теперь очередь черных")
	print("[PASS] Тест 3: Выполнение хода e2-e4")
	
	# Тест 4: Генерация хода жадным ИИ для черных
	var ai_move = logic.get_best_ai_move()
	assert(ai_move.has("from") and ai_move.has("to"), "ИИ нашел легальный ход")
	var ai_res = logic.make_move(ai_move["from"], ai_move["to"])
	assert(ai_res["success"] == true, "Ход ИИ успешно выполнен")
	assert(logic.is_white_turn == true, "Снова очередь белых")
	print("[PASS] Тест 4: Жадный ИИ черных сделал ход: ", ai_move["from"], " -> ", ai_move["to"])
	
	# Тест 5: Конь ходит буквой Г
	var knight_moves = logic.get_legal_moves(Vector2i(1, 0))
	assert(Vector2i(0, 2) in knight_moves or Vector2i(2, 2) in knight_moves, "Конь может прыгнуть на c3 или a3")
	print("[PASS] Тест 5: Ход коня буквой Г")
	
	print("--- [Chess Logic Test Suite] ВСЕ ТЕСТЫ ПРОЙДЕНЫ УСПЕШНО ---")
	quit(0)
