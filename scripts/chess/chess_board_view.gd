class_name ChessBoardView
extends Node3D

## 3D-контроллер шахматной доски для проекта «Белый Король»
## Управляет 3D-моделями фигур, подсветкой ходов, вводом игрока и интеграцией с EventBus.

const ChessLogicScript = preload("res://scripts/chess/chess_logic.gd")
const ChessPiece3DScript = preload("res://scripts/chess/chess_piece_3d.gd")

# Геометрические константы привязки к модели bord.obj
const ORIGIN_X: float = -4.735
const ORIGIN_Z: float = -0.473
const STEP_X: float = 0.5724
const STEP_Z: float = -0.5844

@export_group("Параметры доски и высоты")
## Высота основания фигур над доской (поверхность доски bord.obj = 0.40)
@export_range(0.0, 1.5, 0.005) var surface_y: float = 0.405

@export_group("Скорость перемещения фигур")
## Длительность хода игрока (белые фигуры), секунды
@export_range(0.1, 2.0, 0.05) var white_move_duration: float = 0.4
## Длительность хода войны (черные фигуры, медленное зловещее скольжение со скрежетом)
@export_range(0.5, 4.0, 0.1) var black_move_duration: float = 1.6
## Задержка перед ходом ИИ черных, секунды
@export_range(0.1, 3.0, 0.1) var ai_turn_delay: float = 0.8

# Узел камеры для вида над доской
@onready var camera_point: Marker3D = $CameraPoint
@onready var pieces_container: Node3D = $Pieces
@onready var highlights_container: Node3D = $Highlights
@onready var player_turn_sound: AudioStreamPlayer3D = get_node_or_null("PlayerTurnSound")
@onready var enemy_turn_sound: AudioStreamPlayer3D = get_node_or_null("EnemyTurnSound")
@onready var capture_sound: AudioStreamPlayer3D = get_node_or_null("CaptureSound")
@onready var deselect_sound: AudioStreamPlayer3D = get_node_or_null("DeselectSound")

var sound_player_turn: AudioStream = preload("res://assets/sounds/chess_player_turn.ogg")
var sound_enemy_turn: AudioStream = preload("res://assets/sounds/chess_enemy_turn.ogg")
var sound_capture: AudioStream = preload("res://assets/sounds/chess_capture.wav")
var sound_deselect: AudioStream = preload("res://assets/sounds/chess_deselect.wav")

var logic: ChessLogic = null
var piece_nodes: Dictionary = {} # Vector2i -> ChessPiece3D

# Состояние выбора
var selected_pos: Vector2i = Vector2i(-1, -1)
var current_legal_moves: Array[Vector2i] = []
var is_active: bool = false # Активен ли режим управления шахматами
var is_ai_thinking: bool = false

# Материалы для фигур и подсветки
var white_mat: StandardMaterial3D
var black_mat: StandardMaterial3D
var move_highlight_mat: StandardMaterial3D
var attack_highlight_mat: StandardMaterial3D
var select_highlight_mat: StandardMaterial3D

# Меши для фигур
var meshes: Dictionary = {}

func _get_event_bus() -> Node:
	if not is_inside_tree():
		return null
	if has_node("/root/EventBus"):
		return get_node("/root/EventBus")
	return null

func _ready() -> void:
	_init_materials()
	_init_meshes()
	_setup_audio_players()
	
	logic = ChessLogicScript.new()
	spawn_pieces()
	
	# Подписываемся на события шины
	var bus = _get_event_bus()
	if bus and bus.has_signal("camera_mode_changed"):
		bus.camera_mode_changed.connect(_on_camera_mode_changed)

func _init_materials() -> void:
	# Белые: турнирный самшит с красным фетровым основанием
	white_mat = preload("res://assets/obj/chess/chess_white_material.tres")
	
	# Черные: мореный дуб / эбен с темно-красным фетровым основанием
	black_mat = preload("res://assets/obj/chess/chess_black_material.tres")
	
	# Подсветка доступного хода (зеленый/белый неоновый маркер)
	move_highlight_mat = StandardMaterial3D.new()
	move_highlight_mat.albedo_color = Color(0.2, 0.8, 0.4, 0.8)
	move_highlight_mat.emission_enabled = true
	move_highlight_mat.emission = Color(0.3, 0.9, 0.5)
	move_highlight_mat.emission_energy_multiplier = 2.0
	move_highlight_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	
	# Подсветка атаки/взятия (тревожный красный маркер)
	attack_highlight_mat = StandardMaterial3D.new()
	attack_highlight_mat.albedo_color = Color(0.9, 0.15, 0.15, 0.85)
	attack_highlight_mat.emission_enabled = true
	attack_highlight_mat.emission = Color(1.0, 0.1, 0.1)
	attack_highlight_mat.emission_energy_multiplier = 3.0
	attack_highlight_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	
	# Подсветка выбранной фигуры (золотой маркер)
	select_highlight_mat = StandardMaterial3D.new()
	select_highlight_mat.albedo_color = Color(0.9, 0.75, 0.2, 0.8)
	select_highlight_mat.emission_enabled = true
	select_highlight_mat.emission = Color(1.0, 0.8, 0.2)
	select_highlight_mat.emission_energy_multiplier = 2.5
	select_highlight_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

