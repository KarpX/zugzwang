class_name ChessSearch
extends RefCounted

## Алгоритмы поиска ходов, альфа-бета отсечения и эвристики для ChessBot
## Включает:
## - Хеширование Зобриста (Zobrist Hashing)
## - Transposition Table (TT)
## - Move Ordering: MVV-LVA, Killer Moves, History Heuristic, TT-Best-Move
## - Quiescence Search (форсированные взятия)
## - Итеративный Negamax с отсечением по времени и мгновенной отменой

const ChessEvaluator = preload("res://scripts/chess/bot/chess_evaluator.gd")

const PieceType = ChessEvaluator.PieceType
const PIECE_VALUES = ChessEvaluator.PIECE_VALUES
const BOARD_SIZE: int = 8
const MATE_SCORE: float = 100000.0
const MAX_Q_DEPTH: int = 3

static var node_count: int = 0
static var zobrist_table: Array = []
static var zobrist_turn: int = 0
static var killer_moves: Array = []
static var history_table: Dictionary = {}

## Инициализация случайных чисел для хеширования Зобриста
static func init_zobrist() -> void:
	if not zobrist_table.is_empty():
		return
	var rng = RandomNumberGenerator.new()
	rng.seed = 0x9E3779B9
	for p in 12:
		var piece_arr: Array = []
		for sq in 64:
			piece_arr.append(rng.randi() & 0x7FFFFFFF)
		zobrist_table.append(piece_arr)
	zobrist_turn = rng.randi() & 0x7FFFFFFF

## Быстрый расчет 64-битного хеша Зобриста текущей позиции
static func zobrist_hash(board: Array, is_white_turn: bool) -> int:
	if zobrist_table.is_empty():
		init_zobrist()
	var h: int = 0
	for x in BOARD_SIZE:
		for y in BOARD_SIZE:
			var p = board[x][y]
			if p != null:
				var sq: int = y * 8 + x
				var piece_idx: int = p.type + (0 if p.is_white else 6)
				h ^= zobrist_table[piece_idx][sq]
	if is_white_turn:
		h ^= zobrist_turn
	return h

## Поиск сохраненной оценки позиции в Transposition Table
static func lookup_tt(tt: Dictionary, h: int, depth: int, alpha: float, beta: float) -> Dictionary:
	if not tt.has(h):
		return {"alpha": alpha, "beta": beta}
	var entry = tt[h]
	var res = {
		"alpha": alpha,
		"beta": beta,
		"best_move_from": entry.get("best_move_from", Vector2i(-1, -1)),
		"best_move_to": entry.get("best_move_to", entry.get("best_move", Vector2i(-1, -1)))
	}
	if entry.depth >= depth:
		match entry.flag:
			0:
				res["score"] = entry.score # Точная оценка
			1: # Нижняя граница (Beta cutoff: score >= beta)
				if entry.score >= beta:
					res["score"] = entry.score
			2: # Верхняя граница (Alpha fail-low: score <= alpha)
				if entry.score <= alpha:
					res["score"] = entry.score
	return res

## Сохранение рассчитанной оценки в Transposition Table
static func store_tt(
	tt: Dictionary,
	h: int,
	depth: int,
	score: float,
	flag: int,
	best_move_from: Vector2i = Vector2i(-1, -1),
	best_move_to: Vector2i = Vector2i(-1, -1)
) -> void:
	if not tt.has(h) or tt[h].depth <= depth:
		tt[h] = {
			"depth": depth,
			"score": score,
			"flag": flag,
			"best_move_from": best_move_from,
			"best_move_to": best_move_to
		}

static func move_score(board: Array, m: Dictionary) -> int:
	var target = board[m.to.x][m.to.y]
	var attacker = board[m.from.x][m.from.y]
	if attacker == null:
		return 0
		
	var victim_val: int = 0
	if target != null:
		victim_val = PIECE_VALUES[target.type]
	elif attacker.type == PieceType.PAWN and abs(m.to.x - m.from.x) == 1:
		victim_val = PIECE_VALUES[PieceType.PAWN]
	else:
		return 0
		
	var attacker_val: int = PIECE_VALUES[attacker.type]
	return 1000000 + victim_val * 10 - attacker_val

