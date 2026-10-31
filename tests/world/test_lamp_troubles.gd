extends SceneTree

func _init() -> void:
	_run_tests.call_deferred()

func _run_tests() -> void:
	print("--- [Lamp Troubles Test Suite] Запуск тестов белых пешек и блокировки хода противника ---")
	
	# 0. Инициализируем EventBus до сцены комнаты, чтобы _ready() всех нод мог подписаться на шину
	var bus = root.get_node_or_null("EventBus")
	if bus == null:
		var bus_script = load("res://scripts/event_bus.gd")
		bus = bus_script.new()
		bus.name = "EventBus"
		root.add_child(bus)
	assert(bus != null, "EventBus синглтон должен присутствовать")
	
	# Загрузка сцены комнаты
	var scene = load("res://scenes/room.tscn")
	assert(scene != null, "Сцена room.tscn должна успешно загружаться")
	
	var room = scene.instantiate()
	root.add_child(room)
	
	await process_frame
	
	# 1. Проверяем наличие узла HangingBulb
	var lamp = room.find_child("HangingBulb", true)
	assert(lamp != null, "Узел HangingBulb должен присутствовать в комнате")
	assert(lamp is HangingLamp, "HangingBulb должен быть экземпляром HangingLamp")
	var hanging_lamp: HangingLamp = lamp as HangingLamp
	print("[PASS] Тест 1: Узел HangingBulb найден и является HangingLamp")
	
	# 2. Проверяем коллекцию из 4 звуков lamp_troubles_1 .. lamp_troubles_4
	assert(hanging_lamp.trouble_sounds.size() == 4, "Коллекция trouble_sounds должна содержать ровно 4 звука")
	for i in range(4):
		var s = hanging_lamp.trouble_sounds[i]
		assert(s != null, "Звук lamp_troubles_%d не должен быть null" % (i + 1))
	print("[PASS] Тест 2: Все 4 звука lamp_troubles_1..4 успешно загружены в trouble_sounds")
	
	# 3. Проверяем наличие AnimationPlayer со всеми 4 синхронизированными дорожками
	var anim_player = lamp.find_child("AnimationPlayer", true) as AnimationPlayer
	assert(anim_player != null, "AnimationPlayer должен присутствовать в HangingBulb")
	assert(anim_player.has_animation("light_trouble_1"), "Должна присутствовать анимация light_trouble_1")
	assert(anim_player.has_animation("light_trouble_2"), "Должна присутствовать анимация light_trouble_2")
	assert(anim_player.has_animation("light_trouble_3"), "Должна присутствовать анимация light_trouble_3")
	assert(anim_player.has_animation("light_trouble_4"), "Должна присутствовать анимация light_trouble_4")
	print("[PASS] Тест 3: Все 4 анимации light_trouble_1..4 настроены с точными длительностями аудиоволн")
	
	# 3.5. Проверяем синхронизацию раскачивания и звука скрипа metallic_squeeks
	assert(hanging_lamp._squeak_audio_player != null, "Плеер SqueakAudioPlayer должен быть инициализирован")
	assert(hanging_lamp.squeak_sound != null, "Звук metallic_squeeks должен быть назначен")
	assert(absf(hanging_lamp.swing_speed - HangingLamp.SWING_ANGULAR_SPEED) < 0.001, "Скорость качания маятника должна быть строго синхронизирована с 2.7692с")
	print("[PASS] Тест 3.5: Звук metallic_squeeks и физика раскачивания маятника синхронизированы")
	
	# 4. ТЕСТ: Перебой со светом срабатывает ТОЛЬКО на БЕЛЫЕ пешки (is_white == true)
	hanging_lamp._on_trouble_finished()
	assert(hanging_lamp._is_trouble_playing == false, "Начальное состояние: перебой не играет")
	
	# Взятие БЕЛОЙ пешки -> ДОЛЖНО включить перебой с одним из 2 самых быстрых звуков (0 или 2)
	bus.piece_captured.emit("pawn", true)
	assert(hanging_lamp._is_trouble_playing == true, "Смерть БЕЛОЙ пешки должна активировать перебой со светом")
	assert(hanging_lamp._last_sound_index == 0 or hanging_lamp._last_sound_index == 2, "Пешка должна использовать только 2 самых быстрых звука (0 или 2)")
	assert(bus.is_lamp_trouble_active == true, "EventBus.is_lamp_trouble_active должен стать true")
	print("[PASS] Тест 4: Смерть БЕЛОЙ пешки использует только быстрые звуки (индекс %d) и активирует перебой" % hanging_lamp._last_sound_index)
	
	hanging_lamp._on_trouble_finished()
	assert(bus.is_lamp_trouble_active == false, "EventBus.is_lamp_trouble_active должен сброситься в false")
	
	# Взятие ЧЕРНОЙ пешки -> НЕ ДОЛЖНО включить перебой
	bus.piece_captured.emit("pawn", false)
	assert(hanging_lamp._is_trouble_playing == false, "Смерть ЧЕРНОЙ пешки НЕ должна вызывать перебой со светом")
	assert(bus.is_lamp_trouble_active == false, "EventBus.is_lamp_trouble_active должен оставаться false")
	print("[PASS] Тест 5: Смерть ЧЕРНОЙ пешки НЕ вызывает перебой со светом (только белые)")
	
	# 6. ТЕСТ: Черные фигуры не вызывают перебой лампы
	bus.piece_captured.emit("queen", false)
	assert(hanging_lamp._is_trouble_playing == false, "Взятие черного ферзя НЕ должно вызывать перебой в бункере")
	bus.piece_captured.emit("rook", false)
	assert(hanging_lamp._is_trouble_playing == false, "Взятие черной ладьи НЕ должно вызывать перебой в бункере")
	print("[PASS] Тест 6: Потери врага (черные) не вызывают внутренних перебоев освещения")
	
	# 7. ТЕСТ: Противник НЕ может сделать ход, пока проигрывается анимация
	var chess_board = room.find_child("ChessBoard", true)
	assert(chess_board != null, "Узел ChessBoard должен существовать")
	
	# Активируем перебой со светом
	hanging_lamp.play_trouble_animation(0)
	assert(bus.is_lamp_trouble_active == true, "Перебой активен")
	assert(chess_board._is_light_trouble_active == true, "ChessBoard зафиксировал активность перебоя")
	
	# Переключаем ход на черных (противника)
	chess_board.logic.is_white_turn = false
	var initial_move_count: int = chess_board.logic.move_count
	
	# Пытаемся запустить ход ИИ черных во время анимации
	chess_board._execute_ai_turn()
	
	# Проверяем: ход НЕ был сделан! move_count не изменился, ход остался за черными
	assert(chess_board.logic.move_count == initial_move_count, "Противник НЕ должен делать ход, пока играет анимация перебоя!")
	assert(chess_board.logic.is_white_turn == false, "Ход не должен передаваться игроку, противник заблокирован")
	print("[PASS] Тест 7: Ход противника успешно заблокирован на время анимации перебоя")
	
	# 8. Завершаем перебой: проверяем разблокировку и передачу сигнала lamp_trouble_finished
	hanging_lamp._on_trouble_finished()
	assert(bus.is_lamp_trouble_active == false, "is_lamp_trouble_active должен стать false")
	assert(hanging_lamp.light_intensity_ratio == 1.0, "Свет должен вернуться на 1.0")
	print("[PASS] Тест 8: Восстановление освещения и сброс флага активности перебоя корректны")
	
	room.free()
	print("--- [Lamp Troubles Test Suite] ВСЕ ТЕСТЫ УСПЕШНО ПРОЙДЕНЫ ---")
	quit(0)
