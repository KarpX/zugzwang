extends CharacterBody3D

@export var speed: float = 7.0
@export var jump_velocity: float = 4.5
@export var sensitivity: float = 0.003
@export var table_interact_distance: float = 4.2
@export var table_world_center: Vector3 = Vector3(16.0, 0.0, 20.0)

@onready var head: Node3D = $head
@onready var camera: Camera3D = $head/Camera3D
@onready var player_steps: AudioStreamPlayer3D = $PlayerSteps

# Режимы управления
var is_board_mode: bool = false
var can_move: bool = true       # Вращение камеры мышью
var can_walk: bool = true       # Перемещение WASD
var is_near_table: bool = false

var _cam_tween: Tween = null
var _hud_prompt: Label = null
var _radio_subtitle_label: Label = null
var _radio_tween: Tween = null
var _chess_board_node: Node3D = null

const RADIO_REPORTS_WHITE: Dictionary = {
	"pawn": [
		"«1-е отделение 3-го взвода перестало выходить на связь...»",
		"«Окоп 14 засыпан землей. Живых нет.»",
		"«Рядовой погиб на переправе.»"
	],
	"knight": [
		"«Разведгруппа \"Сокол\" накрыта кассетным ударом в секторе B!»",
		"«Бронемашина связи уничтожена дроном. Координат нет!»"
	],
	"bishop": [
		"«Артиллерийский расчет батареи \"Север\" уничтожен контрбатарейным огнем!»",
		"«Наводчики погибли. Мы ослепли на восточном фланге!»"
	],
	"rook": [
		"«ДОТ-4 пробит бетонобойным снарядом! Весь гарнизон погиб!»",
		"«Укрепрайон \"Цитадель\" пал! Враг прорвал главную линию обороны!»"
	],
	"queen": [
		"«ШТАБ АРМИИ УНИЧТОЖЕН ПРЯМЫМ ПОПАДАНИЕМ! КОМАНДОВАНИЯ БОЛЬШЕ НЕТ!»",
		"«ПОЛНЫЙ РАЗГРОМ! ВСЕМ ПОДРАЗДЕЛЕНИЯМ — ДЕЙСТВОВАТЬ САМОСТОЯТЕЛЬНО!»"
	]
}

# Параметры тряски камеры (Screen Shake при взятиях и стуках)
var _trauma: float = 0.0
var _shake_decay: float = 2.8        # Базовая скорость затухания
var _current_shake_decay: float = 2.8
var _base_max_shake_offset: float = 0.045 # Базовое смещение в метрах
var _current_max_shake_offset: float = 0.045
var _current_max_roll: float = 0.0   # Дополнительный крен при сильной тряске

func _get_event_bus() -> Node:
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/EventBus")

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_setup_hud()
	_find_chess_board()
	_setup_audio_listener()
	
	var bus = _get_event_bus()
	if bus:
		if bus.has_signal("piece_captured"):
			bus.piece_captured.connect(_on_piece_captured)
		if bus.has_signal("door_knock_triggered"):
			bus.door_knock_triggered.connect(_on_door_knock_triggered)

func _setup_audio_listener() -> void:
	if camera != null and camera.get_node_or_null("AudioListener3D") == null:
		var listener = AudioListener3D.new()
		listener.name = "AudioListener3D"
		camera.add_child(listener)
		listener.make_current()

