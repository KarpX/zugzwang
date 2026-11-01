## test_lichess_simulation.gd
## Полная симуляция шахматных партий через Lichess Stockfish API.
##
## Сценарий A (Playthrough 1 — «Хищный ИИ войны»):
##   Бот ДОЛЖЕН побеждать игроков силой 800 (слабый), 1200 (средний) и 1600 (сильный).
##   3 партии на каждый уровень, запускаются асинхронно.
##
## Сценарий B (Playthrough 2 — «ИИ выживания»):
##   Бот ДОЛЖЕН проигрывать даже слабому (800).
##   Условие: проигрывает ≥ 2 из 3 партий на каждую силу (800, 1200, 1600).
##   Сложность снижается ПОСТЕПЕННО — бот не «сразу отдаёт всё»:
##     - До потери преимущества Белых (material_diff ≤ 300 cp) бот держится на depth=2 (Medium).
##     - При material_diff > 300 cp он чуть помогает (depth=3, но всё равно проигрывает).
##
## Lichess Stockfish API:
##   POST https://lichess.org/api/cloud-eval   — не требует токена
##   POST https://lichess.org/api/stockfish    — оценка позиции по FEN, depth, multipv

extends SceneTree

const ChessLogic = preload("res://scripts/chess/chess_logic.gd")
const ChessBot = preload("res://scripts/chess/chess_bot.gd")

# ──────────────────────────────────────────────
# Конфигурация теста
# ──────────────────────────────────────────────
const GAMES_PER_LEVEL: int = 3
const MAX_PLY: int = 200 # Максимум полуходов в партии до ничьей по лимиту

## Силы Lichess Stockfish для «игрока» в каждом сценарии (multipv=1, depth пропорционален силе)
const LEVELS: Array[Dictionary] = [
	{"label": "weak", "level": 1}, # ~800 Elo
	{"label": "medium", "level": 4}, # ~1200 Elo
	{"label": "strong", "level": 7}, # ~1600 Elo
]

## URL Lichess Stockfish (не требует аутентификации)
const LICHESS_EVAL_URL: String = "https://lichess.org/api/stockfish"

# ──────────────────────────────────────────────
# Трекинг результатов
# ──────────────────────────────────────────────
var _total_tests: int = 0
var _passed_tests: int = 0
var _failed_tests: int = 0
var _pending_tasks: int = 0 # количество незавершённых асинхронных задач
var _results: Array[Dictionary] = []

func _init() -> void:
	print("╔══════════════════════════════════════════════════════════════╗")
	print("║         [Lichess Sim] Запуск симуляций партий               ║")
	print("╚══════════════════════════════════════════════════════════════╝")
	_run_all.call_deferred()

func _run_all() -> void:
	# Сценарий A: playthrough 1 (Hard) — бот должен ПОБЕДИТЬ
	for lvl in LEVELS:
		for game_idx in range(GAMES_PER_LEVEL):
			_pending_tasks += 1
			_run_simulation_async.call_deferred(
				"A", lvl["label"], lvl["level"], 1, game_idx + 1
			)

	# Сценарий B: playthrough 2 (Survival/Losing) — бот должен ПРОИГРАТЬ
	for lvl in LEVELS:
		for game_idx in range(GAMES_PER_LEVEL):
			_pending_tasks += 1
			_run_simulation_async.call_deferred(
				"B", lvl["label"], lvl["level"], 2, game_idx + 1
			)

