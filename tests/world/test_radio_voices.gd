extends SceneTree

func _init() -> void:
	_run_tests.call_deferred()

func _run_tests() -> void:
	print("--- [Radio Sound Test Suite] Тестирование шума радио (radio_sound.ogg) строго во время анимации текста ---")

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

	# 2. Поиск нод Radio и Player
	var radio = room.find_child("Radio", true) as RadioController
	assert(radio != null, "Нода Radio должна иметь скрипт RadioController")

	var player = room.find_child("player", true)
	assert(player != null, "Player должен присутствовать в сцене")
	assert(player._radio_subtitle_label != null, "У игрока должен быть инициализирован _radio_subtitle_label")

	# ТЕСТ 1: Загрузка звука radio_sound.ogg
	var stream: AudioStream = radio.get_radio_stream()
	assert(stream != null, "Поток radio_sound.ogg должен быть успешно загружен")
	assert(stream.get_length() > 5.0, "Длина radio_sound.ogg должна быть > 5.0 секунд (фактическая: %.2fс)" % stream.get_length())
	print("[PASS] Тест 1: Звук radio_sound.ogg успешно загружен (длительность: %.2fс)" % stream.get_length())

	# ТЕСТ 2: Расчет длительности анимации текста (печать символов)
	var short_phrase: String = "«Окоп 14 засыпан землей.»" # 25 знаков
	var long_phrase: String = "«ГЕНЕРАЛЬНЫЙ ШТАБ ПРОТИВНИКА СТЕРТ С ЛИЦА ЗЕМЛИ! У НИХ ПОЛНЫЙ ХАОС И ПАНИКА В ЭФИРЕ!»" # 85 знаков

	var short_anim: float = radio.calculate_text_anim_duration(short_phrase)
	var long_anim: float = radio.calculate_text_anim_duration(long_phrase)

	assert(short_anim >= 1.4 and short_anim <= 2.2, "Короткая фраза анимируется ~1.4-2.2с (получено: %.2fс)" % short_anim)
	assert(long_anim >= 2.6 and long_anim <= 3.3, "Длинная фраза анимируется ~2.6-3.3с (получено: %.2fс)" % long_anim)
	assert(long_anim > short_anim, "Длинная фраза печатается дольше короткой")
	print("[PASS] Тест 2: Длительность анимации текста: короткая = %.2fс, длинная = %.2fс" % [short_anim, long_anim])

	# ТЕСТ 3: Воспроизведение radio_sound на AudioStreamPlayer3D во время анимации
	var initial_glow: float = radio.dial_glow.light_energy
	var played_duration: float = radio.play_phrase("«Разведгруппа Сокол накрыта ударом!»", true)
	assert(played_duration >= 1.4, "Длительность проигрывания должна соответствовать анимации фразы")
	assert(radio.is_playing_radio() == true, "AudioStreamPlayer3D должен играть radio_sound во время анимации")
	assert(radio.audio_player.stream == stream, "AudioStreamPlayer3D должен проигрывать именно radio_sound.ogg")
	assert(radio.dial_glow.light_energy >= initial_glow, "DialGlow должен светиться во время анимации текста")
	print("[PASS] Тест 3: Воспроизведение radio_sound на столе и свечение шкалы активны во время анимации текста")

	# ТЕСТ 4: Остановка и синхронное затихание
	radio.stop_radio(true)
	assert(radio.is_playing_radio() == false, "Радио должно немедленно остановиться после stop_radio")
	assert(is_equal_approx(radio.dial_glow.light_energy, initial_glow), "Шкала должна вернуться к фоновой яркости")
	print("[PASS] Тест 4: Функция остановки radio корректно гасит звук и шкалу")

	# ТЕСТ 5: Интеграция с субтитрами через EventBus
	var captured_signal: Dictionary = {}
	var sub_started_cb = func(txt: String, strm: AudioStream, dur: float):
		captured_signal["text"] = txt
		captured_signal["stream"] = strm
		captured_signal["duration"] = dur
	bus.radio_transmission_started.connect(sub_started_cb)

	# Вызов сводки через игрока
	player.show_radio_report("pawn", true)
	assert(captured_signal.has("text"), "EventBus должен получить сигнал radio_transmission_started")
	assert(captured_signal["stream"] == stream, "В сигнале должен передаваться radio_sound stream")
	assert(player._radio_subtitle_label.text == captured_signal["text"], "Текст субтитра должен совпадать со сводкой")
	assert(player._radio_subtitle_label.modulate.a > 0.0, "Субтитр должен быть видимым")
	print("[PASS] Тест 5: Интеграция с субтитрами игрока через EventBus работает корректно")

	# ТЕСТ 6: Сообщение мертвой тишины не запускает звук
	radio.stop_radio(true)
	var silence_phrase: String = "« В радиоэфире мертвая тишина. Больше некому выходить на связь.»"
	radio.play_phrase(silence_phrase, false)
	assert(radio.is_playing_radio() == false, "При мертвой тишине шум радио играть не должен")
	print("[PASS] Тест 6: Мертвая тишина корректно оставляет эфир без звука")

	bus.radio_transmission_started.disconnect(sub_started_cb)
	room.free()
	print("--- [Radio Sound Test Suite] ВСЕ ТЕСТЫ УСПЕШНО ПРОЙДЕНЫ! ---")
	quit(0)
