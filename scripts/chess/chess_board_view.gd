class_name ChessBoardView
extends Node3D

## 3D-контроллер шахматной доски для проекта «Белый Король»
## Координирует 3D-фигуры, ввод игрока, фоновые потоки ИИ/пондеринга и делегирует
## специализированные задачи подсистемам:
## - ChessAudioController: 3D-звуковое оформление ходов, скольжения и взятий
## - ChessBloodManager: процедурные воксельные пятна крови
## - ChessHighlights: неоновые маркеры выбора и доступных ходов
## - ChessPromotionDialog: модальный 3D-диалог превращения пешки
## - ChessDebugHUD: отладочная панель состояния матча и горячие клавиши

const ChessLogicScript = preload("res://scripts/chess/chess_logic.gd")
const ChessPiece3DScript = preload("res://scripts/chess/chess_piece_3d.gd")
const ChessBotScript = preload("res://scripts/chess/chess_bot.gd")
const VoxelBloodStainScript = preload("res://scripts/chess/voxel_blood_stain.gd")

const ChessAudioController = preload("res://scripts/chess/view/chess_audio_controller.gd")
const ChessBloodManager = preload("res://scripts/chess/view/chess_blood_manager.gd")
const ChessHighlights = preload("res://scripts/chess/view/chess_highlights.gd")
const ChessPromotionDialog = preload("res://scripts/chess/view/chess_promotion_dialog.gd")
const ChessDebugHUD = preload("res://scripts/chess/view/chess_debug_hud.gd")
const ChessLightController = preload("res://scripts/chess/view/chess_light_controller.gd")

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

# Узлы сцены
@onready var camera_point: Marker3D = $CameraPoint
@onready var pieces_container: Node3D = $Pieces
@onready var highlights_container: Node3D = $Highlights
@onready var blood_container: Node3D = get_node_or_null("BloodStains")
@onready var player_turn_sound: AudioStreamPlayer3D = get_node_or_null("PlayerTurnSound")
@onready var enemy_turn_sound: AudioStreamPlayer3D = get_node_or_null("EnemyTurnSound")
@onready var capture_sound: AudioStreamPlayer3D = get_node_or_null("CaptureSound")
@onready var deselect_sound: AudioStreamPlayer3D = get_node_or_null("DeselectSound")
@onready var board_light: OmniLight3D = get_node_or_null("BoardLight")

# Специализированные контроллеры подсистем вида
var audio_controller: ChessAudioController = null
var blood_manager: ChessBloodManager = null
var highlights: ChessHighlights = null
var promotion_dialog: ChessPromotionDialog = null
var debug_hud: ChessDebugHUD = null
var light_controller: ChessLightController = null

var logic: ChessLogic = null
var piece_nodes: Dictionary = {} # Vector2i -> ChessPiece3D
var blood_layers: Dictionary = {} # Vector2i -> int (ссылка на blood_manager.blood_layers)

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
var _is_white_moving: bool = false

# Фоновый пре-расчет ходов соперника (Pondering во время хода игрока)
var _ponder_thread: Thread = null
var _is_pondering: bool = false
var _ponder_cancel_requested: bool = false
var _ponder_cache: Dictionary = {}
var _pending_precompute_on_ponder_finish: bool = false

# Состояние превращения пешки
var _promoting_pos: Vector2i = Vector2i(-1, -1)
var _promoting_node: ChessPiece3D = null
var _promotion_dialog: CanvasLayer:
	get:
		return promotion_dialog.dialog_canvas if promotion_dialog != null else null
	set(val):
		if promotion_dialog != null:
			promotion_dialog.dialog_canvas = val

# Материалы для фигур
var white_mat: StandardMaterial3D
var black_mat: StandardMaterial3D

# Меши для фигур
var meshes: Dictionary = {}

var _board_light_tween: Tween = null
var _is_light_trouble_active: bool = false
var _pending_ai_move_during_trouble: Dictionary = {}
var _black_turn_timer: float = 0.0
var is_fast_mode: bool = false
var _is_restarting: bool = false

func _get_event_bus() -> Node:
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/EventBus")

