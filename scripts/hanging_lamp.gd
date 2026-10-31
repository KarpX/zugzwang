class_name HangingLamp
extends MeshInstance3D

## Контроллер реалистичного раскачивания подвесной лампы
## Точка опоры (pivot) модели находится вверху провода (на потолке),
## поэтому достаточно вращать узел по осям X и Z.

@export var is_swinging: bool = false      ## Включить ли раскачивание
@export var base_amplitude: float = 0.035  ## Фоновое легкое покачивание (радианы ~ 2 градуса)
@export var swing_speed: float = 2.2       ## Скорость колебаний маятника
@export var damping: float = 0.985         ## Скорость затухания внешних толчков

var _time: float = 0.0
var _impulse_angle_x: float = 0.0
var _impulse_angle_z: float = 0.0

func _process(delta: float) -> void:
	if not is_swinging:
		return
		
	_time += delta * swing_speed
	
	# Затухание импульсов от толчков
	_impulse_angle_x *= pow(damping, delta * 60.0)
	_impulse_angle_z *= pow(damping, delta * 60.0)
	
	# Гармоническое качание маятника (по двум осям для объемного движения)
	var z_swing = sin(_time) * (base_amplitude + _impulse_angle_z)
	var x_swing = sin(_time * 0.77 + 0.4) * (base_amplitude * 0.4 + _impulse_angle_x)
	
	rotation.z = z_swing
	rotation.x = x_swing

## Функция для передачи импульса лампе (например, когда игрок задел лампу)
func push(impulse_x: float, impulse_z: float) -> void:
	_impulse_angle_x += impulse_x
	_impulse_angle_z += impulse_z
	is_swinging = true
