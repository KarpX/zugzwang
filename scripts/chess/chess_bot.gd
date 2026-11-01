class_name ChessBot
extends RefCounted

## Главный фасад шахматного движка Zugzwang с адаптивной сложностью и фоновым пре-расчетом (Pondering)
## Архитектура разделена на специализированные подсистемы:
## - ChessEvaluator: оценка баланса, таблицы PST, Static Exchange Evaluation (SEE)
## - ChessOpeningBook: гроссмейстерская дебютная книга ходов
## - ChessSearch: хеширование Зобриста, TT, сортировка ходов (MVV-LVA), Quiescence и Negamax поиск

const ChessEvaluator = preload("res://scripts/chess/bot/chess_evaluator.gd")
const ChessOpeningBook = preload("res://scripts/chess/bot/chess_opening_book.gd")
const ChessSearch = preload("res://scripts/chess/bot/chess_search.gd")

const PieceType = ChessEvaluator.PieceType
const PIECE_VALUES = ChessEvaluator.PIECE_VALUES
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

# ==============================================================================
# Легковесное представление доски для быстрого расчета в дереве поиска
# ==============================================================================

class LightPiece:
	var type: int
	var is_white: bool
	var has_moved: bool
	func _init(t: int, w: bool, m: bool = false):
		type = t
		is_white = w
		has_moved = m

static func string_to_type(type_str: String) -> int:
	return ChessEvaluator.string_to_type(type_str)

static func type_to_string(type_int: int) -> String:
	return ChessEvaluator.type_to_string(type_int)

static func make_light_board(logic_grid: Array) -> Array:
	var b: Array = []
	for x in BOARD_SIZE:
		var col: Array = []
		b.append(col)
		for y in BOARD_SIZE:
			var p = logic_grid[x][y]
			if p == null:
				col.append(null)
			else:
				var t_int = string_to_type(p["type"])
				col.append(LightPiece.new(t_int, p["is_white"], p.get("has_moved", false)))
	return b

static func in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < BOARD_SIZE and pos.y >= 0 and pos.y < BOARD_SIZE

static func apply_move(board: Array, from_pos: Vector2i, to_pos: Vector2i) -> Dictionary:
	var moving: LightPiece = board[from_pos.x][from_pos.y]
	var captured: LightPiece = board[to_pos.x][to_pos.y]
	var had_moved = moving.has_moved if moving != null else false
	var castled = false
	var rook_from = Vector2i(-1, -1)
	var rook_to = Vector2i(-1, -1)
	var is_ep = false
	var ep_captured_pos = Vector2i(-1, -1)
	var ep_captured_piece: LightPiece = null

	# Взятие на проходе
	if moving != null and moving.type == PieceType.PAWN and captured == null and from_pos.x != to_pos.x:
		is_ep = true
		ep_captured_pos = Vector2i(to_pos.x, from_pos.y)
		ep_captured_piece = board[ep_captured_pos.x][ep_captured_pos.y]
		board[ep_captured_pos.x][ep_captured_pos.y] = null

	# Рокировка
	if moving != null and moving.type == PieceType.KING and abs(to_pos.x - from_pos.x) == 2:
		castled = true
		var rank = from_pos.y
		if to_pos.x == 6: # Короткая рокировка
			rook_from = Vector2i(7, rank)
			rook_to = Vector2i(5, rank)
		elif to_pos.x == 2: # Длинная рокировка
			rook_from = Vector2i(0, rank)
			rook_to = Vector2i(3, rank)
		if rook_from.x != -1 and board[rook_from.x][rook_from.y] != null:
			var r = board[rook_from.x][rook_from.y]
			board[rook_from.x][rook_from.y] = null
			r.has_moved = true
			board[rook_to.x][rook_to.y] = r

	var was_promotion: bool = false
	board[from_pos.x][from_pos.y] = null
	if moving != null:
		moving.has_moved = true
		# Автоматическое превращение пешки в ферзя на последней горизонтали
		if moving.type == PieceType.PAWN and (to_pos.y == 0 or to_pos.y == 7):
			was_promotion = true
			moving.type = PieceType.QUEEN
	board[to_pos.x][to_pos.y] = moving

	return {
		"from": from_pos, "to": to_pos, "captured": captured, "had_moved": had_moved,
		"castled": castled, "rook_from": rook_from, "rook_to": rook_to,
		"is_ep": is_ep, "ep_pos": ep_captured_pos, "ep_piece": ep_captured_piece,
		"was_promotion": was_promotion
	}

