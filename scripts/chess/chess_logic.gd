class_name ChessLogic
extends RefCounted

## Шахматная логика и правила игры 8x8 для проекта «Белый Король»
## Управляет логическим состоянием партии, валидацией ходов и жадным ИИ войны (Черные).

const BOARD_SIZE: int = 8

# Оценка ценности фигур для жадного ИИ
const PIECE_VALUES: Dictionary = {
	"pawn": 100,
	"knight": 320,
	"bishop": 330,
	"rook": 500,
	"queen": 900,
	"king": 20000
}

# 8x8 матрица: board[x][y] (x: file 0..7, y: rank 0..7)
# null или Dictionary: { "type": String, "is_white": bool, "has_moved": bool }
var grid: Array[Array] = []

var is_white_turn: bool = true
var move_count: int = 0
var is_game_over: bool = false
var winner: String = "" # "white", "black", "draw"

func _init() -> void:
	reset_board()

## Полный сброс доски в начальную расстановку
func reset_board() -> void:
	grid.clear()
	for x in range(BOARD_SIZE):
		var column: Array = []
		for y in range(BOARD_SIZE):
			column.append(null)
		grid.append(column)
	
	is_white_turn = true
	move_count = 0
	is_game_over = false
	winner = ""
	
	_setup_initial_pieces()

func _setup_initial_pieces() -> void:
	# Белые: Y = 0 (фигуры), Y = 1 (пешки)
	# Черные: Y = 7 (фигуры), Y = 6 (пешки)
	var back_rank: Array[String] = [
		"rook", "knight", "bishop", "queen", "king", "bishop", "knight", "rook"
	]
	
	for x in range(BOARD_SIZE):
		# Белые фигуры
		grid[x][0] = _create_piece(back_rank[x], true)
		grid[x][1] = _create_piece("pawn", true)
		
		# Черные фигуры
		grid[x][6] = _create_piece("pawn", false)
		grid[x][7] = _create_piece(back_rank[x], false)

func _create_piece(piece_type: String, is_white: bool) -> Dictionary:
	return {
		"type": piece_type,
		"is_white": is_white,
		"has_moved": false
	}

func get_piece(pos: Vector2i) -> Variant:
	if not is_inside(pos):
		return null
	return grid[pos.x][pos.y]

func is_inside(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < BOARD_SIZE and pos.y >= 0 and pos.y < BOARD_SIZE

## Проверка, свободна ли клетка
func is_empty(pos: Vector2i) -> bool:
	return is_inside(pos) and grid[pos.x][pos.y] == null

## Проверка, занята ли клетка вражеской фигурой
func is_enemy(pos: Vector2i, is_white_source: bool) -> bool:
	var piece = get_piece(pos)
	return piece != null and piece["is_white"] != is_white_source

## Проверка, занята ли клетка своей фигурой
func is_friendly(pos: Vector2i, is_white_source: bool) -> bool:
	var piece = get_piece(pos)
	return piece != null and piece["is_white"] == is_white_source

## Генерация всех легальных ходов для фигуры в клетке from_pos
func get_legal_moves(from_pos: Vector2i) -> Array[Vector2i]:
	var piece = get_piece(from_pos)
	if piece == null:
		return []
	
	var is_white: bool = piece["is_white"]
	var piece_type: String = piece["type"]
	var candidate_moves: Array[Vector2i] = []
	
	match piece_type:
		"pawn":
			candidate_moves = _get_pawn_moves(from_pos, is_white, piece["has_moved"])
		"knight":
			candidate_moves = _get_knight_moves(from_pos, is_white)
		"bishop":
			candidate_moves = _get_sliding_moves(from_pos, is_white, [
				Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)
			])
		"rook":
			candidate_moves = _get_sliding_moves(from_pos, is_white, [
				Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
			])
		"queen":
			candidate_moves = _get_sliding_moves(from_pos, is_white, [
				Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
				Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
			])
		"king":
			candidate_moves = _get_king_moves(from_pos, is_white)
			
	# Фильтрация ходов, оставляющих своего короля под шахом
	var valid_moves: Array[Vector2i] = []
	for target in candidate_moves:
		if not _does_move_leave_king_in_check(from_pos, target, is_white):
			valid_moves.append(target)
			
	return valid_moves

## Правила хода пешки
func _get_pawn_moves(pos: Vector2i, is_white: bool, has_moved: bool) -> Array[Vector2i]:
	var moves: Array[Vector2i] = []
	var forward_dir: int = 1 if is_white else -1
	
	# Шаг вперед на 1 клетку
	var one_step: Vector2i = Vector2i(pos.x, pos.y + forward_dir)
	if is_empty(one_step):
		moves.append(one_step)
		# Шаг вперед на 2 клетки с начальной позиции
		var two_step: Vector2i = Vector2i(pos.x, pos.y + forward_dir * 2)
		if not has_moved and is_empty(two_step):
			moves.append(two_step)
	
	# Взятие по диагонали влево и вправо
	var diag_left: Vector2i = Vector2i(pos.x - 1, pos.y + forward_dir)
	if is_enemy(diag_left, is_white):
		moves.append(diag_left)
		
	var diag_right: Vector2i = Vector2i(pos.x + 1, pos.y + forward_dir)
	if is_enemy(diag_right, is_white):
		moves.append(diag_right)
		
	return moves

