extends SceneTree

# Простой headless тест-раннер для проверки EventBus и базовой логики
func _init() -> void:
	print("--- [Zugzwang Test Suite] Запуск тестов ---")
	
	var bus_script = load("res://scripts/event_bus.gd")
	if not bus_script:
		printerr("[FAIL] Не удалось загрузить res://scripts/event_bus.gd")
		quit(1)
		return
		
	var bus = bus_script.new()
	bus._ready()
	
	# Тест 1: Начальное состояние
	assert(bus.total_losses == 0, "total_losses должен быть 0 при старте")
	assert(bus.current_stage == 1, "current_stage должен быть 1 при старте")
	print("[PASS] Тест 1: Начальное состояние EventBus корректно")
	
	# Тест 2: Эскалация при потерях фигур
	var captured_count: int = 0
	bus.piece_captured.connect(func(_type, _is_white): captured_count += 1)
	
	# Эмулируем 4 взятия (переход на стадию 2)
	for i in range(4):
		bus.piece_captured.emit("pawn", true)
		
	assert(bus.total_losses == 4, "total_losses должен быть равен 4")
	assert(bus.current_stage == 2, "current_stage должен перейти на 2 (Тревога)")
	print("[PASS] Тест 2: Эскалация потерь и смена стадии на 2 (Тревога)")
	
	# Эмулируем взятия до стадии 4 (12 потерь)
	for i in range(8):
		bus.piece_captured.emit("pawn", false)
		
	assert(bus.total_losses == 12, "total_losses должен быть равен 12")
	assert(bus.current_stage == 4, "current_stage должен перейти на 4 (Коллапс)")
	print("[PASS] Тест 3: Эскалация до стадии 4 (Коллапс)")
	
	# Тест 4: Сброс состояния
	bus.reset_game_state()
	assert(bus.total_losses == 0 and bus.current_stage == 1, "reset_game_state должен сбросить всё в 0")
	print("[PASS] Тест 4: Сброс состояния reset_game_state")
	
	bus.free()
	print("--- [Zugzwang Test Suite] ВСЕ ТЕСТЫ УСПЕШНО ПРОЙДЕНЫ ---")
	quit(0)

