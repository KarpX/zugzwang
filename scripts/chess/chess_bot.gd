class_name ChessBot
extends RefCounted

## Шахматный движок на основе Prashanna135/chess с адаптивной сложностью и стилями прохождений
## Включает:
## - Tapered Piece-Square Tables (Midgame / Endgame)
## - Оценка баланса материала и позиции (Evaluation)
## - Хеширование Зобриста (Zobrist hashing) и Transposition Table
## - Сортировка ходов: MVV-LVA взятия > Killer moves > History heuristic
## - Quiescence search (форсированный поиск взятий для устранения эффекта горизонта)
## - Итеративное углубление Negamax с альфа-бета отсечением и контролем времени
## - 1-е прохождение: хищный жадный ИИ войны (истребление армии белых перед матом, Hard)
## - 2-е прохождение: пассивный ИИ выживания (жертвует фигуры, чтобы отсрочить мат, Medium)
## - Динамическая сложность (адаптация к преимуществу игрока)

enum PieceType { KING = 0, QUEEN = 1, ROOK = 2, BISHOP = 3, KNIGHT = 4, PAWN = 5 }

const BOARD_SIZE: int = 8
const MATE_SCORE: float = 100000.0
const INF: float = 1e9
const CHECKMATE_THRESHOLD: float = MATE_SCORE - 200.0

static var last_search_info: Dictionary = {
	"depth": 0,
	"score": 0.0,
	"best_move": {},
	"nodes": 0,
	"time_ms": 0
}

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
	0,0,0,0,0,0,0,0,
	50,50,50,50,50,50,50,50,
	10,10,20,30,30,20,10,10,
	5,5,10,25,25,10,5,5,
	0,0,0,20,20,0,0,0,
	5,-5,-10,0,0,-10,-5,5,
	5,10,10,-20,-20,10,10,5,
	0,0,0,0,0,0,0,0,
]
const PAWN_EG: Array[int] = [
	0,0,0,0,0,0,0,0,
	70,70,70,70,70,70,70,70,
	30,30,40,50,50,40,30,30,
	20,20,30,45,45,30,20,20,
	10,10,20,35,35,20,10,10,
	0,0,10,20,20,10,0,0,
	0,0,0,-10,-10,0,0,0,
	0,0,0,0,0,0,0,0,
]
const KNIGHT_MG: Array[int] = [
	-50,-40,-30,-30,-30,-30,-40,-50,
	-40,-20,0,0,0,0,-20,-40,
	-30,0,10,15,15,10,0,-30,
	-30,5,15,20,20,15,5,-30,
	-30,0,15,20,20,15,0,-30,
	-30,5,10,15,15,10,5,-30,
	-40,-20,0,5,5,0,-20,-40,
	-50,-40,-30,-30,-30,-30,-40,-50,
]
const KNIGHT_EG: Array[int] = [
	-40,-30,-20,-20,-20,-20,-30,-40,
	-30,-15,0,0,0,0,-15,-30,
	-20,0,10,12,12,10,0,-20,
	-20,5,12,15,15,12,5,-20,
	-20,0,12,15,15,12,0,-20,
	-20,5,10,12,12,10,5,-20,
	-30,-15,0,5,5,0,-15,-30,
	-40,-30,-20,-20,-20,-20,-30,-40,
]
const BISHOP_MG: Array[int] = [
	-20,-10,-10,-10,-10,-10,-10,-20,
	-10,0,0,0,0,0,0,-10,
	-10,0,5,10,10,5,0,-10,
	-10,5,5,10,10,5,5,-10,
	-10,0,10,10,10,10,0,-10,
	-10,10,10,10,10,10,10,-10,
	-10,5,0,0,0,0,5,-10,
	-20,-10,-10,-10,-10,-10,-10,-20,
]
const BISHOP_EG: Array[int] = [
	-15,-10,-10,-10,-10,-10,-10,-15,
	-10,0,0,0,0,0,0,-10,
	-10,0,5,5,5,5,0,-10,
	-10,5,5,5,5,5,5,-10,
	-10,0,5,5,5,5,0,-10,
	-10,5,5,5,5,5,5,-10,
	-10,0,5,0,0,0,0,-10,
	-15,-10,-10,-10,-10,-10,-10,-15,
]
const ROOK_MG: Array[int] = [
	0,0,0,0,0,0,0,0,
	5,10,10,10,10,10,10,5,
	-5,0,0,0,0,0,0,-5,
	-5,0,0,0,0,0,0,-5,
	-5,0,0,0,0,0,0,-5,
	-5,0,0,0,0,0,0,-5,
	-5,0,0,0,0,0,0,-5,
	0,0,0,5,5,0,0,0,
]
const ROOK_EG: Array[int] = [
	0,0,0,0,0,0,0,0,
	0,0,0,0,0,0,0,0,
	0,0,0,0,0,0,0,0,
	0,0,0,0,0,0,0,0,
	0,0,0,0,0,0,0,0,
	0,0,0,0,0,0,0,0,
	0,0,0,0,0,0,0,0,
	0,0,0,0,0,0,0,0,
]
const QUEEN_MG: Array[int] = [
	-20,-10,-10,-5,-5,-10,-10,-20,
	-10,0,0,0,0,0,0,-10,
	-10,0,5,5,5,5,0,-10,
	-5,0,5,5,5,5,0,-5,
	0,0,5,5,5,5,0,-5,
	-10,5,5,5,5,5,0,-10,
	-10,0,5,0,0,0,0,-10,
	-20,-10,-10,-5,-5,-10,-10,-20,
]
const QUEEN_EG: Array[int] = [
	-20,-10,-10,-5,-5,-10,-10,-20,
	-10,0,0,0,0,0,0,-10,
	-10,0,5,5,5,5,0,-10,
	-5,0,5,5,5,5,0,-5,
	0,0,5,5,5,5,0,-5,
	-10,5,5,5,5,5,0,-10,
	-10,0,5,0,0,0,0,-10,
	-20,-10,-10,-5,-5,-10,-10,-20,
]
const KING_MG: Array[int] = [
	-30,-40,-40,-50,-50,-40,-40,-30,
	-30,-40,-40,-50,-50,-40,-40,-30,
	-30,-40,-40,-50,-50,-40,-40,-30,
	-30,-40,-40,-50,-50,-40,-40,-30,
	-20,-30,-30,-40,-40,-30,-30,-20,
	-10,-20,-20,-20,-20,-20,-20,-10,
	20,20,0,0,0,0,20,20,
	20,30,10,0,0,10,30,20,
]
const KING_EG: Array[int] = [
	-50,-40,-30,-20,-20,-30,-40,-50,
	-30,-20,-10,0,0,-10,-20,-30,
	-30,-10,20,30,30,20,-10,-30,
	-30,-10,30,40,40,30,-10,-30,
	-30,-10,30,40,40,30,-10,-30,
	-30,-10,20,30,30,20,-10,-30,
	-30,-30,0,0,0,0,-30,-30,
	-50,-30,-30,-30,-30,-30,-30,-50,
]