static func undo_move(board: Array, undo: Dictionary) -> void:
	var from_pos: Vector2i = undo["from"]
	var to_pos: Vector2i = undo["to"]
	var moving: LightPiece = board[to_pos.x][to_pos.y]
	if moving != null:
		moving.has_moved = undo["had_moved"]
		if undo.get("was_promotion", false):
			moving.type = PieceType.PAWN
	board[from_pos.x][from_pos.y] = moving
	board[to_pos.x][to_pos.y] = undo["captured"]

	if undo["is_ep"]:
		var ep_p: Vector2i = undo["ep_pos"]
		board[ep_p.x][ep_p.y] = undo["ep_piece"]

	if undo["castled"]:
		var rf: Vector2i = undo["rook_from"]
		var rt: Vector2i = undo["rook_to"]
		if rt.x != -1 and board[rt.x][rt.y] != null:
			var r = board[rt.x][rt.y]
			r.has_moved = false
			board[rt.x][rt.y] = null
			board[rf.x][rf.y] = r

# ==============================================================================
# Генерация легальных ходов и проверка шаха
# ==============================================================================

static func get_legal_moves(board: Array, from_pos: Vector2i, piece: LightPiece, ep_target: Vector2i = Vector2i(-1, -1), attack_only: bool = false) -> Array[Vector2i]:
	var pseudo = _get_pseudo_moves(board, from_pos, piece, attack_only, ep_target)
	var legal: Array[Vector2i] = []
	for target in pseudo:
		var undo = apply_move(board, from_pos, target)
		if not is_in_check(board, piece.is_white):
			legal.append(target)
		undo_move(board, undo)
	return legal

static func _get_pseudo_moves(board: Array, pos: Vector2i, piece: LightPiece, attack_only: bool, ep_target: Vector2i = Vector2i(-1, -1)) -> Array[Vector2i]:
	var moves: Array[Vector2i] = []
	match piece.type:
		PieceType.PAWN:
			var dir = 1 if piece.is_white else -1
			var start_rank = 1 if piece.is_white else 6
			if not attack_only:
				var fwd = Vector2i(pos.x, pos.y + dir)
				if in_bounds(fwd) and board[fwd.x][fwd.y] == null:
					moves.append(fwd)
					var fwd2 = Vector2i(pos.x, pos.y + dir * 2)
					if pos.y == start_rank and in_bounds(fwd2) and board[fwd2.x][fwd2.y] == null:
						moves.append(fwd2)
			for dx in [-1, 1]:
				var diag = Vector2i(pos.x + dx, pos.y + dir)
				if in_bounds(diag):
					var occ: LightPiece = board[diag.x][diag.y]
					if occ != null:
						if occ.is_white != piece.is_white or attack_only:
							moves.append(diag)
					elif not attack_only and ep_target.x != -1 and diag == ep_target:
						var captured_pawn_pos = Vector2i(diag.x, pos.y)
						if in_bounds(captured_pawn_pos):
							var cap_p = board[captured_pawn_pos.x][captured_pawn_pos.y]
							if cap_p != null and cap_p.type == PieceType.PAWN and cap_p.is_white != piece.is_white:
								moves.append(diag)
		PieceType.KNIGHT:
			for off in ChessEvaluator.KNIGHT_OFFSETS:
				var np = pos + off
				if in_bounds(np):
					var occ: LightPiece = board[np.x][np.y]
					if occ == null or occ.is_white != piece.is_white or attack_only:
						moves.append(np)
		PieceType.BISHOP:
			moves.append_array(_sliding_moves(board, pos, piece, ChessEvaluator.BISHOP_DIRS, attack_only))
		PieceType.ROOK:
			moves.append_array(_sliding_moves(board, pos, piece, ChessEvaluator.ROOK_DIRS, attack_only))
		PieceType.QUEEN:
			moves.append_array(_sliding_moves(board, pos, piece, ChessEvaluator.QUEEN_DIRS, attack_only))
		PieceType.KING:
			for off in ChessEvaluator.KING_OFFSETS:
				var np = pos + off
				if in_bounds(np):
					var occ: LightPiece = board[np.x][np.y]
					if occ == null or occ.is_white != piece.is_white or attack_only:
						moves.append(np)
			if not attack_only and not piece.has_moved:
				moves.append_array(_get_castling_moves(board, pos, piece))
	return moves

