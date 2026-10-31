class_name ChessBoardView
extends Node3D

## 3D-контроллер шахматной доски для проекта «Белый Король»
## Управляет 3D-моделями фигур, подсветкой ходов, вводом игрока и интеграцией с EventBus.

const ChessLogicScript = preload("res://scripts/chess/chess_logic.gd")
const ChessPiece3DScript = preload("res://scripts/chess/chess_piece_3d.gd")
const VoxelBloodStainScript = preload("res://scripts/chess/voxel_blood_stain.gd")

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
@export_range(0.05, 2.0, 0.05) var white_move_duration: float = 0.35
## Длительность хода войны (черные фигуры, медленное зловещее скольжение со скрежетом)
@export_range(0.05, 4.0, 0.1) var black_move_duration: float = 0.8
## Задержка перед ходом ИИ черных после окончания анимации хода игрока, секунды
@export_range(0.0, 2.0, 0.05) var ai_turn_delay: float = 0.2

# Узел камеры для вида над доской
@onready var camera_point: Marker3D = $CameraPoint
@onready var pieces_container: Node3D = $Pieces
@onready var highlights_container: Node3D = $Highlights
@onready var blood_container: Node3D = get_node_or_null("BloodStains")
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
var blood_layers: Dictionary = {} # Vector2i -> int (количество взятий на клетке)

# Состояние выбора
var selected_pos: Vector2i = Vector2i(-1, -1)
var current_legal_moves: Array[Vector2i] = []
var is_active: bool = false # Активен ли режим управления шахматами
var is_ai_thinking: bool = false

# Фоновый параллельный расчет хода ИИ (просчет во время анимации белых)
var _ai_thread: Thread = null
var _precomputed_ai_move: Dictionary = {}
var _is_ai_calculating: bool = false
var _white_animation_finished: bool = false
var _ai_turn_delay_finished: bool = false

# Состояние превращения пешки
var _promoting_pos: Vector2i = Vector2i(-1, -1)
var _promoting_node: ChessPiece3D = null
var _promotion_dialog: CanvasLayer = null

# Материалы для фигур и подсветки
var white_mat: StandardMaterial3D
var black_mat: StandardMaterial3D
var move_highlight_mat: StandardMaterial3D
var attack_highlight_mat: StandardMaterial3D
var select_highlight_mat: StandardMaterial3D

# Меши для фигур
var meshes: Dictionary = {}

@onready var board_light: OmniLight3D = get_node_or_null("BoardLight")
var _board_light_tween: Tween = null
var _is_light_trouble_active: bool = false

# Отладочный HUD и режим быстрой анимации
var is_fast_mode: bool = false
var _debug_hud_canvas: CanvasLayer = null
var _debug_hud_panel: PanelContainer = null
var _debug_hud_label: RichTextLabel = null
var _is_debug_hud_visible: bool = true

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
	
	if blood_container == null:
		blood_container = get_node_or_null("BloodStains")
		if blood_container == null:
			blood_container = Node3D.new()
			blood_container.name = "BloodStains"
			add_child(blood_container)
	
	logic = ChessLogicScript.new()
	ChessBot._init_zobrist()
	spawn_pieces()
	_setup_debug_hud()
	
	# Подписываемся на события шины
	var bus = _get_event_bus()
	if bus and bus.has_signal("camera_mode_changed"):
		bus.camera_mode_changed.connect(_on_camera_mode_changed)
	if bus and bus.has_signal("lamp_flicker_triggered"):
		bus.lamp_flicker_triggered.connect(_on_lamp_flicker_triggered)
	if bus and bus.has_signal("lamp_trouble_finished"):
		bus.lamp_trouble_finished.connect(_on_lamp_trouble_finished)

