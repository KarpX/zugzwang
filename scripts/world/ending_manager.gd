class_name EndingManager
extends Node3D

## EndingManager — Оркестратор кинематографичных концовок проекта «Белый Король»
## Слушает EventBus.game_over(winner) и запускает один из трёх финалов:
## 1. "black": Победа чёрных (взрыв короля, кровавая комната, блэкаут, CCTV, перезапуск)
## 2. "white": Победа белых (открытие бункера, комната с монитором, ловушка, жертвоприношение)
## 3. "draw": Пат (внезапный штурм бункера, автоматные очереди, ликвидация, перезапуск)

const GunfireGen = preload("res://scripts/world/gunfire_audio_generator.gd")
const CCTVOverlayScript = preload("res://scripts/world/cctv_overlay.gd")
const DefeatScreenScript = preload("res://scripts/ui/defeat_screen.gd")

@export var player_node: CharacterBody3D
@export var door_node: Node3D
@export var door_pivot: Node3D
@export var hanging_bulb: MeshInstance3D
@export var radio_dial_light: OmniLight3D
@export var world_environment: WorldEnvironment
@export var security_camera: Node3D
@export var observation_room: Node3D
@export var chess_board_view: Node3D
@export var monitor_glow: SpotLight3D
@export_range(1.0, 10.0, 0.1) var defeat_tension_duration: float = 3.8
@export_range(1.0, 10.0, 0.1) var defeat_screen_display_duration: float = 3.5
@export var final_music: AudioStream = preload("res://assets/sounds/its end.ogg")

var _cctv_overlay: CanvasLayer = null
var _audio_player: AudioStreamPlayer3D = null
var _door_audio_player: AudioStreamPlayer3D = null
var _door_audio_tween: Tween = null
var _tension_audio_player: AudioStreamPlayer = null
var _final_music_player: AudioStreamPlayer = null
var _final_music_tween: Tween = null
var _door_tween: Tween = null
var _is_ending_active: bool = false
var _initial_env_fog_color: Color = Color.WHITE
var _initial_door_rot: Vector3 = Vector3.ZERO
var _initial_door_pos: Vector3 = Vector3.ZERO
var _spawned_particles: Array[Node] = []

func _get_event_bus() -> Node:
	if is_inside_tree():
		return get_node_or_null("/root/EventBus")
	var p = get_parent()
	while p:
		if p.name == "EventBus":
			return p
		var b = p.get_node_or_null("EventBus")
		if b:
			return b
		p = p.get_parent()
	return null

func _ready() -> void:
	_resolve_scene_nodes()
	_setup_audio_player()
	_setup_door_audio_player()
	_setup_cctv_overlay()
	
	var bus: Node = _get_event_bus()
	if bus and bus.has_signal("game_over"):
		bus.game_over.connect(_on_game_over)
		
	if observation_room:
		var trigger = observation_room.get_node_or_null("EntryTrigger") as Area3D
		if trigger and not trigger.body_entered.is_connected(_on_secret_room_body_entered):
			trigger.body_entered.connect(_on_secret_room_body_entered)
			
		var monitor = observation_room.get_node_or_null("CRTMonitor")
		if monitor:
			if monitor.has_signal("revelation_finished") and not monitor.revelation_finished.is_connected(_on_revelation_finished):
				monitor.revelation_finished.connect(_on_revelation_finished)
			if monitor.has_signal("terminal_started") and not monitor.terminal_started.is_connected(_on_terminal_started):
				monitor.terminal_started.connect(_on_terminal_started)

func _resolve_scene_nodes() -> void:
	if player_node == null:
		player_node = get_node_or_null("../player") as CharacterBody3D
	if door_pivot == null:
		door_pivot = get_node_or_null("../walls/DoorPivot") as Node3D
	if door_node == null:
		door_node = get_node_or_null("../walls/DoorPivot/Door") as Node3D
		if door_node == null:
			door_node = get_node_or_null("../walls/Door") as Node3D
	if door_pivot:
		_initial_door_rot = door_pivot.rotation_degrees
		_initial_door_pos = door_pivot.position
	elif door_node:
		_initial_door_rot = door_node.rotation_degrees
		_initial_door_pos = door_node.position
	if hanging_bulb == null:
		hanging_bulb = get_node_or_null("../HangingBulb") as MeshInstance3D
	if radio_dial_light == null:
		radio_dial_light = get_node_or_null("../TableStatic/Table/Radio/DialGlow") as OmniLight3D
	if world_environment == null:
		world_environment = get_node_or_null("../WorldEnvironment") as WorldEnvironment
	if world_environment and world_environment.environment:
		_initial_env_fog_color = world_environment.environment.volumetric_fog_albedo
	if security_camera == null:
		security_camera = get_node_or_null("../walls/CameraBase/CameraPivot") as Node3D
	if chess_board_view == null:
		chess_board_view = get_node_or_null("../TableStatic/Table/ChessBoard") as Node3D
	if observation_room == null:
		observation_room = get_node_or_null("../ObservationRoom") as Node3D
	if monitor_glow == null:
		monitor_glow = get_node_or_null("../ObservationRoom/CRTMonitor/MonitorGlow")