static func _sliding_moves(board: Array, pos: Vector2i, piece: LightPiece, dirs: Array[Vector2i], attack_only: bool = false) -> Array[Vector2i]:
	var moves: Array[Vector2i] = []
	for d in dirs:
		var cur = pos + d
		while in_bounds(cur):
			var occ: LightPiece = board[cur.x][cur.y]
			if occ == null:
				moves.append(cur)
			else:
				if occ.is_white != piece.is_white or attack_only:
					moves.append(cur)
				break
			cur += d
	return moves

static func _get_castling_moves(board: Array, pos: Vector2i, piece: LightPiece) -> Array[Vector2i]:
	var moves: Array[Vector2i] = []
	if is_in_check(board, piece.is_white):
		return moves
	var rank = pos.y
	# Короткая рокировка
	var r_rook = board[7][rank]
	if r_rook != null and r_rook.type == PieceType.ROOK and not r_rook.has_moved:
		if board[5][rank] == null and board[6][rank] == null:
			if not is_square_attacked(board, Vector2i(5, rank), not piece.is_white) and not is_square_attacked(board, Vector2i(6, rank), not piece.is_white):
				moves.append(Vector2i(6, rank))
	# Длинная рокировка
	var l_rook = board[0][rank]
	if l_rook != null and l_rook.type == PieceType.ROOK and not l_rook.has_moved:
		if board[1][rank] == null and board[2][rank] == null and board[3][rank] == null:
			if not is_square_attacked(board, Vector2i(2, rank), not piece.is_white) and not is_square_attacked(board, Vector2i(3, rank), not piece.is_white):
				moves.append(Vector2i(2, rank))
	return moves

static func find_king(board: Array, is_white: bool) -> Vector2i:
	for x in BOARD_SIZE:
		for y in BOARD_SIZE:
			var p: LightPiece = board[x][y]
			if p != null and p.type == PieceType.KING and p.is_white == is_white:
				return Vector2i(x, y)
	return Vector2i(-1, -1)

static func is_square_attacked(board: Array, pos: Vector2i, by_white: bool) -> bool:
	# Атака пешками
	var pawn_dir = -1 if by_white else 1
	for dx in [-1, 1]:
		var ppos = Vector2i(pos.x + dx, pos.y + pawn_dir)
		if in_bounds(ppos):
			var p: LightPiece = board[ppos.x][ppos.y]
			if p != null and p.is_white == by_white and p.type == PieceType.PAWN:
				return true
	# Атака конями
	for off in ChessEvaluator.KNIGHT_OFFSETS:
		var kp = pos + off
		if in_bounds(kp):
			var p: LightPiece = board[kp.x][kp.y]
			if p != null and p.is_white == by_white and p.type == PieceType.KNIGHT:
				return true
	# Атака королем
	for off in ChessEvaluator.KING_OFFSETS:
		var kp = pos + off
		if in_bounds(kp):
			var p: LightPiece = board[kp.x][kp.y]
			if p != null and p.is_white == by_white and p.type == PieceType.KING:
				return true
	# Диагональные лучи (Ферзь / Слон)
	for d in ChessEvaluator.BISHOP_DIRS:
		var cur = pos + d
		while in_bounds(cur):
			var p: LightPiece = board[cur.x][cur.y]
			if p != null:
				if p.is_white == by_white and (p.type == PieceType.BISHOP or p.type == PieceType.QUEEN):
					return true
				break
			cur += d
	# Прямые лучи (Ферзь / Ладья)
	for d in ChessEvaluator.ROOK_DIRS:
		var cur = pos + d
		while in_bounds(cur):
			var p: LightPiece = board[cur.x][cur.y]
			if p != null:
				if p.is_white == by_white and (p.type == PieceType.ROOK or p.type == PieceType.QUEEN):
					return true
				break
			cur += d
	return false