func _ready() -> void:
	_init_submodules()
	_init_materials()
	_init_meshes()
	
	logic = ChessLogicScript.new()
	var bus = _get_event_bus()
	if bus and "current_playthrough" in bus and bus.current_playthrough > 1:
		logic.playthrough = bus.current_playthrough
		
	ChessBotScript._init_zobrist()
	spawn_pieces()
	debug_hud.setup(self)
	_start_pondering()
	
	# Подписываемся на события шины
	if bus and bus.has_signal("camera_mode_changed"):
		bus.camera_mode_changed.connect(_on_camera_mode_changed)
	if bus and bus.has_signal("lamp_flicker_triggered"):
		bus.lamp_flicker_triggered.connect(_on_lamp_flicker_triggered)
	if bus and bus.has_signal("lamp_trouble_finished"):
		bus.lamp_trouble_finished.connect(_on_lamp_trouble_finished)
	if bus and bus.has_signal("seismic_shock_triggered"):
		bus.seismic_shock_triggered.connect(_on_seismic_shock_triggered)
	if bus and bus.has_signal("game_reset"):
		bus.game_reset.connect(func(pt: int):
			if logic:
				logic.playthrough = pt
		)

func _init_submodules() -> void:
	audio_controller = ChessAudioController.new()
	audio_controller.setup(self, player_turn_sound, enemy_turn_sound, capture_sound, deselect_sound)
	
	if blood_container == null:
		blood_container = get_node_or_null("BloodStains")
	blood_manager = ChessBloodManager.new()
	blood_manager.setup(self, blood_container)
	blood_container = blood_manager.blood_container
	blood_layers = blood_manager.blood_layers
	
	if highlights_container == null:
		highlights_container = get_node_or_null("Highlights")
	highlights = ChessHighlights.new()
	highlights.setup(self, highlights_container)
	highlights_container = highlights.highlights_container
	
	promotion_dialog = ChessPromotionDialog.new()
	promotion_dialog.setup(self)
	
	debug_hud = ChessDebugHUD.new()
	
	light_controller = ChessLightController.new()
	light_controller.setup(board_light)

func _exit_tree() -> void:
	_cleanup_ai_thread()
	_cleanup_ponder_thread()

func _process(delta: float) -> void:
	# 1. Проверка готовности фонового потока расчета хода черных
	if _is_ai_calculating and _ai_thread != null:
		if not _ai_thread.is_alive():
			var move = _ai_thread.wait_to_finish()
			_precomputed_ai_move = move if move is Dictionary else {}
			_is_ai_calculating = false
			_ai_thread = null
			_check_execute_ai_turn()

	# 2. Проверка готовности фонового пре-расчета (Pondering)
	if _ponder_thread != null and not _ponder_thread.is_alive():
		var res = _ponder_thread.wait_to_finish()
		if res is Dictionary and not res.is_empty():
			_ponder_cache.merge(res, true)
		_is_pondering = false
		_ponder_thread = null
		if _pending_precompute_on_ponder_finish:
			_pending_precompute_on_ponder_finish = false
			_start_precomputing_ai_move()

	# 3. Watchdog таймер: если на ходе черных бот думает дольше 4.5 секунд — восстанавливаем ход
	if logic != null and not logic.is_game_over and not logic.is_white_turn:
		_black_turn_timer += delta
		if _black_turn_timer > 4.5:
			_recover_stuck_ai_turn()
	else:
		_black_turn_timer = 0.0

	if debug_hud != null and debug_hud.is_visible():
		debug_hud.update(logic, is_fast_mode, _is_ai_calculating, is_ai_thinking, _get_event_bus())

## Аварийное восстановление при зависании или сверхдолгом ходе ИИ
func _recover_stuck_ai_turn() -> void:
	push_warning("[ChessBot Watchdog] Зафиксировано зависание хода ИИ (>4.5с). Аварийное восстановление...")
	_black_turn_timer = 0.0
	_cleanup_ai_thread()
	_cleanup_ponder_thread()
	_pending_precompute_on_ponder_finish = false
	_is_light_trouble_active = false
	var bus = _get_event_bus()
	if bus:
		bus.set("is_lamp_trouble_active", false)
	_white_animation_finished = true
	_ai_turn_delay_finished = true
	
	var fallback_move = logic.get_best_ai_move()
	if fallback_move.is_empty():
		fallback_move = logic._fallback_ai_move()
	if not fallback_move.is_empty():
		_execute_ai_turn(fallback_move)
	else:
		is_ai_thinking = false

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
			KEY_F5:
				trigger_debug_win()
			KEY_F6:
				trigger_debug_loss()
			KEY_F7:
				trigger_debug_draw()

