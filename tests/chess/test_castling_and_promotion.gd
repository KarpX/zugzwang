extends SceneTree

const ChessLogic = preload("res://scripts/chess/chess_logic.gd")
const ChessBoardView = preload("res://scripts/chess/chess_board_view.gd")
const ChessPiece3D = preload("res://scripts/chess/chess_piece_3d.gd")

func _init() -> void:
	print("--- [Castling & Promotion Test Suite] Запуск тестов ---")
	_run_tests.call_deferred()

func _run_tests() -> void:
	_test_kingside_castling()
	_test_queenside_castling()
	_test_castling_restrictions()
	_test_pawn_promotion_logic()
	await _test_pawn_promotion_3d_mesh()
	await _test_promotion_dialog()
	_test_pawn_lifting_on_promotion()
	_test_deselect_sound_on_switch()
	await _test_ai_responds_after_promotion()
	await _test_player_blocked_while_effect_active()
	
	print("--- [Castling & Promotion Test Suite] ВСЕ ТЕСТЫ УСПЕШНО ПРОЙДЕНЫ ---")
	quit(0)

## Тест 1: Короткая рокировка (Kingside O-O)
func _test_kingside_castling() -> void:
	var logic = ChessLogic.new()
	# Очищаем f1 (5, 0) и g1 (6, 0) для белых
	logic.grid[5][0] = null # слон
	logic.grid[6][0] = null # конь
	
	var moves = logic.get_legal_moves(Vector2i(4, 0))
	assert(Vector2i(6, 0) in moves, "Король должен иметь возможность короткой рокировки на (6, 0)")
	
	var res = logic.make_move(Vector2i(4, 0), Vector2i(6, 0))
	assert(res["success"] == true, "Ход рокировки успешен")
	assert(res["castled"] == true, "Флаг castled должен быть true")
	assert(res["rook_from"] == Vector2i(7, 0) and res["rook_to"] == Vector2i(5, 0), "Ладья должна переместиться из (7, 0) в (5, 0)")
	
	var king = logic.get_piece(Vector2i(6, 0))
	var rook = logic.get_piece(Vector2i(5, 0))
	assert(king != null and king["type"] == "king" and king["has_moved"] == true, "Король на (6, 0)")
	assert(rook != null and rook["type"] == "rook" and rook["has_moved"] == true, "Ладья на (5, 0)")
	assert(logic.get_piece(Vector2i(4, 0)) == null, "Клетка e1 (4, 0) свободна")
	assert(logic.get_piece(Vector2i(7, 0)) == null, "Клетка h1 (7, 0) свободна")
	print("[PASS] Тест 1: Короткая рокировка белых (O-O)")

## Тест 2: Длинная рокировка (Queenside O-O-O)
func _test_queenside_castling() -> void:
	var logic = ChessLogic.new()
	# Очищаем b1 (1, 0), c1 (2, 0), d1 (3, 0)
	logic.grid[1][0] = null # конь
	logic.grid[2][0] = null # слон
	logic.grid[3][0] = null # ферзь
	
	var moves = logic.get_legal_moves(Vector2i(4, 0))
	assert(Vector2i(2, 0) in moves, "Король должен иметь возможность длинной рокировки на (2, 0)")
	
	var res = logic.make_move(Vector2i(4, 0), Vector2i(2, 0))
	assert(res["success"] == true, "Ход длинной рокировки успешен")
	assert(res["castled"] == true, "Флаг castled должен быть true")
	assert(res["rook_from"] == Vector2i(0, 0) and res["rook_to"] == Vector2i(3, 0), "Ладья должна переместиться из (0, 0) в (3, 0)")
	
	var king = logic.get_piece(Vector2i(2, 0))
	var rook = logic.get_piece(Vector2i(3, 0))
	assert(king != null and king["type"] == "king" and king["has_moved"] == true, "Король на (2, 0)")
	assert(rook != null and rook["type"] == "rook" and rook["has_moved"] == true, "Ладья на (3, 0)")
	assert(logic.get_piece(Vector2i(4, 0)) == null, "Клетка e1 (4, 0) свободна")
	assert(logic.get_piece(Vector2i(0, 0)) == null, "Клетка a1 (0, 0) свободна")
	print("[PASS] Тест 2: Длинная рокировка белых (O-O-O)")

