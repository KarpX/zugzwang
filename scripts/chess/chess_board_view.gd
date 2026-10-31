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
	
	logic = ChessLogicScript.new()
	spawn_pieces()
	
	# Подписываемся на события шины
	var bus = _get_event_bus()
	if bus and bus.has_signal("camera_mode_changed"):
		bus.camera_mode_changed.connect(_on_camera_mode_changed)

func _init_materials() -> void:
	# Белые: мраморный кремово-белый
	white_mat = StandardMaterial3D.new()
	white_mat.albedo_color = Color(0.88, 0.86, 0.82)
	white_mat.roughness = 0.35
	white_mat.metallic = 0.05
	
	# Черные: обсидиановый темный графит
	black_mat = StandardMaterial3D.new()
	black_mat.albedo_color = Color(0.12, 0.12, 0.14)
	black_mat.roughness = 0.25
	black_mat.metallic = 0.3
	
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
	# Пешка
	var pawn_box = BoxMesh.new()
	pawn_box.size = Vector3(0.36, 0.44, 0.34)
	meshes["pawn"] = pawn_box
	
	# Ладья
	var rook_box = BoxMesh.new()
	rook_box.size = Vector3(0.38, 0.85, 0.38)
	meshes["rook"] = rook_box
	
	# Конь
	var knight_cyl = CylinderMesh.new()
	knight_cyl.top_radius = 0.14
	knight_cyl.bottom_radius = 0.16
	knight_cyl.height = 0.65
	meshes["knight"] = knight_cyl
	
	# Слон
	var bishop_cap = CapsuleMesh.new()
	bishop_cap.radius = 0.16
	bishop_cap.height = 0.95
	meshes["bishop"] = bishop_cap
	
	# Ферзь
	var queen_sph = SphereMesh.new()
	queen_sph.radius = 0.24
	queen_sph.height = 0.48
	meshes["queen"] = queen_sph
	
	# Король
	var king_prism = PrismMesh.new()
	king_prism.size = Vector3(0.42, 0.95, 0.42)
	meshes["king"] = king_prism

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

## Спавн всех 32 фигур в соответствии с логикой
func spawn_pieces() -> void:
	if pieces_container == null:
		pieces_container = get_node_or_null("Pieces")
	if pieces_container == null:
		return
	# Очистка старых фигур
	for child in pieces_container.get_children():
		child.queue_free()
	piece_nodes.clear()
	
	for x in range(8):
		for y in range(8):
			var pos: Vector2i = Vector2i(x, y)
			var piece_data = logic.get_piece(pos)
			if piece_data != null:
				_spawn_piece_at(pos, piece_data["type"], piece_data["is_white"])

func _spawn_piece_at(pos: Vector2i, p_type: String, is_white: bool) -> ChessPiece3D:
	var piece_node = ChessPiece3DScript.new()
	var mesh: Mesh = meshes.get(p_type, meshes["pawn"])
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
		clear_selection()

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
		clear_selection()
		return
		
	_on_cell_clicked(cell)

func _on_cell_clicked(cell: Vector2i) -> void:
	var piece_data = logic.get_piece(cell)
	
	# Если кликнули на свою фигуру (Белые)
	if piece_data != null and piece_data["is_white"] and logic.is_white_turn:
		_select_cell(cell)
		return
		
	# Если клетка выбрана и кликнули на допустимый ход
	if selected_pos != Vector2i(-1, -1) and (cell in current_legal_moves):
		_execute_player_move(selected_pos, cell)
	else:
		clear_selection()

func _select_cell(cell: Vector2i) -> void:
	clear_selection()
	selected_pos = cell
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
	if move_res["captured"]:
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
	piece_node.animate_to(to_global(cell_to_local_pos(to_pos)), white_move_duration, false)
	
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
	piece_node.animate_to(to_global(cell_to_local_pos(to_pos)), black_move_duration, true)
	
	if bus:
		bus.piece_moved.emit(from_pos, to_pos)
		
	# Разрешаем ход игроку только после того, как черная фигура закончит медленное скольжение
	var finish_timer = get_tree().create_timer(black_move_duration)
	finish_timer.timeout.connect(func():
		is_ai_thinking = false
		if move_res["is_checkmate"]:
			if bus:
				bus.game_over.emit(logic.winner)
	)