## Отладочная моментальная победа Белых (Игрок)
func trigger_debug_win() -> void:
	if logic == null:
		logic = ChessLogicScript.new()
	logic.is_game_over = true
	logic.winner = "white"
	clear_selection()
	_clear_highlights()
	_cleanup_ai_thread()
	is_ai_thinking = false
	var bus = _get_event_bus()
	if bus:
		bus.game_over.emit("white")
	_update_debug_hud()

## Отладочное моментальное поражение Белых (Победа Чёрных)
func trigger_debug_loss() -> void:
	if logic == null:
		logic = ChessLogicScript.new()
	logic.is_game_over = true
	logic.winner = "black"
	clear_selection()
	_clear_highlights()
	_cleanup_ai_thread()
	is_ai_thinking = false
	var bus = _get_event_bus()
	if bus:
		bus.game_over.emit("black")
	_update_debug_hud()

## Отладочный моментальный пат (Ничья)
func trigger_debug_draw() -> void:
	if logic == null:
		logic = ChessLogicScript.new()
	logic.is_game_over = true
	logic.winner = "draw"
	clear_selection()
	_clear_highlights()
	_cleanup_ai_thread()
	is_ai_thinking = false
	var bus = _get_event_bus()
	if bus:
		bus.game_over.emit("draw")
	_update_debug_hud()

func _init_materials() -> void:
	white_mat = preload("res://assets/obj/chess/chess_white_material.tres")
	black_mat = preload("res://assets/obj/chess/chess_black_material.tres")

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
	if promotion_dialog != null:
		promotion_dialog.close_dialog()
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

## Автоматический запуск перезапуска доски после мата с атмосферной задержкой
func _trigger_checkmate_restart(delay: float = 2.5) -> void:
	if _is_restarting:
		return
	# Если EndingManager присутствует в сцене, он управляет кинематографичным финалом и перезапуском
	if is_inside_tree() and get_tree().get_nodes_in_group("ending_manager").size() > 0:
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
	_cleanup_ponder_thread()
	_ponder_cache.clear()
	_pending_ai_move_during_trouble.clear()
	_black_turn_timer = 0.0
	clear_selection()
	_clear_highlights()
	clear_blood_stains()
	
	if promotion_dialog != null:
		promotion_dialog.close_dialog()
	_promoting_node = null
		
	is_ai_thinking = false
	_is_white_moving = false
	_white_animation_finished = false
	_ai_turn_delay_finished = false
	
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
	_start_pondering()

# ==============================================================================
# ОТЛАДОЧНЫЙ РЕЖИМ (Debug HUD & Controls)
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
	if debug_hud != null:
		debug_hud.toggle_visibility()

func _update_debug_hud() -> void:
	if debug_hud != null and debug_hud.is_visible():
		debug_hud.update(logic, is_fast_mode, _is_ai_calculating, is_ai_thinking, _get_event_bus())

func _on_camera_mode_changed(is_board_mode: bool) -> void:
	is_active = is_board_mode
	if not is_active:
		clear_selection()

## Проверка, активен ли какой-либо эффект (перебой со светом, блэкаут, полет фигуры игрока, окно превращения)
func is_effect_active() -> bool:
	if _is_light_trouble_active:
		return true
	var bus = _get_event_bus()
	if bus != null and bus.get("is_lamp_trouble_active") == true:
		return true
	if _is_white_moving:
		return true
	if promotion_dialog != null and promotion_dialog.is_open():
		return true
	return false

## Обработка ввода мыши по доске
func _unhandled_input(event: InputEvent) -> void:
	if promotion_dialog != null and promotion_dialog.is_open():
		if promotion_dialog.handle_input(event):
			get_viewport().set_input_as_handled()
		return

	if not is_active or is_ai_thinking or logic.is_game_over or is_effect_active():
		return
		
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_board_click()
	elif event.is_action_pressed("ui_cancel") or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT):
		cancel_selection()

func _handle_board_click() -> void:
	if not is_active or is_ai_thinking or logic.is_game_over or is_effect_active() or not logic.is_white_turn:
		return

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
	if not is_active or is_ai_thinking or logic.is_game_over or is_effect_active() or not logic.is_white_turn:
		return

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

# ==============================================================================
# ПОДСВЕТКА И ДЕЛЕГИРОВАНИЕ (Highlights Delegation)
# ==============================================================================

func _draw_highlights() -> void:
	if highlights != null:
		highlights.draw_highlights(
			selected_pos,
			current_legal_moves,
			logic,
			func(cell: Vector2i): return cell_to_local_pos(cell),
			func(cell: Vector2i): return blood_manager.get_blood_level(cell) if blood_manager else 0
		)