## Правила хода коня (буква "Г")
func _get_knight_moves(pos: Vector2i, is_white: bool) -> Array[Vector2i]:
	var moves: Array[Vector2i] = []
	var offsets: Array[Vector2i] = [
		Vector2i(1, 2), Vector2i(2, 1), Vector2i(-1, 2), Vector2i(-2, 1),
		Vector2i(1, -2), Vector2i(2, -1), Vector2i(-1, -2), Vector2i(-2, -1)
	]
	for offset in offsets:
		var target: Vector2i = pos + offset
		if is_inside(target) and not is_friendly(target, is_white):
			moves.append(target)
	return moves

## Скользящие фигуры (Слон, Ладья, Ферзь)
func _get_sliding_moves(pos: Vector2i, is_white: bool, directions: Array[Vector2i]) -> Array[Vector2i]:
	var moves: Array[Vector2i] = []
	for dir in directions:
		var current: Vector2i = pos + dir
		while is_inside(current):
			if is_empty(current):
				moves.append(current)
			elif is_enemy(current, is_white):
				moves.append(current) # Взятие врага, дальше ход блокируется
				break
			else:
				break # Своя фигура, ход блокируется
			current += dir
	return moves

## Правила хода короля (1 клетка в любом направлении)
func _get_king_moves(pos: Vector2i, is_white: bool) -> Array[Vector2i]:
	var moves: Array[Vector2i] = []
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var target: Vector2i = Vector2i(pos.x + dx, pos.y + dy)
			if is_inside(target) and not is_friendly(target, is_white):
				moves.append(target)
	return moves

## Поиск положения короля
func find_king(is_white: bool) -> Vector2i:
	for x in range(BOARD_SIZE):
		for y in range(BOARD_SIZE):
			var piece = grid[x][y]
			if piece != null and piece["is_white"] == is_white and piece["type"] == "king":
				return Vector2i(x, y)
	return Vector2i(-1, -1)

## Проверка, атакована ли клетка фигурами противника
func is_square_attacked(pos: Vector2i, attacked_by_white: bool) -> bool:
	for x in range(BOARD_SIZE):
		for y in range(BOARD_SIZE):
			var piece = grid[x][y]
			if piece != null and piece["is_white"] == attacked_by_white:
				if _can_piece_attack(Vector2i(x, y), pos):
					return true
	return false

func _can_piece_attack(from_pos: Vector2i, target_pos: Vector2i) -> bool:
	var piece = grid[from_pos.x][from_pos.y]
	if piece == null:
		return false
	
	var is_white: bool = piece["is_white"]
	var piece_type: String = piece["type"]
	
	if piece_type == "pawn":
		var forward_dir: int = 1 if is_white else -1
		return (target_pos.y == from_pos.y + forward_dir) and (abs(target_pos.x - from_pos.x) == 1)
	elif piece_type == "knight":
		var delta: Vector2i = target_pos - from_pos
		return (abs(delta.x) == 1 and abs(delta.y) == 2) or (abs(delta.x) == 2 and abs(delta.y) == 1)
	elif piece_type == "king":
		var delta: Vector2i = target_pos - from_pos
		return abs(delta.x) <= 1 and abs(delta.y) <= 1
	else:
		# Слон, Ладья, Ферзь
		var dir_x: int = target_pos.x - from_pos.x
		var dir_y: int = target_pos.y - from_pos.y
		var is_diag: bool = abs(dir_x) == abs(dir_y)
		var is_ortho: bool = (dir_x == 0 or dir_y == 0)
		
		if piece_type == "bishop" and not is_diag:
			return false
		if piece_type == "rook" and not is_ortho:
			return false
		if piece_type == "queen" and not (is_diag or is_ortho):
			return false
			
		var step: Vector2i = Vector2i(sign(dir_x), sign(dir_y))
		var curr: Vector2i = from_pos + step
		while curr != target_pos:
			if not is_empty(curr):
				return false
			curr += step
		return true

## Проверка, оставляет ли ход короля под шахом
func _does_move_leave_king_in_check(from_pos: Vector2i, to_pos: Vector2i, is_white: bool) -> bool:
	var source_piece = grid[from_pos.x][from_pos.y]
	var target_piece = grid[to_pos.x][to_pos.y]
	
	# Симулируем ход
	grid[to_pos.x][to_pos.y] = source_piece
	grid[from_pos.x][from_pos.y] = null
	
	var king_pos: Vector2i = to_pos if source_piece["type"] == "king" else find_king(is_white)
	var in_check: bool = false
	if king_pos != Vector2i(-1, -1):
		in_check = is_square_attacked(king_pos, not is_white)
		
	# Откатываем симуляцию
	grid[from_pos.x][from_pos.y] = source_piece
	grid[to_pos.x][to_pos.y] = target_piece
	
	return in_check

