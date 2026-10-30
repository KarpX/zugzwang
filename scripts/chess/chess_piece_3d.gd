class_name ChessPiece3D
extends Node3D

## Визуальное 3D-представление шахматной фигуры
## Отвечает за анимацию перемещения Tween, взятия и выделения.

@export var piece_type: String = "pawn"
@export var is_white: bool = true
@export var board_pos: Vector2i = Vector2i.ZERO

var mesh_instance: MeshInstance3D = null
var _move_tween: Tween = null
var _base_y: float = 0.0
var _is_selected: bool = false

func _ready() -> void:
	_base_y = position.y

## Инициализация фигуры
func setup(type: String, white: bool, pos: Vector2i, piece_mesh: Mesh, piece_mat: Material) -> void:
	piece_type = type
	is_white = white
	board_pos = pos
	
	if mesh_instance == null:
		mesh_instance = MeshInstance3D.new()
		add_child(mesh_instance)
		
	mesh_instance.mesh = piece_mesh
	mesh_instance.material_override = piece_mat

## Плавное перемещение фигуры по доске со скольжением
func animate_to(target_world_pos: Vector3, duration: float = 0.35) -> void:
	if _move_tween and _move_tween.is_valid():
		_move_tween.kill()
		
	_move_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Небольшое приподнимание в середине движения для реализма
	var mid_pos: Vector3 = (global_position + target_world_pos) * 0.5
	mid_pos.y += 0.08
	
	_move_tween.tween_property(self, "global_position", mid_pos, duration * 0.4)
	_move_tween.tween_property(self, "global_position", target_world_pos, duration * 0.6)

## Анимация взятия фигуры (падение и растворение/уменьшение)
func animate_capture(duration: float = 0.4) -> void:
	if _move_tween and _move_tween.is_valid():
		_move_tween.kill()
		
	_move_tween = create_tween().set_parallel(true)
	_move_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	
	# Падение на бок и сжатие
	_move_tween.tween_property(self, "rotation_degrees:z", 85.0 if is_white else -85.0, duration)
	_move_tween.tween_property(self, "scale", Vector3(0.01, 0.01, 0.01), duration)
	_move_tween.tween_property(self, "position:y", position.y - 0.2, duration)
	
	_move_tween.chain().tween_callback(queue_free)

## Визуальное выделение фигуры при клике игрока
func set_selected(selected: bool) -> void:
	if _is_selected == selected:
		return
	_is_selected = selected
	
	var hover_tween: Tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var target_y: float = _base_y + (0.18 if _is_selected else 0.0)
	hover_tween.tween_property(self, "position:y", target_y, 0.15)
