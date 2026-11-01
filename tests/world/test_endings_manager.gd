extends SceneTree

## Автоматический тест 3 концовок игры «Белый Король» (EndingManager)

const EndingManagerScript = preload("res://scripts/world/ending_manager.gd")
const GunfireGenScript = preload("res://scripts/world/gunfire_audio_generator.gd")
const ObservationMonitorScript = preload("res://scripts/world/observation_monitor.gd")
const RestartQuoteOverlayScript = preload("res://scripts/ui/restart_quote_overlay.gd")
const DefeatScreenScript = preload("res://scripts/ui/defeat_screen.gd")

func _init() -> void:
	print("--- [TEST] Запуск test_endings_manager.gd ---")
	test_gunfire_audio_generator()
	test_eventbus_quotes()
	test_black_victory_flow()
	test_white_victory_flow()
	test_draw_ending_flow()
	test_restart_quote_overlay()
	test_mega_blood_puddle_and_abrupt_cut()
	test_black_victory_defeat_screen_abrupt_and_scene_restoration()
	test_camera_sound_stopped_and_premature_door_slam()
	test_terminal_proximity_and_gaze()
	test_door_audio_fade_and_player()
	print("--- [PASS] ВСЕ ТЕСТЫ КОНЦОВОК УСПЕШНО ПРОЙДЕНЫ! ---")
	quit(0)

func test_gunfire_audio_generator() -> void:
	print("Тест 1: Процедурный синтез выстрелов и очередей...")
	var single = GunfireGenScript.create_gunshot_sound(0.5)
	assert(single != null, "Одиночный выстрел должен создаваться")
	assert(single.data.size() > 0, "Данные PCM выстрела не должны быть пустыми")
	
	var burst = GunfireGenScript.create_burst_fire_sound(4, 0.08)
	assert(burst != null, "Автоматная очередь должна создаваться")
	assert(burst.data.size() > single.data.size(), "Очередь должна быть длиннее одиночного выстрела")
	print("✓ Тест 1 пройден")

func test_eventbus_quotes() -> void:
	print("Тест 2: Загадочные фразы EventBus...")
	var bus_script = load("res://scripts/event_bus.gd")
	var bus = bus_script.new()
	
	var q_def = bus.get_random_defeat_quote()
	assert(not q_def.is_empty(), "Цитата поражения не должна быть пустой")
	
	var q_draw = bus.get_random_draw_quote()
	assert(not q_draw.is_empty(), "Цитата пата не должна быть пустой")
	
	bus.restart_quote = q_def
	assert(bus.restart_quote == q_def, "restart_quote должна сохраняться в шине")
	bus.free()
	print("✓ Тест 2 пройден")

func test_black_victory_flow() -> void:
	print("Тест 3: Логика победы чёрных (Взрыв короля, блэкаут, камера)...")
	var root_node = get_root()
	var manager = EndingManagerScript.new()
	root_node.add_child(manager)
	
	# Создаем фиктивные ноды окружения
	var door_pivot = Node3D.new()
	door_pivot.name = "DoorPivot"
	manager.door_pivot = door_pivot
	root_node.add_child(door_pivot)
	
	var bulb = MeshInstance3D.new()
	bulb.name = "HangingBulb"
	bulb.set_script(load("res://scripts/hanging_lamp.gd"))
	var light = OmniLight3D.new()
	bulb.add_child(light)
	manager.hanging_bulb = bulb
	root_node.add_child(bulb)
	
	# Запуск финала чёрных
	manager._play_black_victory()
	assert(manager._is_ending_active == true, "Флаг _is_ending_active должен быть true")
	
	# Проверка восстановления комнаты и смены сложности ИИ
	var bus_script = load("res://scripts/event_bus.gd")
	var bus = bus_script.new()
	bus.name = "EventBus"
	bus.current_stage = 4
	root_node.add_child(bus)
	
	manager._fade_and_reload("defeat")
	assert(bus.player_losses == 1, "Счетчик поражений должен увеличиться")
	assert(bus.current_playthrough >= 2, "Сложность ИИ должна измениться (playthrough >= 2)")
	assert(bus.current_stage == 1, "Уровень тревоги должен сброситься на 1 (Затишье)")
	assert(not bus.restart_quote.is_empty(), "Цитата должна быть сгенерирована")
	
	bus.queue_free()
	manager.queue_free()
	door_pivot.queue_free()
	bulb.queue_free()
	print("✓ Тест 3 пройден")