## Синхронизация подсветки доски с перебоем света подвесной лампы
func _on_lamp_flicker_triggered(sound_idx: int, _duration: float) -> void:
	_is_light_trouble_active = true
	if board_light == null:
		return
	if _board_light_tween and _board_light_tween.is_valid():
		_board_light_tween.kill()
	_board_light_tween = create_tween().set_trans(Tween.TRANS_LINEAR)
	match sound_idx:
		0: # lamp_troubles_1 (1.385s)
			_board_light_tween.tween_property(board_light, "light_energy", 0.05, 0.02)
			_board_light_tween.tween_property(board_light, "light_energy", 1.50, 0.02)
			_board_light_tween.tween_property(board_light, "light_energy", 0.00, 0.04)
			_board_light_tween.tween_interval(0.38)
			_board_light_tween.tween_property(board_light, "light_energy", 0.35, 0.04)
			_board_light_tween.tween_property(board_light, "light_energy", 0.20, 0.10)
			_board_light_tween.tween_property(board_light, "light_energy", 0.55, 0.10)
			_board_light_tween.tween_property(board_light, "light_energy", 0.30, 0.10)
			_board_light_tween.tween_property(board_light, "light_energy", 0.60, 0.06)
			_board_light_tween.tween_property(board_light, "light_energy", 1.35, 0.06)
			_board_light_tween.tween_property(board_light, "light_energy", 0.05, 0.04)
			_board_light_tween.tween_property(board_light, "light_energy", 0.15, 0.07)
			_board_light_tween.tween_property(board_light, "light_energy", 0.50, 0.07)
			_board_light_tween.tween_property(board_light, "light_energy", 0.75, 0.08)
			_board_light_tween.tween_property(board_light, "light_energy", 1.45, 0.05)
			_board_light_tween.tween_property(board_light, "light_energy", 0.90, 0.07)
			_board_light_tween.tween_property(board_light, "light_energy", 1.00, 0.085).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		1: # lamp_troubles_2 (1.846s)
			_board_light_tween.tween_property(board_light, "light_energy", 1.50, 0.01)
			_board_light_tween.tween_property(board_light, "light_energy", 0.05, 0.02)
			_board_light_tween.tween_property(board_light, "light_energy", 0.00, 0.05)
			_board_light_tween.tween_property(board_light, "light_energy", 0.35, 0.03)
			_board_light_tween.tween_property(board_light, "light_energy", 0.20, 0.09)
			_board_light_tween.tween_property(board_light, "light_energy", 0.45, 0.10)
			_board_light_tween.tween_property(board_light, "light_energy", 0.25, 0.10)
			_board_light_tween.tween_property(board_light, "light_energy", 1.65, 0.02)
			_board_light_tween.tween_property(board_light, "light_energy", 0.00, 0.05)
			_board_light_tween.tween_interval(0.53)
			_board_light_tween.tween_property(board_light, "light_energy", 1.40, 0.01)
			_board_light_tween.tween_property(board_light, "light_energy", 0.35, 0.03)
			_board_light_tween.tween_property(board_light, "light_energy", 0.60, 0.11)
			_board_light_tween.tween_property(board_light, "light_energy", 0.40, 0.10)
			_board_light_tween.tween_property(board_light, "light_energy", 0.70, 0.10)
			_board_light_tween.tween_property(board_light, "light_energy", 0.10, 0.12)
			_board_light_tween.tween_property(board_light, "light_energy", 1.50, 0.09)
			_board_light_tween.tween_property(board_light, "light_energy", 0.85, 0.09)
			_board_light_tween.tween_property(board_light, "light_energy", 1.00, 0.196).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		2: # lamp_troubles_3 (1.385s)
			_board_light_tween.tween_property(board_light, "light_energy", 0.05, 0.01)
			_board_light_tween.tween_property(board_light, "light_energy", 1.40, 0.01)
			_board_light_tween.tween_property(board_light, "light_energy", 0.00, 0.03)
			_board_light_tween.tween_interval(0.29)
			_board_light_tween.tween_property(board_light, "light_energy", 1.65, 0.01)
			_board_light_tween.tween_property(board_light, "light_energy", 0.45, 0.05)
			_board_light_tween.tween_property(board_light, "light_energy", 0.20, 0.08)
			_board_light_tween.tween_property(board_light, "light_energy", 0.50, 0.08)
			_board_light_tween.tween_property(board_light, "light_energy", 0.00, 0.06)
			_board_light_tween.tween_interval(0.20)
			_board_light_tween.tween_property(board_light, "light_energy", 1.55, 0.01)
			_board_light_tween.tween_property(board_light, "light_energy", 0.60, 0.07)
			_board_light_tween.tween_property(board_light, "light_energy", 0.80, 0.10)
			_board_light_tween.tween_property(board_light, "light_energy", 1.15, 0.15)
			_board_light_tween.tween_property(board_light, "light_energy", 1.00, 0.235).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		3: # lamp_troubles_4 (2.308s)
			_board_light_tween.tween_property(board_light, "light_energy", 0.00, 0.01)
			_board_light_tween.tween_interval(0.56)
			_board_light_tween.tween_property(board_light, "light_energy", 1.75, 0.01)
			_board_light_tween.tween_property(board_light, "light_energy", 0.60, 0.04)
			_board_light_tween.tween_property(board_light, "light_energy", 0.35, 0.06)
			_board_light_tween.tween_property(board_light, "light_energy", 0.00, 0.03)
			_board_light_tween.tween_interval(0.53)
			_board_light_tween.tween_property(board_light, "light_energy", 1.50, 0.01)
			_board_light_tween.tween_property(board_light, "light_energy", 0.00, 0.03)
			_board_light_tween.tween_interval(0.68)
			_board_light_tween.tween_property(board_light, "light_energy", 0.35, 0.03)
			_board_light_tween.tween_property(board_light, "light_energy", 1.35, 0.06)
			_board_light_tween.tween_property(board_light, "light_energy", 0.70, 0.07)
			_board_light_tween.tween_property(board_light, "light_energy", 1.10, 0.08)
			_board_light_tween.tween_property(board_light, "light_energy", 1.00, 0.108).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

## Окончание перебоя со светом: восстановление подсветки и возобновление хода ИИ
func _on_lamp_trouble_finished() -> void:
	_is_light_trouble_active = false
	if board_light:
		board_light.light_energy = 1.0
	# Если ИИ черных ждал окончания анимации перед своим ходом — запускаем ход с атмосферной паузой
	if is_ai_thinking and not logic.is_game_over and not logic.is_white_turn:
		var resume_timer = get_tree().create_timer(0.35)
		resume_timer.timeout.connect(_execute_ai_turn)

func _exit_tree() -> void:
	_cleanup_ai_thread()

