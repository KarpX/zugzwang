class_name HangingLamp
extends MeshInstance3D

## Контроллер реалистичного раскачивания и перебоев со светом подвесной лампы
## Точка опоры (pivot) модели находится вверху провода (на потолке),
## поэтому достаточно вращать узел по осям X и Z.

@export var is_swinging: bool = false      ## Включить ли раскачивание
@export var base_amplitude: float = 0.035  ## Фоновое легкое покачивание (радианы ~ 2 градуса)
@export var swing_speed: float = 2.2       ## Скорость колебаний маятника
@export var damping: float = 0.985         ## Скорость затухания внешних толчков

@export_group("Light Trouble FX")
## Коллекция звуков перебоя со светом (lamp_troubles_1 .. lamp_troubles_4)
@export var trouble_sounds: Array[AudioStream] = [
	preload("res://assets/sounds/lamp_troubles_1.ogg"),
	preload("res://assets/sounds/lamp_troubles_2.ogg"),
	preload("res://assets/sounds/lamp_troubles_3.ogg"),
	preload("res://assets/sounds/lamp_troubles_4.ogg")
]
@export var trouble_sound: AudioStream = preload("res://assets/sounds/lamp_troubles_1.ogg") ## Одиночный fallback
@export var trouble_sound_bus: StringName = &"Sound"
@export var base_light_energy: float = 1.0
@export var base_glow_emission: float = 4.0
@export var trigger_on_pawn_death: bool = true

## Коэффициент интенсивности света (0.0 — полностью выключен, 1.0 — норма)
@export var light_intensity_ratio: float = 1.0:
	set(value):
		light_intensity_ratio = clampf(value, 0.0, 3.0)
		_apply_light_intensity(light_intensity_ratio)

## Точные длительности аудиофайлов lamp_troubles_1 .. lamp_troubles_4
const TROUBLE_DURATIONS: Array[float] = [1.385, 1.846, 1.385, 2.308]

var _time: float = 0.0
var _impulse_angle_x: float = 0.0
var _impulse_angle_z: float = 0.0

var _omni_light: OmniLight3D = null
var _ambient_audio: AudioStreamPlayer3D = null
var _trouble_audio_player: AudioStreamPlayer3D = null
var _anim_player: AnimationPlayer = null
var _glow_material: StandardMaterial3D = null
var _trouble_tween: Tween = null
var _ambient_tween: Tween = null
var _base_ambient_db: float = -8.0
var _is_trouble_playing: bool = false
var _last_sound_index: int = -1

func _get_event_bus() -> Node:
	if not is_inside_tree():
		return null
	if has_node("/root/EventBus"):
		return get_node("/root/EventBus")
	return null

func _ready() -> void:
	# 1. Локальная копия материала свечения колбы (чтобы не портить shared .tres на диске)
	var mat = get_surface_override_material(1)
	if mat is StandardMaterial3D:
		_glow_material = mat.duplicate() as StandardMaterial3D
		set_surface_override_material(1, _glow_material)
		base_glow_emission = _glow_material.emission_energy_multiplier
	elif mesh != null:
		var mesh_mat = mesh.surface_get_material(1)
		if mesh_mat is StandardMaterial3D:
			_glow_material = mesh_mat.duplicate() as StandardMaterial3D
			set_surface_override_material(1, _glow_material)
			base_glow_emission = _glow_material.emission_energy_multiplier

	# 2. Поиск источника света лампы
	_omni_light = get_node_or_null("OmniLight3D") as OmniLight3D
	if _omni_light == null:
		for child in get_children():
			if child is OmniLight3D:
				_omni_light = child
				break
	if _omni_light:
		base_light_energy = _omni_light.light_energy

	# 3. Поиск фонового гула лампы
	_ambient_audio = get_node_or_null("AudioStreamPlayer3D") as AudioStreamPlayer3D
	if _ambient_audio:
		_base_ambient_db = _ambient_audio.volume_db

	# 4. Создание или инициализация 3D-плеера для звуков перебоя со светом
	_trouble_audio_player = get_node_or_null("TroubleAudioPlayer") as AudioStreamPlayer3D
	if _trouble_audio_player == null:
		_trouble_audio_player = AudioStreamPlayer3D.new()
		_trouble_audio_player.name = "TroubleAudioPlayer"
		var init_stream = trouble_sounds[0] if trouble_sounds.size() > 0 else trouble_sound
		_trouble_audio_player.stream = init_stream
		_trouble_audio_player.bus = trouble_sound_bus
		_trouble_audio_player.volume_db = 2.0
		_trouble_audio_player.unit_size = 15.0
		_trouble_audio_player.max_distance = 50.0
		_trouble_audio_player.position = Vector3(0, -14.1, 0)
		add_child(_trouble_audio_player)
	else:
		if _trouble_audio_player.stream == null:
			var init_stream = trouble_sounds[0] if trouble_sounds.size() > 0 else trouble_sound
			_trouble_audio_player.stream = init_stream
		if trouble_sound_bus != &"":
			_trouble_audio_player.bus = trouble_sound_bus

	# 5. Проверка наличия AnimationPlayer
	_anim_player = get_node_or_null("AnimationPlayer") as AnimationPlayer
	if _anim_player:
		_anim_player.animation_finished.connect(func(anim_name: String):
			if anim_name.begins_with("light_trouble"):
				_on_trouble_finished()
		)

	# 6. Подключение к EventBus для реакции на смерть пешек
	var bus = _get_event_bus()
	if bus and bus.has_signal("piece_captured"):
		bus.piece_captured.connect(_on_piece_captured)

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