func _init_meshes() -> void:
	meshes["pawn_white"] = preload("res://assets/obj/chess/pawn_white.obj")
	meshes["rook_white"] = preload("res://assets/obj/chess/rook_white.obj")
	meshes["knight_white"] = preload("res://assets/obj/chess/knight_white.obj")
	meshes["bishop_white"] = preload("res://assets/obj/chess/bishop_white.obj")
	meshes["queen_white"] = preload("res://assets/obj/chess/queen_white.obj")
	meshes["king_white"] = preload("res://assets/obj/chess/king_white.obj")
	
	meshes["pawn_black"] = preload("res://assets/obj/chess/pawn_black.obj")
	meshes["rook_black"] = preload("res://assets/obj/chess/rook_black.obj")
	meshes["knight_black"] = preload("res://assets/obj/chess/knight_black.obj")
	meshes["bishop_black"] = preload("res://assets/obj/chess/bishop_black.obj")
	meshes["queen_black"] = preload("res://assets/obj/chess/queen_black.obj")
	meshes["king_black"] = preload("res://assets/obj/chess/king_black.obj")
	
	meshes["pawn"] = meshes["pawn_white"]
	meshes["rook"] = meshes["rook_white"]
	meshes["knight"] = meshes["knight_white"]
	meshes["bishop"] = meshes["bishop_white"]
	meshes["queen"] = meshes["queen_white"]
	meshes["king"] = meshes["king_white"]

## Преобразование координат клетки доски (file 0..7, rank 0..7) в локальные 3D-координаты
func cell_to_local_pos(cell: Vector2i) -> Vector3:
	var x: float = ORIGIN_X + float(cell.x) * STEP_X
	var z: float = ORIGIN_Z + float(cell.y) * STEP_Z
	return Vector3(x, surface_y, z)

## Преобразование локальной точки пересечения в клетку доски
func local_pos_to_cell(pos: Vector3) -> Vector2i:
	var file: int = int(round((pos.x - ORIGIN_X) / STEP_X))
	var rank: int = int(round((pos.z - ORIGIN_Z) / STEP_Z))
	if file >= 0 and file < 8 and rank >= 0 and rank < 8:
		return Vector2i(file, rank)
	return Vector2i(-1, -1)

## Спавн или подключение существующих 32 фигур со сцены
func spawn_pieces() -> void:
	if pieces_container == null:
		pieces_container = get_node_or_null("Pieces")
	if pieces_container == null:
		return
	
	piece_nodes.clear()
	
	# Проверяем, есть ли уже запеченные в сцене 32 фигуры
	var existing_pieces: Array[Node] = pieces_container.get_children()
	if existing_pieces.size() >= 32:
		for child in existing_pieces:
			if child is ChessPiece3D:
				piece_nodes[child.board_pos] = child
				child.base_y = surface_y
				if child.mesh_instance == null:
					child.mesh_instance = child.get_node_or_null("MeshInstance3D")
		return
	
	# Резервный динамический спавн, если сцена оказалась пустой
	for child in existing_pieces:
		child.queue_free()
	
	for x in range(8):
		for y in range(8):
			var pos: Vector2i = Vector2i(x, y)
			var piece_data = logic.get_piece(pos)
			if piece_data != null:
				_spawn_piece_at(pos, piece_data["type"], piece_data["is_white"])

func _spawn_piece_at(pos: Vector2i, p_type: String, is_white: bool) -> ChessPiece3D:
	var piece_node = ChessPiece3DScript.new()
	var key: String = p_type + ("_white" if is_white else "_black")
	var mesh: Mesh = meshes.get(key, meshes.get(p_type, meshes["pawn"]))
	var mat: Material = white_mat if is_white else black_mat
	piece_node.setup(p_type, is_white, pos, mesh, mat, surface_y)
	
	piece_node.position = cell_to_local_pos(pos)
	pieces_container.add_child(piece_node)
	piece_nodes[pos] = piece_node
	return piece_node