const MG_TABLES: Array = [KING_MG, QUEEN_MG, ROOK_MG, BISHOP_MG, KNIGHT_MG, PAWN_MG]
const EG_TABLES: Array = [KING_EG, QUEEN_EG, ROOK_EG, BISHOP_EG, KNIGHT_EG, PAWN_EG]

# Хеширование Зобриста
static var zobrist_piece: Array = []
static var zobrist_side: int = 0

static func _init_zobrist() -> void:
	if zobrist_piece.is_empty():
		var rng = RandomNumberGenerator.new()
		rng.seed = 987654321
		zobrist_piece.resize(BOARD_SIZE)
		for x in BOARD_SIZE:
			zobrist_piece[x] = []
			zobrist_piece[x].resize(BOARD_SIZE)
			for y in BOARD_SIZE:
				zobrist_piece[x][y] = {}
				for type in range(6):
					for col in range(2):
						zobrist_piece[x][y][type * 2 + col] = rng.randi()
		zobrist_side = rng.randi()

static func _zobrist_hash(board: Array, is_white_turn: bool) -> int:
	var h: int = 0
	for x in BOARD_SIZE:
		for y in BOARD_SIZE:
			var p: LightPiece = board[x][y]
			if p != null:
				var col = 1 if p.is_white else 0
				var key = p.type * 2 + col
				h ^= zobrist_piece[x][y][key]
	if is_white_turn:
		h ^= zobrist_side
	return h

static func _lookup_tt(tt: Dictionary, h: int, depth: int, alpha: float, beta: float) -> Dictionary:
	if tt.has(h):
		var entry = tt[h]
		if entry["depth"] >= depth:
			match entry["flag"]:
				0: return { "score": entry["score"] }
				1: alpha = max(alpha, entry["score"])
				2: beta = min(beta, entry["score"])
			if alpha >= beta:
				return { "score": entry["score"] }
	return { "alpha": alpha, "beta": beta }

static func _store_tt(tt: Dictionary, h: int, depth: int, score: float, flag: int, best_move: Vector2i) -> void:
	tt[h] = {
		"depth": depth,
		"score": score,
		"flag": flag,
		"best_move": best_move
	}

# Внутренний легковесный класс фигуры
class LightPiece:
	var type: int
	var is_white: bool
	var has_moved: bool
	func _init(t: int, w: bool, m: bool = false):
		type = t
		is_white = w
		has_moved = m

static func string_to_type(type_str: String) -> int:
	match type_str:
		"king": return PieceType.KING
		"queen": return PieceType.QUEEN
		"rook": return PieceType.ROOK
		"bishop": return PieceType.BISHOP
		"knight": return PieceType.KNIGHT
		"pawn": return PieceType.PAWN
	return PieceType.PAWN

