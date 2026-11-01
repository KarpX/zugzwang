class_name ChessBloodManager
extends RefCounted

## Менеджер процедурных пятен крови на шахматной доске
## Отвечает за спавн, накопление слоев и очистку воксельных брызг крови при взятиях фигур.

const VoxelBloodStainScript = preload("res://scripts/chess/voxel_blood_stain.gd")

var parent_node: Node3D = null
var blood_container: Node3D = null
var blood_layers: Dictionary = {} # Vector2i -> int (количество взятий на клетке)

func setup(parent: Node3D, container: Node3D = null) -> void:
	parent_node = parent
	blood_container = container
	_ensure_container()

func _ensure_container() -> void:
	if blood_container == null and parent_node != null:
		blood_container = parent_node.get_node_or_null("BloodStains")
		if blood_container == null:
			blood_container = Node3D.new()
			blood_container.name = "BloodStains"
			parent_node.add_child(blood_container)
		if "blood_container" in parent_node:
			parent_node.set("blood_container", blood_container)

## Создание процедурного воксельного пятна крови на клетке доски при взятии фигуры
func spawn_blood_stain(cell: Vector2i, local_cell_pos: Vector3) -> Node3D:
	_ensure_container()
	if blood_container == null:
		return null
		
	var layer_idx: int = blood_layers.get(cell, 0)
	blood_layers[cell] = layer_idx + 1
	
	var stain = VoxelBloodStainScript.new()
	blood_container.add_child(stain)
	stain.create_stain(local_cell_pos, layer_idx, true)
	return stain

## Создание одной гигантской воксельной лужи крови от взрыва белого короля
func spawn_mega_blood_stain(cell: Vector2i, local_cell_pos: Vector3) -> Node3D:
	_ensure_container()
	if blood_container == null:
		return null
		
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var target_c = Vector2i(cell.x + dx, cell.y + dy)
			if target_c.x >= 0 and target_c.x < 8 and target_c.y >= 0 and target_c.y < 8:
				var l_idx: int = blood_layers.get(target_c, 0)
				blood_layers[target_c] = l_idx + 1
				
	var stain = VoxelBloodStainScript.new()
	blood_container.add_child(stain)
	stain.create_mega_stain(local_cell_pos, 0, true)
	return stain

## Получение текущего уровня накопления крови на клетке
func get_blood_level(cell: Vector2i) -> int:
	return blood_layers.get(cell, 0)

## Очистка всех воксельных пятен крови (при сбросе доски / новой партии)
func clear_blood_stains() -> void:
	blood_layers.clear()
	_ensure_container()
	if blood_container != null:
		for child in blood_container.get_children():
			child.queue_free()