func _setup_audio_player() -> void:
	if _audio_player == null and is_inside_tree():
		_audio_player = AudioStreamPlayer3D.new()
		_audio_player.name = "EndingAudioPlayer"
		_audio_player.bus = &"Sound"
		_audio_player.unit_size = 20.0
		_audio_player.max_distance = 60.0
		add_child(_audio_player)


func _setup_door_audio_player() -> void:
	var attach_target: Node = null
	if door_node and door_node.is_inside_tree():
		attach_target = door_node
	elif door_pivot and door_pivot.is_inside_tree():
		attach_target = door_pivot
	elif is_inside_tree():
		attach_target = self
	else:
		attach_target = door_node if door_node != null else (door_pivot if door_pivot != null else self)

	if _door_audio_player == null:
		_door_audio_player = AudioStreamPlayer3D.new()
		_door_audio_player.name = "DoorAudioPlayer"
		_door_audio_player.bus = &"Sound"
		_door_audio_player.unit_size = 20.0
		_door_audio_player.max_distance = 60.0
		attach_target.add_child(_door_audio_player)
	elif _door_audio_player.get_parent() == null:
		attach_target.add_child(_door_audio_player)
	elif _door_audio_player.get_parent() != attach_target and attach_target != self:
		_door_audio_player.reparent(attach_target)

func _play_audio(stream: AudioStream, vol_db: float, pos: Vector3 = Vector3.ZERO) -> void:
	if not is_inside_tree():
		return
	_setup_audio_player()
	if _audio_player and is_inside_tree():
		if pos != Vector3.ZERO:
			_audio_player.global_position = pos
		_audio_player.stream = stream
		_audio_player.volume_db = vol_db
		_audio_player.play()

func _setup_cctv_overlay() -> void:
	_cctv_overlay = CCTVOverlayScript.new()
	_cctv_overlay.name = "CCTVOverlay"
	add_child(_cctv_overlay)

func _on_game_over(winner: String) -> void:
	if _is_ending_active:
		return
	_is_ending_active = true
	
	match winner:
		"black":
			_play_black_victory()
		"white":
			_play_white_victory()
		"draw":
			_play_draw_ending()
		_:
			# Для других исходов (например, breach) управление передается соответствующему модулю
			_is_ending_active = false

# ==============================================================================
# 1. ПОБЕДА ЧЁРНЫХ (Black Victory / White King Detonation)
# ==============================================================================

