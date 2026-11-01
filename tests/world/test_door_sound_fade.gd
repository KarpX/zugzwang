extends SceneTree

## Автоматический тест затухания звуков двери бункера в живом дереве сцены (Door Audio Fade)

const EndingManagerScript = preload("res://scripts/world/ending_manager.gd")

func _init() -> void:
	_run_tests.call_deferred()

func _run_tests() -> void:
	print("--- [Door Sound Fade Test] Тестирование плавного затухания звуков двери ---")
	
	# 1. Инициализация EventBus
	var bus = root.get_node_or_null("EventBus")
	if bus == null:
		var bus_script = load("res://scripts/event_bus.gd")
		bus = bus_script.new()
		bus.name = "EventBus"
		root.add_child(bus)
		
	var manager = EndingManagerScript.new()
	root.add_child(manager)
	
	var door_pivot = Node3D.new()
	door_pivot.name = "DoorPivot"
	root.add_child(door_pivot)
	manager.door_pivot = door_pivot
	
	var door = Node3D.new()
	door.name = "Door"
	door_pivot.add_child(door)
	manager.door_node = door
	
	await process_frame
	
	assert(manager.is_inside_tree() == true, "EndingManager должен быть внутри дерева сцены")
	assert(door.is_inside_tree() == true, "Door должен быть внутри дерева сцены")
	
	# ТЕСТ 1: Проверка создания и прикрепления выделенного _door_audio_player к door_node
	manager._setup_door_audio_player()
	assert(manager._door_audio_player != null, "Плеер двери _door_audio_player должен быть создан")
	assert(manager._door_audio_player.get_parent() == door, "_door_audio_player должен быть прикреплен строго к door_node")
	assert(manager._door_audio_player.bus == &"Sound", "_door_audio_player должен быть назначен на Sound шину")
	print("[PASS] Тест 1: _door_audio_player успешно прикреплен к door_node на шине Sound")
	
	# ТЕСТ 2: Распахивание двери (White Victory)
	manager._play_white_victory()
	assert(manager._door_audio_player.stream != null, "Стрим открывания двери должен быть назначен")
	assert(manager._door_audio_player.stream.resource_path.ends_with("door_open.ogg"), "Должен воспроизводиться door_open.ogg")
	assert(manager._door_audio_player.volume_db == -5.0, "Громкость старта должна быть -5.0 dB")
	assert(manager._door_audio_tween != null and manager._door_audio_tween.is_valid(), "Должен быть создан активный Tween затухания")
	print("[PASS] Тест 2: door_open.ogg играет на -5.0 dB и активен tween затухания")
	
	# ТЕСТ 3: Игрок входит в секретную комнату раньше времени -> затухание 0.35с
	var fake_player = CharacterBody3D.new()
	fake_player.add_to_group("player")
	root.add_child(fake_player)
	
	manager._on_secret_room_body_entered(fake_player)
	assert(manager._door_audio_tween != null and manager._door_audio_tween.is_valid(), "Tween затухания за 0.35с перед захлопыванием должен быть активен")
	print("[PASS] Тест 3: Предыдущий звук открывания плавно затухает за 0.35с при входе в секретную комнату")
	
	# ТЕСТ 4: Захлопывание двери -> грохот door_closed.ogg и мягкое затухание хвоста (0.5с)
	manager._on_secret_door_closed()
	assert(manager._door_audio_player.stream != null, "Стрим захлопывания должен быть назначен")
	assert(manager._door_audio_player.stream.resource_path.ends_with("door_closed.ogg"), "Должен воспроизводиться door_closed.ogg")
	assert(manager._door_audio_player.volume_db == 10.0, "Стартовая громкость захлопывания должна быть 10.0 dB")
	assert(manager._door_audio_tween != null and manager._door_audio_tween.is_valid(), "Tween мягкого затухания хвоста захлопывания должен быть активен")
	print("[PASS] Тест 4: door_closed.ogg играет на 10.0 dB и мягко затухает через tween")
	
	# ТЕСТ 5: Сброс комнаты -> очистка звуков и твинов
	manager.restore_room_to_initial()
	assert(manager._door_audio_player.playing == false, "Плеер двери должен быть остановлен при сбросе")
	assert(manager._door_audio_tween == null or not manager._door_audio_tween.is_valid(), "Tween двери должен быть аннулирован")
	print("[PASS] Тест 5: Восстановление комнаты корректно останавливает плеер и твины двери")
	
	fake_player.queue_free()
	door.queue_free()
	door_pivot.queue_free()
	manager.queue_free()
	
	print("--- [Door Sound Fade Test] ВСЕ ТЕСТЫ УСПЕШНО ПРОЙДЕНЫ! ---")
	quit(0)