func test_white_victory_flow() -> void:
	print("Тест 4: Логика победы белых (Открытие двери, ловушка)...")
	var root_node = get_root()
	var manager = EndingManagerScript.new()
	root_node.add_child(manager)
	
	var door_pivot = Node3D.new()
	door_pivot.name = "DoorPivot"
	manager.door_pivot = door_pivot
	root_node.add_child(door_pivot)
	
	var obs_scene = preload("res://scenes/world/observation_room.tscn")
	var obs_room = obs_scene.instantiate()
	manager.observation_room = obs_room
	root_node.add_child(obs_room)
	
	# 1. Победа белых открывает дверь
	manager._play_white_victory()
	assert(manager._is_ending_active == true, "Флаг _is_ending_active должен быть true")
	
	# 2. Симуляция входа игрока в секретную комнату
	var fake_player = CharacterBody3D.new()
	fake_player.add_to_group("player")
	root_node.add_child(fake_player)
	
	manager._on_secret_room_body_entered(fake_player)
	var blocker = obs_room.get_node_or_null("DoorBlocker") as StaticBody3D
	assert(blocker != null, "DoorBlocker должен присутствовать")
	assert(blocker.collision_layer == 1, "DoorBlocker должен активироваться на layer 1")
	
	# Музыка еще НЕ играет до нажатия [E]
	assert(manager._final_music_player == null, "FinalMusicPlayer не должен играть до нажатия [E]")
	
	# Монитор ждет нажатия [E]
	var monitor = obs_room.get_node_or_null("CRTMonitor") as ObservationMonitor
	assert(monitor != null, "CRTMonitor должен присутствовать")
	assert(monitor.is_awaiting_input == true, "Монитор должен ожидать нажатия [E]")
	
	# Игрок нажимает [E] -> запуск терминала и музыки
	monitor.start_terminal_sequence()
	assert(manager._final_music_player != null, "FinalMusicPlayer должен запуститься после старта терминала")
	assert(manager._final_music_player.stream != null, "Поток финальной музыки должен быть назначен")
	assert(manager._final_music_player.volume_db <= -10.0, "Музыка должна плавно начинаться с тишины (volume_db <= -10.0 при старте)")
	assert(monitor.is_terminal_running == true, "Флаг is_terminal_running должен быть true")
	
	fake_player.queue_free()
	obs_room.queue_free()
	door_pivot.queue_free()
	manager.queue_free()
	print("✓ Тест 4 пройден")

func test_draw_ending_flow() -> void:
	print("Тест 5: Логика пата (Стук, автоматная очередь, резкий черный экран, восстановление сцены)...")
	var root_node = get_root()
	
	# EventBus
	var existing_bus = root_node.get_node_or_null("EventBus")
	if existing_bus:
		existing_bus.free()
	var bus_script = load("res://scripts/event_bus.gd")
	var bus = bus_script.new()
	bus.name = "EventBus"
	bus.current_stage = 3
	root_node.add_child(bus)
	
	# Игрок
	var player = CharacterBody3D.new()
	player.set_script(load("res://scenes/player.gd"))
	var head = Node3D.new()
	head.name = "head"
	player.add_child(head)
	var cam = Camera3D.new()
	cam.name = "Camera3D"
	head.add_child(cam)
	root_node.add_child(player)
	player.is_board_mode = true
	player.can_walk = false
	player.can_move = false
	
	# Доска
	var board_scene = preload("res://scenes/chess/chess_board.tscn")
	var board_view = board_scene.instantiate()
	root_node.add_child(board_view)
	board_view.restart_game(1)
	
	var door_pivot = Node3D.new()
	door_pivot.name = "DoorPivot"
	root_node.add_child(door_pivot)
	
	var manager = EndingManagerScript.new()
	manager.player_node = player
	manager.chess_board_view = board_view
	manager.door_pivot = door_pivot
	root_node.add_child(manager)
	
	manager._play_draw_ending()
	assert(manager._is_ending_active == true, "Флаг _is_ending_active должен быть true")
	
	# Проверяем резкий черный экран пата
	manager._show_abrupt_draw_screen()
	var defeat_screen: DefeatScreen = null
	for child in manager.get_children():
		if child is DefeatScreen:
			defeat_screen = child
			break
			
	assert(defeat_screen != null, "DefeatScreen должен быть создан при пате")
	assert(defeat_screen.visible == true, "DefeatScreen должен быть виден")
	assert(defeat_screen._container.modulate.a == 1.0, "DefeatScreen должен мгновенно появиться с modulate.a = 1.0 (резко)")
	assert(defeat_screen._title_label.text == "П А Т", "Заголовок экрана при пате должен быть 'П А Т'")
	assert(bus.DRAW_QUOTES.has(defeat_screen._quote_label.text), "Цитата должна быть одной из DRAW_QUOTES")
	
	# Проверяем восстановление сцены под черным экраном
	assert(bus.current_stage == 1, "Стадия эскалации должна сброситься на 1")
	assert(player.is_board_mode == false, "Игрок должен выйти из режима стола")
	
	# Завершаем показ экрана
	defeat_screen._dismiss_screen()
	manager._finalize_player_control_after_defeat()
	assert(player.can_walk == true, "После пата и закрытия экрана игрок должен свободно ходить")
	assert(player.can_move == true, "После пата и закрытия экрана игрок должен свободно вращать камеру")
	assert(manager._is_ending_active == false, "Флаг концовки должен быть сброшен")
	
	door_pivot.queue_free()
	manager.queue_free()
	board_view.queue_free()
	player.queue_free()
	bus.queue_free()
	print("✓ Тест 5 пройден")

