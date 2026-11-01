class_name ChessAudioController
extends RefCounted

## Аудио-контроллер шахматной доски для проекта «Белый Король»
## Управляет воспроизведением 3D-звуков ходов игрока, противника, взятий и отмены выбора.

const SoundPlayerTurn = preload("res://assets/sounds/chess_player_turn.ogg")
const SoundEnemyTurn = preload("res://assets/sounds/chess_enemy_turn.ogg")
const SoundCapture = preload("res://assets/sounds/chess_capture.wav")
const SoundDeselect = preload("res://assets/sounds/chess_deselect.wav")

var parent_node: Node3D = null
var player_turn_sound: AudioStreamPlayer3D = null
var enemy_turn_sound: AudioStreamPlayer3D = null
var capture_sound: AudioStreamPlayer3D = null
var deselect_sound: AudioStreamPlayer3D = null

var _enemy_sound_tween: Tween = null

func setup(parent: Node3D,
		p_turn: AudioStreamPlayer3D = null,
		e_turn: AudioStreamPlayer3D = null,
		cap: AudioStreamPlayer3D = null,
		desel: AudioStreamPlayer3D = null) -> void:
	parent_node = parent
	player_turn_sound = p_turn
	enemy_turn_sound = e_turn
	capture_sound = cap
	deselect_sound = desel
	_ensure_audio_players()

func _ensure_audio_players() -> void:
	if parent_node == null:
		return
		
	if player_turn_sound == null:
		player_turn_sound = parent_node.get_node_or_null("PlayerTurnSound")
		if player_turn_sound == null:
			player_turn_sound = AudioStreamPlayer3D.new()
			player_turn_sound.name = "PlayerTurnSound"
			player_turn_sound.stream = SoundPlayerTurn
			player_turn_sound.bus = &"Sound"
			player_turn_sound.unit_size = 5.0
			player_turn_sound.max_distance = 40.0
			parent_node.add_child(player_turn_sound)
			
	if enemy_turn_sound == null:
		enemy_turn_sound = parent_node.get_node_or_null("EnemyTurnSound")
		if enemy_turn_sound == null:
			enemy_turn_sound = AudioStreamPlayer3D.new()
			enemy_turn_sound.name = "EnemyTurnSound"
			enemy_turn_sound.stream = SoundEnemyTurn
			enemy_turn_sound.bus = &"Sound"
			enemy_turn_sound.volume_db = -16.0
			enemy_turn_sound.unit_size = 5.0
			enemy_turn_sound.max_distance = 40.0
			parent_node.add_child(enemy_turn_sound)

	if capture_sound == null:
		capture_sound = parent_node.get_node_or_null("CaptureSound")
		if capture_sound == null:
			capture_sound = AudioStreamPlayer3D.new()
			capture_sound.name = "CaptureSound"
			capture_sound.stream = SoundCapture
			capture_sound.bus = &"Sound"
			capture_sound.unit_size = 5.0
			capture_sound.max_distance = 40.0
			parent_node.add_child(capture_sound)

	if deselect_sound == null:
		deselect_sound = parent_node.get_node_or_null("DeselectSound")
		if deselect_sound == null:
			deselect_sound = AudioStreamPlayer3D.new()
			deselect_sound.name = "DeselectSound"
			deselect_sound.stream = SoundDeselect
			deselect_sound.bus = &"Sound"
			deselect_sound.volume_db = -4.0
			deselect_sound.unit_size = 5.0
			deselect_sound.max_distance = 40.0
			parent_node.add_child(deselect_sound)

## Воспроизведение звука хода игрока (белые: четкий стук постановки на доску)
func play_player_move(world_pos: Vector3) -> void:
	_ensure_audio_players()
	if player_turn_sound and player_turn_sound.is_inside_tree():
		player_turn_sound.global_position = world_pos
		player_turn_sound.pitch_scale = randf_range(0.96, 1.04)
		player_turn_sound.play()

func play_player_turn(world_pos: Vector3) -> void:
	play_player_move(world_pos)

## Воспроизведение звука взятия фигуры (сочный тяжелый удар дерева о дерево)
func play_capture(world_pos: Vector3) -> void:
	_ensure_audio_players()
	if capture_sound and capture_sound.is_inside_tree():
		capture_sound.global_position = world_pos
		capture_sound.pitch_scale = randf_range(0.95, 1.05)
		capture_sound.play()

## Воспроизведение звука отмены выбора фигуры (мягкий глухой щелчок опускания на доску)
func play_deselect(world_pos: Vector3) -> void:
	_ensure_audio_players()
	if deselect_sound and deselect_sound.is_inside_tree():
		deselect_sound.global_position = world_pos
		deselect_sound.pitch_scale = randf_range(0.96, 1.04)
		deselect_sound.play()

## Воспроизведение звука хода врага (черные: медленное зловещее протаскивание по доске)
func play_enemy_move(start_pos: Vector3, end_pos: Vector3, duration: float) -> void:
	_ensure_audio_players()
	if enemy_turn_sound and enemy_turn_sound.is_inside_tree():
		enemy_turn_sound.global_position = start_pos
		if duration > 0.1:
			var normal_len: float = 1.846
			enemy_turn_sound.pitch_scale = clampf(normal_len / duration, 0.75, 1.35)
		else:
			enemy_turn_sound.pitch_scale = 1.0
		enemy_turn_sound.play()
		
		if _enemy_sound_tween and _enemy_sound_tween.is_valid():
			_enemy_sound_tween.kill()
		if parent_node != null and parent_node.is_inside_tree():
			_enemy_sound_tween = parent_node.create_tween()
			_enemy_sound_tween.tween_property(enemy_turn_sound, "global_position", end_pos, duration)

## Остановка звука хода врага
func stop_enemy_move() -> void:
	if _enemy_sound_tween and _enemy_sound_tween.is_valid():
		_enemy_sound_tween.kill()
		_enemy_sound_tween = null
	if enemy_turn_sound and enemy_turn_sound.playing:
		enemy_turn_sound.stop()