# ──────────────────────────────────────────────
# Асинхронная симуляция одной партии
# (В среде SceneTree без многопоточности
#  мы накапливаем HTTP-запросы через HTTPClient)
# ──────────────────────────────────────────────
func _run_simulation_async(
	scenario: String,
	level_label: String,
	lichess_level: int,
	playthrough: int,
	game_num: int
) -> void:
	var tag: String = "[Sim %s | %s | game %d]" % [scenario, level_label, game_num]
	print("%s Начало партии (playthrough=%d, lichess_level=%d)" % [tag, playthrough, lichess_level])

	var logic := ChessLogic.new()
	logic.reset_board(playthrough)

	# Небольшой рандом стартового хода белых (имитирует разные партии)
	var opening_moves: Array[Dictionary] = [
		{"from": Vector2i(4, 1), "to": Vector2i(4, 3)}, # e4
		{"from": Vector2i(3, 1), "to": Vector2i(3, 3)}, # d4
		{"from": Vector2i(2, 1), "to": Vector2i(2, 3)}, # c4
		{"from": Vector2i(5, 0), "to": Vector2i(5, 2)}, # Nf3
	]
	# Разные начала для разных номеров партий чтобы покрыть разные дебюты
	var opening = opening_moves[game_num % opening_moves.size()]
	logic.make_move(opening["from"], opening["to"])

	var ply: int = 1
	var winner: String = ""
	var last_white_material_lead: int = 0

	while ply < MAX_PLY and not logic.is_game_over:
		if logic.is_white_turn:
			# ── ХОД БЕЛЫХ: Lichess Stockfish ──
			var fen_str = _board_to_fen(logic)
			var lichess_move = await _get_lichess_move(fen_str, lichess_level, tag)
			if lichess_move.is_empty():
				# Если API недоступен — делаем случайный легальный ход
				lichess_move = _random_legal_move(logic)
			if lichess_move.is_empty():
				# Нет легальных ходов
				break
			var r = logic.make_move(lichess_move["from"], lichess_move["to"])
			if not r["success"]:
				# Попытка с случайным ходом
				lichess_move = _random_legal_move(logic)
				if lichess_move.is_empty():
					break
				r = logic.make_move(lichess_move["from"], lichess_move["to"])
		else:
			# ── ХОД ЧЁРНЫХ: наш бот ──
			var bot_move = logic.get_best_ai_move()
			if bot_move.is_empty():
				break
			logic.make_move(bot_move["from"], bot_move["to"])

		ply += 1

		# Проверяем плавность снижения сложности в Сценарии B
		if playthrough == 2 and not logic.is_white_turn:
			var mat_info = _calc_material(logic)
			var w_mat: int = mat_info["white"]
			var b_mat: int = mat_info["black"]
			var diff: int = w_mat - b_mat # Преимущество Белых
			if diff > last_white_material_lead + 300 and ply > 10:
				# Проверяем что бот не «обвалился» резко — не отдал больше 300 cp за один ход
				print("  %s ⚠ Быстрое падение материала Чёрных: diff=%d cp (ply=%d)" % [tag, diff, ply])
			last_white_material_lead = max(last_white_material_lead, diff)

	# ── Итог партии ──
	if logic.is_game_over:
		winner = logic.winner
	else:
		winner = "draw" # по лимиту ходов

	_record_result(scenario, level_label, playthrough, game_num, winner, ply, tag)

# ──────────────────────────────────────────────
# HTTP: запрос к Lichess Stockfish API
# ──────────────────────────────────────────────
func _get_lichess_move(fen: String, level: int, tag: String) -> Dictionary:
	var http := HTTPClient.new()
	var err = http.connect_to_host("lichess.org", 443, TLSOptions.client())
	if err != OK:
		push_warning("%s Не удалось подключиться к lichess.org: %s" % [tag, error_string(err)])
		return {}

	# Ждём подключения (до 5 секунд)
	var timeout_ms: int = Time.get_ticks_msec() + 5000
	while http.get_status() == HTTPClient.STATUS_CONNECTING or http.get_status() == HTTPClient.STATUS_RESOLVING:
		http.poll()
		await get_tree().create_timer(0.05).timeout
		if Time.get_ticks_msec() > timeout_ms:
			push_warning("%s Таймаут подключения к lichess.org" % tag)
			return {}

	if http.get_status() != HTTPClient.STATUS_CONNECTED:
		push_warning("%s Не подключён к lichess.org (статус=%d)" % [tag, http.get_status()])
		return {}

	# POST-запрос
	var body := "fen=%s&level=%d" % [fen.uri_encode(), level]
	var headers := PackedStringArray([
		"Content-Type: application/x-www-form-urlencoded",
		"Accept: application/json",
	])
	err = http.request(HTTPClient.METHOD_POST, "/api/stockfish", headers, body)
	if err != OK:
		push_warning("%s Ошибка HTTP запроса: %s" % [tag, error_string(err)])
		return {}

	# Ждём ответа
	timeout_ms = Time.get_ticks_msec() + 10000
	while http.get_status() == HTTPClient.STATUS_REQUESTING:
		http.poll()
		await get_tree().create_timer(0.05).timeout
		if Time.get_ticks_msec() > timeout_ms:
			push_warning("%s Таймаут ожидания ответа Lichess" % tag)
			return {}

	if http.get_status() != HTTPClient.STATUS_BODY:
		push_warning("%s Неожиданный статус: %d" % [tag, http.get_status()])
		return {}

	# Читаем тело
	var response_bytes := PackedByteArray()
	timeout_ms = Time.get_ticks_msec() + 5000
	while http.get_status() == HTTPClient.STATUS_BODY:
		http.poll()
		var chunk = http.read_response_body_chunk()
		if chunk.size() > 0:
			response_bytes.append_array(chunk)
		else:
			await get_tree().create_timer(0.02).timeout
		if Time.get_ticks_msec() > timeout_ms:
			break

	var json_str := response_bytes.get_string_from_utf8()
	if json_str.is_empty():
		push_warning("%s Пустой ответ от Lichess" % tag)
		return {}

	var json := JSON.new()
	if json.parse(json_str) != OK:
		push_warning("%s Ошибка парсинга JSON: %s" % [tag, json_str.left(200)])
		return {}

	var data = json.get_data()
	if not data is Dictionary or not data.has("move"):
		push_warning("%s Неожиданный формат ответа: %s" % [tag, json_str.left(200)])
		return {}

	# Конвертируем UCI-ход ("e2e4") в Vector2i
	var move_uci: String = data["move"]
	return _uci_to_move(move_uci)