static func is_in_check(board: Array, is_white: bool) -> bool:
	var kp = find_king(board, is_white)
	if kp == Vector2i(-1, -1):
		return false
	return is_square_attacked(board, kp, not is_white)

# Делегирование методов оценки для обратной совместимости
static func evaluate_base(board: Array, is_white_perspective: bool) -> float:
	return ChessEvaluator.evaluate_base(board, is_white_perspective)

static func evaluate_for_bot(board: Array, playthrough: int = 1) -> float:
	return ChessEvaluator.evaluate_for_bot(board, playthrough)

static func see(board: Array, from_pos: Vector2i, to_pos: Vector2i) -> int:
	return ChessEvaluator.see(board, from_pos, to_pos)

static func _init_zobrist() -> void:
	ChessSearch.init_zobrist()

# ==============================================================================
# Главная точка входа ИИ: Динамический выбор хода
# ==============================================================================

static func choose_best_move(
	full_board: Array,
	playthrough: int = 1,
	consecutive_wins: int = 0,
	en_passant_target: Vector2i = Vector2i(-1, -1),
	time_limit_override: int = -1,
	depth_override: int = -1,
	cancel_check: Callable = Callable()
) -> Dictionary:
	if cancel_check.is_valid() and cancel_check.call() == true:
		return {}

	ChessSearch.init_zobrist()
	var board = make_light_board(full_board)
	
	# Собираем все легальные ходы Черных
	var all_moves: Array[Dictionary] = []
	for x in BOARD_SIZE:
		for y in BOARD_SIZE:
			var p: LightPiece = board[x][y]
			if p != null and not p.is_white:
				var from_pos = Vector2i(x, y)
				for m in get_legal_moves(board, from_pos, p, en_passant_target):
					all_moves.append({"from": from_pos, "to": m})
					
	if all_moves.is_empty():
		return {}
		
	# Дебютная книга гроссмейстерских ходов на первых 1-4 ходах партии
	var book_move = ChessOpeningBook.get_opening_book_move(board, all_moves)
	if not book_move.is_empty():
		last_search_info = {
			"depth": 1,
			"score": 0.0,
			"best_move": book_move,
			"nodes": 1,
			"time_ms": 0
		}
		return book_move
		
	# Расчет разницы в материале и позиции
	var eval_white = ChessEvaluator.evaluate_base(board, true)
	var white_material = 0
	var black_material = 0
	for x in BOARD_SIZE:
		for y in BOARD_SIZE:
			var p: LightPiece = board[x][y]
			if p != null and p.type != PieceType.KING:
				if p.is_white:
					white_material += PIECE_VALUES[p.type]
				else:
					black_material += PIECE_VALUES[p.type]
					
	var material_diff = white_material - black_material
	
	# Определение динамических параметров поиска (глубина, лимит времени)
	var max_depth: int = 3
	var time_limit_ms: int = 800
	
	if playthrough == 1:
		max_depth = 4
		time_limit_ms = 2500
		if material_diff > 150 or eval_white > 200:
			max_depth = 5
			time_limit_ms = 3500
	else:
		max_depth = 2
		time_limit_ms = 400
		if material_diff > 400 or eval_white > 450:
			max_depth = 3
			time_limit_ms = 500
			
	if depth_override > 0:
		max_depth = depth_override
	if time_limit_override > 0:
		time_limit_ms = time_limit_override

	ChessSearch.killer_moves.clear()
	ChessSearch.history_table.clear()
	
	var best_move: Dictionary = all_moves[0]
	var best_score: float = -INF
	var start_time: int = Time.get_ticks_msec()
	var soft_limit: int = int(time_limit_ms * 0.7)
	var tt: Dictionary = {}
	var completed_depth: int = 1
	var scored_root_moves: Array[Dictionary] = []
	
	# Итеративное углубление поиска
	for depth in range(1, max_depth + 1):
		if cancel_check.is_valid() and cancel_check.call() == true:
			break
		ChessSearch.node_count = 0
		var current_best = best_move
		var alpha: float = -INF
		var aborted: bool = false
		var depth_root_moves: Array[Dictionary] = []
		
		var root_h = ChessSearch.zobrist_hash(board, false)
		var root_tt_from = Vector2i(-1, -1)
		var root_tt_to = Vector2i(-1, -1)
		if tt.has(root_h):
			root_tt_from = tt[root_h].get("best_move_from", Vector2i(-1, -1))
			root_tt_to = tt[root_h].get("best_move_to", tt[root_h].get("best_move", Vector2i(-1, -1)))
		elif best_move != null and not best_move.is_empty():
			root_tt_from = best_move.get("from", Vector2i(-1, -1))
			root_tt_to = best_move.get("to", Vector2i(-1, -1))
			
		all_moves = ChessSearch.sort_moves(board, all_moves, 0, root_tt_to, root_tt_from)
		
		for m in all_moves:
			if cancel_check.is_valid() and cancel_check.call() == true:
				aborted = true
				break
			var undo = apply_move(board, m.from, m.to)
			
			var score: float = 0.0
			if playthrough == 1:
				score = -ChessSearch.negamax(board, depth - 1, true, -INF, -alpha, start_time, time_limit_ms, tt, 0, playthrough, cancel_check)
			else:
				score = -ChessSearch.negamax(board, depth - 1, true, -INF, INF, start_time, time_limit_ms, tt, 0, playthrough, cancel_check)
				
			undo_move(board, undo)
			
			depth_root_moves.append({ "move": m, "score": score })
			
			if score > alpha:
				alpha = score
				current_best = m
			
			var min_safe_depth = 2 if playthrough == 1 else 1
			if depth > min_safe_depth and time_limit_ms > 0 and Time.get_ticks_msec() - start_time >= time_limit_ms:
				aborted = true
				break
				
		if not aborted or depth == 1:
			best_score = alpha
			best_move = current_best
			completed_depth = depth
			scored_root_moves = depth_root_moves
			ChessSearch.store_tt(tt, root_h, depth, best_score, 0, best_move.from, best_move.to)
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
	
	# Во 2-м и последующих прохождениях бот плавно адаптируется к силе игрока
	if playthrough >= 2 and not in_check and scored_root_moves.size() > 1:
		scored_root_moves.sort_custom(func(a, b): return a["score"] > b["score"])
		var top_score: float = scored_root_moves[0]["score"]
		var moved_count = ChessOpeningBook.count_moved_pieces(board)
		var player_advantage = material_diff
		
		var candidate_margin: float = 25.0
		if player_advantage <= 100:
			var progress_factor: float = clamp(float(moved_count - 7) / 12.0, 0.0, 1.0)
			candidate_margin = lerp(25.0, 85.0, progress_factor)
		else:
			candidate_margin = 35.0
			
		var candidates: Array[Dictionary] = []
		for sm in scored_root_moves:
			var m = sm["move"]
			if sm["score"] < top_score - candidate_margin:
				break
			if m["from"] == black_king_pos and m["to"].y < 7 and white_material > 1000:
				continue
			var moving_piece = board[m["from"].x][m["from"].y]
			if moving_piece != null and is_square_attacked(board, m["to"], true):
				if see(board, m["from"], m["to"]) < 0:
					continue
			candidates.append(m)
			if candidates.size() >= 4:
				break
				
		if candidates.size() >= 2:
			var rng = RandomNumberGenerator.new()
			rng.randomize()
			if scored_root_moves[0]["score"] - scored_root_moves[1]["score"] > 60.0 or moved_count < 9:
				final_move = candidates[0]
			else:
				var soften_prob = clamp((candidate_margin - 25.0) / 60.0, 0.35, 0.85)
				if rng.randf() < soften_prob:
					var pick_idx = 1 if (candidates.size() == 2 or rng.randf() < 0.6) else 2
					final_move = candidates[min(pick_idx, candidates.size() - 1)]
				else:
					final_move = candidates[0]
		elif not candidates.is_empty():
			final_move = candidates[0]
			
	last_search_info = {
		"depth": completed_depth,
		"score": best_score,
		"best_move": final_move,
		"nodes": ChessSearch.node_count,
		"time_ms": Time.get_ticks_msec() - start_time
	}
	return final_move