func _play_black_victory() -> void:
	_is_ending_active = true
	_setup_audio_player()
	
	# Блокируем перемещение игрока на время драматического финала
	if player_node:
		player_node.can_walk = false
		player_node.can_move = false
		if "is_defeat_locked" in player_node:
			player_node.is_defeat_locked = true
		
	# 1. Находим белого короля на доске
	var white_king_node: Node3D = null
	var king_cell: Vector2i = Vector2i(4, 0)
	if chess_board_view and "piece_nodes" in chess_board_view:
		var pieces: Dictionary = chess_board_view.piece_nodes
		for cell in pieces:
			var node = pieces[cell]
			if node and "piece_type" in node and node.piece_type == "king" and "is_white" in node and node.is_white:
				white_king_node = node
				king_cell = cell
				break
	
	var explosion_pos: Vector3 = white_king_node.global_position if (white_king_node and white_king_node.is_inside_tree()) else Vector3(16, 2, 20)
	
	# 2. Звук взрыва и разрыва (kill.ogg + boom_3.ogg)
	var kill_sfx = preload("res://assets/sounds/kill.ogg")
	var boom_sfx = preload("res://assets/sounds/boom_3.ogg")
	_play_audio(kill_sfx, 8.0, explosion_pos)
	
	if is_inside_tree():
		var t_boom = create_tween()
		t_boom.tween_interval(0.12)
		t_boom.tween_callback(func():
			_play_audio(boom_sfx, 10.0, explosion_pos)
		)
	
	# 3. Эмиттер взрыва крови белого короля (разлетающиеся воксели)
	_spawn_king_blood_explosion(explosion_pos, king_cell)
	if white_king_node:
		white_king_node.visible = false
		
	# 4. Багровая комната: туман и пост-процессинг
	if world_environment and world_environment.environment and is_inside_tree():
		var env = world_environment.environment
		var env_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		env_tween.tween_property(env, "volumetric_fog_albedo", Color(0.85, 0.05, 0.05, 1.0), 1.2)
		env_tween.parallel().tween_property(env, "adjustment_saturation", 1.8, 1.2)
	
	if not is_inside_tree():
		return
		
	# 5. Спустя 1.2 секунды: гаснет лампа над столом и радио
	var blackout_timer = get_tree().create_timer(1.2)
	blackout_timer.timeout.connect(func():
		_turn_off_lights()
		
		# 6. Включается камера видеонаблюдения, фокусируется на игроке
		if security_camera:
			var spot = security_camera.get_node_or_null("NightVisionSpotLight") as SpotLight3D
			if spot:
				spot.light_color = Color(1.0, 0.05, 0.05, 1.0)
				spot.light_energy = 3.5
				spot.spot_range = 35.0
				
		# 7. Нагнетающий звук (угрожающая сирена/гул с нарастанием частоты и громкости)
		_start_defeat_tension_sound(defeat_tension_duration, func():
			# 8. После окончания нагнетающего звука — РЕЗКО чёрный экран с текстом поражения!
			_show_abrupt_defeat_screen()
		)
	)

