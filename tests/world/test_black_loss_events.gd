extends SceneTree

func _init() -> void:
	_run_tests.call_deferred()

func _run_tests() -> void:
	print("--- [Black Loss Events Test Suite] Тестирование событий потерь Черных фигур (Враг) ---")
	
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
	
	var outside_ctrl = room.find_child("OutsideWarController", true) as OutsideWarController
	assert(outside_ctrl != null, "OutsideWarController должен присутствовать в сцене room.tscn")
	
	var lamp = room.find_child("HangingBulb", true) as HangingLamp
	assert(lamp != null, "HangingBulb должен присутствовать")
	
	var player = room.find_child("player", true)
	assert(player != null, "Player должен присутствовать в сцене")
	
	var chess_board = room.find_child("ChessBoard", true)
	assert(chess_board != null, "ChessBoard должен присутствовать")
	
	# Проверка отсутствия света и пожара у двери бункера
	var door_node = room.find_child("Door", true)
	assert(door_node != null, "Door должна существовать")
	assert(outside_ctrl.get_node_or_null("DoorSeamLight") == null, "Свет под дверью DoorSeamLight должен отсутствовать")
	assert(outside_ctrl.get_node_or_null("DoorSmokeParticles") == null, "Дым и огонь у двери должны отсутствовать")
	
	# Сброс начального счета
	bus.reset_game_state()
	outside_ctrl._on_game_reset(1)
	assert(bus.white_score == 40, "Начальный счет Белых должен быть 40")
	assert(bus.black_score == 40, "Начальный счет Черных должен быть 40")
	assert(bus.outside_stage == 0, "Начальная стадия внешнего мира должна быть 0 (Затишье)")
	assert(outside_ctrl._is_siren_loop_active == false, "Сирена в начале выключена")
	print("[PASS] Тест 1: Инициализация контроллера внешней войны (40/40 очков, свет/пожар у двери отключены)")
	
	# --------------------------------------------------------------------------
	# ТЕСТ 2: Микро-событие — Потеря Черной Пешки (1 очко, взрыв boom_1.ogg)
	# --------------------------------------------------------------------------
	var last_enemy_loss = {}
	var enemy_loss_cb = func(ptype: String, bscore: int):
		last_enemy_loss["piece"] = ptype
		last_enemy_loss["score"] = bscore
	bus.enemy_loss_triggered.connect(enemy_loss_cb)
	
	bus.piece_captured.emit("pawn", false)
	
	assert(bus.black_score == 39, "Счет Черных должен стать 39")
	assert(last_enemy_loss.get("piece") == "pawn" and last_enemy_loss.get("score") == 39, "enemy_loss_triggered должен зафиксировать пешку со счетом 39")
	assert(bus.is_lamp_trouble_active == false, "Взятие черной пешки НЕ должно гасить лампу в бункере")
	assert(player._radio_subtitle_label != null and player._radio_subtitle_label.text.begins_with("«(Перехват)"), "Радио-перехват пешки должен начинаться с «(Перехват): %s" % player._radio_subtitle_label.text)
	assert(outside_ctrl._outside_sfx_player != null and outside_ctrl._outside_sfx_player.stream == OutsideWarController.SOUND_BOOMS[0], "SFX плеер должен воспроизвести boom_1.ogg")
	print("[PASS] Тест 2: Потеря Черной Пешки (1 очко, взрыв boom_1.ogg на шине Outside, лампа не задета, перехват: %s)" % player._radio_subtitle_label.text)
	
	# --------------------------------------------------------------------------
	# ТЕСТ 3: Микро-событие — Потеря Черного Коня (3 очка, взрыв boom_2.ogg)
	# --------------------------------------------------------------------------
	var pre_trauma: float = player._trauma
	bus.piece_captured.emit("knight", false)
	
	assert(bus.black_score == 36, "Счет Черных должен стать 36 (39 - 3)")
	assert(player._radio_subtitle_label.text.begins_with("«(Перехват)"), "Радио-перехват коня должен отобразиться")
	assert(outside_ctrl._outside_sfx_player.stream == OutsideWarController.SOUND_BOOMS[1], "SFX плеер должен воспроизвести boom_2.ogg")
	assert(player._trauma > pre_trauma, "Травма камеры должна возрасти от вибрации бронедвери")
	print("[PASS] Тест 3: Потеря Черного Коня (3 очка, взрыв boom_2.ogg, дрожь стальной двери, перехват: %s)" % player._radio_subtitle_label.text)
	
	# --------------------------------------------------------------------------
	# ТЕСТ 4: Микро-событие — Потеря Черного Слона (3 очка)
	# --------------------------------------------------------------------------
	var last_seismic = {}
	var seismic_cb = func(intensity: float, is_sub: bool):
		last_seismic["intensity"] = intensity
		last_seismic["is_sub"] = is_sub
	bus.seismic_shock_triggered.connect(seismic_cb)
	
	bus.piece_captured.emit("bishop", false)
	
	assert(bus.black_score == 33, "Счет Черных должен стать 33 (36 - 3)")
	assert(last_seismic.get("intensity", 0.0) >= 0.40, "Слон должен вызывать сейсмический подземный толчок (intensity >= 0.40)")
	print("[PASS] Тест 4: Потеря Черного Слона (3 очка, подземный толчок intensity=%.2f, перехват: %s)" % [last_seismic.get("intensity", 0.0), player._radio_subtitle_label.text])
	bus.seismic_shock_triggered.disconnect(seismic_cb)
	
	# --------------------------------------------------------------------------
	# ТЕСТ 5: Макро-стадия I — Дыхание фронта (Счет Черных <= 30)
	# --------------------------------------------------------------------------
	bus.piece_captured.emit("pawn", false) # 33 -> 32
	bus.piece_captured.emit("pawn", false) # 32 -> 31
	assert(bus.outside_stage == 0, "При счете 31 стадия остается 0")
	
	bus.piece_captured.emit("pawn", false) # 31 -> 30 (порог Стадии I внешнего мира, и 6 потерь = Стадия II тревоги бункера)
	assert(bus.black_score == 30, "Счет Черных равен 30")
	assert(bus.outside_stage == 1, "Стадия внешнего мира перешла в 1 (Дыхание фронта)")
	assert(bus.current_stage == 2, "Бункер перешел на Стадию 2 тревоги (total_losses >= 4)")
	assert(outside_ctrl._outside_ambient_player.playing == true, "Фоновый рокот далекой канонады должен звучать")
	assert(outside_ctrl._is_siren_loop_active == true, "Сирена на 2 стадии тревоги успешно активирована")
	print("[PASS] Тест 5: Макро-стадия I достигнута (30 очков, фоновый рокот фронта, сирена тревоги)")
	
	# --------------------------------------------------------------------------
	# ТЕСТ 6: Микро-событие — Потеря Черной Ладьи (5 очков, мощный boom_3.ogg)
	# --------------------------------------------------------------------------
	bus.piece_captured.emit("rook", false)
	assert(bus.black_score == 25, "Счет Черных стал 25 (30 - 5)")
	assert(outside_ctrl._outside_sfx_player.stream == OutsideWarController.SOUND_BOOMS[2], "SFX плеер должен воспроизвести boom_3.ogg")
	assert(player._trauma >= 0.5, "Мощное сотрясение комнаты от взрыва укрепления (trauma >= 0.5)")
	print("[PASS] Тест 6: Потеря Черной Ладьи (5 очков, взрыв boom_3.ogg, сотрясение бронедвери, перехват: %s)" % player._radio_subtitle_label.text)
	
	# --------------------------------------------------------------------------
	# ТЕСТ 7: Макро-стадия II — Запуск бесконечного цикла сирен (Счет Черных <= 20)
	# --------------------------------------------------------------------------
	bus.piece_captured.emit("rook", false) # 25 -> 20 (порог Стадии II!)
	assert(bus.black_score == 20, "Счет Черных равен 20")
	assert(bus.outside_stage == 2, "Стадия внешнего мира перешла в 2 (Сирены)")
	assert(outside_ctrl._is_siren_loop_active == true, "Бесконечный цикл сирен успешно активирован на 2 этапе")
	assert(outside_ctrl._siren_player != null and outside_ctrl._siren_player.stream == OutsideWarController.SOUND_SIREN, "Сирена siren.ogg загружена в плеер")
	assert(outside_ctrl._siren_player.playing == true, "Сирена вдалеке начала играть")
	assert(outside_ctrl._siren_interval == 15.0, "Интервал между сиренами равен ровно 15 секундам")
	
	# Эмулируем завершение сирены для проверки запуска 15-секундного таймера
	outside_ctrl._on_siren_finished()
	assert(outside_ctrl._siren_delay_timer != null, "15-секундный таймер паузы перед следующей сиреной успешно создан")
	print("[PASS] Тест 7: Макро-стадия II (20 очков, сирена вдалеке запущена, цикл: сирена -> пауза 15с -> сирена)")
	
	# --------------------------------------------------------------------------
	# ТЕСТ 8: Микро-событие — Потеря Черного Ферзя (10 очков — Стратегический удар)
	# --------------------------------------------------------------------------
	bus.piece_captured.emit("queen", false)
	assert(bus.black_score == 10, "Счет Черных стал 10 (20 - 10)")
	assert(bus.is_lamp_trouble_active == false, "Взятие Черного Ферзя НЕ гасит свет в бункере (он снаружи!)")
	assert(player._radio_subtitle_label.text.find("СТРАТЕГИЧЕСКИМ УДАРОМ") != -1 or player._radio_subtitle_label.text.find("ГЛАВНЫЙ БУНКЕР") != -1 or player._radio_subtitle_label.text.find("паника в эфире") != -1 or player._radio_subtitle_label.text.find("ГЕНЕРАЛЬНЫЙ ШТАБ") != -1, "Радио-перехват катастрофы врага: %s" % player._radio_subtitle_label.text)
	print("[PASS] Тест 8: Потеря Черного Ферзя (10 очков, стратегический удар boom_3.ogg, свет в комнате стабилен, перехват: %s)" % player._radio_subtitle_label.text)
	
	# --------------------------------------------------------------------------
	# ТЕСТ 9: Макро-стадия III — Радиомолчание судного дня (Счет Черных <= 10)
	# --------------------------------------------------------------------------
	assert(bus.outside_stage == 3, "Стадия внешнего мира перешла в 3 (Радиомолчание судного дня)")
	assert(outside_ctrl._radio_buzzer_player.playing == true, "В радио на столе включился монотонный зуммер номерной станции УВБ-76")
	print("[PASS] Тест 9: Макро-стадия III достигнута (10 очков, ураганный ветер, зуммер радио)")
	
	# --------------------------------------------------------------------------
	# ТЕСТ 10: Макро-стадия IV — Мертвая пустыня (Счет Черных <= 3 очков)
	# --------------------------------------------------------------------------
	bus.piece_captured.emit("knight", false) # 10 -> 7
	bus.piece_captured.emit("bishop", false) # 7 -> 4
	bus.piece_captured.emit("pawn", false)   # 4 -> 3 (порог Стадии IV — Черный Король один!)
	
	assert(bus.black_score == 3, "У Черных осталось ровно 3 очка")
	assert(bus.outside_stage == 4, "Стадия внешнего мира перешла в 4 (Мертвая пустыня)")
	assert(outside_ctrl._is_siren_loop_active == false, "Цикл сирен полностью остановлен на Стадии IV")
	assert(outside_ctrl._siren_player.playing == false, "Плеер сирены остановлен")
	assert(outside_ctrl._outside_ambient_player.playing == false, "Наружный плеер эмбиента остановлен")
	assert(outside_ctrl._radio_buzzer_player.playing == false, "Радио-зуммер остановлен")
	assert(player._radio_subtitle_label.text.find("мертвая тишина") != -1 or player._radio_subtitle_label.text.find("некому выходить") != -1, "Финальный радио-перехват тишины: %s" % player._radio_subtitle_label.text)
	print("[PASS] Тест 10: Макро-стадия IV достигнута (3 очка, Мертвая пустыня: сирены и звуки затихли, полная тишина)")
	
	# --------------------------------------------------------------------------
	# ТЕСТ 11: Уникальность радиоперехватов эфира врага (строки не повторяются)
	# --------------------------------------------------------------------------
	player._unused_radio_reports_black["pawn"] = []
	var seen_intercepts: Dictionary = {}
	for i in range(5):
		player.show_enemy_radio_intercept("pawn")
		var line: String = player._radio_subtitle_label.text
		assert(line.begins_with("«(Перехват)"), "Каждая строка должна быть перехватом: %s" % line)
		assert(not seen_intercepts.has(line), "Перехват пешки не должен повторяться подряд: %s" % line)
		seen_intercepts[line] = true
	print("[PASS] Тест 11: Ротация уникальных перехватов эфира врага без повторений (5 разных перехватов)")
	
	# --------------------------------------------------------------------------
	# ТЕСТ 12: Сброс состояния игры (game_reset)
	# --------------------------------------------------------------------------
	bus.reset_game_state(2)
	assert(bus.black_score == 40, "Счет Черных сброшен до 40")
	assert(bus.outside_stage == 0, "Стадия сброшена до 0")
	assert(outside_ctrl._is_siren_loop_active == false, "Цикл сирен сброшен в false")
	print("[PASS] Тест 12: Сброс состояния игры через reset_game_state")
	
	room.free()
	print("--- [Black Loss Events Test Suite] ВСЕ ТЕСТЫ УСПЕШНО ПРОЙДЕНЫ! ---")
	quit(0)