## Выполнение хода на доске
## Возвращает словарь с результатом:
## {
##   "success": bool,
##   "captured": bool,
##   "captured_piece": String,
##   "captured_is_white": bool,
##   "is_checkmate": bool,
##   "promoted": bool
## }
func make_move(from_pos: Vector2i, to_pos: Vector2i) -> Dictionary:
	var result: Dictionary = {
		"success": false,
		"captured": false,
		"captured_piece": "",
		"captured_is_white": false,
		"is_checkmate": false,
		"promoted": false
	}
	
	var legal_moves = get_legal_moves(from_pos)
	if not (to_pos in legal_moves):
		return result
		
	var piece = grid[from_pos.x][from_pos.y]
	var target = grid[to_pos.x][to_pos.y]
	
	# Проверка взятия
	if target != null:
		result["captured"] = true
		result["captured_piece"] = target["type"]
		result["captured_is_white"] = target["is_white"]
		
	# Перемещение фигуры
	grid[to_pos.x][to_pos.y] = piece
	grid[from_pos.x][from_pos.y] = null
	piece["has_moved"] = true
	
	# Превращение пешки в ферзя на последней горизонтали
	if piece["type"] == "pawn":
		if (piece["is_white"] and to_pos.y == 7) or (not piece["is_white"] and to_pos.y == 0):
			piece["type"] = "queen"
			result["promoted"] = true
			
	move_count += 1
	is_white_turn = not is_white_turn
	result["success"] = true
	
	# Проверка мата следующему игроку
	var next_has_moves: bool = has_any_legal_moves(is_white_turn)
	if not next_has_moves:
		var king_pos = find_king(is_white_turn)
		if king_pos != Vector2i(-1, -1) and is_square_attacked(king_pos, not is_white_turn):
			is_game_over = true
			winner = "white" if not is_white_turn else "black"
			result["is_checkmate"] = true
		else:
			is_game_over = true
			winner = "draw"
			
	return result

## Проверка, есть ли хотя бы один легальный ход у стороны
func has_any_legal_moves(is_white: bool) -> bool:
	for x in range(BOARD_SIZE):
		for y in range(BOARD_SIZE):
			var piece = grid[x][y]
			if piece != null and piece["is_white"] == is_white:
				var moves = get_legal_moves(Vector2i(x, y))
				if moves.size() > 0:
					return true
	return false

## Жадный ИИ войны (Черные фигуры):
## Приоритеты:
## 1. Взятие наиболее ценной белой фигуры (+ценность * 10)
## 2. Нападение на короля / шах
## 3. Продвижение вперед к позиции белых
## 4. Случайный легальный ход
func get_best_ai_move() -> Dictionary:
	var best_score: float = -999999.0
	var best_moves: Array[Dictionary] = []
	
	for x in range(BOARD_SIZE):
		for y in range(BOARD_SIZE):
			var piece = grid[x][y]
			if piece != null and not piece["is_white"]:
				var from_pos: Vector2i = Vector2i(x, y)
				var moves = get_legal_moves(from_pos)
				
				for to_pos in moves:
					var score: float = _evaluate_move(from_pos, to_pos)
					if score > best_score:
						best_score = score
						best_moves = [{ "from": from_pos, "to": to_pos }]
					elif abs(score - best_score) < 0.01:
						best_moves.append({ "from": from_pos, "to": to_pos })
						
	if best_moves.is_empty():
		return {}
		
	# Выбираем случайный ход из лучших
	return best_moves[randi() % best_moves.size()]

func _evaluate_move(from_pos: Vector2i, to_pos: Vector2i) -> float:
	var score: float = 0.0
	var piece = grid[from_pos.x][from_pos.y]
	var target = grid[to_pos.x][to_pos.y]
	
	# 1. Жадное взятие: высший приоритет
	if target != null:
		var target_val: int = PIECE_VALUES.get(target["type"], 100)
		score += target_val * 10.0
		# Если бьем менее ценной фигурой более ценную — бонус
		var piece_val: int = PIECE_VALUES.get(piece["type"], 100)
		score += float(target_val - piece_val)
		
	# 2. Продвижение черных вперед (к игроку: Y уменьшается от 7 до 0)
	score += (7.0 - to_pos.y) * 2.0
	
	# 3. Контроль центра (клетки 3,4 по X и Y)
	var center_dist: float = abs(to_pos.x - 3.5) + abs(to_pos.y - 3.5)
	score += (7.0 - center_dist)
	
	# 4. Небольшой шум (0..1.5) для непредсказуемости
	score += randf() * 1.5
	
	return score
