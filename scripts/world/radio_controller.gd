class_name RadioController
extends MeshInstance3D

## RadioController — Контроллер радиоприёмника на столе бункера.
## Воспроизводит шум радио (radio_sound.ogg) строго во время анимации текста:
## - Пока идет анимация печати текста — играет шум радио
## - Как только анимация прекращается — звук быстро и плавно затихает (fade-out)

const RADIO_SOUND_PATHS: Array[String] = [
	"res://assets/sounds/voices/radio_sound.ogg",
	"res://assets/sounds/radio_sound.ogg",
	"res://sounds/voices/radio_sound.ogg",
	"res://sounds/radio_sound.ogg"
]

@export var radio_sound: AudioStream = null
@export var base_volume_db: float = 2.5
@export var audio_bus: StringName = &"Sound"

@export var fade_in_time: float = 0.10
@export var fade_out_time: float = 0.35

@onready var audio_player: AudioStreamPlayer3D = get_node_or_null("AudioStreamPlayer3D") as AudioStreamPlayer3D
@onready var dial_glow: OmniLight3D = get_node_or_null("DialGlow") as OmniLight3D

var _radio_stream: AudioStream = null
var _sound_tween: Tween = null
var _glow_tween: Tween = null
var _base_glow_energy: float = 0.20

func _ready() -> void:
	_init_components()
	_load_radio_sound()
	_connect_event_bus()

func _init_components() -> void:
	if audio_player == null:
		audio_player = get_node_or_null("AudioStreamPlayer3D") as AudioStreamPlayer3D
	if audio_player == null:
		audio_player = AudioStreamPlayer3D.new()
		audio_player.name = "AudioStreamPlayer3D"
		audio_player.unit_size = 8.0
		audio_player.max_distance = 25.0
		audio_player.volume_db = base_volume_db
		audio_player.bus = audio_bus
		add_child(audio_player)
	else:
		audio_player.volume_db = base_volume_db
		if audio_bus != &"":
			audio_player.bus = audio_bus

	if dial_glow == null:
		dial_glow = get_node_or_null("DialGlow") as OmniLight3D
	if dial_glow:
		dial_glow.light_energy = _base_glow_energy

func _connect_event_bus() -> void:
	var bus: Node = _get_event_bus()
	if bus:
		if bus.has_signal("radio_phrase_triggered") and not bus.radio_phrase_triggered.is_connected(_on_radio_phrase_triggered):
			bus.radio_phrase_triggered.connect(_on_radio_phrase_triggered)
		if bus.has_signal("game_reset") and not bus.game_reset.is_connected(_on_game_reset):
			bus.game_reset.connect(_on_game_reset)

func _get_event_bus() -> Node:
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/EventBus")

## Загрузка аудиопотока шума радио
func _load_radio_sound() -> void:
	if radio_sound != null:
		_radio_stream = radio_sound
		_ensure_stream_loop(_radio_stream)
		return

	for path in RADIO_SOUND_PATHS:
		if ResourceLoader.exists(path):
			var res = load(path)
			if res is AudioStream:
				_radio_stream = res
				_ensure_stream_loop(_radio_stream)
				break

func _ensure_stream_loop(stream: AudioStream) -> void:
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true

## Расчет длительности анимации текста фразы исходя из количества символов
func calculate_text_anim_duration(text: String) -> float:
	var clean_len: int = text.strip_edges().length()
	# Скорость анимации печати: ~25-28 знаков в секунду (от 1.4 до 3.2 сек)
	return clampf(float(clean_len) * 0.038 + 0.6, 1.4, 3.2)

## Воспроизведение шума радио строго на время анимации текста
func play_phrase(phrase_text: String, is_white: bool = true) -> float:
	_init_components()

	# Проверка на сообщения тишины
	var is_silence: bool = (
		phrase_text.find("мертвая тишина") != -1 or
		phrase_text.find("некому выходить") != -1
	)

	var bus: Node = _get_event_bus()

	if is_silence:
		if dial_glow:
			dial_glow.light_energy = _base_glow_energy
		stop_radio(true)
		var silent_dur: float = 2.0
		if bus and bus.has_signal("radio_transmission_started"):
			bus.radio_transmission_started.emit(phrase_text, null, silent_dur)
		return silent_dur

	var anim_duration: float = calculate_text_anim_duration(phrase_text)

	if audio_player and _radio_stream:
		if _sound_tween and _sound_tween.is_valid():
			_sound_tween.kill()

		audio_player.stop()
		audio_player.stream = _radio_stream
		audio_player.pitch_scale = randf_range(0.98, 1.02)
		audio_player.volume_db = -28.0 # Мягкий вход без резкого щелчка
		audio_player.play()

		_sound_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		# 1. Быстрый подъем громкости при старте анимации
		_sound_tween.tween_property(audio_player, "volume_db", base_volume_db, fade_in_time)
		# 2. Звук играет ровно столько, сколько длится анимация текста
		_sound_tween.tween_interval(anim_duration)
		# 3. Как только анимация текста прекращается — звук плавно затихает
		_sound_tween.tween_property(audio_player, "volume_db", -42.0, fade_out_time)
		_sound_tween.tween_callback(audio_player.stop)

	_start_glow_pulse(anim_duration)

	if bus and bus.has_signal("radio_transmission_started"):
		bus.radio_transmission_started.emit(phrase_text, _radio_stream, anim_duration)

	return anim_duration

## Подсветка шкалы радиоприемника во время анимации текста
func _start_glow_pulse(anim_duration: float) -> void:
	if dial_glow == null:
		return

	if _glow_tween and _glow_tween.is_valid():
		_glow_tween.kill()

	_glow_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_glow_tween.tween_property(dial_glow, "light_energy", 1.8, fade_in_time)
	_glow_tween.tween_interval(anim_duration)
	_glow_tween.tween_property(dial_glow, "light_energy", _base_glow_energy, fade_out_time)

## Остановка радио
func stop_radio(immediate: bool = false) -> void:
	if _sound_tween and _sound_tween.is_valid():
		_sound_tween.kill()
	if _glow_tween and _glow_tween.is_valid():
		_glow_tween.kill()
	if dial_glow:
		if immediate:
			dial_glow.light_energy = _base_glow_energy
		else:
			_glow_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			_glow_tween.tween_property(dial_glow, "light_energy", _base_glow_energy, fade_out_time)
	if audio_player:
		if immediate:
			audio_player.stop()
		else:
			var tw = create_tween()
			tw.tween_property(audio_player, "volume_db", -40.0, 0.20)
			tw.tween_callback(audio_player.stop)

func _on_radio_phrase_triggered(phrase_text: String, is_white: bool) -> void:
	play_phrase(phrase_text, is_white)

func _on_game_reset(_playthrough: int) -> void:
	stop_radio(true)

## Геттеры для проверок и тестов
func get_radio_stream() -> AudioStream:
	return _radio_stream

func is_playing_radio() -> bool:
	return audio_player != null and audio_player.playing
