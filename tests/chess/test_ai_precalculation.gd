extends SceneTree

const ChessBoardView = preload("res://scripts/chess/chess_board_view.gd")
const ChessLogic = preload("res://scripts/chess/chess_logic.gd")
const ChessBot = preload("res://scripts/chess/chess_bot.gd")

func _init() -> void:
	print("--- [AI Precalculation Test Suite] Запуск тестов ---")
	_run_tests.call_deferred()

func _run_tests() -> void:
	_test_parallel_move_calculation()
	_test_execution_conditions()
	print("--- [AI Precalculation Test Suite] ВСЕ ТЕСТЫ УСПЕШНО ПРОЙДЕНЫ ---")
	quit(0)

## Тест 1: Просчет хода ИИ в параллельном потоке на клонированной сетке
func _test_parallel_move_calculation() -> void:
	var logic = ChessLogic.new()
	# Белые делают e2-e4
	logic.make_move(Vector2i(4, 1), Vector2i(4, 3))
	
	var grid_copy: Array = logic.clone_grid()
	assert(grid_copy.size() == 8, "Сетка скопирована корректно")
	
	var thread = Thread.new()
	var thread_callable = func():
		return ChessBot.choose_best_move(grid_copy, logic.playthrough)
		
	var err = thread.start(thread_callable)
	assert(err == OK, "Фоновый поток расчета успешно запущен")
	
	var bot_move = thread.wait_to_finish()
	assert(bot_move is Dictionary and not bot_move.is_empty(), "Бот нашел ход в фоновом потоке")
	assert(bot_move.has("from") and bot_move.has("to"), "Ход содержит from и to")
	
	# Проверяем легальность на оригинальной логике
	var legal = logic.get_legal_moves(bot_move["from"])
	assert(bot_move["to"] in legal, "Ход, найденный параллельно, легален на доске")
	print("[PASS] Тест 1: Фоновый расчет хода ИИ на клонированной сетке прошел успешно: ", bot_move)

## Тест 2: Проверка условий выполнения хода в ChessBoardView
func _test_execution_conditions() -> void:
	var board_scene = load("res://scenes/chess/chess_board.tscn")
	assert(board_scene != null, "chess_board.tscn должен загружаться")
	var board_view: ChessBoardView = board_scene.instantiate()
	root.add_child(board_view)
	
	# Исходное состояние: флаги опущены
	assert(board_view._white_animation_finished == false, "Анимация белых не завершена изначально")
	assert(board_view._ai_turn_delay_finished == false, "Задержка не завершена изначально")
	
	# Выполняем ход белых e2-e4 в логике и синхронизируем ноды
	var from_pos = Vector2i(4, 1)
	var to_pos = Vector2i(4, 3)
	board_view.logic.make_move(from_pos, to_pos)
	var p = board_view.piece_nodes.get(from_pos)
	if p:
		board_view.piece_nodes.erase(from_pos)
		board_view.piece_nodes[to_pos] = p
		p.board_pos = to_pos
		
	# Запуск предрасчета
	board_view._start_precomputing_ai_move()
	assert(board_view._is_ai_calculating == true, "Флаг _is_ai_calculating взведен")
	
	# Дожидаемся завершения потока
	while board_view._is_ai_calculating:
		board_view._process(0.016)
		OS.delay_msec(10)
		
	assert(board_view._is_ai_calculating == false, "Расчет завершен")
	assert(not board_view._precomputed_ai_move.is_empty(), "Ход предрассчитан и сохранен")
	
	# При незавершенной анимации ход ИИ НЕ должен выполняться
	board_view._white_animation_finished = false
	board_view._ai_turn_delay_finished = true
	board_view._check_execute_ai_turn()
	assert(board_view.logic.is_white_turn == false, "Ход черных еще не применен на доске")
	
	# При завершении анимации и задержки — ход немедленно исполняется
	board_view._white_animation_finished = true
	board_view._check_execute_ai_turn()
	# После применения хода черных очередь хода возвращается белым
	assert(board_view.logic.is_white_turn == true, "После завершения анимации предрассчитанный ход черных выполнен!")
	
	board_view._cleanup_ai_thread()
	board_view.queue_free()
	print("[PASS] Тест 2: Условия исполнения хода (только после окончания анимации) соблюдены!")
