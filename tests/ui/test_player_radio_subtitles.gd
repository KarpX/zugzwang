extends SceneTree

# Тест-сьют: Проверка UI радио-субтитров игрока, флага EventBus.is_radio_text_visible и свечения шкалы
func _init() -> void:
	print("--- [Player Radio Subtitles Test Suite] Запуск тестов ---")
	_run_tests.call_deferred()

func _run_tests() -> void:
	var bus_node = root.get_node_or_null("EventBus")
	if bus_node == null:
		var bus_script = load("res://scripts/event_bus.gd")
		bus_node = bus_script.new()
		bus_node.name = "EventBus"
		root.add_child(bus_node)
	assert(bus_node != null, "EventBus должен существовать")

	var room_scene = load("res://scenes/room.tscn")
	assert(room_scene != null, "Сцена room.tscn должна существовать")

	var room = room_scene.instantiate()
	root.add_child(room)
	await process_frame

	var player = room.find_child("player", true)
	assert(player != null, "Player должен присутствовать в комнате")
	assert(player._radio_subtitle_label != null, "Субтитры игрока должны быть настроены")

	var radio = room.find_child("Radio", true) as RadioController
	assert(radio != null, "RadioController должен присутствовать на столе")

	# ТЕСТ 1: Базовое свечение шкалы радио равно 0.20
	assert(is_equal_approx(radio.dial_glow.light_energy, 0.20), "Базовое свечение шкалы DialGlow должно быть 0.20")
	print("[PASS] Тест 1: Базовое фоновое свечение шкалы DialGlow = 0.20")

	# ТЕСТ 2: Запуск субтитров устанавливает EventBus.is_radio_text_visible = true
	assert(bus_node.is_radio_text_visible == false, "Изначально is_radio_text_visible должен быть false")
	player._start_subtitle_animation("«Внимание, потеряна радиосвязь!»", 1.5)
	assert(bus_node.is_radio_text_visible == true, "После начала анимации субтитров is_radio_text_visible должен стать true!")
	assert(player._radio_subtitle_label.text == "«Внимание, потеряна радиосвязь!»", "Текст субтитров должен быть установлен")
	print("[PASS] Тест 2: EventBus.is_radio_text_visible = true при начале радиопередачи")

	# ТЕСТ 3: По завершении вырисовывания текста (1.5с) флаг немедленно сбрасывается в false,
	# даже пока текст всё ещё остаётся видимым на экране (2.5с для чтения)
	var captured: Dictionary = {"received": false}
	var actual_bus = player._get_event_bus()
	var on_finish = func(): captured["received"] = true
	actual_bus.radio_transmission_finished.connect(on_finish)

	# Шагаем ровно до момента окончания печати текста (1.5с)
	if player._radio_tween and player._radio_tween.is_valid():
		player._radio_tween.custom_step(1.55)

	assert(bus_node.is_radio_text_visible == false, "Сразу после вырисовывания текста is_radio_text_visible должен стать false!")
	assert(captured["received"] == true, "Сигнал radio_transmission_finished должен быть отправлен сразу после печати!")
	assert(player._radio_subtitle_label.modulate.a > 0.5, "Текст должен всё ещё оставаться видимым для чтения на экране!")
	print("[PASS] Тест 3: Ходы разрешены сразу как текст перестал вырисовываться, пока он виден на экране")

	# ТЕСТ 4: Сброс игры (_on_game_reset) гарантирует скрытие текста и сброс флага
	bus_node.radio_transmission_finished.disconnect(on_finish)
	player._start_subtitle_animation("«Тестовая фраза для сброса»", 2.0)
	assert(bus_node.is_radio_text_visible == true, "Флаг стал true во время фразы")

	player._on_game_reset(1)
	assert(bus_node.is_radio_text_visible == false, "После _on_game_reset флаг is_radio_text_visible должен быть false!")
	assert(player._radio_subtitle_label.text == "", "Текст субтитров должен быть очищен")
	assert(player._radio_subtitle_label.modulate.a == 0.0, "Текст субтитров должен быть полностью прозрачным")
	print("[PASS] Тест 4: _on_game_reset() гарантированно скрывает текст и сбрасывает флаг в false")

	# ТЕСТ 5: Свечение шкалы радио при stop_radio() возвращается к 0.20
	radio.play_phrase("«Приказ номер 144»", true)
	assert(radio.dial_glow.light_energy >= 0.20, "Свет должен усилиться")
	radio.stop_radio(true)
	assert(is_equal_approx(radio.dial_glow.light_energy, 0.20), "После stop_radio(true) DialGlow должен вернуться к 0.20")
	print("[PASS] Тест 5: stop_radio() возвращает свечение DialGlow к _base_glow_energy = 0.20")

	room.free()
	print("--- [Player Radio Subtitles Test Suite] ВСЕ ТЕСТЫ УСПЕШНО ПРОЙДЕНЫ ---")
	quit(0)