func test_restart_quote_overlay() -> void:
	print("Тест 6: Оверлей загадочной цитаты при перезапуске...")
	var overlay = RestartQuoteOverlayScript.new()
	overlay.display_quote("«Тестовая загадочная цитата»")
	
	assert(overlay.quote_label != null, "QuoteLabel должен создаться")
	assert(overlay.quote_label.text == "«Тестовая загадочная цитата»", "Текст цитаты должен совпадать")
	
	overlay.queue_free()
	print("✓ Тест 6 пройден")

func test_mega_blood_puddle_and_abrupt_cut() -> void:
	print("Тест 7: Проверка одной большой лужи крови короля (3x3) и резкого финала...")
	var board_scene = preload("res://scenes/chess/chess_board.tscn")
	var board_view = board_scene.instantiate()
	get_root().add_child(board_view)
	board_view.restart_game(1)
	
	var king_cell = Vector2i(4, 0)
	var mega_stain = board_view.spawn_mega_blood_stain(king_cell)
	assert(mega_stain != null, "Mega blood stain должен быть создан")
	
	# Проверяем, что все клетки 3x3 помечены в blood_layers
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var c = Vector2i(king_cell.x + dx, king_cell.y + dy)
			if c.x >= 0 and c.x < 8 and c.y >= 0 and c.y < 8:
				assert(board_view.blood_layers.has(c), "Клетка %s должна быть покрыта кровью лужи" % str(c))
				assert(board_view.blood_layers[c] > 0, "Уровень крови должен быть > 0")
				
	# Проверяем резкий финал без задержек в EndingManager
	var manager = EndingManagerScript.new()
	get_root().add_child(manager)
	manager._start_tension_sound()
	assert(manager._tension_audio_player != null, "Плеер нагнетания звука должен быть создан")
	
	manager._on_revelation_finished()
	assert(not manager._tension_audio_player.playing, "Нагнетание звука должно резко остановиться")
	
	# Проверяем созданный оверлей смерти с резким черным фоном и текстом
	var found_black: ColorRect = null
	var found_title: Label = null
	for child in manager.get_children():
		if child is CanvasLayer:
			for sub in child.get_children():
				if sub is ColorRect:
					found_black = sub
				elif sub is Label:
					found_title = sub
					
	assert(found_black != null, "Резкий черный экран должен быть создан")
	assert(found_black.color.a == 1.0, "Черный экран должен быть мгновенно 100% непрозрачным (без фейда)")
	assert(found_title != null, "Заголовок Zugzwang должен быть создан")
	assert(found_title.modulate.a == 1.0, "Заголовок должен быть мгновенно 100% непрозрачным (без фейда)")
	
	manager.queue_free()
	board_view.queue_free()
	print("✓ Тест 7 пройден")

