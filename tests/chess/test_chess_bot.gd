extends SceneTree

const ChessLogic = preload("res://scripts/chess/chess_logic.gd")
const ChessBot = preload("res://scripts/chess/chess_bot.gd")

func _init() -> void:
	print("--- [ChessBot Test Suite] Запуск тестов ---")
	_run_tests.call_deferred()

func _run_tests() -> void:
	_test_bot_valid_opening_move()
	_test_playthrough1_predatory_capture()
	_test_playthrough2_survival_move()
	_test_game_reset_and_playthrough_switch()
	_test_avoids_losing_exchange()
	_test_playthrough2_opening_king_stays_safe()
	print("--- [ChessBot Test Suite] ВСЕ ТЕСТЫ УСПЕШНО ПРОЙДЕНЫ ---")
	quit(0)

## Тест 5: Бот отказывается от невыгодного размена (не берет защищенную пешку ферзем)
func _test_avoids_losing_exchange() -> void:
	var logic = ChessLogic.new()
	logic.reset_board(1)
	
	# Расчищаем центр
	logic.grid[3][1] = null # d2
	logic.grid[4][1] = null # e2
	logic.grid[3][6] = null # d7
	logic.grid[4][6] = null # e7
	logic.grid[3][7] = null # d8 (черный ферзь вышел на d5)
	
	# Белые: пешка на d3 (3, 2) защищает пешку на e4 (4, 3)
	logic.grid[3][2] = { "type": "pawn", "is_white": true, "has_moved": true }
	logic.grid[4][3] = { "type": "pawn", "is_white": true, "has_moved": true }
	
	# Черный ферзь на d5 (3, 4) видит защищенную пешку на e4 (4, 3)
	logic.grid[3][4] = { "type": "queen", "is_white": false, "has_moved": true }
	logic.is_white_turn = false
	
	var bot_move = logic.get_best_ai_move()
	assert(not bot_move.is_empty(), "Бот должен найти ход")
	assert(bot_move["to"] != Vector2i(4, 3), "Умный бот НЕ должен зевать ферзя за защищенную пешку на e4!")
	print("[PASS] Тест 5: Бот отказался от невыгодного размена (зевка ферзя): ", bot_move)

## Тест 1: Бот возвращает валидный легальный ход из дебютной позиции
func _test_bot_valid_opening_move() -> void:
	var logic = ChessLogic.new()
	# Белые делают ход e2-e4 (4, 1) -> (4, 3)
	var white_res = logic.make_move(Vector2i(4, 1), Vector2i(4, 3))
	assert(white_res["success"], "Ход белых e2-e4 успешен")
	
	var bot_move = logic.get_best_ai_move()
	assert(not bot_move.is_empty(), "Бот должен найти ход")
	assert(bot_move.has("from") and bot_move.has("to"), "Ход должен содержать from и to")
	
	var legal = logic.get_legal_moves(bot_move["from"])
	assert(bot_move["to"] in legal, "Ход бота должен быть строго легальным")
	print("[PASS] Тест 1: Валидный ход бота в дебюте: ", bot_move["from"], " -> ", bot_move["to"])

## Тест 2: 1-е прохождение (хищный ИИ): приоритет взятия фигур белых
func _test_playthrough1_predatory_capture() -> void:
	var logic = ChessLogic.new()
	logic.reset_board(1) # Playthrough 1
	
	# Создаем позицию, где черный ферзь на d5 (3, 4) может съесть белую ладью на a5 (0, 4)
	# или сделать пассивный ход
	logic.grid[3][4] = { "type": "queen", "is_white": false, "has_moved": true }
	logic.grid[0][4] = { "type": "rook", "is_white": true, "has_moved": true }
	logic.is_white_turn = false
	
	var bot_move = logic.get_best_ai_move()
	assert(not bot_move.is_empty(), "Бот находит ход")
	# Бот должен жадно съесть ладью
	assert(bot_move["to"] == Vector2i(0, 4) or logic.get_piece(bot_move["to"]) != null, "В 1-м прохождении бот выбирает взятие фигуры")
	print("[PASS] Тест 2: 1-е прохождение — жадное взятие фигуры: ", bot_move)

## Тест 3: 2-е прохождение (выживание/поддавки): избегает мата
func _test_playthrough2_survival_move() -> void:
	var logic = ChessLogic.new()
	logic.reset_board(2) # Playthrough 2
	
	# Черный король на e8 (4, 7), под шахом от белой ладьи
	logic.grid[4][1] = null
	logic.grid[4][6] = null # открываем вертикаль e
	logic.grid[4][4] = { "type": "rook", "is_white": true, "has_moved": true } # шах королю
	logic.is_white_turn = false
	
	var bot_move = logic.get_best_ai_move()
	assert(not bot_move.is_empty(), "Бот в прохождении 2 находит спасительный ход")
	var legal = logic.get_legal_moves(bot_move["from"])
	assert(bot_move["to"] in legal, "Ход выживания легален")
	print("[PASS] Тест 3: 2-е прохождение — ход выживания короля: ", bot_move)

## Тест 4: Сброс доски и смена прохождения
func _test_game_reset_and_playthrough_switch() -> void:
	var logic = ChessLogic.new()
	assert(logic.playthrough == 1, "По умолчанию 1-е прохождение")
	
	# Сброс на 2-е прохождение
	logic.reset_board(2)
	assert(logic.playthrough == 2, "После сброса с аргументом 2 — прохождение 2")
	assert(logic.is_white_turn == true, "Ход белых после сброса")
	assert(logic.get_piece(Vector2i(4, 0))["type"] == "king", "Фигуры на стартовых местах")
	print("[PASS] Тест 4: Сброс доски и смена прохождения на 2")

## Тест 6: 2-е прохождение — Король не идет глупо в центр в дебюте
func _test_playthrough2_opening_king_stays_safe() -> void:
	var logic = ChessLogic.new()
	logic.reset_board(2) # Playthrough 2
	
	# Белые играют e2-e4
	logic.make_move(Vector2i(4, 1), Vector2i(4, 3))
	
	# Проверяем 5 разных выборов хода (с учетом фактора вариативности ходов)
	for i in range(5):
		var bot_move = logic.get_best_ai_move()
		assert(not bot_move.is_empty(), "Бот должен вернуть ход")
		var moved_piece = logic.get_piece(bot_move["from"])
		assert(moved_piece["type"] != "king", "Во 2-й игре бот НЕ должен ходить королем в центр в дебюте! Получен ход: %s" % str(bot_move))
	print("[PASS] Тест 6: 2-е прохождение — Король надежно укрыт в дебюте и не идет в центр")