static func type_to_string(type_int: int) -> String:
	match type_int:
		PieceType.KING: return "king"
		PieceType.QUEEN: return "queen"
		PieceType.ROOK: return "rook"
		PieceType.BISHOP: return "bishop"
		PieceType.KNIGHT: return "knight"
		PieceType.PAWN: return "pawn"
	return "pawn"

## Преобразование 8x8 сетки ChessLogic в легкую матрицу light_board[x][y]
static func make_light_board(logic_grid: Array) -> Array:
	var light: Array = []
	for x in BOARD_SIZE:
		var col: Array = []
		light.append(col)
		for y in BOARD_SIZE:
			var p = logic_grid[x][y]
			if p == null:
				col.append(null)
			else:
				var t_int = string_to_type(p["type"])
				col.append(LightPiece.new(t_int, p["is_white"], p.get("has_moved", false)))
	return light

static func in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < BOARD_SIZE and pos.y >= 0 and pos.y < BOARD_SIZE

## Применение хода на легкой доске с сохранением данных для отката
static func apply_move(board: Array, from_pos: Vector2i, to_pos: Vector2i) -> Dictionary:
	var piece: LightPiece = board[from_pos.x][from_pos.y]
	var captured: LightPiece = board[to_pos.x][to_pos.y]
	board[to_pos.x][to_pos.y] = piece
	board[from_pos.x][from_pos.y] = null
	
	var undo: Dictionary = {
		"from": from_pos,
		"to": to_pos,
		"piece": piece,
		"captured": captured,
		"was_moved": piece.has_moved
	}
	piece.has_moved = true
	
	# Рокировка
	if piece.type == PieceType.KING and abs(to_pos.x - from_pos.x) == 2:
		var y = from_pos.y
		var rook_from_x = 7 if to_pos.x == 6 else 0
		var rook_to_x = 5 if to_pos.x == 6 else 3
		var rook: LightPiece = board[rook_from_x][y]
		board[rook_to_x][y] = rook
		board[rook_from_x][y] = null
		if rook != null:
			rook.has_moved = true
		undo["castled"] = true
		undo["rook"] = rook
		undo["rook_from"] = Vector2i(rook_from_x, y)
		undo["rook_to"] = Vector2i(rook_to_x, y)
		
	# Превращение пешки в ферзя
	if piece.type == PieceType.PAWN:
		if (piece.is_white and to_pos.y == 7) or (not piece.is_white and to_pos.y == 0):
			piece.type = PieceType.QUEEN
			undo["promoted"] = true
			
	return undo

## Откат хода
static func undo_move(board: Array, undo: Dictionary) -> void:
	var piece: LightPiece = undo["piece"]
	board[undo["from"].x][undo["from"].y] = piece
	board[undo["to"].x][undo["to"].y] = undo["captured"]
	piece.has_moved = undo["was_moved"]
	
	if undo.has("castled") and undo["castled"]:
		var rook: LightPiece = undo["rook"]
		board[undo["rook_from"].x][undo["rook_from"].y] = rook
		board[undo["rook_to"].x][undo["rook_to"].y] = null
		if rook != null:
			rook.has_moved = false
			
	if undo.has("promoted") and undo["promoted"]:
		piece.type = PieceType.PAWN

# ==============================================================================
# Генерация ходов для легкой доски
# ==============================================================================

static func get_legal_moves(board: Array, from_pos: Vector2i, piece: LightPiece) -> Array[Vector2i]:
	var pseudo: Array[Vector2i] = _get_pseudo_moves(board, from_pos, piece, false)
	if piece.type == PieceType.KING:
		pseudo.append_array(_get_castling_moves(board, from_pos, piece))
		
	var legal: Array[Vector2i] = []
	for target in pseudo:
		var undo = apply_move(board, from_pos, target)
		if not is_in_check(board, piece.is_white):
			legal.append(target)
		undo_move(board, undo)
	return legal

