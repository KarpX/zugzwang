class_name ChessPiece3D
extends Node3D

## Визуальное 3D-представление шахматной фигуры
## Отвечает за анимацию перемещения Tween, взятия и выделения.

@export var piece_type: String = "pawn"
@export var is_white: bool = true
@export var board_pos: Vector2i = Vector2i.ZERO

## Высота основания фигуры на доске (плоскость стола)
@export var base_y: float = 0.405
## Высота приподнимания фигуры при клике игрока
@export var hover_height: float = 0.22

var mesh_instance: MeshInstance3D = null
var _move_tween: Tween = null
var _hover_tween: Tween = null
var _is_selected: bool = false

func _ready() -> void:
	scale = Vector3(0.8, 0.8, 0.8)
	if position.y != 0.0:
		base_y = position.y
	if mesh_instance == null:
		mesh_instance = get_node_or_null("MeshInstance3D")

## Инициализация фигуры и выравнивание основания меша по нулевой плоскости
func setup(type: String, white: bool, pos: Vector2i, piece_mesh: Mesh, piece_mat: Material, surface_height: float = 0.405) -> void:
	scale = Vector3(0.8, 0.8, 0.8)
	piece_type = type
	is_white = white
	board_pos = pos
	base_y = surface_height
	
	if mesh_instance == null:
		mesh_instance = MeshInstance3D.new()
		add_child(mesh_instance)
		
	mesh_instance.mesh = piece_mesh
	mesh_instance.material_override = piece_mat
	
	# Смещаем меш вверх, чтобы основание фигуры (низ) совпадало с локальным Y = 0
	if piece_mesh:
		var aabb: AABB = piece_mesh.get_aabb()
		mesh_instance.position.y = -aabb.position.y
		
	# Поворот фигуры (Конь смотрит на оппонента: белые на -Z (180°), черные на +Z (0°))
	if type == "knight":
		mesh_instance.rotation_degrees.y = 180.0 if is_white else 0.0

## Плавное перемещение фигуры по доске
## is_glide: если true, фигура не приподнимается, а монотонно "плывет" по доске (эффект скрежета черных)
func animate_to(target_world_pos: Vector3, duration: float = 0.35, is_glide: bool = false) -> void:
	if _move_tween and _move_tween.is_valid():
		_move_tween.kill()
	if _hover_tween and _hover_tween.is_valid():
		_hover_tween.kill()
		
	_is_selected = false
	
	if is_glide:
		# Зловещее скольжение черных фигур строго по поверхности стола
		_move_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_move_tween.tween_property(self, "global_position", target_world_pos, duration)
	else:
		# Обычный ход человека (белые): дугообразный перенос фигуры
		_move_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		var mid_pos: Vector3 = (global_position + target_world_pos) * 0.5
		mid_pos.y += 0.12
		_move_tween.tween_property(self, "global_position", mid_pos, duration * 0.45)
		_move_tween.tween_property(self, "global_position", target_world_pos, duration * 0.55)

## Анимация взятия фигуры (падение и растворение/уменьшение)
func animate_capture(duration: float = 0.4) -> void:
	if _move_tween and _move_tween.is_valid():
		_move_tween.kill()
	if _hover_tween and _hover_tween.is_valid():
		_hover_tween.kill()
		
	_move_tween = create_tween().set_parallel(true)
	_move_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	
	# Падение на бок и сжатие
	_move_tween.tween_property(self, "rotation_degrees:z", 85.0 if is_white else -85.0, duration)
	_move_tween.tween_property(self, "scale", Vector3(0.01, 0.01, 0.01), duration)
	_move_tween.tween_property(self, "position:y", position.y - 0.2, duration)
	
	_move_tween.chain().tween_callback(queue_free)

## Визуальное выделение фигуры при клике игрока:
## Поднимается над доской при выборе и плавно опускается обратно на стол при снятии выбора
func set_selected(selected: bool) -> void:
	if _is_selected == selected:
		return
	_is_selected = selected
	
	if _hover_tween and _hover_tween.is_valid():
		_hover_tween.kill()
		
	_hover_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var target_y: float = base_y + (hover_height if _is_selected else 0.0)
	_hover_tween.tween_property(self, "position:y", target_y, 0.18)
