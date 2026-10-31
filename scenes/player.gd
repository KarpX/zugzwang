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
var _chess_board_node: Node3D = null

# Параметры тряски камеры (Screen Shake при взятиях и стуках)
var _trauma: float = 0.0
var _shake_decay: float = 2.8        # Скорость затухания
var _max_shake_offset: float = 0.045 # Максимальное смещение в метрах
var _max_shake_roll: float = 0.035   # Максимальный крен в радианах

func _get_event_bus() -> Node:
	if not is_inside_tree():
		return null
	if has_node("/root/EventBus"):
		return get_node("/root/EventBus")
	return null

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
	add_child(canvas)
	
	_hud_prompt = Label.new()
	_hud_prompt.text = ""
	_hud_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hud_prompt.anchors_preset = Control.PRESET_BOTTOM_WIDE
	_hud_prompt.offset_top = -90.0
	_hud_prompt.offset_bottom = -30.0
	_hud_prompt.add_theme_font_size_override("font_size", 20)
	_hud_prompt.add_theme_color_override("font_color", Color(0.9, 0.9, 0.85, 0.9))
	_hud_prompt.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_hud_prompt.add_theme_constant_override("shadow_offset_x", 1)
	_hud_prompt.add_theme_constant_override("shadow_offset_y", 1)
	canvas.add_child(_hud_prompt)

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
func apply_camera_shake(amount: float = 0.6) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)

## Обработчик взятия фигуры (сокрушительный удар по доске)
func _on_piece_captured(_piece_type: String, _is_white: bool) -> void:
	apply_camera_shake(0.65)

## Обработчик стука в дверь бункера
func _on_door_knock_triggered(knock_level: int) -> void:
	apply_camera_shake(0.35 * float(knock_level))

## Обновление тряски камеры со спадом (используем только h_offset и v_offset для предотвращения крена камеры)
func _update_camera_shake(delta: float) -> void:
	if _trauma <= 0.0:
		if camera != null:
			camera.h_offset = 0.0
			camera.v_offset = 0.0
		return
		
	_trauma = maxf(0.0, _trauma - _shake_decay * delta)
	var shake_power: float = _trauma * _trauma
	
	if camera != null:
		camera.h_offset = randf_range(-1.0, 1.0) * _max_shake_offset * shake_power
		camera.v_offset = randf_range(-1.0, 1.0) * _max_shake_offset * shake_power

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
		
		# Интерполируем yaw и pitch независимо, строго удерживая roll = 0.
		# Это полностью исключает крен и заваливание горизонта при подходе к столу с любой стороны.
		var start_euler: Vector3 = start_trans.basis.orthonormalized().get_euler(EULER_ORDER_YXZ)
		var target_euler: Vector3 = cam_marker.global_transform.basis.orthonormalized().get_euler(EULER_ORDER_YXZ)
		
		var start_yaw: float = start_euler.y
		var target_yaw: float = target_euler.y
		var diff_yaw: float = wrapf(target_euler.y - start_euler.y, -PI, PI)
		var start_pitch: float = start_euler.x
		var target_pitch: float = target_euler.x
		
		if head == null:
			head = get_node_or_null("head")
		if head != null:
			_cam_tween.tween_property(head, "rotation:x", 0.0, 0.75)
		_cam_tween.tween_property(self, "rotation:y", rotation.y + diff_yaw, 0.75)
		
		_cam_tween.tween_method(func(t: float):
			var cur_origin: Vector3 = start_origin.lerp(target_origin, t)
			var cur_yaw: float = start_yaw + diff_yaw * t
			var cur_pitch: float = lerpf(start_pitch, target_pitch, t)
			var cur_basis: Basis = Basis.from_euler(Vector3(cur_pitch, cur_yaw, 0.0), EULER_ORDER_YXZ)
			camera.global_transform = Transform3D(cur_basis, cur_origin)
		, 0.0, 1.0, 0.75)
	
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