## Функция для передачи импульса лампе (например, когда игрок задел лампу или при вспышке)
func push(impulse_x: float, impulse_z: float) -> void:
	_impulse_angle_x += impulse_x
	_impulse_angle_z += impulse_z
	is_swinging = true

## Применение текущего коэффициента к источнику света и материалу колбы
func _apply_light_intensity(ratio: float) -> void:
	if _omni_light:
		_omni_light.light_energy = base_light_energy * ratio
	if _glow_material:
		_glow_material.emission_energy_multiplier = base_glow_emission * ratio

## Обработчик события гибели фигуры
func _on_piece_captured(piece_type: String, is_white: bool) -> void:
	if not trigger_on_pawn_death:
		return
	# Выключение света работает ТОЛЬКО при гибели белых пешек
	if piece_type.to_lower() == "pawn" and is_white:
		play_trouble_animation()

## Запуск анимации перебоя со светом со случайным или заданным звуком
func play_trouble_animation(sound_index: int = -1) -> void:
	_kill_active_tweens()
	_is_trouble_playing = true

	# 1. Выбираем случайный звук из коллекции (без прямого повтора предыдущего)
	var sound_idx: int = _pick_sound_index(sound_index)
	var selected_stream: AudioStream = _get_stream_for_index(sound_idx)
	var duration: float = _get_duration_for_index(sound_idx, selected_stream)

	# Оповещаем шину о перебое со светом
	var bus = _get_event_bus()
	if bus and bus.has_signal("lamp_flicker_triggered"):
		bus.lamp_flicker_triggered.emit(sound_idx, duration)

	# 2. Воспроизводим выбранный звук
	if _trouble_audio_player:
		_trouble_audio_player.stream = selected_stream
		_trouble_audio_player.play()

	# 3. Приглушаем фоновый гул лампы на время искрения и восстанавливаем к концу звука
	if _ambient_audio and _ambient_audio.playing:
		_ambient_audio.volume_db = _base_ambient_db - 35.0
		_ambient_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		var duck_wait: float = maxf(0.1, duration - 0.35)
		_ambient_tween.tween_interval(duck_wait)
		_ambient_tween.tween_property(_ambient_audio, "volume_db", _base_ambient_db, 0.35)

	# 4. Первичный толчок маятника лампы
	push(randf_range(-0.11, 0.11), randf_range(-0.08, 0.08))

	# 5. Проверяем наличие индивидуальной AnimationPlayer дорожки
	var anim_name: String = "light_trouble_%d" % (sound_idx + 1)
	if _anim_player:
		if _anim_player.has_animation(anim_name):
			_anim_player.stop()
			_anim_player.play(anim_name)
			_schedule_trouble_impulses(sound_idx)
			return
		elif _anim_player.has_animation("light_trouble") and sound_idx == 0:
			_anim_player.stop()
			_anim_player.play("light_trouble")
			_schedule_trouble_impulses(sound_idx)
			return

	# 6. Процедурная анимация, точно синхронизированная с аудиоволной выбранного звука
	_play_procedural_flicker(sound_idx)

