class_name OutsideWarController
extends Node3D

## OutsideWarController — Контроллер наружной войны (Потери Черных фигур)
## Реализует:
## 1. Микро-события взятий вражеских фигур (взрывы boom_1..3 на шине Outside, сейсмика, сотрясение двери)
## 2. Макро-стадии эскалации внешнего мира
## 3. Сирена вдалеке на 2 этапе с бесконечным циклом (сирена -> пауза 15с -> сирена)
## Пожар, свет в двери бункера и тени у двери полностью отключены.

const SOUND_BOOMS: Array[AudioStream] = [
	preload("res://assets/sounds/boom_1.ogg"),
	preload("res://assets/sounds/boom_2.ogg"),
	preload("res://assets/sounds/boom_3.ogg")
]

const SOUND_NEAR_BOOMS: Array[AudioStream] = [
	preload("res://assets/sounds/near_boom_1.ogg"),
	preload("res://assets/sounds/near_boom_2.ogg")
]

const SOUND_SIREN: AudioStream = preload("res://assets/sounds/siren.ogg")
const OutsideAudioGen = preload("res://scripts/world/outside_audio_generator.gd")

@export_group("Explicit Audio Players")
@export var outside_sfx_player: AudioStreamPlayer3D
@export var outside_sfx_player_near: AudioStreamPlayer3D
@export var siren_player: AudioStreamPlayer3D
@export var outside_ambient_player: AudioStreamPlayer3D
@export var radio_buzzer_player: AudioStreamPlayer3D

var _outside_sfx_player: AudioStreamPlayer3D:
	get: return outside_sfx_player
	set(val): outside_sfx_player = val

var _outside_sfx_player_near: AudioStreamPlayer3D:
	get: return outside_sfx_player_near
	set(val): outside_sfx_player_near = val

var _siren_player: AudioStreamPlayer3D:
	get: return siren_player
	set(val): siren_player = val

var _outside_ambient_player: AudioStreamPlayer3D:
	get: return outside_ambient_player
	set(val): outside_ambient_player = val

var _radio_buzzer_player: AudioStreamPlayer3D:
	get: return radio_buzzer_player
	set(val): radio_buzzer_player = val

var _door_node: Node3D = null

# Состояние бесконечного цикла сирены на 2 этапе
var _is_siren_loop_active: bool = false
var _siren_delay_timer: SceneTreeTimer = null
var _siren_interval: float = 15.0

# Вспомогательные аудиопотоки
var _sound_front_rumble: AudioStreamWAV = null
var _sound_storm_wind: AudioStreamWAV = null
var _sound_uvb76_buzzer: AudioStreamWAV = null

var _door_shake_tween: Tween = null
var _delayed_shock_tween: Tween = null
var _initial_door_pos: Vector3 = Vector3.ZERO

func _get_event_bus() -> Node:
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/EventBus")

func _ready() -> void:
	_init_audio_streams()
	_setup_audio_players()
	_find_door_node()

	var bus = _get_event_bus()
	if bus:
		if bus.has_signal("piece_captured"):
			bus.piece_captured.connect(_on_piece_captured)
		if bus.has_signal("outside_stage_changed"):
			bus.outside_stage_changed.connect(_on_outside_stage_changed)
		if bus.has_signal("escalation_stage_changed"):
			bus.escalation_stage_changed.connect(_on_escalation_stage_changed)
		if bus.has_signal("game_reset"):
			bus.game_reset.connect(_on_game_reset)
			
		if "current_stage" in bus and bus.current_stage >= 2 and bus.current_stage < 4:
			_start_siren_loop()

func _init_audio_streams() -> void:
	_sound_front_rumble = OutsideAudioGen.create_front_rumble_loop()
	_sound_storm_wind = OutsideAudioGen.create_storm_wind_loop()
	_sound_uvb76_buzzer = OutsideAudioGen.create_radio_uvb76_buzzer()

