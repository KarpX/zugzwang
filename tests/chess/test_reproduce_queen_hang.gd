extends SceneTree

const ChessLogic = preload("res://scripts/chess/chess_logic.gd")
const ChessBot   = preload("res://scripts/chess/chess_bot.gd")

func _init() -> void:
	print("--- [User Scenario Queen Hang Test] ---")
	
	var logic = ChessLogic.new()
	logic.reset_board(1)
	
	# Расчистим d-вертикаль: уберем d2, d7
	logic.grid[3][1] = null
	logic.grid[3][6] = null
	
	# Белый слон на d2 закрылся от шаха черного слона
	logic.grid[3][1] = { "type": "bishop", "is_white": true, "has_moved": true }
	logic.grid[1][3] = { "type": "bishop", "is_white": false, "has_moved": true } # Черный слон на b4
	
	# Белый слон на g5 (6, 4) атакует черного ферзя на d8 (3, 7)
	logic.grid[4][6] = null
	logic.grid[6][4] = { "type": "bishop", "is_white": true, "has_moved": true }
	
	logic.is_white_turn = false
	
	print("Проверяем выбор хода Черных в прохождении 1 (Hard):")
	var move1 = logic.get_best_ai_move()
	var piece1 = logic.get_piece(move1["from"])
	print("Move in playthrough 1: ", move1, " Piece: ", piece1["type"])
	assert(piece1["type"] != "pawn", "Playthrough 1: БОТ СДЕЛАЛ ХОД ПЕШКОЙ И ОТДАЛ ФЕРЗЯ!")
	
	print("Проверяем выбор хода Черных в прохождении 2 (Medium/Survival):")
	logic.playthrough = 2
	var move2 = logic.get_best_ai_move()
	var piece2 = logic.get_piece(move2["from"])
	print("Move in playthrough 2: ", move2, " Piece: ", piece2["type"])
	assert(piece2["type"] != "pawn", "Playthrough 2: БОТ СДЕЛАЛ ХОД ПЕШКОЙ И ОТДАЛ ФЕРЗЯ!")
	
	print("--- [User Scenario Queen Hang Test] ВСЕ ТЕСТЫ ЗАЩИТЫ ФЕРЗЯ УСПЕШНО ПРОЙДЕНЫ ---")
	quit(0)