static func _get_pseudo_moves(board: Array, pos: Vector2i, piece: LightPiece, attack_only: bool) -> Array[Vector2i]:
	match piece.type:
		PieceType.PAWN:
			var moves: Array[Vector2i] = []
			var forward: int = 1 if piece.is_white else -1
			var start_rank: int = 1 if piece.is_white else 6
			if not attack_only:
				var one = Vector2i(pos.x, pos.y + forward)
				if in_bounds(one) and board[one.x][one.y] == null:
					moves.append(one)
					var two = Vector2i(pos.x, pos.y + forward * 2)
					if pos.y == start_rank and board[two.x][two.y] == null:
						moves.append(two)
			for dx in [-1, 1]:
				var diag = Vector2i(pos.x + dx, pos.y + forward)
				if in_bounds(diag):
					var target: LightPiece = board[diag.x][diag.y]
					if attack_only or (target != null and target.is_white != piece.is_white):
						moves.append(diag)
			return moves
			
		PieceType.KNIGHT:
			var offsets = [
				Vector2i(1,2), Vector2i(2,1), Vector2i(-1,2), Vector2i(-2,1),
				Vector2i(1,-2), Vector2i(2,-1), Vector2i(-1,-2), Vector2i(-2,-1)
			]
			var moves: Array[Vector2i] = []
			for o in offsets:
				var p = pos + o
				if in_bounds(p):
					var target: LightPiece = board[p.x][p.y]
					if target == null or target.is_white != piece.is_white:
						moves.append(p)
			return moves
			
		PieceType.BISHOP:
			return _sliding_moves(board, pos, piece, [Vector2i(1,1), Vector2i(1,-1), Vector2i(-1,1), Vector2i(-1,-1)])
		PieceType.ROOK:
			return _sliding_moves(board, pos, piece, [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)])
		PieceType.QUEEN:
			return _sliding_moves(board, pos, piece, [
				Vector2i(1,1), Vector2i(1,-1), Vector2i(-1,1), Vector2i(-1,-1),
				Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)
			])
		PieceType.KING:
			var moves: Array[Vector2i] = []
			for dx in [-1, 0, 1]:
				for dy in [-1, 0, 1]:
					if dx == 0 and dy == 0: continue
					var p = Vector2i(pos.x + dx, pos.y + dy)
					if in_bounds(p):
						var target: LightPiece = board[p.x][p.y]
						if target == null or target.is_white != piece.is_white:
							moves.append(p)
			return moves
	return []

static func _sliding_moves(board: Array, pos: Vector2i, piece: LightPiece, dirs: Array[Vector2i]) -> Array[Vector2i]:
	var moves: Array[Vector2i] = []
	for d in dirs:
		var p = pos + d
		while in_bounds(p):
			var target: LightPiece = board[p.x][p.y]
			if target == null:
				moves.append(p)
			else:
				if target.is_white != piece.is_white:
					moves.append(p)
				break
			p += d
	return moves

static func _get_castling_moves(board: Array, pos: Vector2i, piece: LightPiece) -> Array[Vector2i]:
	var moves: Array[Vector2i] = []
	if piece.has_moved: return moves
	if is_in_check(board, piece.is_white): return moves
	
	var y = pos.y
	# Kingside O-O (ладья на x=7, король идет на x=6)
	var ks_rook: LightPiece = board[7][y]
	if ks_rook != null and ks_rook.type == PieceType.ROOK and ks_rook.is_white == piece.is_white and not ks_rook.has_moved:
		if board[5][y] == null and board[6][y] == null:
			if not is_square_attacked(board, Vector2i(5, y), not piece.is_white) and not is_square_attacked(board, Vector2i(6, y), not piece.is_white):
				moves.append(Vector2i(6, y))
				
	# Queenside O-O-O (ладья на x=0, король идет на x=2)
	var qs_rook: LightPiece = board[0][y]
	if qs_rook != null and qs_rook.type == PieceType.ROOK and qs_rook.is_white == piece.is_white and not qs_rook.has_moved:
		if board[1][y] == null and board[2][y] == null and board[3][y] == null:
			if not is_square_attacked(board, Vector2i(3, y), not piece.is_white) and not is_square_attacked(board, Vector2i(2, y), not piece.is_white):
				moves.append(Vector2i(2, y))
				
	return moves

static func find_king(board: Array, is_white: bool) -> Vector2i:
	for x in BOARD_SIZE:
		for y in BOARD_SIZE:
			var p: LightPiece = board[x][y]
			if p != null and p.type == PieceType.KING and p.is_white == is_white:
				return Vector2i(x, y)
	return Vector2i(-1, -1)

static func is_square_attacked(board: Array, pos: Vector2i, by_white: bool) -> bool:
	for x in BOARD_SIZE:
		for y in BOARD_SIZE:
			var p: LightPiece = board[x][y]
			if p != null and p.is_white == by_white:
				var attacks = _get_pseudo_moves(board, Vector2i(x, y), p, true)
				if pos in attacks:
					return true
	return false

static func is_in_check(board: Array, is_white: bool) -> bool:
	var k_pos = find_king(board, is_white)
	if k_pos.x == -1: return true
	return is_square_attacked(board, k_pos, not is_white)

# ==============================================================================
# СТАТИЧЕСКАЯ ОЦЕНКА РАЗМЕНА (Static Exchange Evaluation — SEE)
# ==============================================================================

## Поиск наименее ценной фигуры стороны by_white, атакующей клетку target_pos
static func get_least_valuable_attacker(board: Array, target_pos: Vector2i, by_white: bool) -> Dictionary:
	var best_piece: LightPiece = null
	var best_pos: Vector2i = Vector2i(-1, -1)
	var best_val: int = 999999
	
	for x in BOARD_SIZE:
		for y in BOARD_SIZE:
			var p: LightPiece = board[x][y]
			if p != null and p.is_white == by_white:
				var from_p = Vector2i(x, y)
				var attacks = _get_pseudo_moves(board, from_p, p, true)
				if target_pos in attacks:
					var val: int = PIECE_VALUES[p.type]
					if val < best_val:
						best_val = val
						best_piece = p
						best_pos = from_p
						
	if best_piece == null:
		return {}
	return { "pos": best_pos, "piece": best_piece, "val": best_val }

