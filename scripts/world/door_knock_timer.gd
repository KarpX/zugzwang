class_name DoorKnockTimer
extends Node3D

## Контроллер анти-AFK системы и ударов в дверь бункера
## Отслеживает бездействие игрока и воспроизводит стуки knock1 -> knock2 -> knock3

@export_group("Интервалы стука")
## Интервалы бездействия в секундах до каждого уровня стука: [30с, 30с, 30с]
@export var knock_intervals: Array[float] = [30.0, 30.0, 30.0]

@export_group("Громкость")
@export_range(-20.0, 10.0, 0.5) var knock_volume_db: float = 3.0

@onready var knock_player: AudioStreamPlayer3D = get_node_or_null("KnockAudioPlayer")

var sound_knock1: AudioStream = preload("res://assets/sounds/knock1.ogg")
var sound_knock2: AudioStream = preload("res://assets/sounds/knock2.ogg")
var sound_knock3: AudioStream = preload("res://assets/sounds/knock3.ogg")

var current_knock_level: int = 0 # 0: тишина, 1: knock1, 2: knock2, 3: knock3 (проигрыш)
var idle_time: float = 0.0
var is_active: bool = true
var is_game_finished: bool = false

var _initial_pos: Vector3 = Vector3.ZERO
var _shake_tween: Tween = null

func _get_event_bus() -> Node:
	if not is_inside_tree():
		return null
	if has_node("/root/EventBus"):
		return get_node("/root/EventBus")
	return null

func _ready() -> void:
	_initial_pos = position
	_setup_audio_player()
	
	var bus = _get_event_bus()
	if bus:
		if bus.is_intro_active:
			is_active = false
		if bus.has_signal("intro_sequence_finished"):
			bus.intro_sequence_finished.connect(func():
				is_active = true
				idle_time = 0.0
			)
		if bus.has_signal("piece_moved"):
			bus.piece_moved.connect(_on_piece_moved)
		if bus.has_signal("game_over"):
			bus.game_over.connect(_on_game_over)
		if bus.has_signal("game_reset"):
			bus.game_reset.connect(_on_game_reset)

func _setup_audio_player() -> void:
	if knock_player == null:
		knock_player = get_node_or_null("KnockAudioPlayer")
		if knock_player == null:
			knock_player = AudioStreamPlayer3D.new()
			knock_player.name = "KnockAudioPlayer"
			knock_player.bus = &"Sound"
			knock_player.unit_size = 15.0
			knock_player.max_distance = 60.0
			knock_player.volume_db = knock_volume_db
			add_child(knock_player)

func _process(delta: float) -> void:
	if not is_active or is_game_finished:
		return
		
	idle_time += delta
	
	# Проверяем переход на следующий уровень стука
	var target_interval: float = _get_current_target_interval()
	if target_interval > 0.0 and idle_time >= target_interval:
		_trigger_next_knock()

func _get_current_target_interval() -> float:
	if current_knock_level < knock_intervals.size():
		return knock_intervals[current_knock_level]
	return -1.0

## Срабатывание очередного уровня стука в дверь
func _trigger_next_knock() -> void:
	current_knock_level += 1
	idle_time = 0.0 # Сбрасываем время для отсчета следующего 30-секундного интервала
	
	var bus = _get_event_bus()
	
	match current_knock_level:
		1:
			_play_knock_sound(sound_knock1)
			_shake_door(0.05, 3)
			if bus:
				bus.door_knock_triggered.emit(1)
		2:
			_play_knock_sound(sound_knock2)
			_shake_door(0.08, 5)
			if bus:
				bus.door_knock_triggered.emit(2)
		3:
			_play_knock_sound(sound_knock3)
			_shake_door(0.18, 7)
			is_active = false
			is_game_finished = true
			if bus:
				bus.door_knock_triggered.emit(3)
				bus.game_over.emit("breach")

func _play_knock_sound(stream: AudioStream) -> void:
	if knock_player == null:
		_setup_audio_player()
	if knock_player and is_inside_tree() and knock_player.is_inside_tree():
		knock_player.stream = stream
		knock_player.volume_db = knock_volume_db
		knock_player.play()

## Вибрация дверного полотна при ударе снаружи
func _shake_door(strength: float, count: int) -> void:
	if _shake_tween and _shake_tween.is_valid():
		_shake_tween.kill()
	_shake_tween = create_tween()
	var base_z: float = _initial_pos.z
	for i in range(count):
		var dir: float = 1.0 if (i % 2 == 0) else -0.5
		_shake_tween.tween_property(self, "position:z", base_z + strength * dir, 0.17)
	_shake_tween.tween_property(self, "position:z", base_z, 0.05)

## Реакция на ход фигуры: игрок проявил активность, таймер и стуки сбрасываются
func _on_piece_moved(_from: Vector2i, _to: Vector2i) -> void:
	reset_idle_timer()

## Сброс таймера бездействия
func reset_idle_timer() -> void:
	idle_time = 0.0
	current_knock_level = 0

func _on_game_over(_winner: String) -> void:
	is_game_finished = true
	is_active = false

func _on_game_reset(_playthrough: int) -> void:
	is_game_finished = false
	is_active = true
	reset_idle_timer()