## Нагнетающий звук перед резким чёрным экраном
func _start_defeat_tension_sound(duration: float, on_finish: Callable) -> void:
	if _tension_audio_player == null:
		_tension_audio_player = AudioStreamPlayer.new()
		_tension_audio_player.name = "DefeatTensionPlayer"
		_tension_audio_player.bus = &"Master"
		add_child(_tension_audio_player)
		
	var siren_sfx = preload("res://assets/sounds/siren.ogg")
	_tension_audio_player.stream = siren_sfx
	_tension_audio_player.volume_db = -18.0
	_tension_audio_player.pitch_scale = 0.28
	
	if is_inside_tree():
		_tension_audio_player.play()
		var t = create_tween().set_parallel(true)
		t.tween_property(_tension_audio_player, "volume_db", 6.0, duration).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
		t.tween_property(_tension_audio_player, "pitch_scale", 0.72, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		
		var finish_timer = get_tree().create_timer(duration)
		finish_timer.timeout.connect(func():
			if _tension_audio_player and _tension_audio_player.playing:
				_tension_audio_player.stop()
			if not on_finish.is_null():
				on_finish.call()
		)
	else:
		if not on_finish.is_null():
			on_finish.call()

## Резкое появление чёрного экрана с текстом поражения
func _show_abrupt_defeat_screen() -> void:
	var bus: Node = _get_event_bus()
	var quote_text: String = ""
	if bus and bus.has_method("get_random_defeat_quote"):
		quote_text = bus.get_random_defeat_quote()
	if quote_text.is_empty():
		quote_text = "«Король пал. Но доска осталась на месте. Играй.»"
		
	var defeat_screen = DefeatScreenScript.new()
	defeat_screen.name = "DefeatScreen"
	add_child(defeat_screen)
	
	var on_restore = func():
		_restore_scene_under_black_screen(true)
		
	defeat_screen.show_defeat(
		quote_text,
		defeat_screen_display_duration,
		on_restore,
		_finalize_player_control_after_defeat,
		"П О Р А Ж Е Н И Е",
		"Фигуры расставлены заново. Сделайте следующий ход."
	)

## Резкое появление чёрного экрана с текстом пата
func _show_abrupt_draw_screen() -> void:
	var bus: Node = _get_event_bus()
	var quote_text: String = ""
	if bus and bus.has_method("get_random_draw_quote"):
		quote_text = bus.get_random_draw_quote()
	if quote_text.is_empty():
		quote_text = "«Война не принимает ничьих. Защищай короля до конца.»"
		
	var defeat_screen = DefeatScreenScript.new()
	defeat_screen.name = "DefeatScreen"
	add_child(defeat_screen)
	
	var on_restore = func():
		_restore_scene_under_black_screen(false)
		
	defeat_screen.show_defeat(
		quote_text,
		defeat_screen_display_duration,
		on_restore,
		_finalize_player_control_after_defeat,
		"П А Т",
		"Партия завершилась вничью. Расставьте фигуры заново."
	)

## Полное восстановление сцены бункера, шахматной доски и игрока под чёрным экраном
func _restore_scene_under_black_screen(is_defeat: bool = true) -> void:
	var bus: Node = _get_event_bus()
	if bus:
		if is_defeat:
			bus.death_count += 1
			bus.player_losses += 1
			bus.current_playthrough = maxi(2, bus.current_playthrough + 1)
		bus.reset_game_state(bus.current_playthrough)
		
	# 1. Восстановление бункера, освещения, тумана, двери и камеры наблюдения
	restore_room_to_initial()
	
	# 2. Очистка остаточных частиц взрыва
	_cleanup_explosion_particles()
	
	# 3. Восстановление шахматной доски (расстановка всех 32 фигур заново)
	if chess_board_view and chess_board_view.has_method("restart_game"):
		var pt: int = bus.current_playthrough if bus else 2
		chess_board_view.restart_game(pt)
		
	# 4. Вывод игрока из режима доски и возврат на стартовую точку
	if player_node:
		if player_node.has_method("reset_to_start"):
			player_node.reset_to_start()
		else:
			if "is_board_mode" in player_node and player_node.is_board_mode:
				if player_node.has_method("exit_board_mode"):
					player_node.exit_board_mode()
				else:
					player_node.is_board_mode = false
					
			var cam = player_node.get_node_or_null("head/Camera3D") as Camera3D
			if cam:
				cam.h_offset = 0.0
				cam.v_offset = 0.0
				cam.position.y = -0.89668
				cam.rotation_degrees.z = 0.0
				
			var head_node = player_node.get_node_or_null("head") as Node3D
			if head_node:
				head_node.rotation.x = 0.0
				
	if bus and bus.has_signal("camera_mode_changed"):
		bus.camera_mode_changed.emit(false)

## Разблокировка игрока после исчезновения чёрного экрана
func _finalize_player_control_after_defeat() -> void:
	_is_ending_active = false
	if player_node:
		if player_node.has_method("unlock_after_defeat"):
			player_node.unlock_after_defeat()
		else:
			player_node.can_walk = true
			player_node.can_move = true
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		
	var bus: Node = _get_event_bus()
	if bus and bus.has_signal("camera_mode_changed"):
		bus.camera_mode_changed.emit(false)

func _cleanup_explosion_particles() -> void:
	for p in _spawned_particles:
		if is_instance_valid(p):
			p.queue_free()
	_spawned_particles.clear()

func _spawn_king_blood_explosion(pos: Vector3, king_cell: Vector2i = Vector2i(4, 0)) -> void:
	var particles = CPUParticles3D.new()
	if is_inside_tree():
		particles.global_position = pos
	else:
		particles.position = pos
	particles.amount = 64
	particles.lifetime = 1.6
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.spread = 180.0
	particles.gravity = Vector3(0, -9.8, 0)
	particles.initial_velocity_min = 4.0
	particles.initial_velocity_max = 9.0
	
	var cube_mesh = BoxMesh.new()
	cube_mesh.size = Vector3(0.12, 0.12, 0.12)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.65, 0.02, 0.02, 1.0)
	mat.roughness = 0.3
	cube_mesh.material = mat
	particles.mesh = cube_mesh
	
	add_child(particles)
	_spawned_particles.append(particles)
	particles.emitting = true
	
	# Добавляем одну гигантскую сплошную воксельную лужу крови, занимающую клетку короля и все клетки вокруг (3x3)
	if chess_board_view and chess_board_view.has_method("spawn_mega_blood_stain"):
		chess_board_view.spawn_mega_blood_stain(king_cell)
	elif chess_board_view and chess_board_view.has_method("spawn_blood_stain"):
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				chess_board_view.spawn_blood_stain(Vector2i(king_cell.x + dx, king_cell.y + dy))