func test_black_victory_defeat_screen_abrupt_and_scene_restoration() -> void:
	print("Тест 8: Резкий черный экран с текстом поражения, восстановление сцены под ним и разблокировка игрока...")
	var root_node = get_root()
	
	# EventBus (гарантируем отсутствие старых экземпляров в /root)
	var existing_bus = root_node.get_node_or_null("EventBus")
	if existing_bus:
		existing_bus.free()
		
	var bus_script = load("res://scripts/event_bus.gd")
	var bus = bus_script.new()
	bus.name = "EventBus"
	bus.current_stage = 4
	root_node.add_child(bus)
	
	# Создаем фиктивного игрока
	var player = CharacterBody3D.new()
	player.set_script(load("res://scenes/player.gd"))
	var head = Node3D.new()
	head.name = "head"
	player.add_child(head)
	var cam = Camera3D.new()
	cam.name = "Camera3D"
	head.add_child(cam)
	var steps = AudioStreamPlayer3D.new()
	steps.name = "PlayerSteps"
	player.add_child(steps)
	player.position = Vector3(16.0, 5.185, 3.5)
	root_node.add_child(player)
	
	# Запоминаем исходную стартовую позицию
	var start_pos = player.global_position
	
	# Игрок подходит к столу и садится
	player.global_position = Vector3(16.0, 5.185, 17.5)
	player.enter_board_mode()
	player.is_board_mode = true
	player.can_walk = false
	player.can_move = false
	
	# Создаем фиктивную доску
	var board_scene = preload("res://scenes/chess/chess_board.tscn")
	var board_view = board_scene.instantiate()
	root_node.add_child(board_view)
	board_view.restart_game(1)
	
	# Создаем фиктивный бункер
	var door_pivot = Node3D.new()
	door_pivot.name = "DoorPivot"
	root_node.add_child(door_pivot)
	
	var bulb = MeshInstance3D.new()
	bulb.name = "HangingBulb"
	bulb.set_script(load("res://scripts/hanging_lamp.gd"))
	var light = OmniLight3D.new()
	bulb.add_child(light)
	root_node.add_child(bulb)
	
	var manager = EndingManagerScript.new()
	manager.player_node = player
	manager.chess_board_view = board_view
	manager.door_pivot = door_pivot
	manager.hanging_bulb = bulb
	root_node.add_child(manager)
	
	# Имитируем поражение (черные выиграли)
	player._on_game_over("black")
	assert(player.is_defeat_locked == true, "При поражении игрок должен быть заблокирован (is_defeat_locked)")
	assert(player.can_walk == false, "При поражении игрок не может ходить")
	assert(player.can_move == false, "При поражении игрок не может вращать камеру")
	
	# Попытка встать из-за стола во время поражения должна блокироваться
	player.exit_board_mode()
	assert(player.is_board_mode == true, "При поражении игрок не может выйти из-за стола")
	
	# 1. Проверяем нагнетающий звук перед черным экраном
	var tension_finished_called: bool = false
	manager._start_defeat_tension_sound(0.05, func():
		tension_finished_called = true
	)
	assert(manager._tension_audio_player != null, "DefeatTensionPlayer должен быть создан")
	assert(manager._tension_audio_player.bus == &"Master", "Tension audio должен быть на шине Master")
	
	# 2. Проверяем резкий черный экран DefeatScreen
	var test_state: Dictionary = {
		"restore_called": false,
		"complete_called": false
	}
	var on_restore = func():
		test_state["restore_called"] = true
		manager._restore_scene_under_black_screen()
	var on_complete = func():
		test_state["complete_called"] = true
		manager._finalize_player_control_after_defeat()

	var defeat_screen = DefeatScreenScript.new()
	root_node.add_child(defeat_screen)
	defeat_screen.show_defeat("«Тестовая фраза поражения»", 0.05, on_restore, on_complete)
	
	# Проверяем, что экран появился РЕЗКО без начального fade-in
	assert(defeat_screen.visible == true, "DefeatScreen должен быть виден")
	assert(defeat_screen._container.modulate.a == 1.0, "DefeatScreen должен мгновенно иметь modulate.a = 1.0 (резко)")
	assert(defeat_screen._bg_rect.color == Color(0, 0, 0, 1), "Фон экрана должен быть абсолютно черным")
	assert(defeat_screen._title_label.text == "П О Р А Ж Е Н И Е", "Заголовок экрана должен быть 'П О Р А Ж Е Н И Е'")
	assert(defeat_screen._quote_label.text == "«Тестовая фраза поражения»", "Текст цитаты должен совпадать")
	
	# Проверяем, что восстановление сцены запустилось СРАЗУ ПОД черным экраном
	assert(test_state["restore_called"] == true, "Восстановление сцены должно произойти под черным экраном")
	assert(bus.player_losses == 1, "Счетчик поражений игрока должен быть увеличен")
	assert(bus.death_count == 1, "Счетчик смертей должен быть увеличен")
	assert(bus.current_playthrough >= 2, "Сложность игры должна быть увеличена")
	assert(bus.current_stage == 1, "Стадия бункера должна сброситься на 1")
	assert(player.is_board_mode == false, "Игрок должен выйти из режима доски")
	assert(player.global_position.distance_to(start_pos) < 0.01, "Игрок должен вернуться на стартовую точку спавна")
	
	# Имитируем завершение экрана (дисмисс)
	defeat_screen._dismiss_screen()
	manager._finalize_player_control_after_defeat()
	
	# Проверяем, что после исчезновения экрана игрок может двигаться
	assert(player.can_walk == true, "После исчезновения черного экрана can_walk должен быть true")
	assert(player.can_move == true, "После исчезновения черного экрана can_move должен быть true")
	assert(player.is_defeat_locked == false, "Блокировка управления поражением должна быть снята")
	assert(manager._is_ending_active == false, "_is_ending_active должен быть сброшен в false")
	
	defeat_screen.queue_free()
	manager.queue_free()
	bulb.queue_free()
	door_pivot.queue_free()
	board_view.queue_free()
	player.queue_free()
	bus.queue_free()
	print("✓ Тест 8 пройден")