## Статическая оценка размена (Static Exchange Evaluation — SEE)
## Возвращает ожидаемый баланс материала при цепочке разменов на клетке to_pos.
## > 0: размен выгоден (чистый выигрыш фигуры или бесплатная фигура)
## == 0: равный размен (конь за коня, пешка за пешку)
## < 0: невыгодный размен / зевок фигуры (ферзь за защищенную пешку и т.п.)
static func see(board: Array, from_pos: Vector2i, to_pos: Vector2i) -> int:
	var target: LightPiece = board[to_pos.x][to_pos.y]
	var attacker: LightPiece = board[from_pos.x][from_pos.y]
	if attacker == null:
		return 0
		
	var target_val: int = PIECE_VALUES[target.type] if target != null else 0
	
	# Если клетка не атакована соперником — фигура забирается бесплатно!
	if not is_square_attacked(board, to_pos, not attacker.is_white):
		return target_val
		
	var gain: Array[int] = [target_val]
	
	# Копия доски для симуляции серии ответных взятий
	var sim_board: Array = []
	for x in BOARD_SIZE:
		var col: Array = []
		for y in BOARD_SIZE:
			col.append(board[x][y])
		sim_board.append(col)
		
	var cur_pos = from_pos
	var cur_piece = attacker
	var cur_color = attacker.is_white
	var d = 0
	
	while true:
		# Ответное взятие оппонента наименее ценной фигурой
		var opp_color = not cur_color
		var defender = get_least_valuable_attacker(sim_board, to_pos, opp_color)
		if defender.is_empty():
			break
			
		d += 1
		gain.append(PIECE_VALUES[cur_piece.type] - gain[d - 1])
		sim_board[to_pos.x][to_pos.y] = cur_piece
		sim_board[cur_pos.x][cur_pos.y] = null
		cur_pos = defender["pos"]
		cur_piece = defender["piece"]
		cur_color = opp_color
		
	# Минимакс-свертка обратным ходом: ни одна сторона не обязана делать невыгодное взятие
	var n: int = gain.size()
	while n > 1:
		n -= 1
		gain[n - 1] = -max(-gain[n - 1], gain[n])
		
	return gain[0]

# ==============================================================================
# ОЦЕНКА ПОЗИЦИИ И СТИЛЕЙ ИГРЫ (Evaluation & Playthrough Personas)
# ==============================================================================

## Базовая позиционная оценка из Prashanna135/chess:
## Материал + Tapered Piece-Square Tables (MG -> EG переход)
static func evaluate_base(board: Array, is_white_perspective: bool) -> float:
	var mg_score: float = 0.0
	var eg_score: float = 0.0
	var mg_mat: float = 0.0
	var eg_mat: float = 0.0
	var total_mat: float = 0.0
	
	for x in BOARD_SIZE:
		for y in BOARD_SIZE:
			var p: LightPiece = board[x][y]
			if p == null: continue
			
			var sign_val: float = 1.0 if p.is_white == is_white_perspective else -1.0
			var type: int = p.type
			var val: int = PIECE_VALUES[type]
			
			if type != PieceType.KING:
				mg_mat += sign_val * val
				eg_mat += sign_val * val
				total_mat += val
				
			# Зеркалирование строк для PST таблиц
			var table_row: int = (7 - y) if p.is_white else y
			var idx: int = table_row * 8 + x
			mg_score += sign_val * MG_TABLES[type][idx]
			eg_score += sign_val * EG_TABLES[type][idx]
			
	var phase: float = clamp((8000.0 - total_mat) / 8000.0, 0.0, 1.0)
	return (mg_score + mg_mat) * (1.0 - phase) + (eg_score + eg_mat) * phase