func _setup_hud() -> void:
	var canvas = CanvasLayer.new()
	canvas.name = "PlayerHUD"
	canvas.layer = 20 # Поверх 3D-графики и спецэффектов
	add_child(canvas)
	
	var root_ctrl = Control.new()
	root_ctrl.name = "HudRoot"
	root_ctrl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(root_ctrl)
	
	_hud_prompt = Label.new()
	_hud_prompt.name = "HudPrompt"
	_hud_prompt.text = ""
	_hud_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hud_prompt.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hud_prompt.offset_top = -65.0
	_hud_prompt.offset_bottom = -20.0
	_hud_prompt.add_theme_font_size_override("font_size", 20)
	_hud_prompt.add_theme_color_override("font_color", Color(0.9, 0.9, 0.85, 0.9))
	_hud_prompt.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_hud_prompt.add_theme_constant_override("shadow_offset_x", 1)
	_hud_prompt.add_theme_constant_override("shadow_offset_y", 1)
	_hud_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_ctrl.add_child(_hud_prompt)

	# Радио-сводка военных потерь (субтитры внизу экрана)
	_radio_subtitle_label = Label.new()
	_radio_subtitle_label.name = "RadioSubtitle"
	_radio_subtitle_label.text = ""
	_radio_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_radio_subtitle_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_radio_subtitle_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_radio_subtitle_label.offset_left = 40.0
	_radio_subtitle_label.offset_right = -40.0
	_radio_subtitle_label.offset_top = -145.0
	_radio_subtitle_label.offset_bottom = -75.0
	_radio_subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_radio_subtitle_label.add_theme_font_size_override("font_size", 22)
	_radio_subtitle_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.35, 1.0))
	_radio_subtitle_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1.0))
	_radio_subtitle_label.add_theme_constant_override("shadow_offset_x", 2)
	_radio_subtitle_label.add_theme_constant_override("shadow_offset_y", 2)
	_radio_subtitle_label.add_theme_color_override("font_outline_color", Color(0.04, 0.04, 0.04, 0.95))
	_radio_subtitle_label.add_theme_constant_override("outline_size", 5)
	_radio_subtitle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_radio_subtitle_label.modulate.a = 0.0
	root_ctrl.add_child(_radio_subtitle_label)

func _find_chess_board() -> void:
	if not is_inside_tree():
		return
	var tree = get_tree()
	if tree:
		var boards = tree.get_nodes_in_group("chess_board")
		if boards.size() > 0:
			_chess_board_node = boards[0]
			return
	_chess_board_node = get_node_or_null("../TableStatic/Table/ChessBoard")

func _unhandled_input(event: InputEvent) -> void:
	# 1. Вращение камеры от первого лица (только в свободном режиме ходьбы)
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if can_move:
			rotate_y(-event.relative.x * sensitivity)
			head.rotate_x(-event.relative.y * sensitivity)
			head.rotation.x = clamp(head.rotation.x, deg_to_rad(-85), deg_to_rad(85))

	# 2. Взаимодействие со столом по клавише [E]
	var is_interact_pressed: bool = event.is_action_pressed("Interact")
	if not is_interact_pressed and event is InputEventKey:
		if event.pressed and not event.echo and event.keycode == KEY_E:
			is_interact_pressed = true
			
	if is_interact_pressed:
		if is_board_mode:
			exit_board_mode()
		elif is_near_table:
			enter_board_mode()

	# 3. Выход из-за стола по Escape
	if event.is_action_pressed("ui_cancel") and is_board_mode:
		exit_board_mode()

func _process(delta: float) -> void:
	_update_camera_shake(delta)

## Применение импульса тряски камеры
func apply_camera_shake(amount: float = 0.6, decay_rate: float = 2.8, max_offset: float = 0.045, max_roll: float = 0.0) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)
	_current_shake_decay = decay_rate
	_current_max_shake_offset = maxf(_current_max_shake_offset, max_offset)
	_current_max_roll = maxf(_current_max_roll, max_roll)