func _on_camera_mode_changed(is_board_mode: bool) -> void:
	is_active = is_board_mode
	if not is_active:
		clear_selection()

## Обработка ввода мыши по доске
func _unhandled_input(event: InputEvent) -> void:
	if not is_active or is_ai_thinking or logic.is_game_over:
		return
		
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_board_click()
	elif event.is_action_pressed("ui_cancel") or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT):
		cancel_selection()

func _handle_board_click() -> void:
	var viewport = get_viewport()
	var camera = viewport.get_camera_3d()
	if not camera:
		return
		
	var mouse_pos = viewport.get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_normal = camera.project_ray_normal(mouse_pos)
	
	# Плоскость поверхности доски в мировых координатах
	var board_global_y: float = global_transform.origin.y + (surface_y * global_transform.basis.y.y)
	if abs(ray_normal.y) < 0.0001:
		return
		
	var t: float = (board_global_y - ray_origin.y) / ray_normal.y
	if t <= 0.0:
		return
		
	var hit_world: Vector3 = ray_origin + ray_normal * t
	var hit_local: Vector3 = to_local(hit_world)
	var cell: Vector2i = local_pos_to_cell(hit_local)
	
	if cell == Vector2i(-1, -1):
		cancel_selection()
		return
		
	_on_cell_clicked(cell)

func _on_cell_clicked(cell: Vector2i) -> void:
	var piece_data = logic.get_piece(cell)
	
	# Если кликнули на свою фигуру (Белые)
	if piece_data != null and piece_data["is_white"] and logic.is_white_turn:
		if selected_pos == cell:
			# Повторный клик по уже выбранной фигуре -> отмена выбора
			cancel_selection()
		else:
			_select_cell(cell)
		return
		
	# Если клетка выбрана и кликнули на допустимый ход
	if selected_pos != Vector2i(-1, -1) and (cell in current_legal_moves):
		_execute_player_move(selected_pos, cell)
	else:
		cancel_selection()

func _select_cell(cell: Vector2i) -> void:
	clear_selection()
	selected_pos = cell
	if logic == null:
		logic = ChessLogicScript.new()
	current_legal_moves = logic.get_legal_moves(cell)
	
	# Анимация поднятия выбранной фигуры
	if piece_nodes.has(cell):
		piece_nodes[cell].set_selected(true)
		
	_draw_highlights()
	
	var bus = _get_event_bus()
	if bus:
		bus.square_selected.emit(cell)
		bus.player_made_action.emit()

func clear_selection() -> void:
	if selected_pos != Vector2i(-1, -1) and piece_nodes.has(selected_pos):
		piece_nodes[selected_pos].set_selected(false)
		
	selected_pos = Vector2i(-1, -1)
	current_legal_moves.clear()
	_clear_highlights()
	
	var bus = _get_event_bus()
	if bus:
		bus.square_deselected.emit()

## Отмена выбора фигуры игроком с воспроизведением мягкого звука опускания на доску
func cancel_selection() -> void:
	if selected_pos != Vector2i(-1, -1):
		var prev_node = piece_nodes.get(selected_pos)
		var sound_pos: Vector3 = Vector3.ZERO
		if prev_node and prev_node.is_inside_tree():
			sound_pos = prev_node.global_position
		elif is_inside_tree():
			sound_pos = global_position
		clear_selection()
		_play_deselect_sound(sound_pos)
	else:
		clear_selection()

func _draw_highlights() -> void:
	_clear_highlights()
	
	# Маркер под выбранной фигурой
	_create_highlight_tile(selected_pos, select_highlight_mat, 0.44)
	
	# Маркеры возможных ходов
	for move_cell in current_legal_moves:
		var target_piece = logic.get_piece(move_cell)
		if target_piece != null:
			# Клетка с врагом — красный маркер
			_create_highlight_tile(move_cell, attack_highlight_mat, 0.42)
		else:
			# Свободная клетка — мягкий зеленый маркер
			_create_highlight_tile(move_cell, move_highlight_mat, 0.28)

func _create_highlight_tile(cell: Vector2i, mat: Material, size: float) -> void:
	if highlights_container == null:
		highlights_container = get_node_or_null("Highlights")
	if highlights_container == null:
		return
		
	var tile = MeshInstance3D.new()
	var quad = BoxMesh.new()
	quad.size = Vector3(size, 0.005, size)
	tile.mesh = quad
	tile.material_override = mat
	
	var pos: Vector3 = cell_to_local_pos(cell)
	pos.y += 0.003 # Тонкий маркер на поверхности доски
	tile.position = pos
	highlights_container.add_child(tile)