func _clear_highlights() -> void:
	if highlights != null:
		highlights.clear_highlights()

func clear_highlights() -> void:
	_clear_highlights()

# ==============================================================================
# ФОНОВЫЕ ПОТОКИ И РАСЧЕТ ИИ (Threading & Pondering)
# ==============================================================================

## Остановка и очистка фонового потока расчета ИИ
func _cleanup_ai_thread() -> void:
	if _ai_thread != null and _ai_thread.is_started():
		_ai_thread.wait_to_finish()
	_ai_thread = null
	_is_ai_calculating = false
	_precomputed_ai_move.clear()

## Остановка и очистка фонового потока пре-расчета (Pondering)
func _cleanup_ponder_thread() -> void:
	_ponder_cancel_requested = true
	if _ponder_thread != null and _ponder_thread.is_started():
		_ponder_thread.wait_to_finish()
	_ponder_thread = null
	_is_pondering = false
	_ponder_cancel_requested = false

## Неблокирующий запрос на отмену пондеринга (без зависаний главного потока!)
func _request_cancel_pondering() -> void:
	_ponder_cancel_requested = true

## Запуск фонового пре-расчета ходов черных во время размышления игрока
func _start_pondering() -> void:
	if _is_pondering or (_ponder_thread != null and _ponder_thread.is_alive()):
		return
	if logic == null or logic.is_game_over or not logic.is_white_turn:
		return
		
	if _ponder_thread != null and not _ponder_thread.is_alive():
		_ponder_thread.wait_to_finish()
		_ponder_thread = null
		
	# Очищаем кэш пондеринга для новой позиции доски, исключая устаревшие ходы
	_ponder_cache.clear()
	_is_pondering = true
	_ponder_cancel_requested = false
	_pending_precompute_on_ponder_finish = false
	
	var grid_copy: Array = logic.clone_grid()
	var pt: int = logic.playthrough
	var ep_target: Vector2i = logic.en_passant_target
	var cancel_fn = func() -> bool:
		return _ponder_cancel_requested
		
	_ponder_thread = Thread.new()
	var err = _ponder_thread.start(func():
		return ChessBotScript.ponder_replies(grid_copy, pt, 64, ep_target, 60000, cancel_fn, _ponder_cache)
	)
	if err != OK:
		_is_pondering = false
		_ponder_thread = null

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
	var ep_target: Vector2i = logic.en_passant_target
	
	_ai_thread = Thread.new()
	var thread_func = func():
		return ChessBotScript.choose_best_move(grid_copy, pt, 0, ep_target)
		
	var err = _ai_thread.start(thread_func)
	if err != OK:
		# Резервный расчет на случай сбоя создания потока
		_is_ai_calculating = false
		_ai_thread = null
		_precomputed_ai_move = ChessBotScript.choose_best_move(grid_copy, pt, 0, ep_target)
		_check_execute_ai_turn()

