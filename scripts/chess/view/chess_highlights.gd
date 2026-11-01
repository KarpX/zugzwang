class_name ChessHighlights
extends RefCounted

## Менеджер визуальной подсветки клеток шахматной доски
## Отвечает за неоновые маркеры выбранной фигуры, доступных ходов и вражеских фигур под боем.

var parent_node: Node3D = null
var highlights_container: Node3D = null

var move_highlight_mat: StandardMaterial3D
var attack_highlight_mat: StandardMaterial3D
var select_highlight_mat: StandardMaterial3D

func setup(parent: Node3D, container: Node3D = null) -> void:
	parent_node = parent
	highlights_container = container
	_init_materials()
	_ensure_container()

func _ensure_container() -> void:
	if highlights_container == null and parent_node != null:
		highlights_container = parent_node.get_node_or_null("Highlights")
		if highlights_container == null:
			highlights_container = Node3D.new()
			highlights_container.name = "Highlights"
			parent_node.add_child(highlights_container)

func _init_materials() -> void:
	if move_highlight_mat != null:
		return
		
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

## Отрисовка маркеров под выбранной клеткой и клетками возможных ходов
func draw_highlights(selected_pos: Vector2i,
		legal_moves: Array[Vector2i],
		logic: RefCounted,
		cell_to_local_pos_fn: Callable,
		get_blood_level_fn: Callable) -> void:
	clear_highlights()
	if selected_pos == Vector2i(-1, -1):
		return
		
	# Маркер под выбранной фигурой
	var sel_pos_3d: Vector3 = cell_to_local_pos_fn.call(selected_pos)
	var sel_blood: int = get_blood_level_fn.call(selected_pos)
	create_highlight_tile(sel_pos_3d, select_highlight_mat, 0.44, sel_blood)
	
	# Маркеры возможных ходов
	var selected_piece = logic.get_piece(selected_pos) if logic else null
	var is_selected_pawn: bool = (selected_piece != null and selected_piece.get("type", "") == "pawn")
	var ep_target: Vector2i = logic.en_passant_target if logic else Vector2i(-1, -1)
	
	for move_cell in legal_moves:
		var target_piece = logic.get_piece(move_cell) if logic else null
		var is_ep_target: bool = is_selected_pawn and ep_target == move_cell and ep_target != Vector2i(-1, -1)
		var cell_pos_3d: Vector3 = cell_to_local_pos_fn.call(move_cell)
		var blood_lvl: int = get_blood_level_fn.call(move_cell)
		
		if target_piece != null or is_ep_target:
			# Клетка с врагом или взятие на проходе — красный маркер
			create_highlight_tile(cell_pos_3d, attack_highlight_mat, 0.42, blood_lvl)
		else:
			# Свободная клетка — мягкий зеленый маркер
			create_highlight_tile(cell_pos_3d, move_highlight_mat, 0.28, blood_lvl)

## Создание отдельного маркерного полигона над клеткой
func create_highlight_tile(pos: Vector3, mat: Material, size: float, blood_lvl: int) -> void:
	_ensure_container()
	if highlights_container == null:
		return
		
	var tile = MeshInstance3D.new()
	var quad = BoxMesh.new()
	
	# Одинаковая толщина и размер маркера как на обычных клетках, так и на клетках с кровью
	var h: float = 0.006
	var y_offset: float = 0.004
	if blood_lvl > 0:
		# На луже крови только поднимаем маркер на поверхность лужи
		y_offset = 0.052 + float(blood_lvl - 1) * 0.006
		
	quad.size = Vector3(size, h, size)
	tile.mesh = quad
	tile.material_override = mat
	tile.position = Vector3(pos.x, pos.y + y_offset, pos.z)
	highlights_container.add_child(tile)

## Очистка всех маркеров подсветки
func clear_highlights() -> void:
	_ensure_container()
	if highlights_container == null:
		return
	for child in highlights_container.get_children():
		child.queue_free()