func _pick_sound_index(forced_index: int) -> int:
	if forced_index >= 0:
		_last_sound_index = forced_index
		return forced_index
		
	var pool_size: int = trouble_sounds.size()
	if pool_size <= 1:
		_last_sound_index = 0
		return 0
		
	var candidates: Array[int] = []
	for i in range(pool_size):
		if i != _last_sound_index:
			candidates.append(i)
			
	var chosen: int = candidates[randi() % candidates.size()]
	_last_sound_index = chosen
	return chosen

func _get_stream_for_index(idx: int) -> AudioStream:
	if idx >= 0 and idx < trouble_sounds.size() and trouble_sounds[idx] != null:
		return trouble_sounds[idx]
	return trouble_sound

func _get_duration_for_index(idx: int, stream: AudioStream) -> float:
	if idx >= 0 and idx < TROUBLE_DURATIONS.size():
		return TROUBLE_DURATIONS[idx]
	if stream != null and stream.get_length() > 0.1:
		return stream.get_length()
	return 1.385

## Импульсы раскачивания маятника на пиках искр при воспроизведении через AnimationPlayer
func _schedule_trouble_impulses(sound_idx: int) -> void:
	var impulse_tween = create_tween()
	match sound_idx:
		0:
			impulse_tween.tween_interval(0.92)
			impulse_tween.tween_callback(func(): push(randf_range(-0.08, 0.08), randf_range(-0.05, 0.05)))
			impulse_tween.tween_interval(0.31)
			impulse_tween.tween_callback(func(): push(randf_range(-0.09, 0.09), randf_range(-0.06, 0.06)))
		1:
			impulse_tween.tween_interval(0.42)
			impulse_tween.tween_callback(func(): push(randf_range(-0.11, 0.11), randf_range(-0.07, 0.07)))
			impulse_tween.tween_interval(0.58)
			impulse_tween.tween_callback(func(): push(randf_range(-0.09, 0.09), randf_range(-0.06, 0.06)))
			impulse_tween.tween_interval(0.56)
			impulse_tween.tween_callback(func(): push(randf_range(-0.08, 0.08), randf_range(-0.05, 0.05)))
		2:
			impulse_tween.tween_interval(0.34)
			impulse_tween.tween_callback(func(): push(randf_range(-0.10, 0.10), randf_range(-0.07, 0.07)))
			impulse_tween.tween_interval(0.48)
			impulse_tween.tween_callback(func(): push(randf_range(-0.09, 0.09), randf_range(-0.06, 0.06)))
		3:
			impulse_tween.tween_interval(0.57)
			impulse_tween.tween_callback(func(): push(randf_range(-0.13, 0.13), randf_range(-0.08, 0.08)))
			impulse_tween.tween_interval(0.67)
			impulse_tween.tween_callback(func(): push(randf_range(-0.09, 0.09), randf_range(-0.06, 0.06)))
			impulse_tween.tween_interval(0.81)
			impulse_tween.tween_callback(func(): push(randf_range(-0.06, 0.06), randf_range(-0.04, 0.04)))

