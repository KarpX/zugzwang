class_name VoxelBloodStain
extends Node3D

## Процедурно генерируемое воксельное пятно крови (крупная сплошная 3D-лужа на 85% клетки)
## Спавнится при взятии фигур на клетке поля боя с анимацией взрывного всплеска и разлета капель.

const VOXEL_STEP: float = 0.034 # Размер вокселя (~3.4 см)
const MAX_RADIUS: float = 0.255 # Радиус лужи (~85% ширины клетки 0.57м)

var multimesh_instance: MultiMeshInstance3D = null
static var blood_material: StandardMaterial3D = null

static func get_blood_material() -> StandardMaterial3D:
	if blood_material == null:
		blood_material = StandardMaterial3D.new()
		# Яркий, глубокий цвет свежей крови (насыщенный багрово-алый, не блеклый)
		blood_material.albedo_color = Color(0.72, 0.03, 0.05)
		blood_material.vertex_color_use_as_albedo = true
		blood_material.roughness = 0.08
		blood_material.metallic = 0.0
		blood_material.clearcoat_enabled = true
		blood_material.clearcoat = 1.0
		blood_material.clearcoat_roughness = 0.04
	return blood_material

## Создание крупной сплошной воксельной лужи крови (~85% клетки доски)
func create_stain(target_local_pos: Vector3, layer_index: int = 0, animate: bool = true) -> void:
	position = target_local_pos
	
	# Сетка занятых вокселей: Vector2i -> высота в вокселях (1, 2, 3)
	var occupied_voxels: Dictionary = {}
	
	# 1. СПЛОШНОЕ ЯДРО ЛУЖИ (плотное заполнение без дыр, диаметр ~35 см)
	var core_radius: float = 5.2
	for x in range(-7, 8):
		for z in range(-7, 8):
			var dist: float = sqrt(float(x * x + z * z))
			if dist <= core_radius:
				# Центр толще (3D-объем свернувшейся крови), края тоньше
				if dist <= 2.6:
					occupied_voxels[Vector2i(x, z)] = 3 # Высокий густой центр
				elif dist <= 4.2:
					occupied_voxels[Vector2i(x, z)] = 2 # Средний слой лужи
				else:
					occupied_voxels[Vector2i(x, z)] = 1 # Края лужи
					
	# 2. ОРГАНИЧНЫЕ ЛОПАСТИ РАСТЕКАНИЯ (4-5 рукавов, заполняющих до 85% клетки)
	var lobe_count: int = randi_range(4, 5)
	var base_rot: float = randf_range(0.0, TAU)
	for lobe_idx in range(lobe_count):
		var angle: float = base_rot + (float(lobe_idx) * (TAU / float(lobe_count))) + randf_range(-0.3, 0.3)
		var lobe_len: int = randi_range(5, 7)
		for step in range(4, lobe_len + 1):
			var gx: int = int(round(cos(angle) * float(step)))
			var gz: int = int(round(sin(angle) * float(step)))
			var key: Vector2i = Vector2i(gx, gz)
			if not occupied_voxels.has(key):
				occupied_voxels[key] = 1
			# Боковое утолщение рукавов для естественной формы лужи
			if step <= 6:
				var side_x: int = gx + (1 if randf() > 0.5 else -1)
				var side_key: Vector2i = Vector2i(side_x, gz)
				if not occupied_voxels.has(side_key):
					occupied_voxels[side_key] = 1
					
	# 3. ОТДЕЛЬНЫЕ КАПЛИ И БРЫЗГИ НА ПЕРИФЕРИИ КЛЕТКИ
	var splash_count: int = randi_range(8, 14)
	for s in range(splash_count):
		var splash_angle: float = randf_range(0.0, TAU)
		var splash_dist: float = randf_range(6.0, 7.6)
		var sx: int = int(round(cos(splash_angle) * splash_dist))
		var sz: int = int(round(sin(splash_angle) * splash_dist))
		occupied_voxels[Vector2i(sx, sz)] = 1
		
	var total_count: int = occupied_voxels.size()
	if total_count == 0:
		return
		
	multimesh_instance = MultiMeshInstance3D.new()
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	
	var box = BoxMesh.new()
	box.size = Vector3(VOXEL_STEP * 1.02, VOXEL_STEP * 0.45, VOXEL_STEP * 1.02)
	mm.mesh = box
	mm.instance_count = total_count
	
	multimesh_instance.multimesh = mm
	multimesh_instance.material_override = get_blood_material()
	add_child(multimesh_instance)
	
	var idx: int = 0
	var base_layer_y: float = float(layer_index) * 0.005 + 0.002
	
	for grid_key in occupied_voxels.keys():
		var gx: int = grid_key.x
		var gz: int = grid_key.y
		var height_level: int = occupied_voxels[grid_key]
		
		var lx: float = float(gx) * VOXEL_STEP
		var lz: float = float(gz) * VOXEL_STEP
		
		var voxel_h_scale: float = 1.0
		var voxel_y_offset: float = 0.0
		if height_level == 3:
			voxel_h_scale = 2.4
			voxel_y_offset = box.size.y * 0.7
		elif height_level == 2:
			voxel_h_scale = 1.6
			voxel_y_offset = box.size.y * 0.3
		else:
			voxel_h_scale = randf_range(0.85, 1.1)
			voxel_y_offset = 0.0
			
		var ly: float = base_layer_y + voxel_y_offset + (box.size.y * 0.5 * voxel_h_scale)
		
		var t: Transform3D = Transform3D()
		t.basis = Basis.from_scale(Vector3(1.02, voxel_h_scale, 1.02))
		t.origin = Vector3(lx, ly, lz)
		mm.set_instance_transform(idx, t)
		
		var dist_from_center: float = Vector2(lx, lz).length()
		var center_factor: float = clampf(dist_from_center / MAX_RADIUS, 0.0, 1.0)
		var r: float = lerpf(0.50, 0.82, center_factor) + randf_range(-0.02, 0.02)
		var g: float = lerpf(0.015, 0.045, center_factor)
		var b: float = lerpf(0.020, 0.050, center_factor)
		mm.set_instance_color(idx, Color(r, g, b, 1.0))
		
		idx += 1
		
	# 4. АНИМАЦИЯ: Взрывной всплеск лужи и разлетающиеся воксельные капли
	if animate:
		_animate_splash(target_local_pos)