func test_camera_sound_stopped_and_premature_door_slam() -> void:
	print("Тест 9: Исправление звука камеры при движении и прерывание анимации двери...")
	var root_node = get_root()
	var manager = EndingManagerScript.new()
	root_node.add_child(manager)
	
	# 1. Проверяем остановку звука камеры наблюдения при открытии двери
	var cam_script = load("res://scripts/world/security_camera.gd")
	var cam_node = Node3D.new()
	cam_node.set_script(cam_script)
	var cam_audio = AudioStreamPlayer3D.new()
	cam_audio.name = "CameraSound"
	cam_node.add_child(cam_audio)
	root_node.add_child(cam_node)
	manager.security_camera = cam_node
	
	# Симулируем, что звук камеры играл во время движения игрока
	cam_audio.stream = AudioStreamWAV.new()
	cam_node._sound_timer = 0.25
	
	var door_pivot = Node3D.new()
	door_pivot.name = "DoorPivot"
	manager.door_pivot = door_pivot
	root_node.add_child(door_pivot)
	
	# Открываем дверь по белой победе
	manager._play_white_victory()
	assert(cam_node._not_follow == true, "Камера должна перестать следовать")
	assert(cam_audio.playing == false, "Звук поворота камеры должен быть принудительно остановлен!")
	assert(is_equal_approx(door_pivot.rotation_degrees.y, manager._initial_door_rot.y - 88.0), "Дверь должна открыться")
	
	# 2. Игрок заходит в комнату ДО окончания анимации открытия двери
	var fake_player = CharacterBody3D.new()
	fake_player.add_to_group("player")
	root_node.add_child(fake_player)
	
	manager._on_secret_room_body_entered(fake_player)
	# Дверь должна принудительно захлопнуться обратно в начальное положение
	assert(is_equal_approx(door_pivot.rotation_degrees.y, manager._initial_door_rot.y), "Дверь должна быть принудительно закрыта!")
	
	fake_player.queue_free()
	door_pivot.queue_free()
	cam_node.queue_free()
	manager.queue_free()
	print("✓ Тест 9 пройден")