## Полная оценка с учётом правил прохождения:
## - 1-е прохождение: хищный ИИ войны (жадно уничтожает армию игрока выгодными разменами перед матом)
## - 2-е прохождение: ИИ выживания (жертвует фигуры, спасая короля, слабее игрока)
static func evaluate_for_bot(board: Array, playthrough: int = 1) -> float:
	# Оценка со стороны Черных (бота)
	var base_score: float = evaluate_base(board, false)
	
	var white_piece_count: int = 0
	var white_material: int = 0
	var black_material: int = 0
	
	for x in BOARD_SIZE:
		for y in BOARD_SIZE:
			var p: LightPiece = board[x][y]
			if p != null and p.type != PieceType.KING:
				if p.is_white:
					white_piece_count += 1
					white_material += PIECE_VALUES[p.type]
				else:
					black_material += PIECE_VALUES[p.type]
					
	if playthrough == 1:
		# ПЕРВОЕ ПРОХОЖДЕНИЕ: Мастерский хищный ИИ Черных
		# 1. Защита собственного материала: Черные не отдают фигуры даром и не идут на плохие размены!
		# 2. Бонус за уничтожение армии белых: начисляется за чистые взятия
		var material_balance = black_material - white_material
		
		# Бонус за устранение фигур игрока (чистые взятия)
		var capture_dominance = (16 - white_piece_count) * 35.0
		if material_balance < 0:
			# Если Черные понесли потери и уступают по материалу — бонус отменяется!
			capture_dominance = 0.0
			
		# В эндшпиле при материальном перевесе: бот методично зачищает остатки пешек и фигур
		var endgame_cleanup = 0.0
		if material_balance >= 200 and white_material > 0:
			endgame_cleanup = (4000.0 - white_material) * 0.15
			
		return base_score + (material_balance * 0.6) + capture_dominance + endgame_cleanup
	else:
		# ВТОРОЕ ПРОХОЖДЕНИЕ: Выживание и поддавки
		# Бот играет слабее игрока (уровень любителя), но держит короля в безопасности
		var king_safety = 0.0
		var black_king_pos = find_king(board, false)
		if black_king_pos.x != -1:
			if is_in_check(board, false):
				king_safety -= 1500.0 # Панический страх шаха
				
			# Безопасность короля: король ОБЯЗАН оставаться на последней горизонтали (y == 7)!
			# Выход короля вперед в дебюте/миттельшпиле жестко наказывается:
			if black_king_pos.y < 7 and white_material > 1200:
				king_safety -= float(7 - black_king_pos.y) * 450.0
			elif black_king_pos.y == 7:
				king_safety += 200.0 # Бонус за укрытие на заднем ряду
				
			# Укрытие за пешками (f7, g7, h7)
			for px in [5, 6, 7]:
				var pawn_cover = board[px][6]
				if pawn_cover != null and not pawn_cover.is_white and pawn_cover.type == PieceType.PAWN:
					king_safety += 30.0
					
		# Бот в матче 2 играет с умеренной оценкой материала (не жертвует фигуры намеренно в пустоту, но уступает позиции)
		var survival_score = (base_score * 0.75) + king_safety
		return survival_score

# ==============================================================================
# Сортировка ходов (Move Ordering: SEE, MVV-LVA, Killers, History)
# ==============================================================================

static var killer_moves: Array = []
static var history_table: Dictionary = {}

static func _move_score(board: Array, m: Dictionary) -> int:
	var target: LightPiece = board[m.to.x][m.to.y]
	if target == null:
		return 0
	var attacker: LightPiece = board[m.from.x][m.from.y]
	var see_val: int = see(board, m.from, m.to)
	if see_val > 0:
		# Выгодное взятие (выигрыш материала)
		return 2000000 + see_val * 10
	elif see_val == 0:
		# Равный размен
		return 1000000 + PIECE_VALUES[target.type] * 10 - PIECE_VALUES[attacker.type]
	else:
		# Невыгодный размен (зевок под защиту оппонента)
		return -500000 + see_val

static func _history_key(m: Dictionary) -> String:
	return "%d,%d->%d,%d" % [m.from.x, m.from.y, m.to.x, m.to.y]

static func _sort_moves(board: Array, moves: Array[Dictionary], ply: int = 0) -> Array[Dictionary]:
	var scored: Array = []
	var killers: Array = []
	if ply < killer_moves.size() and killer_moves[ply] != null:
		killers = killer_moves[ply]
		
	for m in moves:
		var sc: int = 0
		var target: LightPiece = board[m.to.x][m.to.y]
		var attacker: LightPiece = board[m.from.x][m.from.y]
		if target != null:
			sc = _move_score(board, m)
		elif killers.has(m.to):
			sc = 800000
		else:
			sc = history_table.get(_history_key(m), 0)
			# Если тихий ход ставит фигуру под бой соперника и при этом не защищен:
			if attacker != null and is_square_attacked(board, m.to, not attacker.is_white):
				if not is_square_attacked(board, m.to, attacker.is_white):
					sc -= 900000
		scored.append({"move": m, "score": sc})
		
	scored.sort_custom(func(a, b): return a.score > b.score)
	
	var res: Array[Dictionary] = []
	for item in scored:
		res.append(item.move)
	return res

static func _record_killer(m: Dictionary, ply: int, depth: int) -> void:
	if ply >= killer_moves.size():
		killer_moves.resize(ply + 1)
	if killer_moves[ply] == null:
		killer_moves[ply] = []
	var slot: Array = killer_moves[ply]
	if not slot.has(m.to):
		slot.push_front(m.to)
		if slot.size() > 2:
			slot.resize(2)
		killer_moves[ply] = slot
	var key = _history_key(m)
	history_table[key] = history_table.get(key, 0) + depth * depth

# ==============================================================================
# Поиск Quiescence (форсированные взятия)
# ==============================================================================

static var node_count: int = 0