static func history_key(m: Dictionary) -> int:
	return (m.from.x) | (m.from.y << 3) | (m.to.x << 6) | (m.to.y << 9)

## Сортировка ходов: TT Move > MVV-LVA взятия > Killer Moves > History Heuristic
static func sort_moves(
	board: Array,
	moves: Array[Dictionary],
	ply: int = 0,
	tt_move_to: Vector2i = Vector2i(-1, -1),
	tt_move_from: Vector2i = Vector2i(-1, -1)
) -> Array[Dictionary]:
	var scored: Array = []
	var killers: Array = []
	if ply < killer_moves.size() and killer_moves[ply] != null:
		killers = killer_moves[ply]
		
	for m in moves:
		var sc: int = 0
		if tt_move_to != Vector2i(-1, -1) and m.to == tt_move_to and (tt_move_from == Vector2i(-1, -1) or m.from == tt_move_from):
			sc = 2000000
		else:
			var target = board[m.to.x][m.to.y]
			var attacker = board[m.from.x][m.from.y]
			var is_ep: bool = (target == null and attacker != null and attacker.type == PieceType.PAWN and abs(m.to.x - m.from.x) == 1)
			
			if target != null or is_ep:
				sc = move_score(board, m)
			elif killers.has(m.to):
				sc = 800000
			else:
				if attacker != null and ChessBot.is_square_attacked(board, m.from, not attacker.is_white) and not ChessBot.is_square_attacked(board, m.to, not attacker.is_white):
					var rescue_val: int = PIECE_VALUES[attacker.type]
					sc = 600000 + rescue_val
				else:
					sc = clampi(history_table.get(history_key(m), 0), 0, 500000)
					if attacker != null and ChessBot.is_square_attacked(board, m.to, not attacker.is_white):
						if not ChessBot.is_square_attacked(board, m.to, attacker.is_white):
							sc -= 900000
		scored.append({"move": m, "score": sc})
		
	scored.sort_custom(func(a, b): return a.score > b.score)
	
	var res: Array[Dictionary] = []
	for item in scored:
		res.append(item.move)
	return res

static func record_killer(m: Dictionary, ply: int, depth: int) -> void:
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
	var key = history_key(m)
	history_table[key] = history_table.get(key, 0) + depth * depth

## Форсированный поиск Quiescence (дорасчет взятий для защиты от зевков)
static func quiescence(
	board: Array,
	is_white_turn: bool,
	alpha: float,
	beta: float,
	start_time: int,
	time_limit_ms: int,
	playthrough: int,
	q_ply: int = 0,
	cancel_check: Callable = Callable()
) -> float:
	node_count += 1
	if node_count % 128 == 0:
		if cancel_check.is_valid() and cancel_check.call() == true:
			var cancel_eval: float = ChessEvaluator.evaluate_for_bot(board, playthrough)
			return -cancel_eval if is_white_turn else cancel_eval
		if time_limit_ms > 0 and Time.get_ticks_msec() - start_time >= time_limit_ms:
			var timeout_eval: float = ChessEvaluator.evaluate_for_bot(board, playthrough)
			return -timeout_eval if is_white_turn else timeout_eval
			
	var in_check: bool = ChessBot.is_in_check(board, is_white_turn)
	var stand_pat: float = 0.0
	
	if not in_check:
		stand_pat = ChessEvaluator.evaluate_for_bot(board, playthrough)
		if is_white_turn:
			stand_pat = -stand_pat
			
		if stand_pat >= beta:
			return beta
		if alpha < stand_pat:
			alpha = stand_pat
		
	if q_ply >= MAX_Q_DEPTH:
		return alpha
		
	var captures: Array[Dictionary] = []
	for x in BOARD_SIZE:
		for y in BOARD_SIZE:
			var p = board[x][y]
			if p != null and p.is_white == is_white_turn:
				var from_pos = Vector2i(x, y)
				for m in ChessBot.get_legal_moves(board, from_pos, p, Vector2i(-1, -1), not in_check):
					if in_check and q_ply <= 1:
						captures.append({"from": from_pos, "to": m})
					elif board[m.x][m.y] != null:
						var target_p = board[m.x][m.y]
						if PIECE_VALUES[p.type] > PIECE_VALUES[target_p.type] and ChessBot.is_square_attacked(board, m, not p.is_white):
							continue
						captures.append({"from": from_pos, "to": m})
						
	if captures.is_empty():
		if in_check:
			return -(MATE_SCORE - float(q_ply))
		return alpha
		
	captures = sort_moves(board, captures, 0)
	
	for m in captures:
		if cancel_check.is_valid() and cancel_check.call() == true:
			break
		var undo = ChessBot.apply_move(board, m.from, m.to)
		var score = -quiescence(board, not is_white_turn, -beta, -alpha, start_time, time_limit_ms, playthrough, q_ply + 1, cancel_check)
		ChessBot.undo_move(board, undo)
		
		if score >= beta:
			return beta
		if score > alpha:
			alpha = score
			
	return alpha

