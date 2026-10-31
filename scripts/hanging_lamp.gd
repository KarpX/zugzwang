class_name HangingLamp
extends MeshInstance3D

## Контроллер реалистичного раскачивания и перебоев со светом подвесной лампы
## Точка опоры (pivot) модели находится вверху провода (на потолке),
## поэтому достаточно вращать узел по осям X и Z.

## Точные длительности аудиофайлов lamp_troubles_1 .. lamp_troubles_4
const TROUBLE_DURATIONS: Array[float] = [1.385, 1.846, 1.385, 2.308]

## Длительность одного полного аудиоцикла metallic_squeeks.ogg (2.7692с)
const SQUEAK_CYCLE_DURATION: float = 2.769229
## Угловая скорость колебаний маятника, синхронизированная с аудиоциклом скрипа (2*PI / 2.7692)
const SWING_ANGULAR_SPEED: float = TAU / SQUEAK_CYCLE_DURATION

@export_group("Swinging & Squeak")
@export var is_swinging: bool = false      ## Включить ли раскачивание
@export var base_amplitude: float = 0.035  ## Фоновое легкое покачивание (радианы ~ 2 градуса)
@export var swing_speed: float = SWING_ANGULAR_SPEED ## Скорость колебаний маятника, точно синхронизированная с 2.7692с
@export var damping: float = 0.985         ## Скорость затухания внешних толчков
@export var squeak_sound: AudioStream = preload("res://assets/sounds/metallic_squeeks.ogg")
@export var squeak_sound_bus: StringName = &"Sound"
@export var squeak_base_volume_db: float = -14.0
@export var squeak_max_volume_db: float = 1.5

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

const DEFAULT_BASE_AMPLITUDE: float = 0.035

var _time: float = 0.0
var _impulse_angle_x: float = 0.0
var _impulse_angle_z: float = 0.0

var _omni_light: OmniLight3D = null
var _ambient_audio: AudioStreamPlayer3D = null
var _trouble_audio_player: AudioStreamPlayer3D = null
var _squeak_audio_player: AudioStreamPlayer3D = null
var _anim_player: AnimationPlayer = null
var _glow_material: StandardMaterial3D = null
var _trouble_tween: Tween = null
var _ambient_tween: Tween = null
var _amplitude_tween: Tween = null
var _base_ambient_db: float = -8.0
var _is_trouble_playing: bool = false
var _last_sound_index: int = -1

func _get_event_bus() -> Node:
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/EventBus")

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

	# 4.5. Инициализация 3D-плеера для звука скрипа подвеса (metallic_squeeks)
	_squeak_audio_player = get_node_or_null("SqueakAudioPlayer") as AudioStreamPlayer3D
	if _squeak_audio_player == null:
		_squeak_audio_player = AudioStreamPlayer3D.new()
		_squeak_audio_player.name = "SqueakAudioPlayer"
		_squeak_audio_player.unit_size = 8.0
		_squeak_audio_player.max_distance = 35.0
		_squeak_audio_player.position = Vector3(0, 0, 0)
		add_child(_squeak_audio_player)
	_squeak_audio_player.stream = squeak_sound
	_squeak_audio_player.bus = squeak_sound_bus
	_squeak_audio_player.volume_db = squeak_base_volume_db
	if squeak_sound is AudioStreamOggVorbis:
		(squeak_sound as AudioStreamOggVorbis).loop = true
	if is_swinging:
		_squeak_audio_player.play()

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
		if _squeak_audio_player and _squeak_audio_player.playing:
			_squeak_audio_player.stop()
		return
		
	# Запуск воспроизведения скрипа, если раскачивание активно
	if _squeak_audio_player and not _squeak_audio_player.playing:
		_squeak_audio_player.play()

	_time += delta * swing_speed

	# Синхронизация волны звука и покачивания:
	# Корректируем фазу _time по реальной позиции аудиобуфера для устранения малейшего дрифта
	if _squeak_audio_player and _squeak_audio_player.playing:
		var audio_pos: float = _squeak_audio_player.get_playback_position()
		var target_phase: float = (audio_pos / SQUEAK_CYCLE_DURATION) * TAU
		var phase_diff: float = wrapf(target_phase - _time, -PI, PI)
		_time += phase_diff * clampf(delta * 6.0, 0.0, 1.0)
	
	# Затухание импульсов от внешних толчков
	_impulse_angle_x *= pow(damping, delta * 60.0)
	_impulse_angle_z *= pow(damping, delta * 60.0)
	
	# Гармоническое качание маятника по двум осям (эллипс):
	# В точке audio_pos=0.0с (первый скрип) cos(0) = +1.0 (максимальное отклонение)
	# В точке audio_pos=1.38с (второй скрип) cos(PI) = -1.0 (противоположное отклонение)
	var z_swing: float = cos(_time) * (base_amplitude + _impulse_angle_z)
	var x_swing: float = sin(_time) * (base_amplitude * 0.45 + _impulse_angle_x)
	
	rotation.z = z_swing
	rotation.x = x_swing

	# Модуляция громкости скрипа в зависимости от силы покачивания лампы
	if _squeak_audio_player:
		var current_amp: float = maxf(absf(z_swing), absf(x_swing))
		var impulse_factor: float = clampf((current_amp - base_amplitude) / 0.22, 0.0, 1.0)
		_squeak_audio_player.volume_db = lerpf(squeak_base_volume_db, squeak_max_volume_db, impulse_factor)