static func _quiescence(
	board: Array,
	is_white_turn: bool,
	alpha: float,
	beta: float,
	start_time: int,
	time_limit_ms: int,
	playthrough: int
) -> float:
	node_count += 1
	if node_count % 512 == 0 and time_limit_ms > 0:
		if Time.get_ticks_msec() - start_time >= time_limit_ms:
			return 0.0
			
	var stand_pat: float = evaluate_for_bot(board, playthrough)
	if is_white_turn:
		stand_pat = -stand_pat
		
	if stand_pat >= beta:
		return beta
	if alpha < stand_pat:
		alpha = stand_pat
		
	# Ищем только взятия
	var captures: Array[Dictionary] = []
	for x in BOARD_SIZE:
		for y in BOARD_SIZE:
			var p: LightPiece = board[x][y]
			if p != null and p.is_white == is_white_turn:
				var from_pos = Vector2i(x, y)
				for m in get_legal_moves(board, from_pos, p):
					if board[m.x][m.y] != null:
						# В форсированном поиске отсекаем заведомо убыточные взятия (SEE < 0):
						if see(board, from_pos, m) >= 0:
							captures.append({"from": from_pos, "to": m})
						
	if captures.is_empty():
		return alpha
		
	captures = _sort_moves(board, captures, 0)
	
	for m in captures:
		var undo = apply_move(board, m.from, m.to)
		var score = -_quiescence(board, not is_white_turn, -beta, -alpha, start_time, time_limit_ms, playthrough)
		undo_move(board, undo)
		
		if score >= beta:
			return beta
		if score > alpha:
			alpha = score
			
	return alpha

# ==============================================================================
# Итеративный Negamax поиск
# ==============================================================================

static func _negamax(
	board: Array,
	depth: int,
	is_white_turn: bool,
	alpha: float,
	beta: float,
	start_time: int,
	time_limit_ms: int,
	tt: Dictionary,
	ply: int,
	playthrough: int
) -> float:
	node_count += 1
	if node_count % 512 == 0 and time_limit_ms > 0:
		if Time.get_ticks_msec() - start_time >= time_limit_ms:
			return 0.0
			
	var alpha_orig = alpha
	var h = _zobrist_hash(board, is_white_turn)
	var lookup = _lookup_tt(tt, h, depth, alpha, beta)
	if lookup.has("score"):
		return lookup["score"]
	alpha = lookup["alpha"]
	beta = lookup["beta"]
	
	if depth <= 0:
		return _quiescence(board, is_white_turn, alpha, beta, start_time, time_limit_ms, playthrough)
		
	var moves: Array[Dictionary] = []
	for x in BOARD_SIZE:
		for y in BOARD_SIZE:
			var p: LightPiece = board[x][y]
			if p != null and p.is_white == is_white_turn:
				var from_pos = Vector2i(x, y)
				for m in get_legal_moves(board, from_pos, p):
					moves.append({"from": from_pos, "to": m})
					
	if moves.is_empty():
		if is_in_check(board, is_white_turn):
			return -(MATE_SCORE - float(ply))
		return 0.0
		
	moves = _sort_moves(board, moves, ply)
	
	var best = -INF
	var best_move_to = Vector2i(-1, -1)
	for m in moves:
		var undo = apply_move(board, m.from, m.to)
		var was_quiet = (undo["captured"] == null)
		var score = -_negamax(board, depth - 1, not is_white_turn, -beta, -alpha, start_time, time_limit_ms, tt, ply + 1, playthrough)
		undo_move(board, undo)
		
		if score > best:
			best = score
			best_move_to = m.to
		alpha = max(alpha, score)
		if alpha >= beta:
			if was_quiet:
				_record_killer(m, ply, depth)
			break
			
	var flag = 0
	if best <= alpha_orig: flag = 2
	elif best >= beta: flag = 1
	else: flag = 0
	_store_tt(tt, h, depth, best, flag, best_move_to)
	
	return best

# ==============================================================================
# ДИНАМИЧЕСКИЙ ВЫБОР ХОДА (Главная точка входа ИИ)
# ==============================================================================

