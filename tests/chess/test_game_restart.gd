extends SceneTree

const ChessBoardViewScript = preload("res://scripts/chess/chess_board_view.gd")
const ChessLogicScript = preload("res://scripts/chess/chess_logic.gd")
const DoorKnockTimerScript = preload("res://scripts/world/door_knock_timer.gd")

func _init() -> void:
	print("--- Running test_game_restart.gd ---")
	test_board_reset_and_playthrough()
	test_door_knock_timer_reset()
	test_checkmate_restart_integration()
	# test_debug_instant_endings() # [Отключено для релизного билда: отладочные функции закомментированы]
	print("--- All restart tests passed successfully! ---")
	quit(0)

func test_board_reset_and_playthrough() -> void:
	var logic = ChessLogicScript.new()
	assert(logic.playthrough == 1, "Game 1 should start at playthrough 1")
	assert(logic.is_white_turn == true, "White should move first")
	
	# Simulate fool's mate / fast mate
	# 1. f3 e5 2. g4 Qh4#
	# f3: (5, 1) -> (5, 2)
	var m1 = logic.make_move(Vector2i(5, 1), Vector2i(5, 2))
	assert(m1.success, "Move 1 should succeed")
	# e5: (4, 6) -> (4, 4)
	var m2 = logic.make_move(Vector2i(4, 6), Vector2i(4, 4))
	assert(m2.success, "Move 2 should succeed")
	# g4: (6, 1) -> (6, 3)
	var m3 = logic.make_move(Vector2i(6, 1), Vector2i(6, 3))
	assert(m3.success, "Move 3 should succeed")
	# Qh4#: (3, 7) -> (7, 3)
	var m4 = logic.make_move(Vector2i(3, 7), Vector2i(7, 3))
	assert(m4.success, "Move 4 should succeed")
	assert(m4.is_checkmate == true, "Move 4 should be checkmate")
	assert(logic.is_game_over == true, "Game over should be true")
	assert(logic.winner == "black", "Winner should be black")
	
	# Reset for playthrough 2
	logic.reset_board(2)
	assert(logic.playthrough == 2, "Playthrough should now be 2")
	assert(logic.is_game_over == false, "Game over should be false after reset")
	assert(logic.is_white_turn == true, "White should move first in Game 2")
	assert(logic.winner == "", "Winner should be cleared")
	
	# Verify all 32 pieces are back on their starting positions
	var piece_count: int = 0
	for x in range(8):
		for y in range(8):
			var p = logic.get_piece(Vector2i(x, y))
			if p != null:
				piece_count += 1
	assert(piece_count == 32, "All 32 pieces must be placed back on initial positions")
	print("✓ test_board_reset_and_playthrough passed")

func test_door_knock_timer_reset() -> void:
	var root_node = get_root()
	var door_timer = DoorKnockTimerScript.new()
	root_node.add_child(door_timer)
	
	door_timer.idle_time = 35.0
	door_timer.current_knock_level = 1
	door_timer._on_game_over("black")
	assert(door_timer.is_game_finished == true, "Timer should be marked finished on game_over")
	assert(door_timer.is_active == false, "Timer should be inactive on game_over")
	
	door_timer._on_game_reset(2)
	assert(door_timer.is_game_finished == false, "Timer should not be finished after reset")
	assert(door_timer.is_active == true, "Timer should be active after reset")
	assert(door_timer.idle_time == 0.0, "Idle time should be reset to 0")
	assert(door_timer.current_knock_level == 0, "Knock level should be reset to 0")
	
	door_timer.queue_free()
	print("✓ test_door_knock_timer_reset passed")

func test_checkmate_restart_integration() -> void:
	var board_scene = preload("res://scenes/chess/chess_board.tscn")
	var board_view = board_scene.instantiate()
	var root_node = get_root()
	root_node.add_child(board_view)
	
	board_view.white_move_duration = 0.01
	board_view.black_move_duration = 0.01
	board_view.ai_turn_delay = 0.01
	
	# Initial spawn
	board_view.restart_game(1)
	assert(board_view.logic.playthrough == 1, "Board should start with playthrough 1")
	assert(board_view.piece_nodes.size() == 32, "Board should have 32 piece nodes")
	
	# Simulate checkmate restart call
	board_view.restart_game(2)
	assert(board_view.logic.playthrough == 2, "Board should be at playthrough 2")
	assert(board_view.piece_nodes.size() == 32, "All 32 pieces must be respawned")
	assert(board_view.logic.is_game_over == false, "Game must not be game over")
	assert(board_view.logic.is_white_turn == true, "White turn after restart")
	
	board_view.queue_free()
	print("✓ test_checkmate_restart_integration passed")

# func test_debug_instant_endings() -> void:
# 	var board_scene = preload("res://scenes/chess/chess_board.tscn")
# 	var board_view = board_scene.instantiate()
# 	var root_node = get_root()
# 	root_node.add_child(board_view)
# 	board_view.restart_game(1)
# 	
# 	# Тест F5: мгновенная победа белых
# 	board_view.trigger_debug_win()
# 	assert(board_view.logic.is_game_over == true, "Игра должна быть завершена после trigger_debug_win")
# 	assert(board_view.logic.winner == "white", "Победитель должен быть white")
# 	
# 	# Тест F6: мгновенное поражение белых (победа черных)
# 	board_view.trigger_debug_loss()
# 	assert(board_view.logic.is_game_over == true, "Игра должна быть завершена после trigger_debug_loss")
# 	assert(board_view.logic.winner == "black", "Победитель должен быть black")
# 	
# 	# Тест F7: мгновенный пат
# 	board_view.trigger_debug_draw()
# 	assert(board_view.logic.is_game_over == true, "Игра должна быть завершена после trigger_debug_draw")
# 	assert(board_view.logic.winner == "draw", "Победитель должен быть draw")
# 	
# 	board_view.queue_free()
# 	print("✓ test_debug_instant_endings passed")