## Тест 3: Ограничения рокировки (шах, битое поле, ход короля/ладьи, помехи)
func _test_castling_restrictions() -> void:
	# 3.1. Нельзя рокироваться, если король уже ходил
	var logic1 = ChessLogic.new()
	logic1.grid[5][0] = null
	logic1.grid[6][0] = null
	logic1.get_piece(Vector2i(4, 0))["has_moved"] = true
	var moves1 = logic1.get_legal_moves(Vector2i(4, 0))
	assert(not (Vector2i(6, 0) in moves1), "Нельзя рокироваться, если король уже ходил")
	
	# 3.2. Нельзя рокироваться, если ладья уже ходила
	var logic2 = ChessLogic.new()
	logic2.grid[5][0] = null
	logic2.grid[6][0] = null
	logic2.get_piece(Vector2i(7, 0))["has_moved"] = true
	var moves2 = logic2.get_legal_moves(Vector2i(4, 0))
	assert(not (Vector2i(6, 0) in moves2), "Нельзя рокироваться, если ладья уже ходила")
	
	# 3.3. Нельзя рокироваться, если король находится под шахом
	var logic3 = ChessLogic.new()
	logic3.grid[5][0] = null
	logic3.grid[6][0] = null
	logic3.grid[4][1] = null # убираем пешку e2
	logic3.grid[4][5] = { "type": "rook", "is_white": false, "has_moved": true } # вражеская ладья дает шах королю e1
	var moves3 = logic3.get_legal_moves(Vector2i(4, 0))
	assert(not (Vector2i(6, 0) in moves3), "Нельзя рокироваться, находясь под шахом")
	
	# 3.4. Нельзя рокироваться через битое поле (f1 атаковано)
	var logic4 = ChessLogic.new()
	logic4.grid[5][0] = null
	logic4.grid[6][0] = null
	logic4.grid[5][1] = null # убираем пешку f2
	logic4.grid[5][5] = { "type": "rook", "is_white": false, "has_moved": true } # вражеская ладья атакует f1
	var moves4 = logic4.get_legal_moves(Vector2i(4, 0))
	assert(not (Vector2i(6, 0) in moves4), "Нельзя рокироваться через битое поле f1")
	
	# 3.5. Нельзя рокироваться на битое поле (g1 атаковано)
	var logic5 = ChessLogic.new()
	logic5.grid[5][0] = null
	logic5.grid[6][0] = null
	logic5.grid[6][1] = null # убираем пешку g2
	logic5.grid[6][5] = { "type": "rook", "is_white": false, "has_moved": true } # вражеская ладья атакует g1
	var moves5 = logic5.get_legal_moves(Vector2i(4, 0))
	assert(not (Vector2i(6, 0) in moves5), "Нельзя рокироваться на битое поле g1")
	
	# 3.6. Нельзя рокироваться, если между ними фигура
	var logic6 = ChessLogic.new()
	# f1 пуст, но g1 занят
	logic6.grid[5][0] = null
	var moves6 = logic6.get_legal_moves(Vector2i(4, 0))
	assert(not (Vector2i(6, 0) in moves6), "Нельзя рокироваться через занятую клетку g1")
	
	print("[PASS] Тест 3: Все ограничения рокировки соблюдены")

## Тест 4: Логика превращения пешки на 8-й горизонтали
func _test_pawn_promotion_logic() -> void:
	var logic = ChessLogic.new()
	# Ставим белую пешку на e7 (4, 6)
	logic.grid[4][6] = { "type": "pawn", "is_white": true, "has_moved": true }
	logic.grid[4][7] = null # освобождаем клетку превращения e8
	
	var moves = logic.get_legal_moves(Vector2i(4, 6))
	assert(Vector2i(4, 7) in moves, "Пешка может пойти на e8")
	
	# Ход пешкой на e8 с превращением в ферзя по умолчанию
	var res = logic.make_move(Vector2i(4, 6), Vector2i(4, 7), "queen")
	assert(res["success"] == true, "Ход превращения успешен")
	assert(res["promoted"] == true, "Флаг promoted = true")
	assert(res["promoted_to"] == "queen", "Превращена в ферзя")
	assert(logic.get_piece(Vector2i(4, 7))["type"] == "queen", "Фигура на e8 стала ферзем")
	
	# Смена превращения на коня через promote_pawn
	logic.promote_pawn(Vector2i(4, 7), "knight")
	assert(logic.get_piece(Vector2i(4, 7))["type"] == "knight", "Фигура на e8 заменена на коня")
	
	# Проверяем, что теперь фигура ходит как конь
	logic.is_white_turn = true
	var knight_moves = logic.get_legal_moves(Vector2i(4, 7))
	assert(Vector2i(3, 5) in knight_moves or Vector2i(5, 5) in knight_moves, "Превращенная фигура имеет ходы коня")
	print("[PASS] Тест 4: Логика превращения пешки и смены на коня")