## Эффектная анимация шлепка лужи крови и фонтана брызг
func _animate_splash(target_local_pos: Vector3) -> void:
	var final_y: float = target_local_pos.y
	position.y = final_y + 0.09
	scale = Vector3(0.08, 3.5, 0.08)
	
	var tw = create_tween().set_parallel(true)
	# Резкий шлепок вниз на поверхность доски
	tw.tween_property(self, "position:y", final_y, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Взрывное горизонтальное растекание во все стороны с упругим торможением
	tw.tween_property(self, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	# Дополнительные динамические летающие воксели-брызги, взмывающие вверх при ударе
	_spawn_flying_droplets()

## Генерация физичных летающих вокселей-брызг при ударе
func _spawn_flying_droplets() -> void:
	var droplet_count: int = randi_range(8, 14)
	var droplet_mesh = BoxMesh.new()
	droplet_mesh.size = Vector3(0.024, 0.024, 0.024)
	
	for i in range(droplet_count):
		var drop = MeshInstance3D.new()
		drop.mesh = droplet_mesh
		drop.material_override = get_blood_material()
		add_child(drop)
		
		drop.position = Vector3(randf_range(-0.05, 0.05), 0.04, randf_range(-0.05, 0.05))
		
		var fly_angle: float = randf_range(0.0, TAU)
		var fly_speed: float = randf_range(0.14, 0.28)
		var target_x: float = cos(fly_angle) * fly_speed
		var target_z: float = sin(fly_angle) * fly_speed
		var peak_y: float = randf_range(0.14, 0.26)
		
		var d_tween = create_tween()
		d_tween.tween_property(drop, "position:y", peak_y, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		d_tween.tween_property(drop, "position:y", 0.005, 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		
		var side_tween = create_tween()
		side_tween.tween_property(drop, "position:x", target_x, 0.36).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		
		var side_z_tween = create_tween()
		side_z_tween.tween_property(drop, "position:z", target_z, 0.36).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