func test_terminal_proximity_and_gaze() -> void:
	print("Тест 10: Проверка взаимодействия с терминалом (дистанция и направление взгляда)...")
	var root_node = get_root()
	var monitor_script = load("res://scripts/world/observation_monitor.gd")
	var monitor = monitor_script.new()
	monitor.position = Vector3.ZERO
	
	var screen_mesh = MeshInstance3D.new()
	screen_mesh.position = Vector3(0.0, 0.0, 0.21)
	monitor.add_child(screen_mesh)
	monitor.screen_mesh = screen_mesh
	root_node.add_child(monitor)
	
	# Игрок с головой и камерой
	var player = CharacterBody3D.new()
	player.name = "player"
	player.add_to_group("player")
	player.position = Vector3(0.0, 0.0, 1.65)
	var head = Node3D.new()
	head.name = "head"
	player.add_child(head)
	var cam = Camera3D.new()
	cam.name = "Camera3D"
	head.add_child(cam)
	root_node.add_child(player)
	
	# 1. Игрок стоит вблизи (1.44м) и смотрит прямо на монитор (-Z)
	cam.rotation = Vector3.ZERO
	assert(monitor.is_player_looking_at_monitor() == true, "Вблизи и глядя на монитор -> доступно")
	
	# 2. Игрок стоит вблизи, но отвернулся (смотрит вправо на +X, yaw = -PI/2)
	cam.rotation = Vector3(0.0, -PI * 0.5, 0.0)
	assert(monitor.is_player_looking_at_monitor() == false, "Вблизи, но отвернувшись -> недоступно")
	
	# 3. Игрок смотрит на монитор, но отошел на 6 метров назад (z = 6.0)
	cam.rotation = Vector3.ZERO
	player.position = Vector3(0.0, 0.0, 6.0)
	assert(monitor.is_player_looking_at_monitor() == false, "Издали -> недоступно")
	
	player.queue_free()
	monitor.queue_free()
	print("✓ Тест 10 пройден")

func test_door_audio_fade_and_player() -> void:
	print("Тест 11: Плавное затухание звуков двери и выделенный 3D плеер...")
	var root_node = get_root()
	var manager = EndingManagerScript.new()
	root_node.add_child(manager)
	
	var door_pivot = Node3D.new()
	door_pivot.name = "DoorPivot"
	root_node.add_child(door_pivot)
	manager.door_pivot = door_pivot
	
	var door = Node3D.new()
	door.name = "Door"
	door_pivot.add_child(door)
	manager.door_node = door
	
	# 1. Проверяем инициализацию и прикрепление _door_audio_player к door_node
	manager._setup_door_audio_player()
	assert(manager._door_audio_player != null, "Плеер двери _door_audio_player должен быть создан")
	assert(manager._door_audio_player.get_parent() == door, "_door_audio_player должен быть прикреплен к door_node")
	assert(manager._door_audio_player.bus == &"Sound", "_door_audio_player должен использовать Sound шину")
	
	# 2. Победа белых: проверяем запуск door_open.ogg на _door_audio_player
	manager._play_white_victory()
	assert(manager._door_audio_player.stream != null, "Стрим звука открывания должен быть назначен")
	assert(manager._door_audio_player.stream.resource_path.ends_with("door_open.ogg"), "Должен воспроизводиться door_open.ogg")
	assert(manager._door_audio_player.volume_db == -5.0, "Громкость старта должна быть -5.0 dB")
	
	# 3. Вход в секретную комнату: звук открывания должен затухать перед закрытием
	var fake_player = CharacterBody3D.new()
	fake_player.add_to_group("player")
	root_node.add_child(fake_player)
	
	manager._on_secret_room_body_entered(fake_player)
	assert(manager._door_audio_player.volume_db <= -40.0, "Звук открывания должен быть затушен перед звуком закрытия")
	
	# 4. Захлопывание двери: проверяем запуск door_closed.ogg и мягкое затухание
	manager._on_secret_door_closed()
	assert(manager._door_audio_player.stream != null, "Стрим звука закрытия должен быть назначен")
	assert(manager._door_audio_player.stream.resource_path.ends_with("door_closed.ogg"), "Должен воспроизводиться door_closed.ogg")
	assert(manager._door_audio_player.volume_db <= -40.0, "Звук захлопывания должен быть мягко затушен")
	
	# 5. Сброс комнаты: плеер двери должен быть остановлен, а tween уничтожен
	manager.restore_room_to_initial()
	assert(manager._door_audio_player.playing == false, "Плеер двери должен быть остановлен")
	assert(manager._door_audio_tween == null or not manager._door_audio_tween.is_valid(), "Tween двери должен быть аннулирован")
	
	fake_player.queue_free()
	door.queue_free()
	door_pivot.queue_free()
	manager.queue_free()
	print("✓ Тест 11 пройден")

