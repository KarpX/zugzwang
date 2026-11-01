extends SceneTree

const ChessLogic = preload("res://scripts/chess/chess_logic.gd")
const ChessBot = preload("res://scripts/chess/chess_bot.gd")
const ChessBoardView = preload("res://scripts/chess/chess_board_view.gd")

func _init() -> void:
	print("--- [En Passant Test Suite] Запуск тестов ---")
	_run_tests.call_deferred()

func _run_tests() -> void:
	_test_white_captures_en_passant()
	_test_black_captures_en_passant()
	_test_en_passant_expires_after_one_turn()
	_test_en_passant_pin_prevents_illegal_move()
	_test_bot_finds_en_passant_capture()
	_test_board_view_en_passant_3d()
	print("--- [En Passant Test Suite] ВСЕ ТЕСТЫ УСПЕШНО ПРОЙДЕНЫ ---")
	quit(0)

## Тест 1: Белые берут пешку черных на проходе
func _test_white_captures_en_passant() -> void:
	var logic = ChessLogic.new()
	# 1. e4 h6
	logic.make_move(Vector2i(4, 1), Vector2i(4, 3))
	logic.make_move(Vector2i(7, 6), Vector2i(7, 5))
	
	# 2. e5 d5 (черная пешка делает двойной ход d7-d5)
	logic.make_move(Vector2i(4, 3), Vector2i(4, 4)) # Белая пешка на e5
	var d5_res = logic.make_move(Vector2i(3, 6), Vector2i(3, 4)) # Черная пешка на d5
	assert(d5_res.success, "Ход d7-d5 успешен")
	
	# Проверяем целевую клетку взятия на проходе
	assert(logic.en_passant_target == Vector2i(3, 5), "Целевая клетка на проходе d6 (3, 5)")
	
	# Проверяем легальность хода e5xd6
	var legal = logic.get_legal_moves(Vector2i(4, 4))
	assert(Vector2i(3, 5) in legal, "Ход e5xd6 на проходе должен быть среди легальных ходов")
	
	# Выполняем взятие на проходе
	var ep_res = logic.make_move(Vector2i(4, 4), Vector2i(3, 5))
	assert(ep_res.success, "Взятие на проходе выполнено успешно")
	assert(ep_res.captured == true, "Взятие зафиксировано")
	assert(ep_res.captured_piece == "pawn", "Сбитая фигура — пешка")
	assert(ep_res.captured_is_white == false, "Сбита черная пешка")
	assert(ep_res.get("en_passant", false) == true, "Флаг en_passant установлен")
	assert(ep_res.get("en_passant_captured_pos") == Vector2i(3, 4), "Позиция сбитой пешки (3, 4)")
	
	# Проверяем состояние доски
	assert(logic.get_piece(Vector2i(3, 4)) == null, "Клетка d5 (3, 4), где стояла сбитая пешка, теперь пуста!")
	assert(logic.get_piece(Vector2i(3, 5)) != null, "Белая пешка теперь стоит на d6 (3, 5)")
	assert(logic.get_piece(Vector2i(4, 4)) == null, "Исходная клетка e5 (4, 4) пуста")
	assert(logic.en_passant_target == Vector2i(-1, -1), "После хода en_passant_target сброшен")
	print("[PASS] Тест 1: Взятие на проходе белыми (e5xd6) успешно!")