func _setup_audio_players() -> void:
	if outside_sfx_player == null:
		outside_sfx_player = get_node_or_null("OutsideSfxPlayer") as AudioStreamPlayer3D
	if outside_sfx_player_near == null:
		outside_sfx_player_near = get_node_or_null("OutsideSfxPlayerNear") as AudioStreamPlayer3D
	if siren_player == null:
		siren_player = get_node_or_null("SirenPlayer") as AudioStreamPlayer3D
	if outside_ambient_player == null:
		outside_ambient_player = get_node_or_null("OutsideAmbientPlayer") as AudioStreamPlayer3D
	if radio_buzzer_player == null:
		radio_buzzer_player = get_node_or_null("RadioBuzzerPlayer") as AudioStreamPlayer3D

	# Fallback на случай создания ноды без сцены (например, при запуске изолированного юнит-теста)
	if outside_sfx_player == null:
		outside_sfx_player = AudioStreamPlayer3D.new()
		outside_sfx_player.name = "OutsideSfxPlayer"
		outside_sfx_player.position = Vector3(16.0, 2.0, -8.0)
		outside_sfx_player.bus = &"Outside"
		outside_sfx_player.unit_size = 25.0
		outside_sfx_player.max_distance = 120.0
		outside_sfx_player.volume_db = 4.0
		add_child(outside_sfx_player)

	if outside_sfx_player_near == null:
		outside_sfx_player_near = AudioStreamPlayer3D.new()
		outside_sfx_player_near.name = "OutsideSfxPlayerNear"
		outside_sfx_player_near.position = Vector3(16.0, 14.0, 18.0)
		outside_sfx_player_near.bus = &"Outside"
		outside_sfx_player_near.unit_size = 35.0
		outside_sfx_player_near.max_distance = 150.0
		outside_sfx_player_near.volume_db = 6.0
		add_child(outside_sfx_player_near)
	else:
		if outside_sfx_player_near.bus == &"Master" or outside_sfx_player_near.bus == &"":
			outside_sfx_player_near.bus = &"Outside"
		if outside_sfx_player_near.unit_size < 10.0:
			outside_sfx_player_near.unit_size = 35.0
		if outside_sfx_player_near.max_distance < 100.0:
			outside_sfx_player_near.max_distance = 150.0

	if siren_player == null:
		siren_player = AudioStreamPlayer3D.new()
		siren_player.name = "SirenPlayer"
		siren_player.position = Vector3(16.0, 8.0, -25.0)
		siren_player.bus = &"Outside"
		siren_player.unit_size = 25.0
		siren_player.max_distance = 160.0
		siren_player.volume_db = -1.5
		siren_player.stream = SOUND_SIREN
		add_child(siren_player)

	if outside_ambient_player == null:
		outside_ambient_player = AudioStreamPlayer3D.new()
		outside_ambient_player.name = "OutsideAmbientPlayer"
		outside_ambient_player.position = Vector3(16.0, 4.0, -10.0)
		outside_ambient_player.bus = &"Outside"
		outside_ambient_player.unit_size = 30.0
		outside_ambient_player.max_distance = 120.0
		outside_ambient_player.volume_db = 0.0
		add_child(outside_ambient_player)

	if radio_buzzer_player == null:
		radio_buzzer_player = AudioStreamPlayer3D.new()
		radio_buzzer_player.name = "RadioBuzzerPlayer"
		radio_buzzer_player.position = Vector3(16.7, 1.0, 20.65)
		radio_buzzer_player.bus = &"Sound"
		radio_buzzer_player.unit_size = 6.0
		radio_buzzer_player.max_distance = 25.0
		radio_buzzer_player.volume_db = -10.0
		add_child(radio_buzzer_player)

	if siren_player:
		if siren_player.bus == &"Master" or siren_player.bus == &"":
			siren_player.bus = &"Outside"
		if siren_player.unit_size < 10.0:
			siren_player.unit_size = 35.0
		if siren_player.max_distance < 100.0:
			siren_player.max_distance = 200.0
		if siren_player.volume_db < 0.0:
			siren_player.volume_db = 6.0

	if siren_player and not siren_player.finished.is_connected(_on_siren_finished):
		siren_player.finished.connect(_on_siren_finished)