func _process(_delta: float) -> void:
	# Проверка готовности фонового потока расчета хода черных
	if _is_ai_calculating and _ai_thread != null:
		if not _ai_thread.is_alive():
			var move = _ai_thread.wait_to_finish()
			_precomputed_ai_move = move if move is Dictionary else {}
			_is_ai_calculating = false
			_ai_thread = null
			_check_execute_ai_turn()

	if _is_debug_hud_visible and _debug_hud_label != null:
		_update_debug_hud()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var code: Key = event.keycode if event.keycode != KEY_NONE else event.physical_keycode
		match code:
			KEY_F1:
				restart_game(1)
				_update_debug_hud()
			KEY_F2:
				restart_game(2)
				_update_debug_hud()
			KEY_F3:
				toggle_fast_mode()
				_update_debug_hud()
			KEY_F4:
				toggle_debug_hud()

func _init_materials() -> void:
	# Белые: турнирный самшит с красным фетровым основанием
	white_mat = preload("res://assets/obj/chess/chess_white_material.tres")
	
	# Черные: мореный дуб / эбен с темно-красным фетровым основанием
	black_mat = preload("res://assets/obj/chess/chess_black_material.tres")
	
	# Подсветка доступного хода (зеленый/белый неоновый маркер)
	move_highlight_mat = StandardMaterial3D.new()
	move_highlight_mat.albedo_color = Color(0.15, 0.95, 0.45, 0.85)
	move_highlight_mat.emission_enabled = true
	move_highlight_mat.emission = Color(0.2, 1.0, 0.5)
	move_highlight_mat.emission_energy_multiplier = 3.5
	move_highlight_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	move_highlight_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	move_highlight_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	move_highlight_mat.render_priority = 2
	
	# Подсветка атаки/взятия (тревожный красный маркер)
	attack_highlight_mat = StandardMaterial3D.new()
	attack_highlight_mat.albedo_color = Color(1.0, 0.12, 0.15, 0.9)
	attack_highlight_mat.emission_enabled = true
	attack_highlight_mat.emission = Color(1.0, 0.15, 0.15)
	attack_highlight_mat.emission_energy_multiplier = 4.0
	attack_highlight_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	attack_highlight_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	attack_highlight_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	attack_highlight_mat.render_priority = 2
	
	# Подсветка выбранной фигуры (золотой маркер)
	select_highlight_mat = StandardMaterial3D.new()
	select_highlight_mat.albedo_color = Color(1.0, 0.82, 0.15, 0.85)
	select_highlight_mat.emission_enabled = true
	select_highlight_mat.emission = Color(1.0, 0.85, 0.2)
	select_highlight_mat.emission_energy_multiplier = 3.0
	select_highlight_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	select_highlight_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	select_highlight_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	select_highlight_mat.render_priority = 2

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
	clear_blood_stains()
	if _promotion_dialog != null and is_instance_valid(_promotion_dialog):
		_promotion_dialog.queue_free()
		_promotion_dialog = null
	if _promoting_node != null and is_instance_valid(_promoting_node):
		_promoting_node.set_selected(false)
		_promoting_node = null
		
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
	if meshes.is_empty():
		_init_meshes()
	if white_mat == null or black_mat == null:
		_init_materials()
		
	var piece_node = ChessPiece3DScript.new()
	var key: String = p_type + ("_white" if is_white else "_black")
	var mesh: Mesh = meshes.get(key, meshes.get(p_type, null))
	var mat: Material = white_mat if is_white else black_mat
	piece_node.setup(p_type, is_white, pos, mesh, mat, surface_y)
	
	piece_node.position = cell_to_local_pos(pos)
	pieces_container.add_child(piece_node)
	piece_nodes[pos] = piece_node
	return piece_node

var _is_restarting: bool = false

## Автоматический запуск перезапуска доски после мата с атмосферной задержкой
func _trigger_checkmate_restart(delay: float = 2.5) -> void:
	if _is_restarting:
		return
	_is_restarting = true
	var timer = get_tree().create_timer(delay)
	timer.timeout.connect(func():
		_is_restarting = false
		var next_p: int = logic.playthrough + 1
		restart_game(next_p)
	)

## Перезапуск шахматной партии с расстановкой всех 32 фигур обратно на свои места
func restart_game(next_playthrough: int = -1) -> void:
	_cleanup_ai_thread()
	clear_selection()
	_clear_highlights()
	clear_blood_stains()
	
	if _promotion_dialog != null and is_instance_valid(_promotion_dialog):
		_promotion_dialog.queue_free()
		_promotion_dialog = null
	if _promoting_node != null and is_instance_valid(_promoting_node):
		_promoting_node.set_selected(false)
		_promoting_node = null
		
	is_ai_thinking = false
	
	if pieces_container == null:
		pieces_container = get_node_or_null("Pieces")
		
	if pieces_container != null:
		for child in pieces_container.get_children():
			pieces_container.remove_child(child)
			child.queue_free()
			
	piece_nodes.clear()
	
	if logic == null:
		logic = ChessLogicScript.new()
		
	if next_playthrough <= 0:
		next_playthrough = logic.playthrough + 1
	logic.reset_board(next_playthrough)
	
	# Спавним все 32 фигуры на свои исходные места
	for x in range(8):
		for y in range(8):
			var pos: Vector2i = Vector2i(x, y)
			var piece_data = logic.get_piece(pos)
			if piece_data != null:
				_spawn_piece_at(pos, piece_data["type"], piece_data["is_white"])
				
	var bus = _get_event_bus()
	if bus:
		if bus.has_method("reset_game_state"):
			bus.reset_game_state(logic.playthrough)
		elif bus.has_signal("game_reset"):
			bus.game_reset.emit(logic.playthrough)
			
	# Звуковой сигнал перехода хода игроку
	if is_inside_tree():
		_play_player_move_sound(to_global(cell_to_local_pos(Vector2i(4, 0))))
		
	_update_debug_hud()

