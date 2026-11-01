class_name ChessOpeningBook
extends RefCounted

## Дебютная книга гроссмейстерских ходов для ChessBot (первые 1-4 хода партии)
## Содержит классические ответы: Сицилианская, Итальянская, Французская, Каро-Канн, Ферзевый гамбит и др.

const ChessEvaluator = preload("res://scripts/chess/bot/chess_evaluator.gd")

const PieceType = ChessEvaluator.PieceType

## Подсчет фигур, совершивших хотя бы один ход
static func count_moved_pieces(board: Array) -> int:
	var count: int = 0
	for x in 8:
		for y in 8:
			var p = board[x][y]
			if p != null and p.has_moved:
				count += 1
	return count

## Выбор хода из дебютной книги
static func get_opening_book_move(board: Array, legal_moves: Array[Dictionary]) -> Dictionary:
	var moved_count = count_moved_pieces(board)
	var book_candidates: Array[Dictionary] = []
	
	if moved_count == 1:
		# ХОД 1 ЧЕРНЫХ: Белые сделали свой 1-й ход
		if board[4][3] != null and board[4][3].type == PieceType.PAWN and board[4][3].is_white:
			# 1. e4
			book_candidates = [
				{"from": Vector2i(4, 6), "to": Vector2i(4, 4)}, # 1... e5 (Открытая игра)
				{"from": Vector2i(2, 6), "to": Vector2i(2, 4)}, # 1... c5 (Сицилианская защита)
				{"from": Vector2i(4, 6), "to": Vector2i(4, 5)}, # 1... e6 (Французская защита)
				{"from": Vector2i(2, 6), "to": Vector2i(2, 5)}, # 1... c6 (Каро-Канн)
			]
		elif board[3][3] != null and board[3][3].type == PieceType.PAWN and board[3][3].is_white:
			# 1. d4
			book_candidates = [
				{"from": Vector2i(3, 6), "to": Vector2i(3, 4)}, # 1... d5 (Классический ферзевый)
				{"from": Vector2i(6, 7), "to": Vector2i(5, 5)}, # 1... Nf6 (Индийские защиты)
				{"from": Vector2i(4, 6), "to": Vector2i(4, 5)}, # 1... e6
				{"from": Vector2i(2, 6), "to": Vector2i(2, 4)}, # 1... c5 (Бенони)
			]
		elif board[2][3] != null and board[2][3].type == PieceType.PAWN and board[2][3].is_white:
			# 1. c4 (Английское начало)
			book_candidates = [
				{"from": Vector2i(4, 6), "to": Vector2i(4, 4)}, # 1... e5
				{"from": Vector2i(2, 6), "to": Vector2i(2, 4)}, # 1... c5
				{"from": Vector2i(6, 7), "to": Vector2i(5, 5)}, # 1... Nf6
				{"from": Vector2i(4, 6), "to": Vector2i(4, 5)}, # 1... e6
			]
		elif board[5][2] != null and board[5][2].type == PieceType.KNIGHT and board[5][2].is_white:
			# 1. Nf3 (Дебют Рети)
			book_candidates = [
				{"from": Vector2i(3, 6), "to": Vector2i(3, 4)}, # 1... d5
				{"from": Vector2i(6, 7), "to": Vector2i(5, 5)}, # 1... Nf6
				{"from": Vector2i(2, 6), "to": Vector2i(2, 4)}, # 1... c5
			]
	elif moved_count == 3:
		# ХОД 2 ЧЕРНЫХ: Белые сделали свой 2-й ход
		# 1. e4 e5 2. Nf3 -> 2... Nc6 или 2... Nf6
		if board[4][4] != null and board[4][4].type == PieceType.PAWN and not board[4][4].is_white:
			if board[5][2] != null and board[5][2].type == PieceType.KNIGHT and board[5][2].is_white:
				book_candidates = [
					{"from": Vector2i(1, 7), "to": Vector2i(2, 5)}, # 2... Nc6
					{"from": Vector2i(6, 7), "to": Vector2i(5, 5)}, # 2... Nf6
					{"from": Vector2i(3, 6), "to": Vector2i(3, 5)}, # 2... d6
				]
		# 1. e4 c5 2. Nf3 -> 2... Nc6, d6, e6
		elif board[2][4] != null and board[2][4].type == PieceType.PAWN and not board[2][4].is_white:
			if board[5][2] != null and board[5][2].type == PieceType.KNIGHT and board[5][2].is_white:
				book_candidates = [
					{"from": Vector2i(1, 7), "to": Vector2i(2, 5)}, # 2... Nc6
					{"from": Vector2i(3, 6), "to": Vector2i(3, 5)}, # 2... d6
					{"from": Vector2i(4, 6), "to": Vector2i(4, 5)}, # 2... e6
				]
		# 1. e4 e6 -> 2... d5
		elif board[4][5] != null and board[4][5].type == PieceType.PAWN and not board[4][5].is_white:
			book_candidates = [
				{"from": Vector2i(3, 6), "to": Vector2i(3, 4)}, # 2... d5
			]
		# 1. e4 c6 -> 2... d5
		elif board[2][5] != null and board[2][5].type == PieceType.PAWN and not board[2][5].is_white:
			book_candidates = [
				{"from": Vector2i(3, 6), "to": Vector2i(3, 4)}, # 2... d5
			]
		# 1. d4 d5 2. c4 -> 2... e6 или c6
		elif board[3][4] != null and board[3][4].type == PieceType.PAWN and not board[3][4].is_white:
			if board[2][3] != null and board[2][3].type == PieceType.PAWN and board[2][3].is_white:
				book_candidates = [
					{"from": Vector2i(4, 6), "to": Vector2i(4, 5)}, # 2... e6
					{"from": Vector2i(2, 6), "to": Vector2i(2, 5)}, # 2... c6
				]
		# 1. d4 Nf6 2. c4 -> 2... e6 или g6
		elif board[5][5] != null and board[5][5].type == PieceType.KNIGHT and not board[5][5].is_white:
			if board[2][3] != null and board[2][3].type == PieceType.PAWN and board[2][3].is_white:
				book_candidates = [
					{"from": Vector2i(4, 6), "to": Vector2i(4, 5)}, # 2... e6
					{"from": Vector2i(6, 6), "to": Vector2i(6, 5)}, # 2... g6
				]
	elif moved_count == 5:
		# ХОД 3 ЧЕРНЫХ:
		# 1. e4 c5 2. Nf3 d6 3. d4 -> 3... cxd4
		if board[3][3] != null and board[3][3].type == PieceType.PAWN and board[3][3].is_white:
			if board[2][4] != null and board[2][4].type == PieceType.PAWN and not board[2][4].is_white:
				book_candidates = [
					{"from": Vector2i(2, 4), "to": Vector2i(3, 3)}, # 3... cxd4
				]
		# 1. e4 e5 2. Nf3 Nc6 3. Bc4 -> 3... Bc5 или 3... Nf6
		elif board[4][4] != null and board[4][4].type == PieceType.PAWN and not board[4][4].is_white:
			if board[1][5] != null and board[1][5].type == PieceType.KNIGHT and not board[1][5].is_white:
				book_candidates = [
					{"from": Vector2i(5, 7), "to": Vector2i(2, 4)}, # 3... Bc5
					{"from": Vector2i(6, 7), "to": Vector2i(5, 5)}, # 3... Nf6
				]
		# 1. e4 c6 2. d4 d5 3. Nc3 -> 3... dxe4
		elif board[2][5] != null and board[2][5].type == PieceType.PAWN and not board[2][5].is_white:
			if board[3][4] != null and board[3][4].type == PieceType.PAWN and not board[3][4].is_white:
				book_candidates = [
					{"from": Vector2i(3, 4), "to": Vector2i(4, 3)}, # 3... dxe4
				]
		# 1. e4 e6 2. d4 d5 3. Nc3 -> 3... Nf6 или 3... dxe4
		elif board[4][5] != null and board[4][5].type == PieceType.PAWN and not board[4][5].is_white:
			if board[3][4] != null and board[3][4].type == PieceType.PAWN and not board[3][4].is_white:
				book_candidates = [
					{"from": Vector2i(6, 7), "to": Vector2i(5, 5)}, # 3... Nf6
					{"from": Vector2i(3, 4), "to": Vector2i(4, 3)}, # 3... dxe4
				]
	elif moved_count == 7:
		# ХОД 4 ЧЕРНЫХ:
		# В сицилианке после 4. Nxd4 -> 4... Nf6
		if board[3][3] != null and board[3][3].type == PieceType.KNIGHT and board[3][3].is_white:
			if board[3][5] != null and board[3][5].type == PieceType.PAWN and not board[3][5].is_white:
				book_candidates = [
					{"from": Vector2i(6, 7), "to": Vector2i(5, 5)}, # 4... Nf6
					{"from": Vector2i(1, 7), "to": Vector2i(2, 5)}, # 4... Nc6
				]
		# В Каро-Канне после 4. Nxe4 -> 4... Nf6
		elif board[4][3] != null and board[4][3].type == PieceType.KNIGHT and board[4][3].is_white:
			if board[2][5] != null and board[2][5].type == PieceType.PAWN and not board[2][5].is_white:
				book_candidates = [
					{"from": Vector2i(6, 7), "to": Vector2i(5, 5)}, # 4... Nf6
				]

	# Фильтруем только те ходы, которые реально легальны в текущей позиции
	var valid_book_moves: Array[Dictionary] = []
	for bc in book_candidates:
		for lm in legal_moves:
			if lm["from"] == bc["from"] and lm["to"] == bc["to"]:
				valid_book_moves.append(lm)
				break
				
	if valid_book_moves.is_empty():
		return {}
		
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	return valid_book_moves[rng.randi_range(0, valid_book_moves.size() - 1)]
