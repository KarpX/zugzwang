class_name ChessEvaluator
extends RefCounted

## Модуль оценки позиций, таблиц PST и статической оценки разменов (SEE)
## Входит в подсистему шахматного интеллекта ChessBot.

enum PieceType {KING = 0, QUEEN = 1, ROOK = 2, BISHOP = 3, KNIGHT = 4, PAWN = 5}

const BOARD_SIZE: int = 8

const PIECE_VALUES: Dictionary = {
	PieceType.KING: 20000,
	PieceType.QUEEN: 900,
	PieceType.ROOK: 500,
	PieceType.BISHOP: 325,
	PieceType.KNIGHT: 320,
	PieceType.PAWN: 100,
}

# Tapered piece-square tables (MG / EG)
const PAWN_MG: Array[int] = [
	0, 0, 0, 0, 0, 0, 0, 0,
	50, 50, 50, 50, 50, 50, 50, 50,
	10, 10, 20, 30, 30, 20, 10, 10,
	5, 5, 10, 25, 25, 10, 5, 5,
	0, 0, 0, 20, 20, 0, 0, 0,
	5, -5, -10, 0, 0, -10, -5, 5,
	5, 10, 10, -20, -20, 10, 10, 5,
	0, 0, 0, 0, 0, 0, 0, 0,
]
const PAWN_EG: Array[int] = [
	0, 0, 0, 0, 0, 0, 0, 0,
	70, 70, 70, 70, 70, 70, 70, 70,
	30, 30, 40, 50, 50, 40, 30, 30,
	20, 20, 30, 45, 45, 30, 20, 20,
	10, 10, 20, 35, 35, 20, 10, 10,
	0, 0, 10, 20, 20, 10, 0, 0,
	0, 0, 0, -10, -10, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
]
const KNIGHT_MG: Array[int] = [
	-50, -40, -30, -30, -30, -30, -40, -50,
	-40, -20, 0, 0, 0, 0, -20, -40,
	-30, 0, 10, 15, 15, 10, 0, -30,
	-30, 5, 15, 20, 20, 15, 5, -30,
	-30, 0, 15, 20, 20, 15, 0, -30,
	-30, 5, 10, 15, 15, 10, 5, -30,
	-40, -20, 0, 5, 5, 0, -20, -40,
	-50, -40, -30, -30, -30, -30, -40, -50,
]
const KNIGHT_EG: Array[int] = [
	-40, -30, -20, -20, -20, -20, -30, -40,
	-30, -15, 0, 0, 0, 0, -15, -30,
	-20, 0, 10, 12, 12, 10, 0, -20,
	-20, 5, 12, 15, 15, 12, 5, -20,
	-20, 0, 12, 15, 15, 12, 0, -20,
	-20, 5, 10, 12, 12, 10, 5, -20,
	-30, -15, 0, 5, 5, 0, -15, -30,
	-40, -30, -20, -20, -20, -20, -30, -40,
]
const BISHOP_MG: Array[int] = [
	-20, -10, -10, -10, -10, -10, -10, -20,
	-10, 0, 0, 0, 0, 0, 0, -10,
	-10, 0, 5, 10, 10, 5, 0, -10,
	-10, 5, 5, 10, 10, 5, 5, -10,
	-10, 0, 10, 10, 10, 10, 0, -10,
	-10, 10, 10, 10, 10, 10, 10, -10,
	-10, 5, 0, 0, 0, 0, 5, -10,
	-20, -10, -10, -10, -10, -10, -10, -20,
]
const BISHOP_EG: Array[int] = [
	-15, -10, -10, -10, -10, -10, -10, -15,
	-10, 0, 0, 0, 0, 0, 0, -10,
	-10, 0, 5, 5, 5, 5, 0, -10,
	-10, 5, 5, 5, 5, 5, 5, -10,
	-10, 0, 5, 5, 5, 5, 0, -10,
	-10, 5, 5, 5, 5, 5, 5, -10,
	-10, 0, 5, 0, 0, 0, 0, -10,
	-15, -10, -10, -10, -10, -10, -10, -15,
]
const ROOK_MG: Array[int] = [
	0, 0, 0, 0, 0, 0, 0, 0,
	5, 10, 10, 10, 10, 10, 10, 5,
	-5, 0, 0, 0, 0, 0, 0, -5,
	-5, 0, 0, 0, 0, 0, 0, -5,
	-5, 0, 0, 0, 0, 0, 0, -5,
	-5, 0, 0, 0, 0, 0, 0, -5,
	-5, 0, 0, 0, 0, 0, 0, -5,
	0, 0, 0, 5, 5, 0, 0, 0,
]
const ROOK_EG: Array[int] = [
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
]
const QUEEN_MG: Array[int] = [
	-20, -10, -10, -5, -5, -10, -10, -20,
	-10, 0, 0, 0, 0, 0, 0, -10,
	-10, 0, 5, 5, 5, 5, 0, -10,
	-5, 0, 5, 5, 5, 5, 0, -5,
	0, 0, 5, 5, 5, 5, 0, -5,
	-10, 5, 5, 5, 5, 5, 0, -10,
	-10, 0, 5, 0, 0, 0, 0, -10,
	-20, -10, -10, -5, -5, -10, -10, -20,
]
const QUEEN_EG: Array[int] = [
	-20, -10, -10, -5, -5, -10, -10, -20,
	-10, 0, 0, 0, 0, 0, 0, -10,
	-10, 0, 5, 5, 5, 5, 0, -10,
	-5, 0, 5, 5, 5, 5, 0, -5,
	0, 0, 5, 5, 5, 5, 0, -5,
	-10, 5, 5, 5, 5, 5, 0, -10,
	-10, 0, 5, 0, 0, 0, 0, -10,
	-20, -10, -10, -5, -5, -10, -10, -20,
]
const KING_MG: Array[int] = [
	-30, -40, -40, -50, -50, -40, -40, -30,
	-30, -40, -40, -50, -50, -40, -40, -30,
	-30, -40, -40, -50, -50, -40, -40, -30,
	-30, -40, -40, -50, -50, -40, -40, -30,
	-20, -30, -30, -40, -40, -30, -30, -20,
	-10, -20, -20, -20, -20, -20, -20, -10,
	20, 20, -10, -10, -10, -10, 20, 20,
	10, 20, 30, -20, 20, -20, 30, 10,
]
const KING_EG: Array[int] = [
	-50, -40, -30, -20, -20, -30, -40, -50,
	-30, -20, -10, 0, 0, -10, -20, -30,
	-30, -10, 20, 30, 30, 20, -10, -30,
	-30, -10, 30, 40, 40, 30, -10, -30,
	-30, -10, 30, 40, 40, 30, -10, -30,
	-30, -10, 20, 30, 30, 20, -10, -30,
	-30, -30, 0, 0, 0, 0, -30, -30,
	-50, -30, -30, -30, -30, -30, -30, -50,
]