func _clear_highlights() -> void:
	if highlights_container == null:
		highlights_container = get_node_or_null("Highlights")
	if highlights_container == null:
		return
	for child in highlights_container.get_children():
		child.queue_free()
		

## Выполнение хода игрока
func _execute_player_move(from_pos: Vector2i, to_pos: Vector2i) -> void:
	clear_selection()
	
	var piece_node = piece_nodes.get(from_pos)
	if not piece_node:
		return
		
	var move_res = logic.make_move(from_pos, to_pos)
	if not move_res["success"]:
		return
		
	var bus = _get_event_bus()
	
	# Обработка взятия
	var is_capture: bool = move_res["captured"]
	if is_capture:
		var victim_node = piece_nodes.get(to_pos)
		if victim_node:
			victim_node.animate_capture()
			piece_nodes.erase(to_pos)
			
		if bus:
			bus.piece_captured.emit(move_res["captured_piece"], move_res["captured_is_white"])
			
	# Перемещение 3D-ноды (ход игрока белыми — дуговой перенос)
	piece_nodes.erase(from_pos)
	piece_nodes[to_pos] = piece_node
	piece_node.board_pos = to_pos
	var target_world_pos: Vector3 = to_global(cell_to_local_pos(to_pos))
	
	if white_move_duration <= 0.05:
		if is_capture:
			_play_capture_sound(target_world_pos)
		else:
			_play_player_move_sound(target_world_pos)
		piece_node.animate_to(target_world_pos, white_move_duration, false)
	else:
		piece_node.animate_to(target_world_pos, white_move_duration, false, func():
			if is_capture:
				_play_capture_sound(target_world_pos)
			else:
				_play_player_move_sound(target_world_pos)
		)
	
	if bus:
		bus.piece_moved.emit(from_pos, to_pos)
		bus.player_made_action.emit()
		
	if move_res["is_checkmate"]:
		if bus:
			bus.game_over.emit(logic.winner)
		return
		
	# Ход ИИ (Черные) с атмосферной задержкой после завершения хода белых
	is_ai_thinking = true
	var timer = get_tree().create_timer(white_move_duration + ai_turn_delay)
	timer.timeout.connect(_execute_ai_turn)

## Ход ИИ войны
func _execute_ai_turn() -> void:
	if logic.is_game_over or not is_inside_tree():
		is_ai_thinking = false
		return
		
	var ai_move = logic.get_best_ai_move()
	if ai_move.is_empty():
		is_ai_thinking = false
		return
		
	var from_pos: Vector2i = ai_move["from"]
	var to_pos: Vector2i = ai_move["to"]
	var piece_node = piece_nodes.get(from_pos)
	if not piece_node:
		is_ai_thinking = false
		return
		
	var move_res = logic.make_move(from_pos, to_pos)
	if not move_res["success"]:
		is_ai_thinking = false
		return
		
	var bus = _get_event_bus()
	# Обработка взятия белой фигуры
	if move_res["captured"]:
		var victim_node = piece_nodes.get(to_pos)
		if victim_node:
			victim_node.animate_capture(black_move_duration * 0.5)
			piece_nodes.erase(to_pos)
			
		if bus:
			bus.piece_captured.emit(move_res["captured_piece"], move_res["captured_is_white"])
			
	# Медленное скольжение черной фигуры строго по доске (для звука скрежета)
	piece_nodes.erase(from_pos)
	piece_nodes[to_pos] = piece_node
	piece_node.board_pos = to_pos
	
	var start_world_pos: Vector3 = piece_node.global_position
	var target_world_pos: Vector3 = to_global(cell_to_local_pos(to_pos))
	_play_enemy_move_sound(start_world_pos, target_world_pos, black_move_duration)
	
	piece_node.animate_to(target_world_pos, black_move_duration, true, func():
		_stop_enemy_move_sound()
	)
	
	if bus:
		bus.piece_moved.emit(from_pos, to_pos)
		
	# Разрешаем ход игроку только после того, как черная фигура закончит медленное скольжение
	var finish_timer = get_tree().create_timer(black_move_duration)
	finish_timer.timeout.connect(func():
		_stop_enemy_move_sound()
		is_ai_thinking = false
		if move_res["is_checkmate"]:
			if bus:
				bus.game_over.emit(logic.winner)
	)

