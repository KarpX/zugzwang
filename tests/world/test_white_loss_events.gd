extends SceneTree

func _init() -> void:
	_run_tests.call_deferred()

func _run_tests() -> void:
	print("--- [White Loss Events Test Suite] Тестирование микро-событий потерь Белых фигур ---")
	
	# 0. Инициализируем EventBus до сцены комнаты
	var bus = root.get_node_or_null("EventBus")
	if bus == null:
		var bus_script = load("res://scripts/event_bus.gd")
		bus = bus_script.new()
		bus.name = "EventBus"
		root.add_child(bus)
	assert(bus != null, "EventBus должен существовать")
	
	var scene = load("res://scenes/room.tscn")
	assert(scene != null, "Сцена room.tscn должна загружаться")
	
	var room = scene.instantiate()
	root.add_child(room)
	
	await process_frame
	
	var lamp = room.find_child("HangingBulb", true) as HangingLamp
	assert(lamp != null, "HangingBulb должен присутствовать")
	
	var cam_node = room.find_child("SecurityCamera", true)
	if cam_node == null:
		cam_node = room.find_child("camera", true)
	var sec_camera: SecurityCamera = null
	if cam_node is SecurityCamera:
		sec_camera = cam_node as SecurityCamera
	else:
		sec_camera = room.find_child("*SecurityCamera*", true, false) as SecurityCamera
	
	var player = room.find_child("player", true)
	assert(player != null, "Player должен присутствовать в сцене")
	
	var chess_board = room.find_child("ChessBoard", true)
	assert(chess_board != null, "ChessBoard должен присутствовать")
	
	# Сброс начального счета
	bus.reset_game_state()
	assert(bus.white_score == 40, "Начальный счет Белых должен быть 40")
	assert(bus.black_score == 40, "Начальный счет Черных должен быть 40")
	print("[PASS] Тест 1: Инициализация счета и сцены room.tscn успешна (40/40 очков)")
	
	# --------------------------------------------------------------------------
	# ТЕСТ 2: Потеря Белой Пешки (1 очко)
	# --------------------------------------------------------------------------
	var last_score_event = {}
	var score_callback = func(is_white: bool, new_score: int):
		last_score_event["is_white"] = is_white
		last_score_event["score"] = new_score
	bus.score_updated.connect(score_callback)
	
	lamp._on_trouble_finished()
	bus.piece_captured.emit("pawn", true)
	
	assert(bus.white_score == 39, "Счет Белых должен стать 39")
	assert(last_score_event.get("is_white") == true and last_score_event.get("score") == 39, "score_updated должен сообщить 39")
	assert(bus.is_lamp_trouble_active == true, "Свет должен уйти в перебой на белую пешку")
	assert(is_equal_approx(lamp.base_amplitude, HangingLamp.DEFAULT_BASE_AMPLITUDE), "Лампа НЕ должна увеличивать амплитуду при потере пешки (остается 0.035)")
	assert(player._trauma > 0.0, "Игрок должен получить импульс сотрясения камеры")
	assert(player._radio_subtitle_label != null and player._radio_subtitle_label.text != "", "Радио-субтитр пешки должен отображаться")
	assert(player._radio_subtitle_label.get_parent().name == "HudRoot", "Радио-субтитр должен быть внутри HudRoot (Control full-rect)")
	assert(player._radio_subtitle_label.modulate.a > 0.0, "Радио-субтитр должен быть видимым (alpha > 0)")
	print("[PASS] Тест 2: Потеря Белой Пешки (1 очко, перебой лампы без раскачки base_amplitude=%.3f, радио в HudRoot: %s)" % [lamp.base_amplitude, player._radio_subtitle_label.text])
	
	lamp._on_trouble_finished()
	
	# --------------------------------------------------------------------------
	# ТЕСТ 3: Потеря Белого Коня (3 очка)
	# --------------------------------------------------------------------------
	lamp._on_trouble_finished()
	var pre_trauma: float = player._trauma
	bus.piece_captured.emit("knight", true)
	assert(bus.white_score == 36, "Счет Белых должен стать 36 (39 - 3)")
	assert(player._trauma > pre_trauma, "Травма камеры должна возрасти при гибели коня")
	assert(is_equal_approx(lamp.base_amplitude, 0.3), "Конь/Слон должны увеличить base_amplitude лампы до 0.3")
	assert(sec_camera == null or sec_camera._twitch_tween != null, "Сервопривод камеры безопасности должен получить рывок")
	assert(lamp._is_trouble_playing == true, "Конь должен активировать перебой со светом (из всех звуков)")
	print("[PASS] Тест 3: Потеря Белого Коня (3 очка, раскачивание лампы base_amplitude=%.3f со звуком %d, рывок камеры, радио: %s)" % [lamp.base_amplitude, lamp._last_sound_index, player._radio_subtitle_label.text])
	
	lamp._on_trouble_finished()
	
	# --------------------------------------------------------------------------
	# ТЕСТ 4: Потеря Белого Слона (3 очка)
	# --------------------------------------------------------------------------
	bus.piece_captured.emit("bishop", true)
	assert(bus.white_score == 33, "Счет Белых должен стать 33 (36 - 3)")
	assert(lamp._is_trouble_playing == true, "Слон должен активировать перебой со светом (из всех звуков)")
	assert(is_equal_approx(lamp.base_amplitude, 0.3), "Слон должен увеличить base_amplitude лампы до 0.3")
	assert(player._radio_subtitle_label.text != "", "Радио-сводка слона должна отобразиться")
	print("[PASS] Тест 4: Потеря Белого Слона (3 очка, base_amplitude=%.3f, радио: %s)" % [lamp.base_amplitude, player._radio_subtitle_label.text])
	
	# --------------------------------------------------------------------------
	# ТЕСТ 5: Потеря Белой Ладьи (5 очков)
	# --------------------------------------------------------------------------
	lamp._on_trouble_finished()
	lamp.base_amplitude = HangingLamp.DEFAULT_BASE_AMPLITUDE
	bus.piece_captured.emit("rook", true)
	assert(bus.white_score == 28, "Счет Белых должен стать 28 (33 - 5)")
	assert(bus.is_lamp_trouble_active == true, "Ладья вызывает блэкаут на 0.45с и вспышку перекала")
	assert(is_equal_approx(lamp.base_amplitude, HangingLamp.DEFAULT_BASE_AMPLITUDE), "Ладья НЕ должна раскачивать лампу (base_amplitude=0.035)")
	assert(chess_board._is_light_trouble_active == true, "Шахматная доска должна синхронизировать блэкаут")
	print("[PASS] Тест 5: Потеря Белой Ладьи (5 очков, блэкаут 0.45с, base_amplitude=%.3f без раскачки, радио: %s)" % [lamp.base_amplitude, player._radio_subtitle_label.text])
	
	lamp._on_trouble_finished()
	
	# --------------------------------------------------------------------------
	# ТЕСТ 6: Потеря Белого Ферзя (10 очков — Катастрофа в бункере)
	# --------------------------------------------------------------------------
	bus.piece_captured.emit("queen", true)
	assert(bus.white_score == 18, "Счет Белых должен стать 18 (28 - 10)")
	assert(bus.is_lamp_trouble_active == true, "Ферзь вызывает катастрофический блэкаут на 2.5 секунды")
	assert(player._trauma >= 0.99, "Гибель ферзя дает максимальную травму камеры (1.0)")
	assert(player._current_max_shake_offset >= 0.14, "Сверхсильное смещение камеры при гибели ферзя (0.14м)")
	assert(is_equal_approx(lamp.base_amplitude, 0.5), "Ферзь должен увеличить base_amplitude лампы до 0.5")
	print("[PASS] Тест 6: Потеря Белого Ферзя (10 очков, аварийный блэкаут 2.5с, base_amplitude=%.3f, trauma=%.2f, shake_offset=%.3f, радио: %s)" % [lamp.base_amplitude, player._trauma, player._current_max_shake_offset, player._radio_subtitle_label.text])
	
	# --------------------------------------------------------------------------
	# ТЕСТ 7: Блокировка хода Черных во время катастрофы ферзя
	# --------------------------------------------------------------------------
	chess_board.logic.is_white_turn = false
	var moves_before = chess_board.logic.move_count
	chess_board._execute_ai_turn()
	assert(chess_board.logic.move_count == moves_before, "Противник НЕ должен ходить во время блэкаута ферзя")
	print("[PASS] Тест 7: Противник заблокирован во время аварийного блэкаута")
	
	# --------------------------------------------------------------------------
	# ТЕСТ 8: Восстановление после блэкаута
	# --------------------------------------------------------------------------
	lamp._on_trouble_finished()
	assert(bus.is_lamp_trouble_active == false, "Свет восстановлен, флаг сброшен")
	assert(chess_board._is_light_trouble_active == false, "Подсветка доски восстановлена")
	print("[PASS] Тест 8: Полное восстановление освещения и снятие блокировки")
	
	# --------------------------------------------------------------------------
	# ТЕСТ 9: Потери Черных (Враг) НЕ вызывают аварий внутри бункера
	# --------------------------------------------------------------------------
	bus.piece_captured.emit("queen", false)
	assert(bus.black_score == 30, "Счет Черных снизился на 10 очков (40 -> 30)")
	assert(bus.is_lamp_trouble_active == false, "Взятие черного ферзя НЕ гасит свет в бункере")
	print("[PASS] Тест 9: Взятие черных фигур снижает вражеский счет и не гасит свет в бункере")
	
	room.free()
	print("--- [White Loss Events Test Suite] ВСЕ ТЕСТЫ УСПЕШНО ПРОЙДЕНЫ! ---")
	quit(0)