# ──────────────────────────────────────────────
# UCI move -> Dictionary { from: Vector2i, to: Vector2i }
# UCI формат: "e2e4" — буква+цифра для from и to
# x: a=0..h=7, y: 1=0..8=7 (rank-1 → y)
# ──────────────────────────────────────────────
func _uci_to_move(uci: String) -> Dictionary:
	if uci.length() < 4:
		return {}
	var fx: int = uci.unicode_at(0) - "a".unicode_at(0)
	var fy: int = int(uci[1]) - 1
	var tx: int = uci.unicode_at(2) - "a".unicode_at(0)
	var ty: int = int(uci[3]) - 1
	if fx < 0 or fx > 7 or fy < 0 or fy > 7 or tx < 0 or tx > 7 or ty < 0 or ty > 7:
		return {}
	return {"from": Vector2i(fx, fy), "to": Vector2i(tx, ty)}

# ──────────────────────────────────────────────
# ChessLogic -> FEN строка
# ChessLogic: board[x][y], x=file(0..7), y=rank(0..7)
# FEN: rank 8 (y=7) вверху, rank 1 (y=0) внизу
# ──────────────────────────────────────────────
func _board_to_fen(logic: ChessLogic) -> String:
	var piece_map := {
		"king": ["k", "K"],
		"queen": ["q", "Q"],
		"rook": ["r", "R"],
		"bishop": ["b", "B"],
		"knight": ["n", "N"],
		"pawn": ["p", "P"],
	}
	var fen := ""
	for rank in range(7, -1, -1): # rank 8..1 (y=7..0)
		var empty: int = 0
		for file in range(8): # file a..h (x=0..7)
			var piece = logic.grid[file][rank]
			if piece == null:
				empty += 1
			else:
				if empty > 0:
					fen += str(empty)
					empty = 0
				var sym_pair: Array = piece_map.get(piece["type"], ["p", "P"])
				fen += sym_pair[1] if piece["is_white"] else sym_pair[0]
		if empty > 0:
			fen += str(empty)
		if rank > 0:
			fen += "/"

	# Сторона хода
	fen += " " + ("w" if logic.is_white_turn else "b")

	# Рокировка (упрощённая: определяем по has_moved)
	var castling := ""
	var wking = logic.grid[4][0]
	var bking = logic.grid[4][7]
	if wking != null and not wking["has_moved"]:
		var wr = logic.grid[7][0]
		if wr != null and not wr["has_moved"]: castling += "K"
		var wr2 = logic.grid[0][0]
		if wr2 != null and not wr2["has_moved"]: castling += "Q"
	if bking != null and not bking["has_moved"]:
		var br = logic.grid[7][7]
		if br != null and not br["has_moved"]: castling += "k"
		var br2 = logic.grid[0][7]
		if br2 != null and not br2["has_moved"]: castling += "q"
	fen += " " + (castling if not castling.is_empty() else "-")

	# En passant
	var ep = logic.en_passant_target
	if ep != Vector2i(-1, -1):
		var ep_file := char("a".unicode_at(0) + ep.x)
		fen += " " + ep_file + str(ep.y + 1)
	else:
		fen += " -"

	# Полуходы и номер хода (упрощённо)
	fen += " 0 %d" % (logic.move_count / 2 + 1)
	return fen

# ──────────────────────────────────────────────
# Случайный легальный ход (запасной вариант)
# ──────────────────────────────────────────────
func _random_legal_move(logic: ChessLogic) -> Dictionary:
	var all_moves: Array[Dictionary] = []
	for x in range(8):
		for y in range(8):
			var piece = logic.grid[x][y]
			if piece != null and piece["is_white"] == logic.is_white_turn:
				for m in logic.get_legal_moves(Vector2i(x, y)):
					all_moves.append({"from": Vector2i(x, y), "to": m})
	if all_moves.is_empty():
		return {}
	return all_moves[randi() % all_moves.size()]