## Тест 5: Обновление 3D-модели фигуры при превращении
func _test_pawn_promotion_3d_mesh() -> void:
	var board_scene = load("res://scenes/chess/chess_board.tscn")
	assert(board_scene != null, "chess_board.tscn должен загружаться")
	var board: ChessBoardView = board_scene.instantiate()
	root.add_child(board)
	await process_frame
	
	var pawn_node = ChessPiece3D.new()
	var pawn_mesh: Mesh = board.meshes["pawn_white"]
	var queen_mesh: Mesh = board.meshes["queen_white"]
	var knight_mesh: Mesh = board.meshes["knight_white"]
	
	pawn_node.setup("pawn", true, Vector2i(4, 6), pawn_mesh, board.white_mat)
	root.add_child(pawn_node)
	assert(pawn_node.piece_type == "pawn", "Начальный тип — пешка")
	assert(pawn_node.mesh_instance.mesh == pawn_mesh, "Начальный меш — пешка")
	
	# Превращаем в ферзя
	pawn_node.change_type("queen", queen_mesh, board.white_mat)
	assert(pawn_node.piece_type == "queen", "Тип фигуры стал queen")
	assert(pawn_node.mesh_instance.mesh == queen_mesh, "3D-меш фигуры изменился на ферзя")
	
	# Превращаем в коня
	pawn_node.change_type("knight", knight_mesh, board.white_mat)
	assert(pawn_node.piece_type == "knight", "Тип фигуры стал knight")
	assert(pawn_node.mesh_instance.mesh == knight_mesh, "3D-меш фигуры изменился на коня")
	assert(pawn_node.mesh_instance.rotation_degrees.y == 180.0, "Белый конь развернут на 180° в сторону врага")
	
	pawn_node.free()
	board.free()
	print("[PASS] Тест 5: 3D-модель фигуры корректно обновляется при превращении")

## Тест 6: Диалог превращения пешки (UI)
func _test_promotion_dialog() -> void:
	var board_scene = load("res://scenes/chess/chess_board.tscn")
	var board: ChessBoardView = board_scene.instantiate()
	root.add_child(board)
	await process_frame
	
	var test_piece = board.piece_nodes.get(Vector2i(0, 1))
	assert(test_piece != null, "Пешка должна существовать на (0, 1)")
	
	# Отображаем диалог превращения
	board._show_promotion_dialog(Vector2i(0, 7), test_piece)
	assert(board._promotion_dialog != null and is_instance_valid(board._promotion_dialog), "PromotionCanvas должен быть создан")
	
	# Выбираем превращение в ладью
	board._on_promotion_selected(Vector2i(0, 7), test_piece, "rook")
	assert(board._promotion_dialog == null, "Диалог должен быть закрыт после выбора")
	assert(test_piece.piece_type == "rook", "Фигура должна стать rook")
	assert(test_piece.mesh_instance.mesh == board.meshes["rook_white"], "3D-меш должен стать rook_white")
	
	board.free()
	print("[PASS] Тест 6: Диалог превращения корректно отображается и применяет выбор")

## Тест 7: Поднятие пешки при достижении края и опускание после выбора
func _test_pawn_lifting_on_promotion() -> void:
	var board_scene = load("res://scenes/chess/chess_board.tscn")
	var board: ChessBoardView = board_scene.instantiate()
	root.add_child(board)
	
	var pawn = board.piece_nodes.get(Vector2i(0, 1))
	assert(pawn != null, "Пешка должна быть найдена")
	pawn.set_selected(true)
	assert(pawn._is_selected == true, "Пешка должна быть в состоянии selected при промоушне")
	
	# Применение выбора фигуры
	board._on_promotion_selected(Vector2i(0, 7), pawn, "queen")
	assert(pawn._is_selected == false, "Фигура должна опуститься на стол (selected == false) после выбора")
	
	board.free()
	print("[PASS] Тест 7: Пешка поднимается при превращении и опускается после выбора")

## Тест 8: Воспроизведение звука отмены выбора при клике на другую фигуру
func _test_deselect_sound_on_switch() -> void:
	var board_scene = load("res://scenes/chess/chess_board.tscn")
	var board: ChessBoardView = board_scene.instantiate()
	root.add_child(board)
	board.is_active = true
	
	# 1. Выбираем фигуру А (0, 1)
	board._on_cell_clicked(Vector2i(0, 1))
	assert(board.selected_pos == Vector2i(0, 1), "Фигура (0, 1) выбрана")
	
	# 2. Кликаем на фигуру Б (1, 1), когда выбрана фигура А
	# Это должно вызвать воспроизведение звука отмены старой фигуры и выбрать новую
	var deselect_sound_player = board.deselect_sound
	assert(deselect_sound_player != null, "DeselectSound плеер должен быть инициализирован")
	
	board._on_cell_clicked(Vector2i(1, 1))
	assert(board.selected_pos == Vector2i(1, 1), "Фигура (1, 1) теперь выбрана")
	assert(deselect_sound_player.playing == true, "Звук отмены выбора фигуры должен проигрываться при переключении")
	
	board.free()
	print("[PASS] Тест 8: Звук отмены выбора воспроизводится при выборе другой фигуры")

