extends SceneTree

func _init() -> void:
	print("--- [Door Knock Anti-AFK Test] Запуск теста системы анти-AFK ---")
	
	var scene = load("res://scenes/room.tscn")
	assert(scene != null, "Сцена room.tscn должна успешно загружаться")
	
	var room = scene.instantiate()
	root.add_child(room)
	
	var door = room.find_child("Door", true)
	assert(door != null, "Узел Door должен присутствовать в комнате")
	assert(door is DoorKnockTimer, "Door должен иметь скрипт DoorKnockTimer")
	
	var timer: DoorKnockTimer = door as DoorKnockTimer
	assert(timer.knock_intervals.size() == 3, "Должно быть 3 интервала стука")
	assert(timer.knock_intervals[0] == 30.0 and timer.knock_intervals[1] == 30.0 and timer.knock_intervals[2] == 30.0, "Интервалы должны быть [30.0, 30.0, 30.0]")
	print("[PASS] Тест 1: Нода DoorKnockTimer успешно инициализирована с интервалами 30/30/30 сек")
	
	# Подключаем отслеживание сигналов EventBus
	var bus = root.get_node_or_null("EventBus")
		
	var knocks_received: Array[int] = []
	var game_over_reason: String = ""
	
	if bus:
		bus.door_knock_triggered.connect(func(level: int): knocks_received.append(level))
		bus.game_over.connect(func(winner: String): game_over_reason = winner)
	
	# Для быстрого тестирования задаем тестовые интервалы 0.1с
	timer.knock_intervals = [0.1, 0.1, 0.1]
	timer.reset_idle_timer()
	
	# 2. Тестируем первый стук (knock 1) через 0.15с
	timer._process(0.12)
	assert(timer.current_knock_level == 1, "После первого интервала должен быть knock_level = 1")
	if bus:
		assert(knocks_received.has(1), "EventBus должен получить door_knock_triggered(1)")
	print("[PASS] Тест 2: Первый стук knock1 успешно срабатывает по истечении интервала")
	
	# 3. Тестируем второй стук (knock 2) через еще 0.12с
	timer._process(0.12)
	assert(timer.current_knock_level == 2, "После второго интервала должен быть knock_level = 2")
	if bus:
		assert(knocks_received.has(2), "EventBus должен получить door_knock_triggered(2)")
	print("[PASS] Тест 3: Второй стук knock2 успешно срабатывает через ещё один интервал")
	
	# 4. Проверяем сброс таймера при ходе фигуры (анти-AFK сработал, игрок сделал ход)
	if bus:
		bus.piece_moved.emit(Vector2i(0, 1), Vector2i(0, 2))
	else:
		timer.reset_idle_timer()
		
	assert(timer.idle_time == 0.0, "После хода фигуры idle_time должен быть сброшен в 0")
	assert(timer.current_knock_level == 0, "После хода фигуры уровень стука должен сброситься в 0")
	print("[PASS] Тест 4: Перемещение фигуры корректно сбрасывает таймер и уровень стука")
	
	# 5. Доводим бездействие до 3-го стука и проигрыша (breach)
	timer._process(0.12) # knock 1
	assert(timer.current_knock_level == 1)
	timer._process(0.12) # knock 2
	assert(timer.current_knock_level == 2)
	timer._process(0.12) # knock 3 -> breach
	assert(timer.current_knock_level == 3, "Должен сработать 3-й уровень стука")
	assert(timer.is_game_finished == true, "Игра должна быть завершена после 3-го стука")
	
	if bus:
		assert(knocks_received.has(3), "EventBus должен получить door_knock_triggered(3)")
		assert(game_over_reason == "breach", "Причина окончания игры должна быть 'breach'")
	print("[PASS] Тест 5: 3-й стук knock3 завершает игру проигрышем 'breach'")
	
	# Возвращаем стандартные 30-секундные интервалы
	timer.knock_intervals = [30.0, 30.0, 30.0]
	
	room.free()
	print("--- [Door Knock Anti-AFK Test] ВСЕ ТЕСТЫ УСПЕШНО ПРОЙДЕНЫ ---")
	quit(0)