## Тест 2: Черные берут пешку белых на проходе
func _test_black_captures_en_passant() -> void:
	var logic = ChessLogic.new()
	# 1. a3 d5
	logic.make_move(Vector2i(0, 1), Vector2i(0, 2))
	logic.make_move(Vector2i(3, 6), Vector2i(3, 4))
	
	# 2. a4 d4
	logic.make_move(Vector2i(0, 2), Vector2i(0, 3))
	logic.make_move(Vector2i(3, 4), Vector2i(3, 3)) # Черная пешка на d4
	
	# 3. Белые играют e2-e4 (двойной шаг пешки рядом с d4)
	var e4_res = logic.make_move(Vector2i(4, 1), Vector2i(4, 3))
	assert(e4_res.success, "Ход e2-e4 успешен")
	assert(logic.en_passant_target == Vector2i(4, 2), "Целевая клетка на проходе e3 (4, 2)")
	
	# Черные имеют легальный ход d4xe3
	var legal = logic.get_legal_moves(Vector2i(3, 3))
	assert(Vector2i(4, 2) in legal, "Ход d4xe3 на проходе легален для черных")
	
	# Выполняем взятие
	var ep_res = logic.make_move(Vector2i(3, 3), Vector2i(4, 2))
	assert(ep_res.success, "Взятие на проходе черными успешно")
	assert(ep_res.captured == true, "Взятие зафиксировано")
	assert(ep_res.captured_is_white == true, "Сбита белая пешка")
	assert(ep_res.get("en_passant", false) == true, "Флаг en_passant установлен")
	assert(ep_res.get("en_passant_captured_pos") == Vector2i(4, 3), "Позиция сбитой белой пешки e4 (4, 3)")
	
	# Проверяем доску
	assert(logic.get_piece(Vector2i(4, 3)) == null, "Белая пешка на e4 (4, 3) удалена с доски!")
	assert(logic.get_piece(Vector2i(4, 2)) != null, "Черная пешка находится на e3 (4, 2)")
	print("[PASS] Тест 2: Взятие на проходе черными (d4xe3) успешно!")

## Тест 3: Право взятия на проходе сгорает через 1 ход
func _test_en_passant_expires_after_one_turn() -> void:
	var logic = ChessLogic.new()
	# 1. e4 h6 2. e5 d5
	logic.make_move(Vector2i(4, 1), Vector2i(4, 3))
	logic.make_move(Vector2i(7, 6), Vector2i(7, 5))
	logic.make_move(Vector2i(4, 3), Vector2i(4, 4))
	logic.make_move(Vector2i(3, 6), Vector2i(3, 4))
	assert(logic.en_passant_target == Vector2i(3, 5), "Целевая клетка d6 доступна")
	
	# Белые делают ДРУГОЙ ход (например a2-a3)
	logic.make_move(Vector2i(0, 1), Vector2i(0, 2))
	assert(logic.en_passant_target == Vector2i(-1, -1), "После хода en_passant_target аннулирован!")
	
	# Черные ходят a7-a6
	logic.make_move(Vector2i(0, 6), Vector2i(0, 5))
	
	# Теперь белые больше НЕ могут взять на проходе
	var legal = logic.get_legal_moves(Vector2i(4, 4))
	assert(not (Vector2i(3, 5) in legal), "Право взятия на проходе безвозвратно сгорело!")
	print("[PASS] Тест 3: Сгорание права взятия на проходе при пропуске хода подтверждено!")

## Тест 4: Нельзя брать на проходе, если это открывает шах своему королю
func _test_en_passant_pin_prevents_illegal_move() -> void:
	var logic = ChessLogic.new()
	logic.reset_board(1)
	
	# Расчищаем 5-ю горизонталь (y = 4)
	for x in range(8):
		logic.grid[x][4] = null
	# Убираем мешающие пешки
	logic.grid[4][1] = null # e2
	logic.grid[3][6] = null # d7
	
	# Белый король на e5 (4, 4)
	logic.grid[4][0] = null
	logic.grid[4][4] = { "type": "king", "is_white": true, "has_moved": true }
	# Белая пешка на f5 (5, 4)
	logic.grid[5][1] = null
	logic.grid[5][4] = { "type": "pawn", "is_white": true, "has_moved": true }
	
	# Черная ладья на h5 (7, 4)
	logic.grid[7][7] = null
	logic.grid[7][4] = { "type": "rook", "is_white": false, "has_moved": true }
	
	# Черная пешка делает двойной ход g7-g5 (6, 6) -> (6, 4)
	# Пешка встает между белой пешкой f5 и черной ладьей h5
	logic.grid[6][6] = null
	logic.grid[6][4] = { "type": "pawn", "is_white": false, "has_moved": true }
	logic.en_passant_target = Vector2i(6, 5) # g6
	logic.is_white_turn = true
	
	# Если белая пешка f5 побьет на проходе g6 (5, 4) -> (6, 5):
	# обе пешки (f5 и g5) исчезают с 5-й горизонтали, и ладья h5 объявит шах королю e5!
	var legal = logic.get_legal_moves(Vector2i(5, 4))
	assert(not (Vector2i(6, 5) in legal), "Взятие на проходе ЗАПРЕЩЕНО, так как открывает горизонтальный шах королю!")
	print("[PASS] Тест 4: Защита короля при связке по горизонтали работает корректно!")