func _find_door_node() -> void:
	if not is_inside_tree():
		return
	var root = get_tree().current_scene if get_tree().current_scene else get_parent()
	if root:
		_door_node = root.find_child("Door", true, false)
		if _door_node:
			_initial_door_pos = _door_node.position

## Обработчик взятия фигур
func _on_piece_captured(piece_type: String, is_white: bool) -> void:
	if is_white:
		_handle_white_piece_loss(piece_type)
		return
		
	var type: String = piece_type.to_lower()
	match type:
		"pawn":
			_handle_enemy_pawn()
		"knight":
			_handle_enemy_knight()
		"bishop":
			_handle_enemy_bishop()
		"rook":
			_handle_enemy_rook()
		"queen":
			_handle_enemy_queen()

# ==============================================================================
# МИКРО-СОБЫТИЯ ПОТЕРЬ БЕЛЫХ (Близкие взрывы near_boom_1..2 через OutsideSfxPlayerNear)
# ==============================================================================

func _handle_white_piece_loss(piece_type: String) -> void:
	var type: String = piece_type.to_lower()
	match type:
		"pawn":
			# Белая пешка: хлесткий разрыв near_boom_1 вблизи бункера
			var stream = SOUND_NEAR_BOOMS[0] if SOUND_NEAR_BOOMS.size() > 0 else SOUND_BOOMS[0]
			_play_outside_near_boom(stream, 4.0, randf_range(0.95, 1.05))
		"knight":
			# Белый конь: близкий мощный разрыв near_boom_2 + содрогание двери
			var stream = SOUND_NEAR_BOOMS[1] if SOUND_NEAR_BOOMS.size() > 1 else SOUND_NEAR_BOOMS[0]
			_play_outside_near_boom(stream, 6.0, randf_range(0.95, 1.05))
			_shake_door(0.06, 4)
		"bishop":
			# Белый слон: близкий глухой разрыв near_boom_1
			var stream = SOUND_NEAR_BOOMS[0] if SOUND_NEAR_BOOMS.size() > 0 else SOUND_BOOMS[0]
			_play_outside_near_boom(stream, 6.5, 0.90)
			_shake_door(0.08, 4)
		"rook":
			# Белая ладья: тяжелый фугасный удар возле бункера near_boom_2
			var stream = SOUND_NEAR_BOOMS[1] if SOUND_NEAR_BOOMS.size() > 1 else SOUND_NEAR_BOOMS[0]
			_play_outside_near_boom(stream, 8.5, 0.85)
			_shake_door(0.12, 6)
		"queen":
			# Белый ферзь: катастрофический близкий удар — каскад near_boom_1 + near_boom_2
			var stream1 = SOUND_NEAR_BOOMS[0] if SOUND_NEAR_BOOMS.size() > 0 else SOUND_BOOMS[0]
			var stream2 = SOUND_NEAR_BOOMS[1] if SOUND_NEAR_BOOMS.size() > 1 else stream1
			_play_outside_near_boom(stream1, 9.5, 0.80)
			_shake_door(0.16, 8)
			var t = create_tween()
			t.tween_interval(0.35)
			t.tween_callback(func():
				_play_outside_near_boom(stream2, 10.5, 0.75)
			)

# ==============================================================================
# МИКРО-СОБЫТИЯ ПОТЕРЬ ЧЕРНЫХ (Взрывы boom_1..3 снаружи бункера)
# ==============================================================================

func _kill_delayed_shock() -> void:
	if _delayed_shock_tween and _delayed_shock_tween.is_valid():
		_delayed_shock_tween.kill()
		_delayed_shock_tween = null

