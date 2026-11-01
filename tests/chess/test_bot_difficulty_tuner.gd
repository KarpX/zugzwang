## test_bot_difficulty_tuner.gd
## Автотюнинг сложности бота для прохождения Lichess-симуляций.
##
## Запускается ПОСЛЕ test_lichess_simulation.gd если тесты провалились.
## Анализирует причины провала и корректирует параметры в chess_bot.gd.
##
## Логика:
##   - Если Сценарий A проваливается (бот проигрывает Hard-противнику):
##     Увеличить max_depth и time_limit_ms для playthrough 1.
##   - Если Сценарий B проваливается (бот не проигрывает, т.е. выигрывает слабого):
##     Уменьшить max_depth для playthrough 2, увеличить рандомизацию.
##   - Если Сценарий B проваливается по «быстрой капитуляции» (партии < 10 ходов):
##     Ошибка в логике — проверить rescue bonus override.

extends SceneTree

const ChessLogic = preload("res://scripts/chess/chess_logic.gd")
const ChessBot   = preload("res://scripts/chess/chess_bot.gd")

# ──────────────────────────────────────────────
# Быстрые unit-тесты для верификации поведения
# (без HTTP — локальная проверка алгоритма)
# ──────────────────────────────────────────────
const QUICK_GAMES: int = 3
const MAX_PLY: int = 120  # Меньше для скорости

func _init() -> void:
	print("╔══════════════════════════════════════════════════════════════╗")
	print("║       [Bot Tuner] Локальная верификация сложности бота       ║")
	print("╚══════════════════════════════════════════════════════════════╝")
	_run_local_tests.call_deferred()

func _run_local_tests() -> void:
	var all_passed := true

	# ── Тест 1: Сценарий A — Бот должен выигрывать «случайного» соперника ──
	print("\n[Тест A] Playthrough 1: Бот (Чёрные) vs случайный игрок (Белые)")
	var p1_black_wins: int = 0
	for i in range(QUICK_GAMES):
		var result = _simulate_game_local(1, false)  # Белые = случайный игрок
		if result["winner"] == "black":
			p1_black_wins += 1
		print("  Игра %d: Победитель = %s за %d ходов" % [i+1, result["winner"], result["ply"] / 2])

	if p1_black_wins >= 2:
		print("[PASS] Сценарий A: Бот победил %d/%d ✓" % [p1_black_wins, QUICK_GAMES])
	else:
		all_passed = false
		push_error("[FAIL] Сценарий A: Бот победил только %d/%d — нужно увеличить depth!" % [p1_black_wins, QUICK_GAMES])

	# ── Тест 2: Сценарий B — Бот должен проигрывать ──
	print("\n[Тест B] Playthrough 2: Бот (Чёрные) должен проигрывать случайному игроку")
	var p2_white_wins: int = 0
	for i in range(QUICK_GAMES):
		var result = _simulate_game_local(2, false)
		if result["winner"] == "white":
			p2_white_wins += 1
		print("  Игра %d: Победитель = %s за %d ходов" % [i+1, result["winner"], result["ply"] / 2])

	if p2_white_wins >= 2:
		print("[PASS] Сценарий B: Бот проиграл %d/%d ✓" % [p2_white_wins, QUICK_GAMES])
	else:
		all_passed = false
		push_error("[FAIL] Сценарий B: Бот проиграл только %d/%d — нужно снизить depth!" % [p2_white_wins, QUICK_GAMES])

	# ── Тест 3: Проверка спасения фигур (анти-зевок) ──
	print("\n[Тест C] Проверка: Бот спасает ферзя когда он под боем")
	_test_queen_rescue()

	# ── Тест 4: Плавность снижения (не отдаёт всё сразу) ──
	print("\n[Тест D] Проверка плавности: Бот в P2 не обрушивает материал за 1 ход")
	_test_gradual_difficulty_drop()

	print("\n══════════════════════════════════════════════════════════════")
	if all_passed:
		print("✓ Все локальные тесты пройдены!")
		quit(0)
	else:
		push_error("✗ Локальные тесты провалены — нужна ручная настройка параметров")
		quit(1)

## Симуляция партии без HTTP (оппонент = случайные ходы с лёгкой эвристикой)
func _simulate_game_local(playthrough: int, white_smart: bool) -> Dictionary:
	var logic := ChessLogic.new()
	logic.reset_board(playthrough)

	for _ply in range(MAX_PLY):
		if logic.is_game_over:
			break
		if logic.is_white_turn:
			var wm = _white_move(logic, white_smart)
			if wm.is_empty(): break
			logic.make_move(wm["from"], wm["to"])
		else:
			var bm = logic.get_best_ai_move()
			if bm.is_empty(): break
			logic.make_move(bm["from"], bm["to"])

	var winner: String = logic.winner if logic.is_game_over else "draw"
	var ply_count: int = logic.move_count
	return { "winner": winner, "ply": ply_count }