# ==============================================================================
# ОТЛАДОЧНЫЙ РЕЖИМ И ПАНЕЛЬ ПЕРЕМЕННЫХ (Debug HUD & Testing Controls)
# ==============================================================================

func toggle_fast_mode() -> void:
	is_fast_mode = not is_fast_mode
	if is_fast_mode:
		white_move_duration = 0.05
		black_move_duration = 0.05
		ai_turn_delay = 0.02
	else:
		white_move_duration = 0.35
		black_move_duration = 0.8
		ai_turn_delay = 0.2

func toggle_debug_hud() -> void:
	_is_debug_hud_visible = not _is_debug_hud_visible
	if _debug_hud_canvas != null and is_instance_valid(_debug_hud_canvas):
		_debug_hud_canvas.visible = _is_debug_hud_visible

func _setup_debug_hud() -> void:
	if not is_inside_tree():
		return
	if _debug_hud_canvas != null and is_instance_valid(_debug_hud_canvas):
		return
		
	var canvas = CanvasLayer.new()
	canvas.name = "DebugHUDCanvas"
	canvas.layer = 12
	add_child(canvas)
	_debug_hud_canvas = canvas
	
	var panel = PanelContainer.new()
	panel.name = "DebugPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 16.0
	panel.offset_top = 16.0
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.12, 0.88)
	style.border_color = Color(0.2, 0.7, 0.9, 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 14.0
	style.content_margin_top = 10.0
	style.content_margin_right = 14.0
	style.content_margin_bottom = 10.0
	panel.add_theme_stylebox_override("panel", style)
	canvas.add_child(panel)
	_debug_hud_panel = panel
	
	var label = RichTextLabel.new()
	label.name = "DebugLabel"
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.custom_minimum_size = Vector2(340, 190)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	_debug_hud_label = label
	
	_update_debug_hud()

func _update_debug_hud() -> void:
	if not _is_debug_hud_visible or _debug_hud_label == null:
		return
		
	var pt = logic.playthrough if logic else 1
	var pt_color = "#ff5555" if pt == 1 else "#55ff88"
	var pt_name = "МАТЧ 1: ХИЩНЫЙ ИИ (Hard)" if pt == 1 else "МАТЧ 2: ПОДДАВКИ (Medium)"
	
	var speed_text = "[color=#ffd700]⚡ 0.05с (БЫСТРО)[/color]" if is_fast_mode else "[color=#aaaaaa]0.8с (Норма)[/color]"
	var turn_text = "[color=#ffffff]Белые (Игрок)[/color]" if (logic and logic.is_white_turn) else "[color=#ff8888]Черные (ИИ)[/color]"
	var ai_status = "[color=#88ff88]Ожидание[/color]"
	if _is_ai_calculating:
		ai_status = "[color=#ffaa00]⚡ Просчет (в полете)...[/color]"
	elif is_ai_thinking:
		ai_status = "[color=#ff5555]Ходит...[/color]"
	
	var w_mat = 0
	var b_mat = 0
	if logic:
		for x in range(8):
			for y in range(8):
				var p = logic.get_piece(Vector2i(x, y))
				if p != null and p["type"] != "king":
					var val = ChessLogic.PIECE_VALUES.get(p["type"], 0)
					if p["is_white"]: w_mat += val
					else: b_mat += val
	var diff = w_mat - b_mat
	var diff_str = ("+" if diff > 0 else "") + str(diff)
	var diff_color = "#88ffaa" if diff > 0 else ("#ff8888" if diff < 0 else "#cccccc")
	
	var bus = _get_event_bus()
	var losses = bus.total_losses if bus else 0
	var stage = bus.current_stage if bus else 1
	
	var bot_info = ChessBot.last_search_info
	var eval_score = bot_info.get("score", 0.0)
	var search_depth = bot_info.get("depth", 0)
	
	var text = "[b][color=#33ccff]⚙ ОТЛАДКА ШАХМАТ (ZUGZWANG)[/color][/b]\n"
	text += "Режим: [color=%s][b]%s[/b][/color]\n" % [pt_color, pt_name]
	text += "Скорость ходов: %s\n" % speed_text
	text += "Ход #%d: %s | ИИ: %s\n" % [logic.move_count if logic else 0, turn_text, ai_status]
	text += "Материал: Белые %d | Черные %d ([color=%s]%s[/color])\n" % [w_mat, b_mat, diff_color, diff_str]
	text += "Оценка ИИ: [color=#88ffaa]%.1f cp[/color] (глубина %d)\n" % [eval_score, search_depth]
	text += "Бункер: Потери %d/16 | Стадия тревоги %d/4\n" % [losses, stage]
	text += "[color=#445566]──────────────────────────────────[/color]\n"
	text += "[color=#bbccdd][b][F1][/b] Матч 1 | [b][F2][/b] Матч 2 | [b][F3][/b] Скорость | [b][F4][/b] Скрыть[/color]"
	
	_debug_hud_label.text = text

func _on_camera_mode_changed(is_board_mode: bool) -> void:
	is_active = is_board_mode
	if not is_active:
		clear_selection()

## Обработка ввода мыши по доске
func _unhandled_input(event: InputEvent) -> void:
	if _promotion_dialog != null and is_instance_valid(_promotion_dialog):
		if event is InputEventKey and event.pressed and not event.echo:
			var code: Key = event.keycode if event.keycode != KEY_NONE else event.physical_keycode
			match code:
				KEY_1, KEY_Q:
					_on_promotion_selected(_promoting_pos, _promoting_node, "queen")
					get_viewport().set_input_as_handled()
					return
				KEY_2, KEY_R:
					_on_promotion_selected(_promoting_pos, _promoting_node, "rook")
					get_viewport().set_input_as_handled()
					return
				KEY_3, KEY_B:
					_on_promotion_selected(_promoting_pos, _promoting_node, "bishop")
					get_viewport().set_input_as_handled()
					return
				KEY_4, KEY_N, KEY_K:
					_on_promotion_selected(_promoting_pos, _promoting_node, "knight")
					get_viewport().set_input_as_handled()
					return
		return

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
			# Если до этого была выбрана другая фигура — воспроизводим звук отмены выбора старой фигуры
			if selected_pos != Vector2i(-1, -1):
				var prev_node = piece_nodes.get(selected_pos)
				var sound_pos: Vector3 = prev_node.global_position if (prev_node and prev_node.is_inside_tree()) else global_position
				_play_deselect_sound(sound_pos)
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
		
	var blood_lvl: int = blood_layers.get(cell, 0)
	var pos: Vector3 = cell_to_local_pos(cell)
	
	var tile = MeshInstance3D.new()
	var quad = BoxMesh.new()
	
	# Одинаковая толщина и размер маркера как на обычных клетках, так и на клетках с кровью
	var h: float = 0.006
	var y_offset: float = 0.004
	if blood_lvl > 0:
		# На луже крови только поднимаем маркер на поверхность лужи, сохраняя размер и форму абсолютно одинаковыми
		y_offset = 0.052 + float(blood_lvl - 1) * 0.006
		
	quad.size = Vector3(size, h, size)
	tile.mesh = quad
	tile.material_override = mat
	tile.position = Vector3(pos.x, pos.y + y_offset, pos.z)
	highlights_container.add_child(tile)

func _clear_highlights() -> void:
	if highlights_container == null:
		highlights_container = get_node_or_null("Highlights")
	if highlights_container == null:
		return
	for child in highlights_container.get_children():
		child.queue_free()

func clear_highlights() -> void:
	_clear_highlights()
		

## Остановка и очистка фонового потока расчета ИИ
func _cleanup_ai_thread() -> void:
	if _ai_thread != null and _ai_thread.is_started():
		_ai_thread.wait_to_finish()
	_ai_thread = null
	_is_ai_calculating = false
	_white_animation_finished = false
	_ai_turn_delay_finished = false
	_precomputed_ai_move.clear()

## Запуск фонового просчета хода черных (выполняется ПАРАЛЛЕЛЬНО с анимацией полета фигуры игрока)
func _start_precomputing_ai_move() -> void:
	_cleanup_ai_thread()
	
	if logic == null or logic.is_game_over:
		return
		
	is_ai_thinking = true
	_is_ai_calculating = true
	_precomputed_ai_move.clear()
	
	var grid_copy: Array = logic.clone_grid()
	var pt: int = logic.playthrough
	
	_ai_thread = Thread.new()
	var thread_func = func():
		return ChessBot.choose_best_move(grid_copy, pt)
		
	var err = _ai_thread.start(thread_func)
	if err != OK:
		# Резервный расчет на случай сбоя создания потока
		_is_ai_calculating = false
		_ai_thread = null
		_precomputed_ai_move = ChessBot.choose_best_move(grid_copy, pt)

## Проверка условий для фактического перемещения черной фигуры по доске
func _check_execute_ai_turn() -> void:
	# ИИ начинает ход только когда:
	# 1. Анимация переноса белой фигуры полностью завершилась
	# 2. Задержка между ходами истекла
	# 3. Фоновый расчет хода ИИ завершен
	if not _white_animation_finished or not _ai_turn_delay_finished or _is_ai_calculating:
		return
	if logic == null or logic.is_game_over or not is_inside_tree():
		is_ai_thinking = false
		return
		
	var move_to_play: Dictionary = _precomputed_ai_move
	_precomputed_ai_move = {}
	_white_animation_finished = false
	_ai_turn_delay_finished = false
	
	_execute_ai_turn(move_to_play)

## Выполнение хода игрока
func _execute_player_move(from_pos: Vector2i, to_pos: Vector2i) -> void:
	clear_selection()
	
	var piece_node = piece_nodes.get(from_pos)
	if not piece_node:
		return
		
	var is_pawn_promotion: bool = (piece_node.piece_type == "pawn" and piece_node.is_white and to_pos.y == 7)
	
	var move_res = logic.make_move(from_pos, to_pos)
	if not move_res["success"]:
		return
		
	var bus = _get_event_bus()
	
	# Обработка рокировки (анимация перемещения ладьи)
	if move_res.get("castled", false):
		var r_from: Vector2i = move_res["rook_from"]
		var r_to: Vector2i = move_res["rook_to"]
		var rook_node = piece_nodes.get(r_from)
		if rook_node:
			piece_nodes.erase(r_from)
			piece_nodes[r_to] = rook_node
			rook_node.board_pos = r_to
			var r_target_world: Vector3 = to_global(cell_to_local_pos(r_to))
			rook_node.animate_to(r_target_world, white_move_duration, false)
			if bus:
				bus.piece_moved.emit(r_from, r_to)
	
	# Обработка взятия
	var is_capture: bool = move_res["captured"]
	var victim_node = piece_nodes.get(to_pos) if is_capture else null
	if is_capture:
		piece_nodes.erase(to_pos)
			
	# Перемещение 3D-ноды (ход игрока белыми — дуговой перенос)
	piece_nodes.erase(from_pos)
	piece_nodes[to_pos] = piece_node
	piece_node.board_pos = to_pos
	var target_world_pos: Vector3 = to_global(cell_to_local_pos(to_pos))
	
	# СБРАСЫВАЕМ ФЛАГИ ГОТОВНОСТИ И ЗАПУСКАЕМ РАСЧЕТ ИИ НЕ ДОЖИДАЯСЬ ОКОНЧАНИЯ АНИМАЦИИ
	_white_animation_finished = false
	_ai_turn_delay_finished = false
	if not is_pawn_promotion and not move_res["is_checkmate"]:
		_start_precomputing_ai_move()
	
	var on_move_finished = func():
		if is_capture:
			_play_capture_sound(target_world_pos)
			if victim_node:
				victim_node.animate_capture(0.25)
			# Процедурное воксельное пятно крови на клетке гибели фигуры
			spawn_blood_stain(to_pos)
			# Окрашиваем фигуру-убийцу кровью
			if piece_node:
				piece_node.apply_blood_stain()
			if bus:
				bus.piece_captured.emit(move_res["captured_piece"], move_res["captured_is_white"])
		else:
			_play_player_move_sound(target_world_pos)
			
		if is_pawn_promotion:
			# Поднимаем пешку над доской как при выборе фигуры
			piece_node.set_selected(true)
			# Показываем модальное окно выбора фигуры для превращения
			_show_promotion_dialog(to_pos, piece_node)
		else:
			if move_res["is_checkmate"]:
				if bus:
					bus.game_over.emit(logic.winner)
				_trigger_checkmate_restart()
				return
				
			# Анимация перемещения белой фигуры завершилась
			_white_animation_finished = true
			
			# Задержка перед ходом черных
			var delay: float = 0.02 if is_fast_mode else ai_turn_delay
			if delay <= 0.01:
				_ai_turn_delay_finished = true
				_check_execute_ai_turn()
			else:
				var timer = get_tree().create_timer(delay)
				timer.timeout.connect(func():
					_ai_turn_delay_finished = true
					_check_execute_ai_turn()
				)
	
	if white_move_duration <= 0.05:
		on_move_finished.call()
		piece_node.animate_to(target_world_pos, white_move_duration, false)
	else:
		piece_node.animate_to(target_world_pos, white_move_duration, false, on_move_finished)
	
	if bus:
		bus.piece_moved.emit(from_pos, to_pos)
		bus.player_made_action.emit()

## Ход ИИ войны (использует предрассчитанный ход ai_move)
func _execute_ai_turn(ai_move: Dictionary = {}) -> void:
	if logic == null or logic.is_game_over or not is_inside_tree():
		is_ai_thinking = false
		return

	# Блокировка: пока проигрывается анимация перебоя со светом, противник не может сделать ход
	var bus = _get_event_bus()
	var is_trouble: bool = _is_light_trouble_active
	if bus and bus.get("is_lamp_trouble_active") == true:
		is_trouble = true
	if is_trouble:
		is_ai_thinking = true
		return
		
	if ai_move.is_empty():
		ai_move = logic.get_best_ai_move()
		
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
	
	# Обработка рокировки черных (анимация ладьи)
	if move_res.get("castled", false):
		var r_from: Vector2i = move_res["rook_from"]
		var r_to: Vector2i = move_res["rook_to"]
		var rook_node = piece_nodes.get(r_from)
		if rook_node:
			piece_nodes.erase(r_from)
			piece_nodes[r_to] = rook_node
			rook_node.board_pos = r_to
			var r_target_world: Vector3 = to_global(cell_to_local_pos(r_to))
			rook_node.animate_to(r_target_world, black_move_duration, true)
			if bus:
				bus.piece_moved.emit(r_from, r_to)
				
	# Обработка взятия белой фигуры
	var is_ai_capture: bool = move_res["captured"]
	var victim_node = piece_nodes.get(to_pos) if is_ai_capture else null
	if is_ai_capture:
		piece_nodes.erase(to_pos)
			
	# Превращение пешки черных в ферзя
	if move_res.get("promoted", false):
		var promo_mesh: Mesh = meshes.get("queen_black", meshes.get("queen", meshes["pawn"]))
		piece_node.change_type("queen", promo_mesh, black_mat)
			
	# Медленное скольжение черной фигуры строго по доске (для звука скрежета)
	piece_nodes.erase(from_pos)
	piece_nodes[to_pos] = piece_node
	piece_node.board_pos = to_pos
	
	var start_world_pos: Vector3 = piece_node.global_position
	var target_world_pos: Vector3 = to_global(cell_to_local_pos(to_pos))
	_play_enemy_move_sound(start_world_pos, target_world_pos, black_move_duration)
	
	piece_node.animate_to(target_world_pos, black_move_duration, true, func():
		_stop_enemy_move_sound()
		if is_ai_capture:
			_play_capture_sound(target_world_pos)
			if victim_node:
				victim_node.animate_capture(0.25)
			# Процедурное воксельное пятно крови на клетке гибели фигуры
			spawn_blood_stain(to_pos)
			# Окрашиваем фигуру-убийцу черных кровью
			if piece_node:
				piece_node.apply_blood_stain()
			if bus:
				bus.piece_captured.emit(move_res["captured_piece"], move_res["captured_is_white"])
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
			_trigger_checkmate_restart()
	)

# ==============================================================================
# ПРЕВРАЩЕНИЕ ПЕШКИ (Pawn Promotion UI)
# ==============================================================================

## Отображение модального диалога выбора фигуры для превращения пешки
func _show_promotion_dialog(cell: Vector2i, piece_node: ChessPiece3D) -> void:
	_promoting_pos = cell
	_promoting_node = piece_node
	
	if _promotion_dialog != null and is_instance_valid(_promotion_dialog):
		_promotion_dialog.queue_free()
		
	var canvas = CanvasLayer.new()
	canvas.name = "PromotionCanvas"
	canvas.layer = 15
	add_child(canvas)
	_promotion_dialog = canvas
	
	# Легкое затемнение фона, позволяющее видеть приподнятую пешку на доске
	var overlay = ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.45)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.add_child(overlay)
	
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(center)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vbox)
	
	# Заголовок "ПРЕВРАЩЕНИЕ ПЕШКИ"
	var title = Label.new()
	title.text = "ПРЕВРАЩЕНИЕ ПЕШКИ"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.94, 0.91, 0.82))
	title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	title.add_theme_constant_override("shadow_offset_x", 1)
	title.add_theme_constant_override("shadow_offset_y", 2)
	vbox.add_child(title)
	
	# Ряд полупрозрачных карточек с 3D-моделями фигур
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(hbox)
	
	var options: Array[Dictionary] = [
		{"type": "queen", "name": "Ферзь"},
		{"type": "rook", "name": "Ладья"},
		{"type": "bishop", "name": "Слон"},
		{"type": "knight", "name": "Конь"}
	]
	
	for opt in options:
		var card_btn = Button.new()
		card_btn.custom_minimum_size = Vector2(115, 155)
		card_btn.text = ""
		card_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		
		# Стиль карточки: полупрозрачный темный фон
		var normal_style = StyleBoxFlat.new()
		normal_style.bg_color = Color(0.09, 0.09, 0.11, 0.65)
		normal_style.border_color = Color(0.48, 0.45, 0.38, 0.55)
		normal_style.set_border_width_all(1)
		normal_style.set_corner_radius_all(6)
		normal_style.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
		normal_style.shadow_size = 6
		card_btn.add_theme_stylebox_override("normal", normal_style)
		
		var hover_style = StyleBoxFlat.new()
		hover_style.bg_color = Color(0.20, 0.18, 0.13, 0.85)
		hover_style.border_color = Color(0.96, 0.86, 0.55, 0.95)
		hover_style.set_border_width_all(2)
		hover_style.set_corner_radius_all(6)
		hover_style.shadow_color = Color(0.96, 0.86, 0.55, 0.25)
		hover_style.shadow_size = 10
		card_btn.add_theme_stylebox_override("hover", hover_style)
		
		var pressed_style = StyleBoxFlat.new()
		pressed_style.bg_color = Color(0.28, 0.24, 0.16, 0.95)
		pressed_style.border_color = Color(1.0, 0.92, 0.65, 1.0)
		pressed_style.set_border_width_all(2)
		pressed_style.set_corner_radius_all(6)
		card_btn.add_theme_stylebox_override("pressed", pressed_style)
		
		var focus_style = StyleBoxEmpty.new()
		card_btn.add_theme_stylebox_override("focus", focus_style)
		
		# Внутренний контейнер с отступами
		var margin = MarginContainer.new()
		margin.set_anchors_preset(Control.PRESET_FULL_RECT)
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		margin.add_theme_constant_override("margin_left", 6)
		margin.add_theme_constant_override("margin_top", 6)
		margin.add_theme_constant_override("margin_right", 6)
		margin.add_theme_constant_override("margin_bottom", 6)
		card_btn.add_child(margin)
		
		var card_vbox = VBoxContainer.new()
		card_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_vbox.add_theme_constant_override("separation", 4)
		margin.add_child(card_vbox)
		
		# 3D Viewport для отображения фигуры
		var vp_container = SubViewportContainer.new()
		vp_container.custom_minimum_size = Vector2(103, 110)
		vp_container.stretch = true
		vp_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_vbox.add_child(vp_container)
		
		var vp = SubViewport.new()
		vp.size = Vector2i(103, 110)
		vp.transparent_bg = true
		vp.own_world_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp_container.add_child(vp)
		
		# Освещение в SubViewport (теплый свет сверху-спереди + мягкий контурный свет)
		var key_light = DirectionalLight3D.new()
		key_light.rotation_degrees = Vector3(-35, 30, 0)
		key_light.light_color = Color(1.0, 0.96, 0.88)
		key_light.light_energy = 1.6
		vp.add_child(key_light)
		
		var rim_light = DirectionalLight3D.new()
		rim_light.rotation_degrees = Vector3(25, -150, 0)
		rim_light.light_color = Color(0.65, 0.75, 0.90)
		rim_light.light_energy = 0.7
		vp.add_child(rim_light)
		
		# Камера, сфокусированная на фигуре
		var cam = Camera3D.new()
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.fov = 38.0
		cam.look_at_from_position(Vector3(0.0, 0.58, 1.85), Vector3(0.0, 0.54, 0.0))
		vp.add_child(cam)
		
		# 3D-модель фигуры
		var pivot = Node3D.new()
		pivot.position = Vector3(0.0, 0.0, 0.0)
		vp.add_child(pivot)
		
		var mesh_node = MeshInstance3D.new()
		var p_key: String = opt["type"] + "_white"
		mesh_node.mesh = meshes.get(p_key, meshes.get(opt["type"]))
		mesh_node.material_override = white_mat
		pivot.add_child(mesh_node)
		
		# Плавное вращение фигуры на 360 градусов
		var spin_tween = vp.create_tween().set_loops()
		spin_tween.tween_property(pivot, "rotation_degrees:y", 360.0, 8.0).from(0.0)
		
		# Название фигуры
		var name_lbl = Label.new()
		name_lbl.text = opt["name"]
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_lbl.add_theme_font_size_override("font_size", 14)
		name_lbl.add_theme_color_override("font_color", Color(0.90, 0.88, 0.82))
		card_vbox.add_child(name_lbl)
		
		# Интерактивность при наведении курсора
		card_btn.mouse_entered.connect(func():
			name_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.65))
		)
		card_btn.mouse_exited.connect(func():
			name_lbl.add_theme_color_override("font_color", Color(0.90, 0.88, 0.82))
		)
		
		var chosen: String = opt["type"]
		card_btn.pressed.connect(func(): _on_promotion_selected(cell, piece_node, chosen))
		hbox.add_child(card_btn)

