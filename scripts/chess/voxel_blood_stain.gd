class_name VoxelBloodStain
extends Node3D

## Процедурно генерируемое воксельное пятно крови (огромная сплошная 3D-лужа на 90-100% клетки со всплесками в швы)
## Спавнится при взятии фигур на клетке поля боя с анимацией взрывного всплеска и разлета капель.

const VOXEL_STEP: float = 0.038 # Размер вокселя (~3.8 см)
const MAX_RADIUS: float = 0.320 # Максимальный радиус растекания лужи (~0.64м, перекрывает всю клетку 0.57м)

var multimesh_instance: MultiMeshInstance3D = null
static var blood_material: StandardMaterial3D = null

static func get_blood_material() -> StandardMaterial3D:
	if blood_material == null:
		blood_material = StandardMaterial3D.new()
		# Высокая яркость альбедо с легким оттенком, чтобы vertex_color не темнел в грязь
		blood_material.albedo_color = Color(1.0, 0.88, 0.88)
		blood_material.vertex_color_use_as_albedo = true
		blood_material.roughness = 0.05
		blood_material.metallic = 0.0
		blood_material.clearcoat_enabled = true
		blood_material.clearcoat = 1.0
		blood_material.clearcoat_roughness = 0.03
		# Зловещий багровый отблеск плоти, чтобы кровь не превращалась в черную грязь в глубоких тенях бункера
		blood_material.emission_enabled = true
		blood_material.emission = Color(0.14, 0.01, 0.01)
	return blood_material

## Создание огромной сплошной воксельной лужи крови (закрывает всю клетку доски и затекает в швы)
func create_stain(target_local_pos: Vector3, layer_index: int = 0, animate: bool = true) -> void:
	position = target_local_pos
	
	# Сетка занятых вокселей: Vector2i -> высота в вокселях (1, 2, 3, 4)
	var occupied_voxels: Dictionary = {}
	
	# 1. МАССИВНОЕ СПЛОШНОЕ ЯДРО ЛУЖИ (плотное заполнение без дыр, радиус ~26 см -> диаметр ~52 см)
	var core_radius: float = 6.8
	for x in range(-9, 10):
		for z in range(-9, 10):
			var dist: float = sqrt(float(x * x + z * z))
			if dist <= core_radius:
				# Центр толще (3D-объем свернувшейся крови), края тоньше
				if dist <= 2.2:
					occupied_voxels[Vector2i(x, z)] = 4 # Самый густой центр
				elif dist <= 4.0:
					occupied_voxels[Vector2i(x, z)] = 3 # Толстый слой лужи
				elif dist <= 5.6:
					occupied_voxels[Vector2i(x, z)] = 2 # Средний слой
				else:
					occupied_voxels[Vector2i(x, z)] = 1 # Края лужи
					
	# 2. ОРГАНИЧНЫЕ ЛОПАСТИ РАСТЕКАНИЯ (5-6 рукавов, выходящих за границы клетки в стыки)
	var lobe_count: int = randi_range(5, 6)
	var base_rot: float = randf_range(0.0, TAU)
	for lobe_idx in range(lobe_count):
		var angle: float = base_rot + (float(lobe_idx) * (TAU / float(lobe_count))) + randf_range(-0.35, 0.35)
		var lobe_len: int = randi_range(7, 9)
		for step in range(5, lobe_len + 1):
			var gx: int = int(round(cos(angle) * float(step)))
			var gz: int = int(round(sin(angle) * float(step)))
			var key: Vector2i = Vector2i(gx, gz)
			if not occupied_voxels.has(key):
				occupied_voxels[key] = 1
			# Боковое утолщение рукавов для естественной формы растекания
			if step <= 7:
				var side_x: int = gx + (1 if randf() > 0.5 else -1)
				var side_key: Vector2i = Vector2i(side_x, gz)
				if not occupied_voxels.has(side_key):
					occupied_voxels[side_key] = 1
					
	# 3. МНОЖЕСТВЕННЫЕ КАПЛИ И БРЫЗГИ НА ПЕРИФЕРИИ И В ШВАХ
	var splash_count: int = randi_range(14, 22)
	for s in range(splash_count):
		var splash_angle: float = randf_range(0.0, TAU)
		var splash_dist: float = randf_range(7.2, 9.5)
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
	box.size = Vector3(VOXEL_STEP * 1.03, VOXEL_STEP * 0.45, VOXEL_STEP * 1.03)
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
		if height_level == 4:
			voxel_h_scale = 3.0
			voxel_y_offset = box.size.y * 1.0
		elif height_level == 3:
			voxel_h_scale = 2.2
			voxel_y_offset = box.size.y * 0.6
		elif height_level == 2:
			voxel_h_scale = 1.5
			voxel_y_offset = box.size.y * 0.25
		else:
			voxel_h_scale = randf_range(0.85, 1.15)
			voxel_y_offset = 0.0
			
		var ly: float = base_layer_y + voxel_y_offset + (box.size.y * 0.5 * voxel_h_scale)
		
		var t: Transform3D = Transform3D()
		t.basis = Basis.from_scale(Vector3(1.02, voxel_h_scale, 1.02))
		t.origin = Vector3(lx, ly, lz)
		mm.set_instance_transform(idx, t)
		
		var dist_from_center: float = Vector2(lx, lz).length()
		var center_factor: float = clampf(dist_from_center / MAX_RADIUS, 0.0, 1.0)
		# Центр — густая запекшаяся багровая кровь, края и брызги — яркая алая свежая кровь
		var r: float = lerpf(0.55, 0.92, center_factor) + randf_range(-0.02, 0.02)
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
	position.y = final_y + 0.12
	scale = Vector3(0.08, 4.0, 0.08)
	
	var tw = create_tween().set_parallel(true)
	# Резкий шлепок вниз на поверхность доски
	tw.tween_property(self, "position:y", final_y, 0.26).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Взрывное горизонтальное растекание во все стороны с упругим торможением
	tw.tween_property(self, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	# Дополнительные динамические летающие воксели-брызги, взмывающие вверх при ударе
	_spawn_flying_droplets()

## Генерация физичных летающих вокселей-брызг при ударе
func _spawn_flying_droplets() -> void:
	var droplet_count: int = randi_range(14, 22)
	var droplet_mesh = BoxMesh.new()
	droplet_mesh.size = Vector3(0.026, 0.026, 0.026)
	
	for i in range(droplet_count):
		var drop = MeshInstance3D.new()
		drop.mesh = droplet_mesh
		drop.material_override = get_blood_material()
		add_child(drop)
		
		drop.position = Vector3(randf_range(-0.06, 0.06), 0.04, randf_range(-0.06, 0.06))
		
		var fly_angle: float = randf_range(0.0, TAU)
		var fly_speed: float = randf_range(0.18, 0.38)
		var target_x: float = cos(fly_angle) * fly_speed
		var target_z: float = sin(fly_angle) * fly_speed
		var peak_y: float = randf_range(0.18, 0.34)
		
		var d_tween = create_tween()
		d_tween.tween_property(drop, "position:y", peak_y, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		d_tween.tween_property(drop, "position:y", 0.005, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		
		var side_tween = create_tween()
		side_tween.tween_property(drop, "position:x", target_x, 0.38).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		
		var side_z_tween = create_tween()
		side_z_tween.tween_property(drop, "position:z", target_z, 0.38).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