## Пешка (1 очко): Далекий глухой артиллерийский разрыв boom_1
func _handle_enemy_pawn() -> void:
	_kill_delayed_shock()
	_play_outside_boom(SOUND_BOOMS[0], 0.0, randf_range(0.92, 1.05))
	# Вибрация пола спустя 0.6 секунды после взятия
	_delayed_shock_tween = create_tween()
	_delayed_shock_tween.tween_interval(0.6)
	_delayed_shock_tween.tween_callback(func():
		var bus = _get_event_bus()
		if bus and bus.has_signal("seismic_shock_triggered"):
			bus.seismic_shock_triggered.emit(0.15, true)
	)

## Конь (3 очка): Разрыв boom_2, дрожь стальной двери бункера
func _handle_enemy_knight() -> void:
	_kill_delayed_shock()
	_play_outside_boom(SOUND_BOOMS[1], 3.5, randf_range(0.95, 1.05))
	_shake_door(0.05, 4)
	
	var bus = _get_event_bus()
	if bus and bus.has_signal("seismic_shock_triggered"):
		bus.seismic_shock_triggered.emit(0.30, false)

## Слон (3 очка): Залп артиллерии boom_1..2, подземный толчок
func _handle_enemy_bishop() -> void:
	_kill_delayed_shock()
	_play_outside_boom(SOUND_BOOMS[0], 4.5, 0.88)
	
	var bus = _get_event_bus()
	if bus and bus.has_signal("seismic_shock_triggered"):
		bus.seismic_shock_triggered.emit(0.42, true)

## Ладья (5 очков): Мощный близкий взрыв укрепления boom_3, сильное сотрясение
func _handle_enemy_rook() -> void:
	_kill_delayed_shock()
	_play_outside_boom(SOUND_BOOMS[2], 7.0, randf_range(0.85, 0.95))
	_shake_door(0.12, 6)
	
	var bus = _get_event_bus()
	if bus and bus.has_signal("seismic_shock_triggered"):
		bus.seismic_shock_triggered.emit(0.72, false)

## Ферзь (10 очков): Стратегический удар — пауза 1.2с тишины, циклопический разрыв boom_3
func _handle_enemy_queen() -> void:
	_kill_delayed_shock()
	var t = create_tween()
	t.tween_interval(1.2)
	t.tween_callback(func():
		_play_outside_boom(SOUND_BOOMS[2], 9.5, 0.80)
		_shake_door(0.18, 8)
		
		var bus = _get_event_bus()
		if bus and bus.has_signal("seismic_shock_triggered"):
			bus.seismic_shock_triggered.emit(1.0, true)
	)

# ==============================================================================
# МАКРО-СТАДИИ И СИСТЕМА СИРЕН (ЭТАП 2: сирена -> пауза 15с -> сирена ...)
# ==============================================================================

func _on_escalation_stage_changed(stage: int, _total_losses: int) -> void:
	if stage >= 2 and stage < 4:
		_start_siren_loop()
	elif stage >= 4:
		_stop_siren_loop()

func _on_outside_stage_changed(stage: int, _black_score: int) -> void:
	match stage:
		0:
			pass
		1:
			# Стадия I (осталось <= 30 очков): Дыхание фронта
			_play_ambient_loop(_sound_front_rumble, -4.0)
		2:
			# Стадия II (осталось <= 20 очков): Запуск бесконечного цикла сирены
			_start_siren_loop()
		3:
			# Стадия III (осталось <= 10 очков): Радиомолчание судного дня
			_play_ambient_loop(_sound_storm_wind, 1.0)
			# Включается номерная радиостанция
			if _radio_buzzer_player and _sound_uvb76_buzzer:
				_radio_buzzer_player.stream = _sound_uvb76_buzzer
				_radio_buzzer_player.play()
		4:
			# Стадия IV (осталось <= 3 очков): Мертвая пустыня — полная тишина
			_stop_siren_loop()
			if _outside_ambient_player:
				_outside_ambient_player.stop()
			if _radio_buzzer_player:
				_radio_buzzer_player.stop()