## Выбор наилучшего хода с учетом динамической сложности и прохождения
static func choose_best_move(
	full_board: Array,
	playthrough: int = 1,
	consecutive_wins: int = 0
) -> Dictionary:
	_init_zobrist()
	var board = make_light_board(full_board)
	
	# Собираем все легальные ходы Черных
	var all_moves: Array[Dictionary] = []
	for x in BOARD_SIZE:
		for y in BOARD_SIZE:
			var p: LightPiece = board[x][y]
			if p != null and not p.is_white:
				var from_pos = Vector2i(x, y)
				for m in get_legal_moves(board, from_pos, p):
					all_moves.append({"from": from_pos, "to": m})
					
	if all_moves.is_empty():
		return {}
		
	# 1. Расчет разницы в материале и позиции для динамической сложности
	var eval_white = evaluate_base(board, true)
	var white_material = 0
	var black_material = 0
	var white_pieces_remaining = 0
	
	for x in BOARD_SIZE:
		for y in BOARD_SIZE:
			var p: LightPiece = board[x][y]
			if p != null and p.type != PieceType.KING:
				if p.is_white:
					white_material += PIECE_VALUES[p.type]
					white_pieces_remaining += 1
				else:
					black_material += PIECE_VALUES[p.type]
					
	var material_diff = white_material - black_material # преимущество игрока
	
	# 2. Определение динамических параметров поиска (глубина, случайность, лимит времени)
	var max_depth: int = 3
	var _randomness: float = 0.0
	var time_limit_ms: int = 800
	
	if playthrough == 1:
		# Первое прохождение: Сложность высокая и НЕ падает ниже Hard!
		max_depth = 4
		_randomness = 0.0
		time_limit_ms = 1000
		
		# Если игрок вдруг получает преимущество по фигурам или позиции — бот включает максимальную ярость
		if material_diff > 200 or eval_white > 250:
			max_depth = 5
			time_limit_ms = 1500
	else:
		# Второе прохождение: Сложность начинается со средней (Medium)
		# Бот поддается, слабее игрока, но пытается выжить
		max_depth = 2
		_randomness = 0.16
		time_limit_ms = 400
		
		# Если игрок сильно впереди, бот чуть подтягивает выживание, но не превышает depth 3
		if material_diff > 300 or eval_white > 350:
			max_depth = 3
			_randomness = 0.08
			time_limit_ms = 600
		elif material_diff < -300: # если игрок отстает, бот делает ошибки охотнее
			_randomness = 0.25
			
	# Сброс вспомогательных структур
	killer_moves.clear()
	history_table.clear()
	
	var best_move: Dictionary = all_moves[0]
	var best_score: float = -INF
	var start_time: int = Time.get_ticks_msec()
	var soft_limit: int = int(time_limit_ms * 0.6)
	var tt: Dictionary = {}
	var completed_depth: int = 1
	var scored_root_moves: Array[Dictionary] = []
	
	# Итеративное углубление поиска
	for depth in range(1, max_depth + 1):
		node_count = 0
		var current_best = best_move
		var alpha: float = -INF
		var beta: float = INF
		var aborted: bool = false
		var depth_root_moves: Array[Dictionary] = []
		
		all_moves = _sort_moves(board, all_moves, 0)
		
		for m in all_moves:
			var undo = apply_move(board, m.from, m.to)
			
			# Честная оценка хода через Negamax
			var score = -_negamax(board, depth - 1, true, -beta, -alpha, start_time, time_limit_ms, tt, 0, playthrough)
			undo_move(board, undo)
			
			depth_root_moves.append({ "move": m, "score": score })
			
			if time_limit_ms > 0 and Time.get_ticks_msec() - start_time >= time_limit_ms:
				aborted = true
				break
				
			if score > alpha:
				alpha = score
				current_best = m
			var h = _zobrist_hash(board, false)
			_store_tt(tt, h, depth, score, 0 if score > best_score else 1, m.to)
				
		if not aborted:
			best_score = alpha
			best_move = current_best
			completed_depth = depth
			scored_root_moves = depth_root_moves
		else:
			break
			
		var elapsed = Time.get_ticks_msec() - start_time
		if time_limit_ms > 0 and elapsed >= soft_limit:
			break
		if best_score > CHECKMATE_THRESHOLD:
			break
			
	# Выбор финального хода
	var final_move: Dictionary = best_move
	var black_king_pos = find_king(board, false)
	var in_check: bool = is_in_check(board, false)
	
	if playthrough == 2 and not in_check and scored_root_moves.size() > 1:
		scored_root_moves.sort_custom(func(a, b): return a["score"] > b["score"])
		var top_score: float = scored_root_moves[0]["score"]
		
		# Собираем хорошие ходы (без грубых зевок короля и без выхода короля в центр в дебюте)
		var candidates: Array[Dictionary] = []
		for sm in scored_root_moves:
			var m = sm["move"]
			# Отсекаем ходы с оценкой намного ниже лучшей
			if sm["score"] < top_score - 180.0:
				break
			# В дебюте/миттельшпиле король НЕ идет вперед в центр
			if m["from"] == black_king_pos and m["to"].y < 7 and white_material > 1000:
				continue
			candidates.append(m)
			if candidates.size() >= 3:
				break
				
		if candidates.size() >= 2:
			var rng = RandomNumberGenerator.new()
			rng.randomize()
			# 65% шанс сыграть чуть более пассивный/человеческий ход #2
			if rng.randf() < 0.65:
				final_move = candidates[1]
			else:
				final_move = candidates[0]
		elif not candidates.is_empty():
			final_move = candidates[0]
			
	last_search_info = {
		"depth": completed_depth,
		"score": best_score,
		"best_move": final_move,
		"nodes": node_count,
		"time_ms": Time.get_ticks_msec() - start_time
	}
	return final_move