## Показ радио-сводки военных потерь (субтитры внизу экрана)
func show_radio_report(piece_type: String) -> void:
	if _radio_subtitle_label == null or not is_inside_tree():
		return
		
	var pool: Array = RADIO_REPORTS_WHITE.get(piece_type, [])
	if pool.is_empty():
		return
		
	var text_line: String = pool[randi() % pool.size()]
	
	# Цветовая кодировка степени тревоги в зависимости от ранга фигуры
	match piece_type:
		"queen":
			_radio_subtitle_label.add_theme_color_override("font_color", Color(1.0, 0.28, 0.28, 1.0))
		"rook":
			_radio_subtitle_label.add_theme_color_override("font_color", Color(1.0, 0.65, 0.25, 1.0))
		"knight", "bishop":
			_radio_subtitle_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.35, 1.0))
		_:
			_radio_subtitle_label.add_theme_color_override("font_color", Color(0.95, 0.90, 0.75, 1.0))
			
	_radio_subtitle_label.text = text_line
	_radio_subtitle_label.visible_ratio = 1.0
	_radio_subtitle_label.modulate.a = 0.15
	
	if _radio_tween and _radio_tween.is_valid():
		_radio_tween.kill()
		
	_radio_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# Быстрое и надежное проявление текста
	_radio_tween.tween_property(_radio_subtitle_label, "modulate:a", 1.0, 0.20)
	# Время удержания на экране
	_radio_tween.tween_interval(4.5)
	# Плавное угасание в темноту
	_radio_tween.tween_property(_radio_subtitle_label, "modulate:a", 0.0, 0.8)

## Обработчик взятия фигуры (сотрясение комнаты и радио-сводка потерь)
func _on_piece_captured(piece_type: String, is_white: bool) -> void:
	if is_white:
		var piece_key: String = piece_type.to_lower()
		match piece_key:
			"pawn":
				apply_camera_shake(0.20, 3.2, 0.035, 0.0)
			"knight", "bishop":
				apply_camera_shake(0.40, 2.5, 0.055, 0.015)
			"rook":
				apply_camera_shake(0.65, 2.0, 0.085, 0.035)
			"queen":
				# Катастрофа при потере Ферзя: камера трясется ОЧЕНЬ сильно (максимальная травма, долгое затухание, амплитуда 14см и крен)
				apply_camera_shake(1.0, 0.85, 0.14, 0.07)
			_:
				apply_camera_shake(0.30, 2.8, 0.045, 0.0)
		show_radio_report(piece_key)
	else:
		# Взятие черной фигуры игроком: отдача удара без панических сводок
		apply_camera_shake(0.30, 2.8, 0.045, 0.0)

## Обработчик стука в дверь бункера
func _on_door_knock_triggered(knock_level: int) -> void:
	apply_camera_shake(0.35 * float(knock_level), 2.2, 0.05 * float(knock_level), 0.015 * float(knock_level))

## Обновление тряски камеры со спадом
func _update_camera_shake(delta: float) -> void:
	if _trauma <= 0.0:
		if camera != null:
			camera.h_offset = 0.0
			camera.v_offset = 0.0
			camera.rotation.z = 0.0
		_current_shake_decay = _shake_decay
		_current_max_shake_offset = _base_max_shake_offset
		_current_max_roll = 0.0
		return
		
	_trauma = maxf(0.0, _trauma - _current_shake_decay * delta)
	var shake_power: float = _trauma * _trauma
	
	if camera != null:
		camera.h_offset = randf_range(-1.0, 1.0) * _current_max_shake_offset * shake_power
		camera.v_offset = randf_range(-1.0, 1.0) * _current_max_shake_offset * shake_power
		if _current_max_roll > 0.0:
			camera.rotation.z = randf_range(-1.0, 1.0) * _current_max_roll * shake_power