func _turn_off_lights() -> void:
	if hanging_bulb:
		if "light_intensity_ratio" in hanging_bulb:
			hanging_bulb.light_intensity_ratio = 0.0
		var bulb_light = hanging_bulb.get_node_or_null("OmniLight3D") as OmniLight3D
		if bulb_light:
			bulb_light.light_energy = 0.0
			
	if radio_dial_light:
		radio_dial_light.light_energy = 0.0

# ==============================================================================
# 2. ПОБЕДА БЕЛЫХ (White Victory / Observation Room Reveal)
# ==============================================================================

func _play_white_victory() -> void:
	_is_ending_active = true
	var bus: Node = _get_event_bus()
	if bus and bus.has_signal("white_victory_door_opened"):
		bus.white_victory_door_opened.emit()
	if bus and bus.has_signal("ending_sequence_started"):
		bus.ending_sequence_started.emit("white")
		
	if security_camera:
		if security_camera.has_method("toggle_follow"):
			security_camera.toggle_follow(true)
		if security_camera.has_method("fade_out_camera_sound"):
			security_camera.fade_out_camera_sound(2.0)
		elif security_camera.has_method("stop_camera_sound"):
			security_camera.stop_camera_sound()
	_setup_audio_player()
	# 1. Тяжелый звук открывания гермозамков и распахивания двери на выделенном плеере
	var door_open_sfx = preload("res://assets/sounds/door_open.ogg")
	_setup_door_audio_player()
	if _door_audio_player:
		if _door_audio_tween and _door_audio_tween.is_valid():
			_door_audio_tween.kill()
		_door_audio_player.stream = door_open_sfx
		_door_audio_player.volume_db = -5.0
		if _door_audio_player.is_inside_tree():
			_door_audio_player.play()
		
		# Плавное затухание громкости в конце движения двери (последние 0.9с) до -40 dB
		if is_inside_tree():
			_door_audio_tween = create_tween()
			_door_audio_tween.tween_interval(2.9)
			_door_audio_tween.tween_property(_door_audio_player, "volume_db", -40.0, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			_door_audio_tween.tween_callback(func():
				if _door_audio_player and _door_audio_player.stream == door_open_sfx:
					_door_audio_player.stop()
			)
	
	# 2. Плавное распахивание тяжелой двери бункера
	var target_door = door_pivot if door_pivot else door_node
	if target_door and is_inside_tree():
		if _door_tween and _door_tween.is_valid():
			_door_tween.kill()
		_door_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_door_tween.tween_interval(0.6)
		# Вращаем дверь на петле
		_door_tween.tween_property(target_door, "rotation_degrees:y", _initial_door_rot.y - 88.0, 3.2)
	elif target_door:
		target_door.rotation_degrees.y = _initial_door_rot.y - 88.0
	
	
	# 3. Игрок автоматически встает из-за стола и смотрит на дверь
	if player_node:
		if "is_board_mode" in player_node and player_node.is_board_mode:
			if player_node.has_method("exit_board_mode"):
				player_node.exit_board_mode()
		player_node.can_walk = true
		player_node.can_move = true
	
	if monitor_glow:
		monitor_glow.visible = true

func _on_secret_room_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
		
	var bus: Node = _get_event_bus()
	if bus and bus.has_signal("secret_room_entered"):
		bus.secret_room_entered.emit()

	# Отключаем триггер, чтобы не срабатывал повторно
	if observation_room:
		var trigger = observation_room.get_node_or_null("EntryTrigger") as Area3D
		if trigger:
			trigger.set_deferred("monitoring", false)
			
	# Плавно затушаем предыдущий звук открывания двери за 0.35с перед закрытием
	if _door_audio_tween and _door_audio_tween.is_valid():
		_door_audio_tween.kill()
	if _door_audio_player and (_door_audio_player.playing or _door_audio_player.stream != null):
		if is_inside_tree():
			_door_audio_tween = create_tween()
			_door_audio_tween.tween_property(_door_audio_player, "volume_db", -40.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			_door_audio_tween.tween_callback(func():
				if _door_audio_player and _door_audio_player.playing:
					_door_audio_player.stop()
			)
		else:
			_door_audio_player.volume_db = -40.0
			_door_audio_player.stop()
			
	# 1. Плавное и кинематографичное закрытие двери бункера за спиной игрока
	var target_door = door_pivot if door_pivot else door_node
	var close_duration: float = 0.78
	if target_door and is_inside_tree():
		# Немедленно прерываем анимацию открытия двери, если она еще длится
		if _door_tween and _door_tween.is_valid():
			_door_tween.kill()
		_door_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		_door_tween.tween_property(target_door, "rotation_degrees:y", _initial_door_rot.y, close_duration)
		_door_tween.tween_callback(_on_secret_door_closed)
	elif target_door:
		target_door.rotation_degrees.y = _initial_door_rot.y
		_on_secret_door_closed()
				
	# 2. Активируем готовность терминала к вводу [E]
	if observation_room:
		var monitor = observation_room.get_node_or_null("CRTMonitor")
		if monitor:
			if monitor.has_signal("terminal_started") and not monitor.terminal_started.is_connected(_on_terminal_started):
				monitor.terminal_started.connect(_on_terminal_started)
			if monitor.has_signal("revelation_finished") and not monitor.revelation_finished.is_connected(_on_revelation_finished):
				monitor.revelation_finished.connect(_on_revelation_finished)
			if monitor.has_method("enable_terminal_input"):
				monitor.enable_terminal_input()

## Завершение полного закрытия двери секретной комнаты: грохот, тряска камеры, блок выхода
func _on_secret_door_closed() -> void:
	# Грохот захлопнувшейся двери на выделенном 3D плеере двери
	var slam_sfx = preload("res://assets/sounds/door_closed.ogg")
	_setup_door_audio_player()
	if _door_audio_player:
		if _door_audio_tween and _door_audio_tween.is_valid():
			_door_audio_tween.kill()
		_door_audio_player.stream = slam_sfx
		_door_audio_player.volume_db = 10.0
		if _door_audio_player.is_inside_tree():
			_door_audio_player.play()
		
		# Мягкое затухание хвоста звука захлопывания двери (длительность семпла 1.15с)
		if is_inside_tree():
			_door_audio_tween = create_tween()
			_door_audio_tween.tween_interval(0.65)
			_door_audio_tween.tween_property(_door_audio_player, "volume_db", -40.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			_door_audio_tween.tween_callback(func():
				if _door_audio_player and _door_audio_player.stream == slam_sfx:
					_door_audio_player.stop()
			)
		else:
			_door_audio_player.volume_db = -40.0
			_door_audio_player.stop()
	
	# Тряска экрана и подземный толчок
	if player_node and player_node.has_method("apply_camera_shake"):
		player_node.apply_camera_shake(0.65, 2.5, 0.08)
	var bus: Node = _get_event_bus()
	if bus and bus.has_signal("seismic_shock_triggered"):
		bus.seismic_shock_triggered.emit(0.7, false)
		
	# Блокируем обратный выход ТОЛЬКО когда дверь полностью закрылась
	if observation_room:
		var blocker = observation_room.get_node_or_null("DoorBlocker") as StaticBody3D
		if blocker:
			blocker.collision_layer = 1
			var col = blocker.get_node_or_null("CollisionShape3D") as CollisionShape3D
			if col:
				col.set_deferred("disabled", false)

func _on_terminal_started() -> void:
	# Финальная музыка (its end) с плавным нарастанием громкости после открытия терминала
	_play_final_music(8.0, -2.0)

## Нагнетание тревожного звука во время откровения на мониторе
func _start_tension_sound() -> void:
	if _tension_audio_player == null:
		_tension_audio_player = AudioStreamPlayer.new()
		_tension_audio_player.name = "TensionRiserPlayer"
		_tension_audio_player.bus = &"Master"
		add_child(_tension_audio_player)
		
	var siren_sfx = preload("res://assets/sounds/siren.ogg")
	_tension_audio_player.stream = siren_sfx
	_tension_audio_player.volume_db = -22.0
	_tension_audio_player.pitch_scale = 0.28
	
	# Нагнетание: постепенный экспоненциальный рост громкости и повышение тона к кульминации
	if is_inside_tree():
		_tension_audio_player.play()
		var t = create_tween().set_parallel(true)
		t.tween_property(_tension_audio_player, "volume_db", 6.0, 11.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
		t.tween_property(_tension_audio_player, "pitch_scale", 0.72, 11.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

## Воспроизведение финальной музыки (its end.ogg) с плавным нарастанием громкости
func _play_final_music(fade_in_duration: float = 4.0, target_volume_db: float = -2.0) -> void:
	if _final_music_player == null:
		_final_music_player = AudioStreamPlayer.new()
		_final_music_player.name = "FinalMusicPlayer"
		_final_music_player.bus = &"Master"
		add_child(_final_music_player)
		
	if final_music != null:
		_final_music_player.stream = final_music
	elif ResourceLoader.exists("res://assets/sounds/its end.ogg"):
		_final_music_player.stream = load("res://assets/sounds/its end.ogg")
		
	_final_music_player.volume_db = -45.0
	
	if _final_music_tween and _final_music_tween.is_valid():
		_final_music_tween.kill()
		
	if is_inside_tree():
		_final_music_player.play()
		_final_music_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_final_music_tween.tween_property(_final_music_player, "volume_db", target_volume_db, fade_in_duration)

func _on_revelation_finished() -> void:
	# Финал: смерть игрока / жертва принята
	if player_node:
		player_node.can_walk = false
		player_node.can_move = false
		
	# Резкая остановка нагнетания звука сразу на пике (cut to dead silence)
	if _tension_audio_player and _tension_audio_player.playing:
		_tension_audio_player.stop()
		
	# Короткий глухой удар смерти (kill_sfx)
	var kill_sfx = preload("res://assets/sounds/kill.ogg")
	_play_audio(kill_sfx, 8.0, global_position if is_inside_tree() else Vector3.ZERO)
		
	var death_canvas = CanvasLayer.new()
	death_canvas.layer = 30
	add_child(death_canvas)
	
	# РЕЗКИЙ черный экран (без плавного затухания, моментальный жесткий срез)
	var black_rect = ColorRect.new()
	black_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	black_rect.color = Color(0.0, 0.0, 0.0, 1.0)
	black_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	death_canvas.add_child(black_rect)
	
	# РЕЗКО появляющийся текст Zugzwang сразу на экране
	var title = Label.new()
	title.text = "Z U G Z W A N G\n\nПоложение, при котором любой ход ведёт к ухудшению ситуации."
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	title.modulate.a = 1.0
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 0.95))
	death_canvas.add_child(title)

# ==============================================================================
# 3. ПАТ (Stalemate / Breach & Gunfire Assault)
# ==============================================================================

func _play_draw_ending() -> void:
	_is_ending_active = true
	_setup_audio_player()
	
	# Блокируем перемещение игрока на время драматического финала
	if player_node:
		player_node.can_walk = false
		player_node.can_move = false
		
	# 1. Внезапный яростный стук в дверь (knock3)
	var knock_sfx = preload("res://assets/sounds/knock3.ogg")
	var door_pos: Vector3 = door_node.global_position if (door_node and door_node.is_inside_tree()) else Vector3(16, 2, 0)
	_play_audio(knock_sfx, 14.0, door_pos)
	
	# Тряска двери
	var target_door = door_pivot if door_pivot else door_node
	if target_door and is_inside_tree():
		if _door_tween and _door_tween.is_valid():
			_door_tween.kill()
		_door_tween = create_tween()
		for i in range(8):
			var offset: float = 0.15 if (i % 2 == 0) else -0.15
			var base_z: float = _initial_door_pos.z if _initial_door_pos != Vector3.ZERO else target_door.position.z
			_door_tween.tween_property(target_door, "position:z", base_z + offset, 0.06)
		_door_tween.tween_property(target_door, "rotation_degrees:y", -25.0, 0.1) # Дверь приоткрывается
	elif target_door:
		target_door.rotation_degrees.y = -25.0
		
	if not is_inside_tree():
		return
		
	# 2. Автоматная стрельба через 0.6 секунды
	var gun_timer = get_tree().create_timer(0.6)
	gun_timer.timeout.connect(func():
		var burst_stream = GunfireGen.create_burst_fire_sound(5, 0.08)
		_audio_player.stream = burst_stream
		_audio_player.volume_db = 15.0
		_audio_player.play()
		
		# Тряска камеры игрока и падение на пол
		if player_node:
			player_node.can_walk = false
			player_node.can_move = false
			if "is_defeat_locked" in player_node:
				player_node.is_defeat_locked = true
			var cam = player_node.get_node_or_null("head/Camera3D") as Camera3D
			if cam:
				var fall_tween = create_tween().set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
				fall_tween.tween_property(cam, "position:y", -1.8, 0.4)
				fall_tween.parallel().tween_property(cam, "rotation_degrees:z", 35.0, 0.4)
				
		# 3. После окончания звуков выстрелов и падения (через 1.4 секунды) — РЕЗКО чёрный экран!
		var assault_finish_timer = get_tree().create_timer(1.4)
		assault_finish_timer.timeout.connect(func():
			if _audio_player and _audio_player.playing:
				_audio_player.stop()
			_show_abrupt_draw_screen()
		)
	)

## Возврат комнаты, света, камеры и окружения в первоначальное чистое состояние
func restore_room_to_initial() -> void:
	_is_ending_active = false
	if _tension_audio_player and _tension_audio_player.playing:
		_tension_audio_player.stop()
	if _final_music_player and _final_music_player.playing:
		_final_music_player.stop()
	if _final_music_tween and _final_music_tween.is_valid():
		_final_music_tween.kill()
	if _door_audio_tween and _door_audio_tween.is_valid():
		_door_audio_tween.kill()
	if _door_audio_player and _door_audio_player.playing:
		_door_audio_player.stop()
		
	_cleanup_explosion_particles()
	
	# 1. Восстановление света подвесной лампы и радиоприёмника
	if hanging_bulb:
		if "light_intensity_ratio" in hanging_bulb:
			hanging_bulb.light_intensity_ratio = 1.0
		var bulb_light = hanging_bulb.get_node_or_null("OmniLight3D") as OmniLight3D
		if bulb_light:
			bulb_light.light_energy = 1.0
			bulb_light.light_color = Color(1.0, 0.941, 0.663, 1.0)
			
	if radio_dial_light:
		radio_dial_light.light_energy = 0.8
		
	# 2. Восстановление тумана и пост-процессинга
	if world_environment and world_environment.environment:
		var env = world_environment.environment
		env.volumetric_fog_albedo = _initial_env_fog_color
		env.adjustment_saturation = 0.9
		
	# 3. Восстановление камеры наблюдения
	if security_camera:
		var spot = security_camera.get_node_or_null("NightVisionSpotLight") as SpotLight3D
		if spot:
			spot.light_color = Color(1.0, 0.1, 0.1, 1.0)
			spot.light_energy = 1.6
			spot.spot_range = 28.0
			
	# 4. Закрытие двери и сброс секретной комнаты
	var target_door = door_pivot if door_pivot else door_node
	if target_door:
		if _door_tween and _door_tween.is_valid():
			_door_tween.kill()
		target_door.rotation_degrees.y = _initial_door_rot.y
		if _initial_door_pos != Vector3.ZERO:
			target_door.position = _initial_door_pos
			
	if observation_room:
		var blocker = observation_room.get_node_or_null("DoorBlocker") as StaticBody3D
		if blocker:
			blocker.collision_layer = 0
			var col = blocker.get_node_or_null("CollisionShape3D") as CollisionShape3D
			if col:
				col.set_deferred("disabled", true)
		var trigger = observation_room.get_node_or_null("EntryTrigger") as Area3D
		if trigger:
			trigger.set_deferred("monitoring", true)
		
	# 5. Возврат управления игроку
	if player_node:
		if player_node.has_method("reset_to_start"):
			player_node.reset_to_start()
		else:
			player_node.can_walk = true
			player_node.can_move = true
			var cam = player_node.get_node_or_null("head/Camera3D") as Camera3D
			if cam:
				cam.position.y = -0.89668
				cam.rotation_degrees.z = 0.0
				cam.h_offset = 0.0
				cam.v_offset = 0.0

func _fade_and_reload(reason: String) -> void:
	var bus: Node = _get_event_bus()
	if bus:
		if reason == "defeat":
			if bus.has_method("get_random_defeat_quote"):
				bus.restart_quote = bus.get_random_defeat_quote()
			bus.death_count += 1
			bus.player_losses += 1
			# Учитываем проигрыш игрока и меняем сложность ИИ (переход на следующее прохождение / поддавки)
			bus.current_playthrough = maxi(2, bus.current_playthrough + 1)
			bus.reset_game_state(bus.current_playthrough)
		elif reason == "draw":
			if bus.has_method("get_random_draw_quote"):
				bus.restart_quote = bus.get_random_draw_quote()
			bus.reset_game_state(bus.current_playthrough)
			
	restore_room_to_initial()
	if is_inside_tree():
		get_tree().reload_current_scene()
