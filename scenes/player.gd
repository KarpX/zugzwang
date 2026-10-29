extends CharacterBody3D

@export var speed: float = 7.0
@export var jump_velocity: float = 4.5
@export var sensitivity: float = 0.003

@onready var head: Node3D = $head
@onready var camera: Camera3D = $head/Camera3D

# Переменные взаимодействия с ПК / окружением
var is_working: bool = false
var old_cam_transform: Transform3D
var can_move: bool = true       # Управляет возможностью вращать камеру
var can_walk: bool = true       # Управляет перемещением на WASD
var can_exit_pc: bool = false

func _ready() -> void:
	# Скрываем и блокируем курсор в окне игры при старте
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	# 1. Вращение камеры (только если курсор захвачен и движение не заблокировано)
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if can_move:
			# Поворот персонажа влево-вправо
			rotate_y(-event.relative.x * sensitivity)
			# Наклон головы вверх-вниз
			head.rotate_x(-event.relative.y * sensitivity)
			# Ограничиваем угол обзора (чтобы не сломать шею на 360 градусов)
			head.rotation.x = clamp(head.rotation.x, deg_to_rad(-85), deg_to_rad(85))

	# 2. Быстрый выход/возврат курсора по Escape (для отладки)
	if event.is_action_pressed("ui_cancel") and not is_working:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	# Гравитация должна действовать всегда, даже если персонаж не ходит
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Если ходить запрещено (например, сели за ПК) — плавно останавливаемся
	if not can_walk:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)
		move_and_slide()
		return

	# Получение направления ходьбы
	var input_dir := Input.get_vector("Left", "Right", "Forward", "Back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	move_and_slide()