## Процедурная анимация мерцания света, синхронизированная с точными пиками аудиоволн
func _play_procedural_flicker(sound_idx: int) -> void:
	_trouble_tween = create_tween().set_trans(Tween.TRANS_LINEAR)

	match sound_idx:
		0: # lamp_troubles_1.ogg (1.385s: спазм 0.00с, тишина 0.08-0.46с, зуммер 0.46-0.86с, искра 0.92с, искра 1.23с)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.05, 0.02)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 1.60, 0.02)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.00, 0.04)
			_trouble_tween.tween_interval(0.38) # Полная тьма
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.35, 0.04)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.20, 0.10)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.55, 0.10)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.30, 0.10)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.60, 0.06)
			_trouble_tween.tween_callback(func(): push(randf_range(-0.08, 0.08), randf_range(-0.05, 0.05)))
			_trouble_tween.tween_property(self, "light_intensity_ratio", 1.35, 0.06)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.05, 0.04)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.15, 0.07)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.50, 0.07)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.75, 0.08)
			_trouble_tween.tween_callback(func(): push(randf_range(-0.09, 0.09), randf_range(-0.06, 0.06)))
			_trouble_tween.tween_property(self, "light_intensity_ratio", 1.45, 0.05)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.90, 0.07)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 1.00, 0.085).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

		1: # lamp_troubles_2.ogg (1.846s: искра 0.00с, гул 0.11-0.42с, двойная искра 0.42с, долгая тьма 0.47-1.00с, искра 1.00с, треск 1.56с)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 1.60, 0.01)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.05, 0.02)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.00, 0.05)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.35, 0.03)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.20, 0.09)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.45, 0.10)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.25, 0.10)
			_trouble_tween.tween_callback(func(): push(randf_range(-0.11, 0.11), randf_range(-0.07, 0.07)))
			_trouble_tween.tween_property(self, "light_intensity_ratio", 1.65, 0.02)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.00, 0.05)
			_trouble_tween.tween_interval(0.53) # Долгая тьма более полусекунды
			_trouble_tween.tween_callback(func(): push(randf_range(-0.09, 0.09), randf_range(-0.06, 0.06)))
			_trouble_tween.tween_property(self, "light_intensity_ratio", 1.40, 0.01)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.35, 0.03)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.60, 0.11)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.40, 0.10)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.70, 0.10)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.10, 0.12)
			_trouble_tween.tween_callback(func(): push(randf_range(-0.08, 0.08), randf_range(-0.05, 0.05)))
			_trouble_tween.tween_property(self, "light_intensity_ratio", 1.50, 0.09)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.85, 0.09)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 1.00, 0.196).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

		2: # lamp_troubles_3.ogg (1.385s: искра 0.00с, тьма 0.02-0.34с, удар 0.34с, зуммер 0.36-0.59с, тьма 0.64-0.82с, щелчок 0.82с)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.05, 0.01)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 1.40, 0.01)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.00, 0.03)
			_trouble_tween.tween_interval(0.29)
			_trouble_tween.tween_callback(func(): push(randf_range(-0.10, 0.10), randf_range(-0.07, 0.07)))
			_trouble_tween.tween_property(self, "light_intensity_ratio", 1.65, 0.01)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.45, 0.05)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.20, 0.08)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.50, 0.08)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.00, 0.06)
			_trouble_tween.tween_interval(0.20)
			_trouble_tween.tween_callback(func(): push(randf_range(-0.09, 0.09), randf_range(-0.06, 0.06)))
			_trouble_tween.tween_property(self, "light_intensity_ratio", 1.55, 0.01)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.60, 0.07)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.80, 0.10)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 1.15, 0.15)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 1.00, 0.235).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

		3: # lamp_troubles_4.ogg (2.308s: тишина 0.00-0.57с, гигантская вспышка 0.57с, тьма 0.71-1.24с, вспышка 1.24с, тьма 1.28-1.96с, зажигание 2.05с)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.00, 0.01)
			_trouble_tween.tween_interval(0.56) # Долгая напряженная пауза в темноте
			_trouble_tween.tween_callback(func(): push(randf_range(-0.13, 0.13), randf_range(-0.08, 0.08)))
			_trouble_tween.tween_property(self, "light_intensity_ratio", 1.75, 0.01)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.60, 0.04)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.35, 0.06)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.00, 0.03)
			_trouble_tween.tween_interval(0.53) # Вторая пауза темноты
			_trouble_tween.tween_callback(func(): push(randf_range(-0.09, 0.09), randf_range(-0.06, 0.06)))
			_trouble_tween.tween_property(self, "light_intensity_ratio", 1.50, 0.01)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.00, 0.03)
			_trouble_tween.tween_interval(0.68) # Третья пауза темноты
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.35, 0.03)
			_trouble_tween.tween_callback(func(): push(randf_range(-0.06, 0.06), randf_range(-0.04, 0.04)))
			_trouble_tween.tween_property(self, "light_intensity_ratio", 1.35, 0.06)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.70, 0.07)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 1.10, 0.08)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 1.00, 0.108).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	_trouble_tween.finished.connect(_on_trouble_finished)

func _on_trouble_finished() -> void:
	_is_trouble_playing = false
	light_intensity_ratio = 1.0
	_apply_light_intensity(1.0)
	if _ambient_audio:
		_ambient_audio.volume_db = _base_ambient_db
	var bus = _get_event_bus()
	if bus and bus.has_signal("lamp_trouble_finished"):
		bus.lamp_trouble_finished.emit()

func _kill_active_tweens() -> void:
	if _trouble_tween and _trouble_tween.is_valid():
		_trouble_tween.kill()
	if _ambient_tween and _ambient_tween.is_valid():
		_ambient_tween.kill()