## Функция для передачи импульса лампе (например, когда игрок задел лампу или при вспышке)
func push(impulse_x: float, impulse_z: float) -> void:
	_impulse_angle_x += impulse_x
	_impulse_angle_z += impulse_z
	is_swinging = true
	if _squeak_audio_player and not _squeak_audio_player.playing:
		_squeak_audio_player.play()

## Увеличение амплитуды качания лампы с плавным затуханием до базового 0.035
func trigger_amplitude_burst(target_amplitude: float, decay_duration: float = 6.5) -> void:
	if _amplitude_tween and _amplitude_tween.is_valid():
		_amplitude_tween.kill()
	base_amplitude = target_amplitude
	is_swinging = true
	if _squeak_audio_player and not _squeak_audio_player.playing:
		_squeak_audio_player.play()
	_amplitude_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_amplitude_tween.tween_property(self, "base_amplitude", DEFAULT_BASE_AMPLITUDE, decay_duration)

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
	if not is_white:
		return
		
	var type: String = piece_type.to_lower()
	match type:
		"pawn":
			# Пешка: 2 самых быстрых звука перебоя (0 и 2). Лампу НЕ раскачиваем!
			play_trouble_animation(-1, [0, 2])
		"knight", "bishop":
			# Конь и Слон: увеличиваем амплитуду до 0.3 с плавным затуханием до 0.035
			trigger_amplitude_burst(0.3, 6.0)
			play_trouble_animation(-1, [0, 1, 2, 3])
		"rook":
			# Ладья: мощный блэкаут на 0.85с со вспышкой перекала (все звуки). Лампу НЕ раскачиваем!
			play_rook_outage()
		"queen":
			# Ферзь: увеличиваем амплитуду до 0.5 с плавным затуханием до 0.035 + катастрофический блэкаут 2.5с!
			trigger_amplitude_burst(0.5, 9.0)
			play_queen_catastrophic_outage(2.5)

## Легкое дрожание света при потере коня/слона
func _play_minor_flicker(duration: float = 0.3) -> void:
	if _trouble_tween and _trouble_tween.is_valid():
		_trouble_tween.kill()
	_trouble_tween = create_tween().set_trans(Tween.TRANS_LINEAR)
	_trouble_tween.tween_property(self, "light_intensity_ratio", 0.65, duration * 0.3)
	_trouble_tween.tween_property(self, "light_intensity_ratio", 1.25, duration * 0.3)
	_trouble_tween.tween_property(self, "light_intensity_ratio", 1.0, duration * 0.4)