## Обработка выбора фигуры для превращения
func _on_promotion_selected(cell: Vector2i, piece_node: ChessPiece3D, chosen_type: String) -> void:
	if _promotion_dialog != null and is_instance_valid(_promotion_dialog):
		_promotion_dialog.queue_free()
		_promotion_dialog = null
		
	if piece_node == null and piece_nodes.has(cell):
		piece_node = piece_nodes[cell]
		
	_promoting_pos = Vector2i(-1, -1)
	_promoting_node = null
	
	# 1. Обновляем тип в логике
	logic.promote_pawn(cell, chosen_type)
	
	# 2. Обновляем 3D-модель фигуры и опускаем её обратно на доску
	if piece_node:
		var key: String = chosen_type + "_white"
		var new_mesh: Mesh = meshes.get(key, meshes.get(chosen_type, meshes["queen"]))
		piece_node.change_type(chosen_type, new_mesh, white_mat)
		piece_node.set_selected(false)
		_play_player_move_sound(piece_node.global_position)
		
	var bus = _get_event_bus()
	if logic.is_game_over:
		if bus:
			bus.game_over.emit(logic.winner)
		_trigger_checkmate_restart()
		return
		
	# 3. Передаем ход черному ИИ с параллельным фоновым просчетом
	_white_animation_finished = true
	_ai_turn_delay_finished = false
	_start_precomputing_ai_move()
	var delay: float = 0.02 if is_fast_mode else ai_turn_delay
	if delay <= 0.01:
		_ai_turn_delay_finished = true
		_check_execute_ai_turn()
	else:
		var timer = get_tree().create_timer(delay)
		timer.timeout.connect(func():
			_ai_turn_delay_finished = true
			_check_execute_ai_turn()
		)