## Проверка условий для фактического перемещения черной фигуры по доске
func _check_execute_ai_turn() -> void:
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
	
	# Обработка взятия (включая взятие на проходе)
	var is_capture: bool = move_res["captured"]
	var capture_pos: Vector2i = move_res["en_passant_captured_pos"] if move_res.get("en_passant", false) else to_pos
	var victim_node = piece_nodes.get(capture_pos) if is_capture else null
	if is_capture:
		piece_nodes.erase(capture_pos)
			
	# Перемещение 3D-ноды (ход игрока белыми — дуговой перенос)
	piece_nodes.erase(from_pos)
	piece_nodes[to_pos] = piece_node
	piece_node.board_pos = to_pos
	var target_world_pos: Vector3 = to_global(cell_to_local_pos(to_pos))
	
	# Сбрасываем флаги готовности и запускаем расчет ИИ не дожидаясь окончания анимации
	_white_animation_finished = false
	_ai_turn_delay_finished = false
	_is_white_moving = true
	
	# Проверяем кэш фонового пре-расчета (Pondering)
	var played_key: String = "%d_%d_%d_%d" % [from_pos.x, from_pos.y, to_pos.x, to_pos.y]
	_request_cancel_pondering()
	
	var has_valid_cache: bool = false
	if _ponder_cache.has(played_key) and not _ponder_cache[played_key].is_empty():
		var cached_move: Dictionary = _ponder_cache[played_key]
		if cached_move.has("from") and cached_move.has("to"):
			var c_from: Vector2i = cached_move["from"]
			var c_to: Vector2i = cached_move["to"]
			var p_node = piece_nodes.get(c_from)
			if p_node != null and not p_node.is_white:
				var legals = logic.get_legal_moves(c_from)
				if c_to in legals:
					_precomputed_ai_move = cached_move
					_is_ai_calculating = false
					is_ai_thinking = true
					has_valid_cache = true
					
	if not has_valid_cache:
		_precomputed_ai_move.clear()
		if not is_pawn_promotion and not move_res["is_checkmate"]:
			if _ponder_thread != null and _ponder_thread.is_alive():
				_pending_precompute_on_ponder_finish = true
				_is_ai_calculating = true
				is_ai_thinking = true
			else:
				_start_precomputing_ai_move()
	
	var on_move_finished = func():
		_is_white_moving = false
		if is_capture:
			_play_capture_sound(target_world_pos)
			if victim_node:
				victim_node.animate_capture(0.25)
			# Процедурное воксельное пятно крови на клетке гибели фигуры
			spawn_blood_stain(capture_pos)
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
		_pending_ai_move_during_trouble = ai_move
		is_ai_thinking = true
		get_tree().create_timer(2.6).timeout.connect(func():
			if _is_light_trouble_active or (bus and bus.get("is_lamp_trouble_active") == true):
				_is_light_trouble_active = false
				if bus:
					bus.set("is_lamp_trouble_active", false)
				_on_lamp_trouble_finished()
		, CONNECT_ONE_SHOT)
		return
		
	if ai_move.is_empty():
		ai_move = logic.get_best_ai_move()
	if ai_move.is_empty():
		ai_move = logic._fallback_ai_move()
	if ai_move.is_empty():
		is_ai_thinking = false
		return
		
	var from_pos: Vector2i = ai_move["from"]
	var to_pos: Vector2i = ai_move["to"]
	var piece_node = piece_nodes.get(from_pos)
	if not piece_node:
		push_warning("[ChessBot] piece_nodes не содержит фигуру на %s для хода ИИ! Запуск fallback..." % str(from_pos))
		var fallback_move = logic._fallback_ai_move()
		if not fallback_move.is_empty() and fallback_move != ai_move:
			_execute_ai_turn(fallback_move)
		else:
			is_ai_thinking = false
		return
		
	var move_res = logic.make_move(from_pos, to_pos)
	if not move_res["success"]:
		push_warning("[ChessBot] make_move вернул false для хода ИИ %s -> %s! Запуск fallback..." % [str(from_pos), str(to_pos)])
		var fallback_move = logic._fallback_ai_move()
		if not fallback_move.is_empty() and fallback_move != ai_move:
			_execute_ai_turn(fallback_move)
		else:
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
				
	# Обработка взятия белой фигуры (включая взятие на проходе)
	var is_ai_capture: bool = move_res["captured"]
	var ai_capture_pos: Vector2i = move_res["en_passant_captured_pos"] if move_res.get("en_passant", false) else to_pos
	var victim_node = piece_nodes.get(ai_capture_pos) if is_ai_capture else null
	if is_ai_capture:
		piece_nodes.erase(ai_capture_pos)
			
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
			spawn_blood_stain(ai_capture_pos)
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
		else:
			_start_pondering()
	)

# ==============================================================================
# ПРЕВРАЩЕНИЕ ПЕШКИ (Pawn Promotion Delegation)
# ==============================================================================

## Отображение модального диалога выбора фигуры для превращения пешки
func _show_promotion_dialog(cell: Vector2i, piece_node: ChessPiece3D) -> void:
	_promoting_pos = cell
	_promoting_node = piece_node
	if promotion_dialog != null:
		promotion_dialog.show_dialog(
			cell,
			piece_node,
			meshes,
			white_mat,
			func(c: Vector2i, node: Node3D, chosen_type: String):
				_on_promotion_selected(c, node as ChessPiece3D, chosen_type)
		)

## Обработка выбора фигуры для превращения
func _on_promotion_selected(cell: Vector2i, piece_node: ChessPiece3D, chosen_type: String) -> void:
	if promotion_dialog != null:
		promotion_dialog.close_dialog()
		
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
	_is_white_moving = false
	_ai_turn_delay_finished = false
	_start_precomputing_ai_move()
	_white_animation_finished = true
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
# ВОКСЕЛЬНЫЕ ПЯТНА КРОВИ (Blood Stains Delegation)
# ==============================================================================

