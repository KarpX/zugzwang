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

## Полуугол поля зрения / мертвая зона (в градусах).
## Пока цель находится внутри этого угла от оптической оси камеры, камера неподвижна.
## Движение происходит только тогда, когда цель смещает границу поля зрения.
@export_range(1.0, 45.0, 0.5) var fov_margin_deg: float = 14.0

## Автоматически синхронизировать полуугол поля зрения с дочерним SpotLight3D
@export var sync_fov_with_spotlight: bool = true

## Задержка выключения звука сервопривода (сек) для сглаживания микро-пауз между кадрами
@export_range(0.05, 0.5, 0.05) var sound_stop_delay: float = 0.25

@onready var camera_sound: AudioStreamPlayer3D = get_node_or_null("CameraSound")

var _sound_timer: float = 0.0
var _twitch_quat: Quaternion = Quaternion.IDENTITY
var _twitch_tween: Tween = null

func _get_event_bus() -> Node:
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/EventBus")

func _ready() -> void:
	if camera_sound == null:
		camera_sound = get_node_or_null("CameraSound")
	if camera_sound and camera_sound.stream is AudioStreamOggVorbis:
		(camera_sound.stream as AudioStreamOggVorbis).loop = true
	if sync_fov_with_spotlight:
		var spotlight: SpotLight3D = get_node_or_null("NightVisionSpotLight") as SpotLight3D
		if spotlight:
			fov_margin_deg = spotlight.spot_angle
	_resolve_target()
	
	var bus = _get_event_bus()
	if bus and bus.has_signal("piece_captured"):
		bus.piece_captured.connect(_on_piece_captured)

## Нервный рывок сервопривода камеры при потерях фигур
func twitch_camera(intensity: float = 0.35) -> void:
	if _twitch_tween and _twitch_tween.is_valid():
		_twitch_tween.kill()
		
	_update_camera_sound(true)
	
	var yaw_impulse: float = randf_range(0.25, 0.45) * (1.0 if randf() > 0.5 else -1.0) * intensity
	var pitch_impulse: float = randf_range(-0.35, 0.15) * intensity
	var target_q: Quaternion = Quaternion.from_euler(Vector3(pitch_impulse, yaw_impulse, 0.0))
	
	_twitch_tween = create_tween().set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_twitch_tween.tween_method(func(val: float):
		_twitch_quat = Quaternion.IDENTITY.slerp(target_q, val)
	, 1.0, 0.0, 0.75)
	_twitch_tween.finished.connect(func():
		_twitch_quat = Quaternion.IDENTITY
		_update_camera_sound(false)
	)

func _on_piece_captured(piece_type: String, is_white: bool) -> void:
	if not is_white:
		return
	var type: String = piece_type.to_lower()
	match type:
		"knight":
			twitch_camera(0.45)
		"bishop":
			twitch_camera(0.30)
		"rook":
			twitch_camera(0.60)
		"queen":
			twitch_camera(0.95)

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
			_update_camera_sound(false, delta)
			return

	var target_pos: Vector3 = target.global_position + Vector3(0.0, vertical_offset, 0.0)
	var dir_to_target: Vector3 = target_pos - global_position
	if dir_to_target.length_squared() < 0.1:
		_update_camera_sound(false, delta)
		return

	# Вектор "вверх" с защитой от вертикального вырождения
	var up_vec: Vector3 = Vector3.UP
	var dir_norm: Vector3 = dir_to_target.normalized()
	if absf(dir_norm.dot(up_vec)) > 0.99:
		up_vec = Vector3.FORWARD

	# Направление взгляда камеры (локальная ось -Z в мировых координатах)
	var current_forward: Vector3 = -global_basis.z.normalized()
	var cos_angle: float = clampf(current_forward.dot(dir_norm), -1.0, 1.0)
	var angle_to_target: float = acos(cos_angle)
	var fov_margin_rad: float = deg_to_rad(fov_margin_deg)

	# 1. Если цель находится внутри поля зрения камеры — камера неподвижна (с учетом импульса вздрагивания)
	if angle_to_target <= fov_margin_rad:
		if _twitch_quat != Quaternion.IDENTITY:
			var base_quat: Quaternion = global_basis.get_rotation_quaternion()
			global_basis = Basis(base_quat * _twitch_quat)
		_update_camera_sound(false, delta)
		return

	# 2. Цель пересекает границу поля зрения — вычисляем величину выхода за границу
	var excess_angle: float = angle_to_target - fov_margin_rad
	# Минимальный порог для защиты от шума floating-point
	var min_threshold_rad: float = minf(deg_to_rad(turn_threshold_deg), deg_to_rad(0.05))
	if excess_angle <= min_threshold_rad:
		if _twitch_quat != Quaternion.IDENTITY:
			var base_quat: Quaternion = global_basis.get_rotation_quaternion()
			global_basis = Basis(base_quat * _twitch_quat)
		_update_camera_sound(false, delta)
		return

	# Целевой трансформ, направляющий локальную ось -Z прямо на игрока
	var target_transform: Transform3D = global_transform.looking_at(target_pos, up_vec)
	var current_quat: Quaternion = global_basis.get_rotation_quaternion()
	var target_quat: Quaternion = target_transform.basis.get_rotation_quaternion()

	var total_quat_angle: float = current_quat.angle_to(target_quat)
	if total_quat_angle < 0.0001:
		if _twitch_quat != Quaternion.IDENTITY:
			global_basis = Basis(current_quat * _twitch_quat)
		_update_camera_sound(false, delta)
		return

	# Двигаем границу поля зрения со скоростью слежения сервопривода (не более tracking_speed * delta)
	var max_step: float = tracking_speed * delta
	var turn_angle: float = minf(excess_angle, max_step)
	var slerp_fraction: float = clampf(turn_angle / total_quat_angle, 0.0, 1.0)

	var next_quat: Quaternion = current_quat.slerp(target_quat, slerp_fraction)
	global_basis = Basis(next_quat * _twitch_quat)

	_update_camera_sound(true, delta)

## Управление воспроизведением звука сервопривода камеры с поддержкой сглаживания микро-пауз
func _update_camera_sound(is_turning: bool, delta: float = 0.0) -> void:
	if camera_sound == null or not camera_sound.is_inside_tree():
		return

	if is_turning:
		_sound_timer = sound_stop_delay
		if not camera_sound.playing:
			camera_sound.play()
	else:
		if delta > 0.0 and _sound_timer > 0.0:
			_sound_timer -= delta
			if _sound_timer <= 0.0:
				if camera_sound.playing:
					camera_sound.stop()
		else:
			_sound_timer = 0.0
			if camera_sound.playing:
				camera_sound.stop()