# ==============================================================================
# ВОКСЕЛЬНЫЕ ПЯТНА КРОВИ (Voxel Blood Stains)
# ==============================================================================

## Создание процедурного воксельного пятна крови на клетке доски при взятии фигуры
func spawn_blood_stain(cell: Vector2i) -> Node3D:
	if blood_container == null:
		blood_container = get_node_or_null("BloodStains")
		if blood_container == null:
			blood_container = Node3D.new()
			blood_container.name = "BloodStains"
			add_child(blood_container)
			
	var layer_idx: int = blood_layers.get(cell, 0)
	blood_layers[cell] = layer_idx + 1
	
	var stain = VoxelBloodStainScript.new()
	var local_cell_pos: Vector3 = cell_to_local_pos(cell)
	blood_container.add_child(stain)
	stain.create_stain(local_cell_pos, layer_idx, true)
	return stain

## Очистка всех воксельных пятен крови (при сбросе доски / новой партии)
func clear_blood_stains() -> void:
	blood_layers.clear()
	if blood_container == null:
		blood_container = get_node_or_null("BloodStains")
	if blood_container != null:
		for child in blood_container.get_children():
			child.queue_free()

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

func _play_player_turn_sound(world_pos: Vector3) -> void:
	_play_player_move_sound(world_pos)

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
