class_name PumpkinFlicker
extends OmniLight3D

## Реалистичное мерцание свечи внутри праздничной тыквы (Jack-o'-lantern)
@export var base_energy: float = 1.15
@export var flicker_intensity: float = 0.22
@export var flicker_speed: float = 8.5

var _time: float = 0.0

func _process(delta: float) -> void:
	_time += delta * flicker_speed
	# Органический составной шум из некратных гармоник
	var n: float = sin(_time * 1.0) * 0.42 + sin(_time * 2.7) * 0.35 + sin(_time * 5.3) * 0.23
	light_energy = max(0.2, base_energy + n * flicker_intensity)