const MG_TABLES: Array = [KING_MG, QUEEN_MG, ROOK_MG, BISHOP_MG, KNIGHT_MG, PAWN_MG]
const EG_TABLES: Array = [KING_EG, QUEEN_EG, ROOK_EG, BISHOP_EG, KNIGHT_EG, PAWN_EG]

const KNIGHT_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 2), Vector2i(2, 1), Vector2i(-1, 2), Vector2i(-2, 1),
	Vector2i(1, -2), Vector2i(2, -1), Vector2i(-1, -2), Vector2i(-2, -1)
]
const BISHOP_DIRS: Array[Vector2i] = [
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)
]
const ROOK_DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
]
const QUEEN_DIRS: Array[Vector2i] = [
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
]
const KING_OFFSETS: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)
]
const MINOR_START_SQUARES: Array[Vector2i] = [
	Vector2i(1, 7), Vector2i(2, 7), Vector2i(5, 7), Vector2i(6, 7)
]
const KINGSIDE_COVER_FILES: Array[int] = [5, 6, 7]
const QUEENSIDE_COVER_FILES: Array[int] = [0, 1, 2]

static func string_to_type(type_str: String) -> int:
	match type_str.to_lower():
		"king": return PieceType.KING
		"queen": return PieceType.QUEEN
		"rook": return PieceType.ROOK
		"bishop": return PieceType.BISHOP
		"knight": return PieceType.KNIGHT
		_: return PieceType.PAWN

static func type_to_string(type_int: int) -> String:
	match type_int:
		PieceType.KING: return "king"
		PieceType.QUEEN: return "queen"
		PieceType.ROOK: return "rook"
		PieceType.BISHOP: return "bishop"
		PieceType.KNIGHT: return "knight"
		_: return "pawn"

## Поиск наименее ценного атакующего для статической оценки разменов (SEE)
static func get_least_valuable_attacker(board: Array, target_pos: Vector2i, by_white: bool) -> Dictionary:
	var best_attacker_pos: Vector2i = Vector2i(-1, -1)
	var best_attacker_val: int = 999999
	var best_attacker_type: int = -1
	
	for x in BOARD_SIZE:
		for y in BOARD_SIZE:
			var p = board[x][y]
			if p != null and p.is_white == by_white:
				var from_pos = Vector2i(x, y)
				if ChessBot.is_square_attacked(board, target_pos, by_white):
					var legal_m = ChessBot.get_legal_moves(board, from_pos, p)
					if target_pos in legal_m:
						var val: int = PIECE_VALUES[p.type]
						if val < best_attacker_val:
							best_attacker_val = val
							best_attacker_pos = from_pos
							best_attacker_type = p.type
							if val == 100: # Пешка — самый дешевый атакующий
								return { "pos": from_pos, "val": val, "type": p.type }
								
	if best_attacker_pos.x != -1:
		return { "pos": best_attacker_pos, "val": best_attacker_val, "type": best_attacker_type }
	return {}

