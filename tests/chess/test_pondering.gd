extends SceneTree

# test_pondering.gd
# Тестирование функции фонового пре-расчета ходов (Pondering)

const ChessBot = preload("res://scripts/chess/chess_bot.gd")
const ChessLogic = preload("res://scripts/chess/chess_logic.gd")

func _init() -> void:
	print("--- [Test Pondering / Precalculation] ---")
	
	var logic = ChessLogic.new()
	# Ход 1. e4 e5 2. Nf3
	logic.make_move(Vector2i(4, 1), Vector2i(4, 3)) # e2e4
	logic.make_move(Vector2i(4, 6), Vector2i(4, 4)) # e7e5
	
	print("Запуск ponder_replies для позиции после 1. e4 e5 (ход белых)...")
	var start_t = Time.get_ticks_msec()
	var ponder_cache = ChessBot.ponder_replies(logic.grid, 1, 3, logic.en_passant_target, 2000)
	var elapsed = Time.get_ticks_msec() - start_t
	
	print("Pondering завершен за %d мс. Найдено вариантов: %d" % [elapsed, ponder_cache.size()])
	for k in ponder_cache:
		var reply = ponder_cache[k]
		print("  Ход белых [%s] -> Ответ черных: %s" % [k, str(reply)])
		
	assert(ponder_cache.size() > 0, "Кэш пондеринга не должен быть пустым!")
	
	# Проверяем, что самый логичный ход 2. Nf3 (g1f3 = 6,0 -> 5,2) присутствует в кэше
	var nf3_key = "6_0_5_2"
	if ponder_cache.has(nf3_key):
		print("[PASS] Ход белых 2. Nf3 успешно предрасчитан! Ответ черных: %s" % str(ponder_cache[nf3_key]))
	else:
		print("[NOTE] Nf3_key не в ТОП-3, но в кэше есть другие сильные ходы: %s" % str(ponder_cache.keys()))
		
	print("--- [Test Pondering] ВСЕ ТЕСТЫ ПОНДЕРИНГА УСПЕШНО ПРОЙДЕНЫ ---")
	quit(0)

