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
var kill_count: int = 0
var _blood_droplets_container: Node3D = null

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
## on_complete: вызывается по завершении анимации перемещения
func animate_to(target_world_pos: Vector3, duration: float = 0.35, is_glide: bool = false, on_complete: Callable = Callable()) -> void:
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
		
	if on_complete.is_valid():
		_move_tween.chain().tween_callback(on_complete)

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

## Замена типа фигуры (например, при превращении пешки) с обновлением 3D-меша
func change_type(new_type: String, new_mesh: Mesh, new_mat: Material) -> void:
	piece_type = new_type
	if mesh_instance == null:
		mesh_instance = get_node_or_null("MeshInstance3D")
		if mesh_instance == null:
			mesh_instance = MeshInstance3D.new()
			add_child(mesh_instance)
			
	mesh_instance.mesh = new_mesh
	mesh_instance.material_override = new_mat
	
	if new_mesh:
		var aabb: AABB = new_mesh.get_aabb()
		mesh_instance.position.y = -aabb.position.y
		
	if new_type == "knight":
		mesh_instance.rotation_degrees.y = 180.0 if is_white else 0.0
	else:
		mesh_instance.rotation_degrees.y = 0.0

## Окрашивание фигуры-убийцы кровью жертвы (материал + налипшие воксели)
func apply_blood_stain() -> void:
	kill_count += 1
	
	# 1. Покрытие материала кровавым налетом (дублируем, чтобы изменить только эту фигуру)
	if mesh_instance != null:
		var mat = mesh_instance.material_override
		if mat is StandardMaterial3D:
			var piece_mat: StandardMaterial3D = mat.duplicate() as StandardMaterial3D
			
			var blood_factor: float = clampf(float(kill_count) * 0.25, 0.0, 0.8)
			if is_white:
				# Белая фигура покрывается багровыми разводами
				piece_mat.albedo_color = Color(1.0, 1.0 - blood_factor * 0.7, 1.0 - blood_factor * 0.7)
			else:
				# Черная фигура приобретает хищный темно-кровавый блеск
				piece_mat.albedo_color = Color(1.0 + blood_factor * 0.6, 1.0 - blood_factor * 0.4, 1.0 - blood_factor * 0.4)
				
			piece_mat.roughness = clampf(piece_mat.roughness - 0.08 * float(kill_count), 0.12, 0.8)
			mesh_instance.material_override = piece_mat
			
	# 2. Налипшие влажные воксели крови на юбке и теле фигуры
	if _blood_droplets_container == null:
		_blood_droplets_container = Node3D.new()
		_blood_droplets_container.name = "BloodDroplets"
		add_child(_blood_droplets_container)
		
	var blood_mat: StandardMaterial3D = null
	if ResourceLoader.exists("res://scripts/chess/voxel_blood_stain.gd"):
		var VoxelScript = load("res://scripts/chess/voxel_blood_stain.gd")
		if VoxelScript.has_method("get_blood_material"):
			blood_mat = VoxelScript.get_blood_material()
			
	if blood_mat == null:
		blood_mat = StandardMaterial3D.new()
		blood_mat.albedo_color = Color(0.72, 0.03, 0.05)
		blood_mat.roughness = 0.08
		
	var new_drops_count: int = randi_range(4, 7)
	for i in range(new_drops_count):
		var drop = MeshInstance3D.new()
		var drop_box = BoxMesh.new()
		var drop_s: float = randf_range(0.018, 0.032)
		drop_box.size = Vector3(drop_s, drop_s, drop_s)
		drop.mesh = drop_box
		drop.material_override = blood_mat
		
		# Расположение на радиусе основания фигуры
		var angle: float = randf_range(0.0, TAU)
		var r: float = randf_range(0.08, 0.15)
		var h: float = randf_range(0.015, 0.12 + float(kill_count) * 0.04)
		
		drop.position = Vector3(cos(angle) * r, h, sin(angle) * r)
		drop.rotation = Vector3(randf_range(-0.3, 0.3), randf_range(0.0, TAU), randf_range(-0.3, 0.3))
		_blood_droplets_container.add_child(drop)