## Запуск бесконечного цикла сирен на втором этапе
func _start_siren_loop() -> void:
	if _is_siren_loop_active:
		return
	_is_siren_loop_active = true
	_play_siren_instance()

## Воспроизведение одного прохода сирены вдалеке
func _play_siren_instance() -> void:
	if not _is_siren_loop_active or _siren_player == null:
		return
	_siren_player.stream = SOUND_SIREN
	_siren_player.play()

## Коллбэк окончания звучания сирены: ждем 15 секунд и запускаем следующую
func _on_siren_finished() -> void:
	if not _is_siren_loop_active or not is_inside_tree():
		return
		
	_siren_delay_timer = get_tree().create_timer(_siren_interval)
	_siren_delay_timer.timeout.connect(func():
		if _is_siren_loop_active:
			_play_siren_instance()
	)

## Остановка цикла сирены
func _stop_siren_loop() -> void:
	_is_siren_loop_active = false
	_siren_delay_timer = null
	if _siren_player and _siren_player.playing:
		_siren_player.stop()

# ==============================================================================
# ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ ЗВУКА И ДВЕРИ
# ==============================================================================

func _play_outside_boom(stream: AudioStream, vol_db: float = 4.0, pitch: float = 1.0) -> void:
	if _outside_sfx_player == null or stream == null:
		return
	_outside_sfx_player.stream = stream
	_outside_sfx_player.volume_db = vol_db
	_outside_sfx_player.pitch_scale = pitch
	_outside_sfx_player.play()

func _play_outside_near_boom(stream: AudioStream, vol_db: float = 6.0, pitch: float = 1.0) -> void:
	if _outside_sfx_player_near == null or stream == null:
		return
	_outside_sfx_player_near.stream = stream
	_outside_sfx_player_near.volume_db = vol_db
	_outside_sfx_player_near.pitch_scale = pitch
	_outside_sfx_player_near.play()

func _play_ambient_loop(stream: AudioStream, vol_db: float = 0.0) -> void:
	if _outside_ambient_player == null or stream == null:
		return
	_outside_ambient_player.stream = stream
	_outside_ambient_player.volume_db = vol_db
	_outside_ambient_player.play()

## Содрогание бронедвери от наружной ударной волны
func _shake_door(offset: float = 0.08, count: int = 5) -> void:
	if _door_node == null:
		_find_door_node()
	if _door_node == null:
		return
		
	if _door_shake_tween and _door_shake_tween.is_valid():
		_door_shake_tween.kill()
		
	_door_shake_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var step_time: float = 0.04
	for i in range(count):
		var factor: float = float(count - i) / float(count)
		var shake_z: float = _initial_door_pos.z + randf_range(-offset, offset) * factor
		var shake_x: float = _initial_door_pos.x + randf_range(-offset * 0.4, offset * 0.4) * factor
		_door_shake_tween.tween_property(_door_node, "position", Vector3(shake_x, _initial_door_pos.y, shake_z), step_time)
	_door_shake_tween.tween_property(_door_node, "position", _initial_door_pos, 0.06)

func _on_game_reset(_playthrough: int) -> void:
	_stop_siren_loop()
	if _outside_sfx_player and _outside_sfx_player.playing:
		_outside_sfx_player.stop()
	if _outside_sfx_player_near and _outside_sfx_player_near.playing:
		_outside_sfx_player_near.stop()
	if _outside_ambient_player:
		_outside_ambient_player.stop()
	if _radio_buzzer_player:
		_radio_buzzer_player.stop()
	if _door_node and _initial_door_pos != Vector3.ZERO:
		_door_node.position = _initial_door_pos