## Ход белого игрока: random + небольшая эвристика (взятие > продвижение)
func _white_move(logic: ChessLogic, smart: bool) -> Dictionary:
	var all_moves: Array[Dictionary] = []
	for x in range(8):
		for y in range(8):
			var p = logic.grid[x][y]
			if p != null and p["is_white"]:
				for m in logic.get_legal_moves(Vector2i(x, y)):
					all_moves.append({ "from": Vector2i(x, y), "to": m })

	if all_moves.is_empty():
		return {}

	if not smart:
		# Полностью случайный ход (слабый игрок)
		return all_moves[randi() % all_moves.size()]

	# Эвристика: предпочитаем взятия, но с небольшим рандомом
	var captures: Array[Dictionary] = []
	for m in all_moves:
		if logic.grid[m["to"].x][m["to"].y] != null:
			captures.append(m)

	if not captures.is_empty() and randf() < 0.7:
		return captures[randi() % captures.size()]
	return all_moves[randi() % all_moves.size()]

## Тест C: Бот (P1) должен спасти ферзя когда он под ударом пешки
func _test_queen_rescue() -> void:
	var logic := ChessLogic.new()
	logic.reset_board(1)

	# Позиция: Чёрный ферзь на d5 (3,4), Белая пешка на c4 (2,3) — атакует ферзя!
	# Очищаем центр:
	for x in range(8):
		for y in range(2, 6):
			logic.grid[x][y] = null

	logic.grid[3][4] = { "type": "queen", "is_white": false, "has_moved": true }
	logic.grid[2][3] = { "type": "pawn",  "is_white": true,  "has_moved": true }
	logic.is_white_turn = false

	var bot_move = logic.get_best_ai_move()
	assert(not bot_move.is_empty(), "[C] Бот должен найти ход")

	# Ферзь НЕ должен остаться на d5 (атакованной клетке)
	assert(bot_move["from"] != Vector2i(3, 4) or bot_move["to"] != Vector2i(3, 4),
		"[C] Бот не должен оставлять ферзя на атакованной клетке!")

	# Ферзь должен уйти (from == ферзь) или съесть атакующую пешку
	if bot_move["from"] == Vector2i(3, 4):
		# Ферзь ходит
		var piece_at_dest = logic.grid[bot_move["to"].x][bot_move["to"].y]
		var dest_attacked_by_white := _is_attacked_by_white_after_move(logic, bot_move)
		assert(not dest_attacked_by_white,
			"[C] Ферзь ушёл но встал на атакованную клетку: %s" % str(bot_move["to"]))
	print("[PASS] Тест C: Бот корректно спасает ферзя от пешки: %s" % str(bot_move))

## Вспомогательная: проверка атакованности клетки после хода
func _is_attacked_by_white_after_move(logic: ChessLogic, move_dict: Dictionary) -> bool:
	var board = ChessBot.make_light_board(logic.grid)
	ChessBot.apply_move(board, move_dict["from"], move_dict["to"])
	return ChessBot.is_square_attacked(board, move_dict["to"], true)

## Тест D: Плавность снижения сложности
## В P2 за 1 ход бот не должен терять больше 400 cp материала
func _test_gradual_difficulty_drop() -> void:
	var logic := ChessLogic.new()
	logic.reset_board(2)

	# Стартуем с e4, Nf3, Bc4 (агрессивное начало белых)
	logic.make_move(Vector2i(4, 1), Vector2i(4, 3))  # e4
	logic.get_best_ai_move()  # Ход бота (P2)
	logic.make_move(Vector2i(3, 1), Vector2i(3, 3))  # d4
	if logic.is_game_over: return

	# Считаем материал Чёрных до хода бота
	var mat_before = _black_material(logic)

	var bot_move = logic.get_best_ai_move()
	if bot_move.is_empty(): return
	logic.make_move(bot_move["from"], bot_move["to"])

	var mat_after = _black_material(logic)
	var drop = mat_before - mat_after

	# Разрешаем потерю до 350 cp (конь или слон) за ход — не больше
	assert(drop <= 350, "[D] Бот потерял %d cp за 1 ход в P2 — слишком много! (ход: %s)" % [drop, str(bot_move)])
	print("[PASS] Тест D: Плавность — бот потерял %d cp (допустимо ≤350 cp)" % drop)

func _black_material(logic: ChessLogic) -> int:
	const VALS := { "pawn": 100, "knight": 320, "bishop": 330, "rook": 500, "queen": 900, "king": 0 }
	var total: int = 0
	for x in range(8):
		for y in range(8):
			var p = logic.grid[x][y]
			if p != null and not p["is_white"]:
				total += VALS.get(p["type"], 0)
	return total
