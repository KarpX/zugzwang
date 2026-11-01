extends SceneTree

func _init() -> void:
	print("--- [IntroDisclaimerOverlay Test] Запуск теста дисклеймера и описания дел ---")

	var bus_script = load("res://scripts/event_bus.gd")
	assert(bus_script != null, "event_bus.gd должен загружаться")
	var bus = bus_script.new()
	bus.name = "EventBus"
	root.add_child(bus)
	bus._ready()

	var overlay_script = load("res://scripts/ui/intro_disclaimer_overlay.gd")
	assert(overlay_script != null, "intro_disclaimer_overlay.gd должен успешно загружаться")

	var overlay = overlay_script.new()
	assert(overlay != null, "Экземпляр IntroDisclaimerOverlay должен создаваться")
	assert(overlay.layer == 40, "Слой оверлея должен быть 40 (поверх всего)")

	# Не вызываем таймеры во время headless unit-теста
	overlay.auto_advance_delay = 999.0
	root.add_child(overlay)

	# Тест 1: Проверка сигналов и флага EventBus
	assert(bus.is_intro_active == true, "EventBus.is_intro_active должен быть true во время заставки")
	print("[PASS] Тест 1: EventBus.is_intro_active корректно установлен в true")

	# Тест 2: Проверка содержимого стадии ДИСКЛЕЙМЕР
	assert(overlay.current_stage == 0, "Начальная стадия должна быть 0 (DISCLAIMER)")
	var body_label = overlay.find_child("BodyLabel", true, false) as Label
	var category_label = overlay.find_child("CategoryLabel", true, false) as Label
	assert(body_label != null, "BodyLabel должен присутствовать")
	assert(category_label != null, "CategoryLabel должен присутствовать")
	assert(category_label.text.contains("ДИСКЛЕЙМЕР"), "Заголовок должен содержать ДИСКЛЕЙМЕР")
	assert(body_label.text.contains("Все действия выдуманы и не связаны с реальностью"), "Текст должен содержать дисклеймер")
	assert(body_label.text.contains("Любые совпадения случайны"), "Текст должен содержать фразу о совпадениях")
	print("[PASS] Тест 2: Текст дисклеймера корректно отображается")

	# Тест 3: Переход на стадию ОПИСАНИЕ ДЕЛ (Брифинг)
	overlay.current_stage = 1
	overlay._show_stage(1)
	assert(overlay.current_stage == 1, "Стадия должна быть 1 (BRIEFING)")
	assert(category_label.text.contains("ОПИСАНИЕ"), "Заголовок должен содержать ОПИСАНИЕ ДЕЛ")
	assert(body_label.text.contains("Вы – генерал-майор подразделения N"), "Текст должен содержать звание и подразделение")
	assert(body_label.text.contains("Вам необходимо выиграть сражение"), "Текст должен содержать приказ")
	print("[PASS] Тест 3: Текст описания дел корректно отображается")

	# Тест 4: Завершение заставки и восстановление состояния
	overlay._notify_bus_finished()
	assert(bus.is_intro_active == false, "EventBus.is_intro_active должен стать false после завершения")
	print("[PASS] Тест 4: Завершение заставки сбрасывает is_intro_active в false")

	overlay.queue_free()
	bus.queue_free()
	print("--- [IntroDisclaimerOverlay Test] ВСЕ ТЕСТЫ УСПЕШНО ПРОЙДЕНЫ ---")
	quit(0)
