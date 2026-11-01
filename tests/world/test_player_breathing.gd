extends SceneTree

func _init() -> void:
	_run_tests.call_deferred()

func _run_tests() -> void:
	print("--- [Player Breathing & Vignette Test Suite] Тестирование звука breath и виньетки ---")

	# 0. Инициализируем EventBus
	var bus = root.get_node_or_null("EventBus")
	if bus == null:
		var bus_script = load("res://scripts/event_bus.gd")
		bus = bus_script.new()
		bus.name = "EventBus"
		root.add_child(bus)
	assert(bus != null, "EventBus должен существовать")

	# 1. Загрузка сцены room.tscn
	var scene = load("res://scenes/room.tscn")
	assert(scene != null, "Сцена room.tscn должна успешно загружаться")

	var room = scene.instantiate()
	root.add_child(room)

	await process_frame

	var player = room.find_child("player", true)
	assert(player != null, "Player должен присутствовать в сцене")

	# ТЕСТ 1: Инициализация компонентов breath_player и виньетки
	var breath_player = player.get_node_or_null("head/AudioStreamPlayer3D") as AudioStreamPlayer3D
	assert(breath_player != null, "AudioStreamPlayer3D должен присутствовать в head игрока")
	assert(breath_player.stream != null, "Плеер дыхания должен иметь аудиопоток breath.ogg")
	assert(player._vignette_rect != null, "В HudRoot должна быть создана PanicVignette")
	assert(player._vignette_material != null, "У PanicVignette должен быть ShaderMaterial")
	assert(player.get_vignette_opacity() == 0.0, "Начальная прозрачность виньетки должна быть 0.0")
	assert(player.is_heavy_breathing == false, "В начале игрок дышит спокойно (is_heavy_breathing == false)")
	print("[PASS] Тест 1: Инициализация breath_player в голове игрока и шейдера виньетки успешна")

	# ТЕСТ 2: Страшное событие 1 — Потеря белой королевы (Ферзя)
	bus.piece_captured.emit("queen", true)
	await process_frame
	
	assert(player.is_heavy_breathing == true, "После потери Ферзя должно включиться тяжелое дыхание")
	assert(breath_player.playing == true, "AudioStreamPlayer3D в head должен играть звук дыхания")
	assert(player.get_vignette_opacity() > 0.0, "Виньетка должна активироваться (opacity > 0.0, текущая: %.2f)" % player.get_vignette_opacity())
	print("[PASS] Тест 2: Потеря белой королевы запустила звук breath и виньетку паники")

	# ТЕСТ 3: Остановка тяжелого дыхания
	player.stop_heavy_breathing(0.05)
	assert(player.is_heavy_breathing == false, "После stop_heavy_breathing флаг сбрасывается в false")
	print("[PASS] Тест 3: Ручная остановка дыхания корректно завершает эффект")

	# ТЕСТ 4: Страшное событие 2 — Проигрыш Белых (мат от Черных)
	bus.game_over.emit("black")
	await process_frame

	assert(player.is_heavy_breathing == true, "Мат Белым должен вызвать панику и тяжелое дыхание")
	assert(breath_player.playing == true, "Звук breath должен играть при поражении")
	assert(player.get_vignette_opacity() > 0.0, "Виньетка должна затемнять экран при поражении")
	print("[PASS] Тест 4: Проигрыш Белых (game_over black) активировал звук breath и виньетку")

	# ТЕСТ 5: Страшное событие 3 — Проигрыш Белых через штурм бункера (breach)
	player.stop_heavy_breathing(0.05)
	bus.game_over.emit("breach")
	await process_frame

	assert(player.is_heavy_breathing == true, "Штурм бункера (breach) должен активировать тяжелое дыхание")
	assert(breath_player.playing == true, "Звук breath играет при выбитой двери")
	print("[PASS] Тест 5: Проигрыш через выбитую дверь (breach) активировал дыхание")

	# ТЕСТ 6: Сброс игры (reset_game_state) останавливает эффект
	bus.reset_game_state()
	await process_frame
	assert(player.is_heavy_breathing == false, "Сброс игры должен выключить тяжелое дыхание")
	print("[PASS] Тест 6: reset_game_state сбрасывает панику и дыхание")

	room.free()
	print("--- [Player Breathing & Vignette Test Suite] ВСЕ ТЕСТЫ УСПЕШНО ПРОЙДЕНЫ! ---")
	quit(0)
