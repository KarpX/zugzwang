class_name SecurityCamera
extends Node3D

## Скорость поворота сервопривода камеры (радианы в секунду)
@export_range(0.5, 10.0, 0.1) var tracking_speed: float = 2.2

## Смещение цели по высоте (целимся в грудь/голову игрока)
@export var vertical_offset: float = 1.8

## Цель для слежения (если не задана, ищется узел в группе "player")
@export var target: Node3D = null

## Ограничения вертикального угла наклона (Pitch) в градусах
@export var min_pitch_deg: float = -75.0
@export var max_pitch_deg: float = 20.0

## Порог угла (в градусах), при котором камера считается поворачивающейся
@export var turn_threshold_deg: float = 0.2

@onready var camera_sound: AudioStreamPlayer3D = get_node_or_null("CameraSound")

func _ready() -> void:
	if camera_sound == null:
		camera_sound = get_node_or_null("CameraSound")
	if camera_sound and camera_sound.stream is AudioStreamOggVorbis:
		(camera_sound.stream as AudioStreamOggVorbis).loop = true
	_resolve_target()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_DISABLED or what == NOTIFICATION_UNPARENTED:
		_update_camera_sound(false)

func _resolve_target() -> void:
	if target and is_instance_valid(target):
		return
	
	# Сначала ищем по иерархии нод в комнате (работает всегда)
	var player_node: Node = get_node_or_null("../../../player")
	if player_node is Node3D:
		target = player_node as Node3D
		return

	# Поиск игрока через дерево групп, если узел в SceneTree
	if is_inside_tree() and get_tree():
		var player_in_group: Node = get_tree().get_first_node_in_group("player")
		if player_in_group is Node3D:
			target = player_in_group as Node3D
			return
		
		var root_player: Node = get_node_or_null("/root/room/player")
		if root_player is Node3D:
			target = root_player as Node3D

func _process(delta: float) -> void:
	if not is_inside_tree():
		return

	if not target or not is_instance_valid(target):
		_resolve_target()
		if not target:
			_update_camera_sound(false)
			return

	var target_pos: Vector3 = target.global_position + Vector3(0.0, vertical_offset, 0.0)
	var dir_to_target: Vector3 = target_pos - global_position
	if dir_to_target.length_squared() < 0.1:
		_update_camera_sound(false)
		return

	# Вектор "вверх" с защитой от вертикального вырождения
	var up_vec: Vector3 = Vector3.UP
	var dir_norm: Vector3 = dir_to_target.normalized()
	if absf(dir_norm.dot(up_vec)) > 0.99:
		up_vec = Vector3.FORWARD

	# Целевой трансформ, направляющий локальную ось -Z на игрока
	var target_transform: Transform3D = global_transform.looking_at(target_pos, up_vec)
	var current_quat: Quaternion = global_basis.get_rotation_quaternion()
	var target_quat: Quaternion = target_transform.basis.get_rotation_quaternion()

	var angle_to_target: float = current_quat.angle_to(target_quat)
	var is_turning: bool = false

	# Если угол до цели превышает минимальный порог, сервопривод камеры поворачивается
	if angle_to_target > deg_to_rad(turn_threshold_deg):
		var slerp_factor: float = clampf(tracking_speed * delta, 0.0, 1.0)
		var next_quat: Quaternion = current_quat.slerp(target_quat, slerp_factor)
		global_basis = Basis(next_quat)
		is_turning = true
	else:
		# Достигли цели — фиксируем направление и останавливаем звук
		global_basis = Basis(target_quat)
		is_turning = false

	_update_camera_sound(is_turning)

## Управление воспроизведением звука сервопривода камеры
func _update_camera_sound(is_turning: bool) -> void:
	if camera_sound == null or not camera_sound.is_inside_tree():
		return

	if is_turning:
		if not camera_sound.playing:
			camera_sound.play()
	else:
		if camera_sound.playing:
			camera_sound.stop()