## Тест 9: ИИ отвечает ходом после превращения пешки в ферзя и не зависает
func _test_ai_responds_after_promotion() -> void:
	var board_scene = load("res://scenes/chess/chess_board.tscn")
	var board: ChessBoardView = board_scene.instantiate()
	root.add_child(board)
	await process_frame
	
	# Очищаем доску и создаем ситуацию превращения
	for p in board.piece_nodes.values():
		p.queue_free()
	board.piece_nodes.clear()
	for x in 8:
		for y in 8:
			board.logic.grid[x][y] = null
			
	# Белый король (4, 0), черная ладья (7, 7), черный король (0, 7), белая пешка (4, 6)
	board.logic.grid[4][0] = { "type": "king", "is_white": true, "has_moved": true }
	board.logic.grid[0][7] = { "type": "king", "is_white": false, "has_moved": true }
	board.logic.grid[7][7] = { "type": "rook", "is_white": false, "has_moved": true }
	board.logic.grid[4][6] = { "type": "pawn", "is_white": true, "has_moved": true }
	
	board._spawn_piece_at(Vector2i(4, 0), "king", true)
	board._spawn_piece_at(Vector2i(0, 7), "king", false)
	board._spawn_piece_at(Vector2i(7, 7), "rook", false)
	board._spawn_piece_at(Vector2i(4, 6), "pawn", true)
	board.logic.is_white_turn = true
	board.is_active = true
	
	# Ход пешки на клетку превращения e8 (4, 7)
	board._execute_player_move(Vector2i(4, 6), Vector2i(4, 7))
	await process_frame
	
	# Игрок выбирает превращение в ферзя
	board._on_promotion_selected(Vector2i(4, 7), board.piece_nodes.get(Vector2i(4, 7)), "queen")
	assert(board.logic.get_piece(Vector2i(4, 7))["type"] == "queen", "Пешка стала ферзём")
	assert(board.logic.is_white_turn == false, "Ход перешел Черным")
	
	# Ждем расчета и ответа ИИ
	var ai_responded: bool = false
	for i in range(120):
		await process_frame
		if board.logic.move_count >= 2:
			ai_responded = true
			break
			
	assert(ai_responded == true, "ИИ должен сделать ответный ход и не зависнуть после превращения пешки")
	board.free()
	print("[PASS] Тест 9: ИИ корректно отвечает ходом после превращения пешки в ферзя (без зависания)")

## Тест 10: Проверка эффектов: перебой света НЕ блокирует ввод игрока, а перемещение фигуры блокирует
func _test_player_blocked_while_effect_active() -> void:
	var board_scene = load("res://scenes/chess/chess_board.tscn")
	var board: ChessBoardView = board_scene.instantiate()
	root.add_child(board)
	await process_frame
	
	board.is_active = true
	board.logic.is_white_turn = true
	assert(board.is_effect_active() == false, "В спокойном состоянии эффектов нет")
	
	# 1. Активируем перебой со светом: игрок НЕ должен блокироваться
	board._is_light_trouble_active = true
	assert(board.is_effect_active() == false, "Перебой со светом не должен блокировать ввод доски")
	board._on_cell_clicked(Vector2i(0, 1))
	assert(board.selected_pos == Vector2i(0, 1), "Игрок может выбирать фигуру во время перебоя со светом")
	board.cancel_selection()
	
	# 2. Активируем эффект перемещения фигуры белых (_is_white_moving): ввод блокируется
	board._is_white_moving = true
	assert(board.is_effect_active() == true, "Перемещение фигуры белых должно считаться активным блокирующим эффектом")
	board._on_cell_clicked(Vector2i(0, 1))
	assert(board.selected_pos == Vector2i(-1, -1), "Игрок НЕ может выбрать фигуру во время движения фигуры")
	
	# 3. Окончание движения фигуры
	board._is_white_moving = false
	assert(board.is_effect_active() == false, "После окончания движения эффект снимается")
	board._on_cell_clicked(Vector2i(0, 1))
	assert(board.selected_pos == Vector2i(0, 1), "После окончания движения игрок снова может сделать ход")
	
	board.free()
	print("[PASS] Тест 10: Перебой со светом не блокирует ввод игрока, а перемещение фигуры блокирует")