## Тест 5: Движок ChessBot учитывает взятие на проходе
func _test_bot_finds_en_passant_capture() -> void:
	var logic = ChessLogic.new()
	logic.reset_board(1)
	
	# Создаем позицию, где у черных на выбор пассивный ход или взятие на проходе
	# Белая пешка на e4 (4, 3) только что сделала ход e2-e4
	logic.grid[4][1] = null
	logic.grid[4][3] = { "type": "pawn", "is_white": true, "has_moved": true }
	# Черная пешка на d4 (3, 3)
	logic.grid[3][6] = null
	logic.grid[3][3] = { "type": "pawn", "is_white": false, "has_moved": true }
	logic.en_passant_target = Vector2i(4, 2) # e3
	logic.is_white_turn = false
	
	var bot_move = logic.get_best_ai_move()
	assert(not bot_move.is_empty(), "Бот находит ход")
	var legal = logic.get_legal_moves(bot_move["from"])
	assert(bot_move["to"] in legal, "Ход бота легален")
	print("[PASS] Тест 5: Бот корректно анализирует позицию с активным en passant target: ", bot_move)

## Тест 6: 3D-представление корректно удаляет сбитую фигуру при взятии на проходе
func _test_board_view_en_passant_3d() -> void:
	var scene = load("res://scenes/chess/chess_board.tscn")
	assert(scene != null, "Сцена доски загружается")
	var board_view: ChessBoardView = scene.instantiate()
	root.add_child(board_view)
	
	# e4, h6, e5, d5 в логике
	board_view.logic.make_move(Vector2i(4, 1), Vector2i(4, 3))
	board_view.logic.make_move(Vector2i(7, 6), Vector2i(7, 5))
	board_view.logic.make_move(Vector2i(4, 3), Vector2i(4, 4))
	board_view.logic.make_move(Vector2i(3, 6), Vector2i(3, 4))
	
	# Синхронизируем 3D-ноды
	var wp = board_view.piece_nodes[Vector2i(4, 1)]
	board_view.piece_nodes.erase(Vector2i(4, 1))
	board_view.piece_nodes[Vector2i(4, 4)] = wp
	wp.board_pos = Vector2i(4, 4)
	
	var bp = board_view.piece_nodes[Vector2i(3, 6)]
	board_view.piece_nodes.erase(Vector2i(3, 6))
	board_view.piece_nodes[Vector2i(3, 4)] = bp
	bp.board_pos = Vector2i(3, 4)
	
	# Проверяем наличие 3D-ноды черной пешки на d5 (3, 4)
	assert(board_view.piece_nodes.has(Vector2i(3, 4)), "3D-нода черной пешки присутствует на d5")
	
	# Белые делают взятие на проходе e5xd6 (4, 4) -> (3, 5)
	board_view._execute_player_move(Vector2i(4, 4), Vector2i(3, 5))
	
	# Нода сбитой черной пешки на d5 (3, 4) должна быть стерта из piece_nodes!
	assert(not board_view.piece_nodes.has(Vector2i(3, 4)), "3D-нода сбитой на проходе пешки на d5 удалена из активных нод!")
	assert(board_view.piece_nodes.has(Vector2i(3, 5)), "Белая пешка переместилась на d6 (3, 5)!")
	
	board_view._cleanup_ai_thread()
	board_view.queue_free()
	print("[PASS] Тест 6: 3D-ноды доски корректно обрабатывают взятие на проходе!")