## Создание процедурного воксельного пятна крови на клетке доски при взятии фигуры
func spawn_blood_stain(cell: Vector2i) -> Node3D:
	if blood_manager != null:
		var local_pos = cell_to_local_pos(cell)
		return blood_manager.spawn_blood_stain(cell, local_pos)
	return null

## Создание одной гигантской воксельной лужи крови от взрыва белого короля
## Занимает саму клетку короля и ВСЕ соседние клетки вокруг (зона 3x3)
func spawn_mega_blood_stain(cell: Vector2i) -> Node3D:
	if blood_container == null:
		blood_container = get_node_or_null("BloodStains")
		if blood_container == null:
			blood_container = Node3D.new()
			blood_container.name = "BloodStains"
			add_child(blood_container)
			
	# Помечаем в словаре blood_layers все 9 клеток (3x3), чтобы маркеры ходов/выбора учитывали слой
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var target_c = Vector2i(cell.x + dx, cell.y + dy)
			if target_c.x >= 0 and target_c.x < 8 and target_c.y >= 0 and target_c.y < 8:
				var l_idx: int = blood_layers.get(target_c, 0)
				blood_layers[target_c] = l_idx + 1
				
	var stain = VoxelBloodStainScript.new()
	var local_cell_pos: Vector3 = cell_to_local_pos(cell)
	blood_container.add_child(stain)
	stain.create_mega_stain(local_cell_pos, 0, true)
	return stain

## Очистка всех воксельных пятен крови (при сбросе доски / новой партии)
func clear_blood_stains() -> void:
	if blood_manager != null:
		blood_manager.clear_blood_stains()
	else:
		blood_layers.clear()

# ==============================================================================
# АУДИО (Audio Delegation)
# ==============================================================================

func _play_player_move_sound(world_pos: Vector3) -> void:
	if audio_controller != null:
		audio_controller.play_player_move(world_pos)

func _play_player_turn_sound(world_pos: Vector3) -> void:
	_play_player_move_sound(world_pos)

func _play_capture_sound(world_pos: Vector3) -> void:
	if audio_controller != null:
		audio_controller.play_capture(world_pos)

func _play_deselect_sound(world_pos: Vector3) -> void:
	if audio_controller != null:
		audio_controller.play_deselect(world_pos)

func _play_enemy_move_sound(start_pos: Vector3, end_pos: Vector3, duration: float) -> void:
	if audio_controller != null:
		audio_controller.play_enemy_move(start_pos, end_pos, duration)

func _stop_enemy_move_sound() -> void:
	if audio_controller != null:
		audio_controller.stop_enemy_move()

# ==============================================================================
# ПЕРЕБОИ СО СВЕТОМ И СЕЙСМИКА (EventBus Handlers)
# ==============================================================================

## Синхронизация подсветки доски с перебоем света подвесной лампы
func _on_lamp_flicker_triggered(sound_idx: int, _duration: float) -> void:
	_is_light_trouble_active = true
	clear_selection()
	if light_controller != null:
		light_controller.play_flicker(sound_idx, self)

## Окончание перебоя со светом: восстановление подсветки и возобновление хода ИИ
func _on_lamp_trouble_finished() -> void:
	_is_light_trouble_active = false
	if light_controller != null:
		light_controller.reset_light()
	if is_ai_thinking and not logic.is_game_over and not logic.is_white_turn:
		var move_to_resume: Dictionary = _pending_ai_move_during_trouble
		_pending_ai_move_during_trouble = {}
		var resume_timer = get_tree().create_timer(0.35)
		resume_timer.timeout.connect(func():
			_execute_ai_turn(move_to_resume)
		)

## Подпрыгивание фигур на доске при подземном толчке (Слон, Ладья, Ферзь противника)
func _on_seismic_shock_triggered(intensity: float, _is_subterranean: bool) -> void:
	if intensity < 0.35:
		return
	var jump_height: float = clampf(intensity * 0.045, 0.015, 0.05)
	for cell in piece_nodes.keys():
		var piece = piece_nodes[cell]
		if piece is ChessPiece3D and is_instance_valid(piece):
			var base: float = piece.base_y
			var t = piece.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			t.tween_property(piece, "position:y", base + jump_height, 0.07)
			t.set_ease(Tween.EASE_IN).tween_property(piece, "position:y", base, 0.11)