# ==============================================================================
# ЗВУКИ ПЕРЕМЕЩЕНИЯ ФИГУР (Player & Enemy Turn Audio)
# ==============================================================================

## Инициализация нод проигрывания звуков (если отсутствуют в сцене)
func _setup_audio_players() -> void:
	if player_turn_sound == null:
		player_turn_sound = get_node_or_null("PlayerTurnSound")
		if player_turn_sound == null:
			player_turn_sound = AudioStreamPlayer3D.new()
			player_turn_sound.name = "PlayerTurnSound"
			player_turn_sound.stream = sound_player_turn
			player_turn_sound.bus = &"Sound"
			player_turn_sound.unit_size = 5.0
			player_turn_sound.max_distance = 40.0
			add_child(player_turn_sound)
			
	if enemy_turn_sound == null:
		enemy_turn_sound = get_node_or_null("EnemyTurnSound")
		if enemy_turn_sound == null:
			enemy_turn_sound = AudioStreamPlayer3D.new()
			enemy_turn_sound.name = "EnemyTurnSound"
			enemy_turn_sound.stream = sound_enemy_turn
			enemy_turn_sound.bus = &"Sound"
			enemy_turn_sound.volume_db = -16.0
			enemy_turn_sound.unit_size = 5.0
			enemy_turn_sound.max_distance = 40.0
			add_child(enemy_turn_sound)

	if capture_sound == null:
		capture_sound = get_node_or_null("CaptureSound")
		if capture_sound == null:
			capture_sound = AudioStreamPlayer3D.new()
			capture_sound.name = "CaptureSound"
			capture_sound.stream = sound_capture
			capture_sound.bus = &"Sound"
			capture_sound.unit_size = 5.0
			capture_sound.max_distance = 40.0
			add_child(capture_sound)

	if deselect_sound == null:
		deselect_sound = get_node_or_null("DeselectSound")
		if deselect_sound == null:
			deselect_sound = AudioStreamPlayer3D.new()
			deselect_sound.name = "DeselectSound"
			deselect_sound.stream = sound_deselect
			deselect_sound.bus = &"Sound"
			deselect_sound.volume_db = -4.0
			deselect_sound.unit_size = 5.0
			deselect_sound.max_distance = 40.0
			add_child(deselect_sound)

## Воспроизведение звука хода игрока (белые: четкий стук постановки на доску)
func _play_player_move_sound(world_pos: Vector3) -> void:
	if player_turn_sound == null:
		_setup_audio_players()
	if player_turn_sound and is_inside_tree() and player_turn_sound.is_inside_tree():
		player_turn_sound.global_position = world_pos
		player_turn_sound.pitch_scale = randf_range(0.96, 1.04)
		player_turn_sound.play()

## Воспроизведение звука взятия фигуры (сочный тяжелый удар дерева о дерево)
func _play_capture_sound(world_pos: Vector3) -> void:
	if capture_sound == null:
		_setup_audio_players()
	if capture_sound and is_inside_tree() and capture_sound.is_inside_tree():
		capture_sound.global_position = world_pos
		capture_sound.pitch_scale = randf_range(0.95, 1.05)
		capture_sound.play()

## Воспроизведение звука отмены выбора фигуры (мягкий глухой щелчок опускания на доску)
func _play_deselect_sound(world_pos: Vector3) -> void:
	if deselect_sound == null:
		_setup_audio_players()
	if deselect_sound and is_inside_tree() and deselect_sound.is_inside_tree():
		deselect_sound.global_position = world_pos
		deselect_sound.pitch_scale = randf_range(0.96, 1.04)
		deselect_sound.play()

## Воспроизведение звука хода врага (черные: медленное зловещее протаскивание по доске)
func _play_enemy_move_sound(start_pos: Vector3, end_pos: Vector3, duration: float) -> void:
	if enemy_turn_sound == null:
		_setup_audio_players()
	if enemy_turn_sound and is_inside_tree() and enemy_turn_sound.is_inside_tree():
		enemy_turn_sound.global_position = start_pos
		if duration > 0.1:
			var normal_len: float = 1.846
			enemy_turn_sound.pitch_scale = clampf(normal_len / duration, 0.75, 1.35)
		else:
			enemy_turn_sound.pitch_scale = 1.0
		enemy_turn_sound.play()
		
		var sound_tween: Tween = create_tween()
		sound_tween.tween_property(enemy_turn_sound, "global_position", end_pos, duration)

## Остановка звука хода врага
func _stop_enemy_move_sound() -> void:
	if enemy_turn_sound and enemy_turn_sound.playing:
		enemy_turn_sound.stop()