## Static Exchange Evaluation (SEE): расчет выгоды цепочки взятий на одном поле
static func see(board: Array, from_pos: Vector2i, to_pos: Vector2i) -> int:
	var moving_p = board[from_pos.x][from_pos.y]
	if moving_p == null:
		return 0
	var target_p = board[to_pos.x][to_pos.y]
	var initial_gain = PIECE_VALUES[target_p.type] if target_p != null else 0
	
	var dlist: Array[int] = [initial_gain]
	var current_side_is_white = not moving_p.is_white
	
	var undo_stack: Array[Dictionary] = []
	var undo_first = ChessBot.apply_move(board, from_pos, to_pos)
	undo_stack.append(undo_first)
	
	var depth = 0
	while depth < 8:
		depth += 1
		var attacker = get_least_valuable_attacker(board, to_pos, current_side_is_white)
		if attacker.is_empty():
			break
			
		var att_pos: Vector2i = attacker["pos"]
		var captured_val = PIECE_VALUES[board[to_pos.x][to_pos.y].type]
		var gain = captured_val - dlist[dlist.size() - 1]
		dlist.append(gain)
		
		var undo_next = ChessBot.apply_move(board, att_pos, to_pos)
		undo_stack.append(undo_next)
		current_side_is_white = not current_side_is_white
		
	# Откатываем все примененные ходы цепочки
	while not undo_stack.is_empty():
		var u = undo_stack.pop_back()
		ChessBot.undo_move(board, u)
		
	# Minimax откат полученной выгоды с конца списка
	var i = dlist.size() - 1
	while i > 0:
		dlist[i - 1] = max(0, dlist[i - 1] - dlist[i])
		i -= 1
		
	return dlist[0]

## Базовая позиционная и материальная оценка доски (Tapered Eval)
static func evaluate_base(board: Array, is_white_perspective: bool) -> float:
	var mg_white: int = 0
	var eg_white: int = 0
	var mg_black: int = 0
	var eg_black: int = 0
	var game_phase: int = 0
	
	for x in BOARD_SIZE:
		for y in BOARD_SIZE:
			var p = board[x][y]
			if p == null:
				continue
			var sq_w = (7 - y) * 8 + x
			var sq_b = y * 8 + x
			var val = PIECE_VALUES[p.type]
			
			if p.is_white:
				mg_white += val + MG_TABLES[p.type][sq_w]
				eg_white += val + EG_TABLES[p.type][sq_w]
			else:
				mg_black += val + MG_TABLES[p.type][sq_b]
				eg_black += val + EG_TABLES[p.type][sq_b]
				
			match p.type:
				PieceType.KNIGHT, PieceType.BISHOP: game_phase += 1
				PieceType.ROOK: game_phase += 2
				PieceType.QUEEN: game_phase += 4
				
	game_phase = min(game_phase, 24)
	var mg_score = mg_white - mg_black
	var eg_score = eg_white - eg_black
	var eval_score = float((mg_score * game_phase + eg_score * (24 - game_phase)) / 24)
	return eval_score if is_white_perspective else -eval_score

