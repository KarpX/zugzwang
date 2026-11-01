extends SceneTree

# benchmark_chess_bot.gd
# Замер производительности и скорости поиска ChessBot (узлы в секунду, время на ход)

const ChessBot = preload("res://scripts/chess/chess_bot.gd")
const ChessLogic = preload("res://scripts/chess/chess_logic.gd")

func _init() -> void:
	print("======================================================================")
	print("       CHESS BOT BENCHMARK (MEASURING BASELINE PERFORMANCE)           ")
	print("======================================================================")
	
	var test_positions = [
		# 1. Начальная позиция после 1. e4
		["e2e4"],
		# 2. Итальянская партия
		["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "f8c5", "d2d3"],
		# 3. Сицилианская защита
		["e2e4", "c7c5", "g1f3", "d7d6", "d2d4", "c5d4", "f3d4", "g8f6", "b1c3"],
		# 4. Французская защита (острый миттельшпиль)
		["e2e4", "e7e6", "d2d4", "d7d5", "b1c3", "g8f6", "c1g5", "f8e7", "e4e5", "f6d7"],
		# 5. Ферзевый гамбит
		["d2d4", "d7d5", "c2c4", "e7e6", "b1c3", "g8f6", "c1g5", "b8d7", "e2e3"]
	]
	
	var total_time_ms: int = 0
	var total_nodes: int = 0
	
	for i in range(test_positions.size()):
		var moves = test_positions[i]
		var logic = ChessLogic.new()
		for m in moves:
			var from_pos = Vector2i(m.unicode_at(0) - 97, int(m.substr(1, 1)) - 1)
			var to_pos = Vector2i(m.unicode_at(2) - 97, int(m.substr(3, 1)) - 1)
			logic.make_move(from_pos, to_pos)
			
		var start_t = Time.get_ticks_msec()
		var res = ChessBot.choose_best_move(logic.grid, 1, 0, logic.en_passant_target)
		var elapsed = Time.get_ticks_msec() - start_t
		
		var info = ChessBot.last_search_info
		var nodes = info.get("nodes", 0)
		var nps = int(float(nodes) / max(0.001, float(elapsed) / 1000.0))
		
		total_time_ms += elapsed
		total_nodes += nodes
		
		print("Тест %d: Время = %4d мс | Узлов = %6d | NPS = %7d | Ход = %s" % [
			i + 1, elapsed, nodes, nps, str(res)
		])
		
	var avg_time = float(total_time_ms) / float(test_positions.size())
	var overall_nps = int(float(total_nodes) / max(0.001, float(total_time_ms) / 1000.0))
	
	print("----------------------------------------------------------------------")
	print("ИТОГО BASELINE:")
	print("Среднее время на ход (Hard): %.1f мс" % avg_time)
	print("Всего узлов: %d" % total_nodes)
	print("Общий NPS (Nodes Per Second): %d" % overall_nps)
	print("Общее время 5 позиций: %d мс" % total_time_ms)
	print("======================================================================")
	
	quit(0)