## Итеративный Negamax поиск с альфа-бета отсечением
static func negamax(
	board: Array,
	depth: int,
	is_white_turn: bool,
	alpha: float,
	beta: float,
	start_time: int,
	time_limit_ms: int,
	tt: Dictionary,
	ply: int,
	playthrough: int,
	cancel_check: Callable = Callable()
) -> float:
	node_count += 1
	if node_count % 128 == 0:
		if cancel_check.is_valid() and cancel_check.call() == true:
			var cancel_eval: float = ChessEvaluator.evaluate_for_bot(board, playthrough)
			return -cancel_eval if is_white_turn else cancel_eval
		if time_limit_ms > 0 and Time.get_ticks_msec() - start_time >= time_limit_ms:
			var timeout_eval: float = ChessEvaluator.evaluate_for_bot(board, playthrough)
			return -timeout_eval if is_white_turn else timeout_eval
			
	var alpha_orig = alpha
	var h = zobrist_hash(board, is_white_turn)
	var lookup = lookup_tt(tt, h, depth, alpha, beta)
	if lookup.has("score"):
		return lookup["score"]
	alpha = lookup["alpha"]
	beta = lookup["beta"]
	var tt_from: Vector2i = lookup.get("best_move_from", Vector2i(-1, -1))
	var tt_to: Vector2i = lookup.get("best_move_to", Vector2i(-1, -1))
	
	var in_check: bool = ChessBot.is_in_check(board, is_white_turn)
	if in_check and ply < 10 and depth <= 1:
		depth += 1
		
	if depth <= 0:
		return quiescence(board, is_white_turn, alpha, beta, start_time, time_limit_ms, playthrough, 0, cancel_check)
		
	var moves: Array[Dictionary] = []
	for x in BOARD_SIZE:
		for y in BOARD_SIZE:
			var p = board[x][y]
			if p != null and p.is_white == is_white_turn:
				var from_pos = Vector2i(x, y)
				for m in ChessBot.get_legal_moves(board, from_pos, p):
					moves.append({"from": from_pos, "to": m})
					
	if moves.is_empty():
		if ChessBot.is_in_check(board, is_white_turn):
			return -(MATE_SCORE - float(ply))
		return 0.0
		
	moves = sort_moves(board, moves, ply, tt_to, tt_from)
	
	var best = -INF
	var best_move_from = Vector2i(-1, -1)
	var best_move_to = Vector2i(-1, -1)
	for m in moves:
		if cancel_check.is_valid() and cancel_check.call() == true:
			break
		var undo = ChessBot.apply_move(board, m.from, m.to)
		var was_quiet = (undo["captured"] == null)
		var score = -negamax(board, depth - 1, not is_white_turn, -beta, -alpha, start_time, time_limit_ms, tt, ply + 1, playthrough, cancel_check)
		ChessBot.undo_move(board, undo)
		
		if score > best:
			best = score
			best_move_from = m.from
			best_move_to = m.to
		alpha = max(alpha, score)
		if alpha >= beta:
			if was_quiet:
				record_killer(m, ply, depth)
			best_move_from = m.from
			best_move_to = m.to
			break
			
	var flag = 0
	if best <= alpha_orig: flag = 2
	elif best >= beta: flag = 1
	else: flag = 0
	store_tt(tt, h, depth, best, flag, best_move_from, best_move_to)
	
	return best