## Полная оценка позиции для ИИ Черных с учетом прохождения и драматургии
static func evaluate_for_bot(board: Array, playthrough: int = 1) -> float:
	var mg_white: int = 0
	var eg_white: int = 0
	var mg_black: int = 0
	var eg_black: int = 0
	var game_phase: int = 0
	
	var white_material_raw: int = 0
	var black_material_raw: int = 0
	var white_pieces_count: int = 0
	
	var white_pawn_files: Dictionary = {}
	var black_pawn_files: Dictionary = {}
	var white_rooks: Array[Vector2i] = []
	var black_rooks: Array[Vector2i] = []
	var black_queen_pos: Vector2i = Vector2i(-1, -1)
	
	for x in BOARD_SIZE:
		for y in BOARD_SIZE:
			var p = board[x][y]
			if p == null:
				continue
				
			var val = PIECE_VALUES[p.type]
			var sq_w = (7 - y) * 8 + x
			var sq_b = y * 8 + x
			
			if p.is_white:
				mg_white += val + MG_TABLES[p.type][sq_w]
				eg_white += val + EG_TABLES[p.type][sq_w]
				if p.type != PieceType.KING:
					white_material_raw += val
					white_pieces_count += 1
				if p.type == PieceType.PAWN:
					white_pawn_files[x] = true
				elif p.type == PieceType.ROOK:
					white_rooks.append(Vector2i(x, y))
			else:
				mg_black += val + MG_TABLES[p.type][sq_b]
				eg_black += val + EG_TABLES[p.type][sq_b]
				if p.type != PieceType.KING:
					black_material_raw += val
				if p.type == PieceType.PAWN:
					black_pawn_files[x] = true
				elif p.type == PieceType.ROOK:
					black_rooks.append(Vector2i(x, y))
				elif p.type == PieceType.QUEEN:
					black_queen_pos = Vector2i(x, y)
					
			match p.type:
				PieceType.KNIGHT, PieceType.BISHOP: game_phase += 1
				PieceType.ROOK: game_phase += 2
				PieceType.QUEEN: game_phase += 4
				
	game_phase = min(game_phase, 24)
	var mg_score = mg_black - mg_white
	var eg_score = eg_black - eg_white
	var base_score = float((mg_score * game_phase + eg_score * (24 - game_phase)) / 24)
	
	var bonus: float = 0.0
	
	# Бонус за открытые и полуоткрытые вертикали для ладей
	for r in black_rooks:
		var has_black_pawn = black_pawn_files.has(r.x)
		var has_white_pawn = white_pawn_files.has(r.x)
		if not has_black_pawn and not has_white_pawn:
			bonus += 25.0 # Полностью открытая вертикаль
		elif not has_black_pawn:
			bonus += 15.0 # Полуоткрытая вертикаль
			
	for r in white_rooks:
		var has_black_pawn = black_pawn_files.has(r.x)
		var has_white_pawn = white_pawn_files.has(r.x)
		if not has_black_pawn and not has_white_pawn:
			bonus -= 25.0
		elif not has_white_pawn:
			bonus -= 15.0
			
	# Безопасность черного короля
	var b_king = ChessBot.find_king(board, false)
	if b_king.x != -1:
		if b_king.y >= 6: # В безопасности на 7-й или 8-й горизонтали
			if b_king.x >= 5: # Короткая рокировка
				for f in KINGSIDE_COVER_FILES:
					if black_pawn_files.has(f):
						bonus += 12.0
			elif b_king.x <= 2: # Длинная рокировка
				for f in QUEENSIDE_COVER_FILES:
					if black_pawn_files.has(f):
						bonus += 12.0
						
	# Штраф за застрявшие легкие фигуры в дебюте
	if game_phase >= 20:
		for sq in MINOR_START_SQUARES:
			var p = board[sq.x][sq.y]
			if p != null and not p.is_white and not p.has_moved:
				bonus -= 8.0
				
	# Защита черного ферзя от безнаказанного висения под боем
	if black_queen_pos.x != -1:
		if ChessBot.is_square_attacked(board, black_queen_pos, true):
			bonus -= 650.0
			
	if playthrough == 1:
		# 1-е прохождение: Жажда крови (Hard)
		# Истребление фигур игрока дает огромный дофаминовый бонус движку
		var captured_white_pieces = 15 - white_pieces_count
		bonus += float(captured_white_pieces * 18.0)
		
		# Штраф за то, что белый король слишком комфортно себя чувствует
		var w_king = ChessBot.find_king(board, true)
		if w_king.x != -1 and b_king.x != -1:
			var king_dist = abs(b_king.x - w_king.x) + abs(b_king.y - w_king.y)
			if game_phase < 12: # В эндшпиле гоним короля к краю
				bonus += float((14 - king_dist) * 5.0)
				
		return base_score + bonus
	else:
		# 2-е прохождение: Адаптивный ИИ выживания (Medium/Adaptive)
		# Защита фигур от бессмысленной отдачи (SEE)
		var rescue_bonus: float = 0.0
		for x in BOARD_SIZE:
			for y in BOARD_SIZE:
				var p = board[x][y]
				if p != null and not p.is_white:
					var pos = Vector2i(x, y)
					if ChessBot.is_square_attacked(board, pos, true):
						var see_loss = -see(board, pos, pos)
						if see_loss > 0:
							rescue_bonus -= float(see_loss * 0.8)
							
		# Удержание центра в дебюте
		var center_hold: float = 0.0
		if game_phase >= 18:
			var e4_d4_p = [board[3][3], board[4][3], board[3][4], board[4][4]]
			for cp in e4_d4_p:
				if cp != null and not cp.is_white:
					center_hold += 12.0
					
		return base_score + (bonus * 0.5) + rescue_bonus + center_hold