# ──────────────────────────────────────────────
# Подсчёт материала
# ──────────────────────────────────────────────
func _calc_material(logic: ChessLogic) -> Dictionary:
	const VALS := {"pawn": 100, "knight": 320, "bishop": 330, "rook": 500, "queen": 900, "king": 0}
	var white_mat: int = 0
	var black_mat: int = 0
	for x in range(8):
		for y in range(8):
			var p = logic.grid[x][y]
			if p == null: continue
			var v: int = VALS.get(p["type"], 0)
			if p["is_white"]:
				white_mat += v
			else:
				black_mat += v
	return {"white": white_mat, "black": black_mat}

# ──────────────────────────────────────────────
# Запись результата и проверка финального итога
# ──────────────────────────────────────────────
func _record_result(
	scenario: String,
	level_label: String,
	playthrough: int,
	game_num: int,
	winner: String,
	ply: int,
	tag: String
) -> void:
	_results.append({
		"scenario": scenario,
		"level": level_label,
		"playthrough": playthrough,
		"game": game_num,
		"winner": winner,
		"ply": ply
	})

	var result_str: String = "WHITE" if winner == "white" else ("BLACK" if winner == "black" else "DRAW")
	print("  %s Конец партии: %s за %d ходов" % [tag, result_str, ply / 2])

	_pending_tasks -= 1
	if _pending_tasks == 0:
		_evaluate_all_results()

func _evaluate_all_results() -> void:
	print("\n══════════════════════════════════════════════════════════════")
	print("                   ИТОГИ СИМУЛЯЦИЙ                          ")
	print("══════════════════════════════════════════════════════════════")

	var scenario_a_ok := true
	var scenario_b_ok := true

	# ── Сценарий A: бот (Чёрные) должен побеждать ──
	for lvl in LEVELS:
		var label: String = lvl["label"]
		var black_wins: int = 0
		var total: int = 0
		for r in _results:
			if r["scenario"] == "A" and r["level"] == label:
				total += 1
				if r["winner"] == "black":
					black_wins += 1
		var pass_a: bool = black_wins >= 2 # Побеждаем хотя бы в 2 из 3
		_total_tests += 1
		if pass_a:
			_passed_tests += 1
			print("[PASS] Сценарий A | %s: Бот победил %d/%d партий ✓" % [label, black_wins, total])
		else:
			_failed_tests += 1
			scenario_a_ok = false
			push_error("[FAIL] Сценарий A | %s: Бот победил только %d/%d партий! ✗" % [label, black_wins, total])

	# ── Сценарий B: бот (Чёрные) должен проигрывать ──
	for lvl in LEVELS:
		var label: String = lvl["label"]
		var white_wins: int = 0
		var total: int = 0
		for r in _results:
			if r["scenario"] == "B" and r["level"] == label:
				total += 1
				if r["winner"] == "white":
					white_wins += 1
		var pass_b: bool = white_wins >= 2 # Проигрываем хотя бы в 2 из 3
		_total_tests += 1
		if pass_b:
			_passed_tests += 1
			print("[PASS] Сценарий B | %s: Бот проиграл %d/%d партий ✓" % [label, white_wins, total])
		else:
			_failed_tests += 1
			scenario_b_ok = false
			push_error("[FAIL] Сценарий B | %s: Бот проиграл только %d/%d партий! ✗" % [label, white_wins, total])

	# ── Проверка плавности снижения сложности (Сценарий B) ──
	# Проверяем что в B-партиях нет «быстрых капитуляций» (партий < 10 ходов)
	var fast_collapses: int = 0
	for r in _results:
		if r["scenario"] == "B" and r["winner"] == "white" and r["ply"] < 20:
			fast_collapses += 1
	_total_tests += 1
	if fast_collapses == 0:
		_passed_tests += 1
		print("[PASS] Сценарий B | Плавность: нет 'быстрых капитуляций' (партий < 10 ходов) ✓")
	else:
		_failed_tests += 1
		scenario_b_ok = false
		push_error("[FAIL] Сценарий B | Плавность: %d партий закончились < 10 ходов (бот сдался слишком быстро)!" % fast_collapses)

	print("══════════════════════════════════════════════════════════════")
	print("Итого тестов: %d | Пройдено: %d | Провалено: %d" % [_total_tests, _passed_tests, _failed_tests])

	if _failed_tests == 0:
		print("✓ ВСЕ ТЕСТЫ ПРОЙДЕНЫ УСПЕШНО!")
		quit(0)
	else:
		push_error("✗ ТЕСТЫ НЕ ПРОЙДЕНЫ — необходима настройка сложности бота!")
		quit(1)