func _physics_process(delta: float) -> void:
	# Гравитация
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Проверка дистанции до шахматного стола (в горизонтальной плоскости XZ)
	if not is_board_mode:
		var current_pos: Vector3 = global_position if is_inside_tree() else position
		var horiz_dist: float = Vector2(current_pos.x, current_pos.z).distance_to(Vector2(table_world_center.x, table_world_center.z))
		is_near_table = (horiz_dist <= table_interact_distance)
		if _hud_prompt != null:
			_hud_prompt.text = "[E] Сесть за шахматный стол" if is_near_table else ""

	if not can_walk:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)
		move_and_slide()
		_update_footsteps(Vector2.ZERO)
		return

	# Перемещение WASD
	var input_dir := Input.get_vector("Left", "Right", "Forward", "Back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	move_and_slide()
	_update_footsteps(input_dir)

## Обновление звука шагов: играет при движении и останавливается при остановке
func _update_footsteps(input_dir: Vector2) -> void:
	if player_steps == null:
		return
	
	var has_input: bool = not input_dir.is_zero_approx()
	var horizontal_speed_sq: float = Vector2(velocity.x, velocity.z).length_squared()
	var is_moving: bool = can_walk and is_on_floor() and has_input and (horizontal_speed_sq > 0.1)
	
	if is_moving:
		if not player_steps.playing:
			player_steps.play()
	else:
		if player_steps.playing:
			player_steps.stop()

## Плавный переход камеры за шахматный стол
func enter_board_mode() -> void:
	if is_board_mode:
		return
	if camera == null:
		camera = get_node_or_null("head/Camera3D")
	if _chess_board_node == null:
		_find_chess_board()
	if _chess_board_node == null:
		return
		
	var cam_marker: Marker3D = _chess_board_node.get_node_or_null("CameraPoint")
	if not cam_marker:
		return
		
	is_board_mode = true
	can_walk = false
	can_move = false
	if player_steps != null and player_steps.playing:
		player_steps.stop()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _hud_prompt != null:
		_hud_prompt.text = "[E] / [Esc] Встать из-за стола"
	
	if camera != null:
		if _cam_tween and _cam_tween.is_valid():
			_cam_tween.kill()
		_cam_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		
		# Сбрасываем остаточную тряску
		_trauma = 0.0
		camera.h_offset = 0.0
		camera.v_offset = 0.0
		camera.rotation.z = 0.0
		
		var start_trans: Transform3D = camera.global_transform
		var start_origin: Vector3 = start_trans.origin
		var target_origin: Vector3 = cam_marker.global_position
		
		# Интерполируем yaw и pitch в одной плавной траектории напрямую в точку CameraPoint (roll строго = 0)
		var start_euler: Vector3 = start_trans.basis.orthonormalized().get_euler(EULER_ORDER_YXZ)
		var target_euler: Vector3 = cam_marker.global_transform.basis.orthonormalized().get_euler(EULER_ORDER_YXZ)
		
		var start_yaw: float = start_euler.y
		var diff_yaw: float = wrapf(target_euler.y - start_euler.y, -PI, PI)
		var start_pitch: float = start_euler.x
		var target_pitch: float = target_euler.x
		
		_cam_tween.tween_method(func(t: float):
			var cur_origin: Vector3 = start_origin.lerp(target_origin, t)
			var cur_yaw: float = start_yaw + diff_yaw * t
			var cur_pitch: float = lerpf(start_pitch, target_pitch, t)
			var cur_basis: Basis = Basis.from_euler(Vector3(cur_pitch, cur_yaw, 0.0), EULER_ORDER_YXZ)
			camera.global_transform = Transform3D(cur_basis, cur_origin)
		, 0.0, 1.0, 0.75)
		_cam_tween.chain().tween_callback(func():
			if camera != null and cam_marker != null and is_instance_valid(cam_marker):
				camera.global_transform = cam_marker.global_transform
		)
	
	var bus = _get_event_bus()
	if bus:
		bus.camera_mode_changed.emit(true)
		bus.player_made_action.emit()
	elif _chess_board_node.has_method("_on_camera_mode_changed"):
		# Прямой вызов если шина не зарегистрирована (например, в изолированных тестах)
		_chess_board_node._on_camera_mode_changed(true)

## Возврат камеры обратно к телу персонажа
func exit_board_mode() -> void:
	if not is_board_mode:
		return
		
	is_board_mode = false
	can_walk = true
	can_move = true
	if _hud_prompt != null:
		_hud_prompt.text = ""
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	if camera != null:
		if _cam_tween and _cam_tween.is_valid():
			_cam_tween.kill()
		_cam_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		_cam_tween.tween_property(camera, "transform", Transform3D.IDENTITY, 0.65)
	
	var bus = _get_event_bus()
	if bus:
		bus.camera_mode_changed.emit(false)
		bus.player_made_action.emit()
	elif _chess_board_node and _chess_board_node.has_method("_on_camera_mode_changed"):
		_chess_board_node._on_camera_mode_changed(false)