# ==============================================================================
# Фоновый пре-расчет (Pondering)
# ==============================================================================

static func ponder_replies(
	full_board: Array,
	playthrough: int = 1,
	max_candidates: int = 64,
	en_passant_target: Vector2i = Vector2i(-1, -1),
	time_limit_ms: int = 60000,
	cancel_check: Callable = Callable(),
	cache_dict: Dictionary = {}
) -> Dictionary:
	ChessSearch.init_zobrist()
	var start_time: int = Time.get_ticks_msec()
	var board = make_light_board(full_board)
	
	if cancel_check.is_valid() and cancel_check.call() == true:
		return cache_dict
	
	var white_moves: Array[Dictionary] = []
	for x in BOARD_SIZE:
		for y in BOARD_SIZE:
			var p: LightPiece = board[x][y]
			if p != null and p.is_white:
				var from_pos = Vector2i(x, y)
				for m in get_legal_moves(board, from_pos, p, en_passant_target):
					white_moves.append({"from": from_pos, "to": m})
					
	if white_moves.is_empty():
		return cache_dict
		
	white_moves = ChessSearch.sort_moves(board, white_moves, 0)
	
	var scored_white: Array[Dictionary] = []
	var tt: Dictionary = {}
	
	for wm in white_moves:
		if cancel_check.is_valid() and cancel_check.call() == true:
			return cache_dict
		if Time.get_ticks_msec() - start_time >= time_limit_ms:
			break
		var undo = apply_move(board, wm.from, wm.to)
		var sc = -ChessSearch.negamax(board, 1, false, -INF, INF, start_time, time_limit_ms, tt, 0, playthrough, cancel_check)
		undo_move(board, undo)
		scored_white.append({"move": wm, "score": sc})
		
	if scored_white.is_empty():
		return cache_dict
		
	scored_white.sort_custom(func(a, b): return a["score"] > b["score"])
	
	var candidate_count = min(max_candidates, scored_white.size())
	
	for i in range(candidate_count):
		if cancel_check.is_valid() and cancel_check.call() == true:
			break
		if Time.get_ticks_msec() - start_time >= time_limit_ms:
			break
		var wm: Dictionary = scored_white[i]["move"]
		var key: String = "%d_%d_%d_%d" % [wm.from.x, wm.from.y, wm.to.x, wm.to.y]
		
		if cache_dict.has(key):
			continue
		
		var undo = apply_move(board, wm.from, wm.to)
		
		var new_ep: Vector2i = Vector2i(-1, -1)
		var moved_p = board[wm.to.x][wm.to.y]
		if moved_p != null and moved_p.type == PieceType.PAWN and abs(wm.to.y - wm.from.y) == 2:
			new_ep = Vector2i(wm.from.x, (wm.from.y + wm.to.y) / 2)
			
		var next_grid: Array = []
		for gx in BOARD_SIZE:
			var gcol: Array = []
			next_grid.append(gcol)
			for gy in BOARD_SIZE:
				var lp: LightPiece = board[gx][gy]
				if lp == null:
					gcol.append(null)
				else:
					gcol.append({
						"type": type_to_string(lp.type),
						"is_white": lp.is_white,
						"has_moved": lp.has_moved
					})
					
		var ponder_depth: int = 3 if playthrough == 1 else 2
		var ponder_time_limit: int = 300 if playthrough == 1 else 200
		var best_black_reply = choose_best_move(next_grid, playthrough, 0, new_ep, ponder_time_limit, ponder_depth, cancel_check)
		undo_move(board, undo)
		
		if cancel_check.is_valid() and cancel_check.call() == true:
			break
			
		if not best_black_reply.is_empty():
			cache_dict[key] = best_black_reply
			
	return cache_dict