## Перебой со светом при потере Ладьи (глубокий блэкаут на 0.45с, вспышка перекала 1.6x)
func play_rook_outage(sound_index: int = -1) -> void:
	_kill_active_tweens()
	_is_trouble_playing = true
	var duration: float = 0.85

	var bus = _get_event_bus()
	if bus and bus.has_signal("lamp_flicker_triggered"):
		bus.lamp_flicker_triggered.emit(-2, duration)

	# Звук искрения из всех доступных звуков
	var sound_idx: int = _pick_sound_index(sound_index, [0, 1, 2, 3])
	if _trouble_audio_player and trouble_sounds.size() > 0:
		_trouble_audio_player.stream = _get_stream_for_index(sound_idx)
		_trouble_audio_player.play()

	_trouble_tween = create_tween().set_trans(Tween.TRANS_LINEAR)
	# Мгновенный блэкаут
	_trouble_tween.tween_property(self, "light_intensity_ratio", 0.0, 0.03)
	_trouble_tween.tween_interval(0.42)
	# Вспышка перекала
	_trouble_tween.tween_property(self, "light_intensity_ratio", 1.6, 0.05)
	_trouble_tween.tween_property(self, "light_intensity_ratio", 0.85, 0.1)
	_trouble_tween.tween_property(self, "light_intensity_ratio", 1.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_trouble_tween.finished.connect(_on_trouble_finished)

## Катастрофический блэкаут при потере Ферзя (свет вырубается на 2.5 секунды)
func play_queen_catastrophic_outage(duration: float = 2.5) -> void:
	_kill_active_tweens()
	_is_trouble_playing = true

	var bus = _get_event_bus()
	if bus and bus.has_signal("lamp_flicker_triggered"):
		bus.lamp_flicker_triggered.emit(-3, duration)

	# Воспроизводим самый длинный звук перебоя (lamp_troubles_4)
	if _trouble_audio_player and trouble_sounds.size() >= 4:
		_trouble_audio_player.stream = trouble_sounds[3]
		_trouble_audio_player.play()

	# Гул полностью приглушается
	if _ambient_audio and _ambient_audio.playing:
		_ambient_audio.volume_db = _base_ambient_db - 45.0
		_ambient_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_ambient_tween.tween_interval(duration - 0.4)
		_ambient_tween.tween_property(_ambient_audio, "volume_db", _base_ambient_db, 0.4)

	_trouble_tween = create_tween().set_trans(Tween.TRANS_LINEAR)
	# Свет мгновенно гаснет в 0.0
	_trouble_tween.tween_property(self, "light_intensity_ratio", 0.0, 0.02)
	_trouble_tween.tween_interval(duration - 0.45) # 2 секунды абсолютной тьмы
	# Попытки запуска генератора
	_trouble_tween.tween_property(self, "light_intensity_ratio", 0.4, 0.04)
	_trouble_tween.tween_property(self, "light_intensity_ratio", 0.05, 0.04)
	_trouble_tween.tween_property(self, "light_intensity_ratio", 0.8, 0.05)
	_trouble_tween.tween_property(self, "light_intensity_ratio", 0.2, 0.05)
	_trouble_tween.tween_property(self, "light_intensity_ratio", 1.5, 0.07)
	_trouble_tween.tween_property(self, "light_intensity_ratio", 1.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_trouble_tween.finished.connect(_on_trouble_finished)

## Запуск анимации перебоя со светом со случайным или заданным звуком
## allowed_indices: разрешенные индексы звуков (например, [0, 2] для быстрых звуков пешки)
func play_trouble_animation(sound_index: int = -1, allowed_indices: Array[int] = []) -> void:
	_kill_active_tweens()
	_is_trouble_playing = true

	# 1. Выбираем случайный звук из разрешенного пула (без прямого повтора предыдущего)
	var sound_idx: int = _pick_sound_index(sound_index, allowed_indices)
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

	# 4. Проверяем наличие индивидуальной AnimationPlayer дорожки
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

func _pick_sound_index(forced_index: int, allowed_indices: Array[int] = []) -> int:
	if forced_index >= 0:
		_last_sound_index = forced_index
		return forced_index
		
	var pool: Array[int] = []
	if not allowed_indices.is_empty():
		for idx in allowed_indices:
			if idx >= 0 and idx < trouble_sounds.size():
				pool.append(idx)
	else:
		for i in range(trouble_sounds.size()):
			pool.append(i)
			
	if pool.is_empty():
		return 0
	if pool.size() == 1:
		_last_sound_index = pool[0]
		return pool[0]
		
	var candidates: Array[int] = []
	for idx in pool:
		if idx != _last_sound_index:
			candidates.append(idx)
			
	if candidates.is_empty():
		candidates = pool
		
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

## Зарезервировано для эффектов на пиках искр (раскачивание контролируется через trigger_amplitude_burst)
func _schedule_trouble_impulses(_sound_idx: int) -> void:
	pass

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
			_trouble_tween.tween_property(self, "light_intensity_ratio", 1.35, 0.06)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.05, 0.04)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.15, 0.07)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.50, 0.07)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.75, 0.08)
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
			_trouble_tween.tween_property(self, "light_intensity_ratio", 1.65, 0.02)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.00, 0.05)
			_trouble_tween.tween_interval(0.53) # Долгая тьма более полусекунды
			_trouble_tween.tween_property(self, "light_intensity_ratio", 1.40, 0.01)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.35, 0.03)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.60, 0.11)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.40, 0.10)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.70, 0.10)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.10, 0.12)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 1.50, 0.09)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.85, 0.09)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 1.00, 0.196).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

		2: # lamp_troubles_3.ogg (1.385s: искра 0.00с, тьма 0.02-0.34с, удар 0.34с, зуммер 0.36-0.59с, тьма 0.64-0.82с, щелчок 0.82с)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.05, 0.01)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 1.40, 0.01)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.00, 0.03)
			_trouble_tween.tween_interval(0.29)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 1.65, 0.01)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.45, 0.05)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.20, 0.08)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.50, 0.08)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.00, 0.06)
			_trouble_tween.tween_interval(0.20)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 1.55, 0.01)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.60, 0.07)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.80, 0.10)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 1.15, 0.15)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 1.00, 0.235).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

		3: # lamp_troubles_4.ogg (2.308s: тишина 0.00-0.57с, гигантская вспышка 0.57с, тьма 0.71-1.24с, вспышка 1.24с, тьма 1.28-1.96с, зажигание 2.05с)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.00, 0.01)
			_trouble_tween.tween_interval(0.56) # Долгая напряженная пауза в темноте
			_trouble_tween.tween_property(self, "light_intensity_ratio", 1.75, 0.01)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.60, 0.04)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.35, 0.06)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.00, 0.03)
			_trouble_tween.tween_interval(0.53) # Вторая пауза темноты
			_trouble_tween.tween_property(self, "light_intensity_ratio", 1.50, 0.01)
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.00, 0.03)
			_trouble_tween.tween_interval(0.68) # Третья пауза темноты
			_trouble_tween.tween_property(self, "light_intensity_ratio", 0.35, 0.03)
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
