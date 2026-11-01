class_name ChessPromotionDialog
extends RefCounted

## Модальный диалог выбора фигуры при превращении пешки
## Отображает атмосферное окно с карточками и вращающимися 3D-моделями фигур (Ферзь, Ладья, Слон, Конь).

var parent_node: Node3D = null
var dialog_canvas: CanvasLayer = null
var promoting_cell: Vector2i = Vector2i(-1, -1)
var promoting_node: Node3D = null
var on_piece_selected: Callable = Callable()

func setup(parent: Node3D) -> void:
	parent_node = parent

func is_open() -> bool:
	return dialog_canvas != null and is_instance_valid(dialog_canvas)

func close_dialog() -> void:
	if dialog_canvas != null and is_instance_valid(dialog_canvas):
		dialog_canvas.queue_free()
		dialog_canvas = null
	if promoting_node != null and is_instance_valid(promoting_node):
		if promoting_node.has_method("set_selected"):
			promoting_node.set_selected(false)
	promoting_cell = Vector2i(-1, -1)
	promoting_node = null
	on_piece_selected = Callable()

## Отображение модального диалога выбора фигуры
func show_dialog(cell: Vector2i,
		piece_node: Node3D,
		meshes: Dictionary,
		white_mat: Material,
		callback: Callable) -> void:
	close_dialog()
	
	promoting_cell = cell
	promoting_node = piece_node
	on_piece_selected = callback
	
	if parent_node == null or not parent_node.is_inside_tree():
		return
		
	var canvas = CanvasLayer.new()
	canvas.name = "PromotionCanvas"
	canvas.layer = 15
	parent_node.add_child(canvas)
	dialog_canvas = canvas
	
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
		card_btn.pressed.connect(func(): _choose(chosen))
		hbox.add_child(card_btn)

func _choose(chosen_type: String) -> void:
	var c_cell = promoting_cell
	var c_node = promoting_node
	var cb = on_piece_selected
	close_dialog()
	if cb.is_valid():
		cb.call(c_cell, c_node, chosen_type)

## Обработка клавиатурного ввода (1/Q, 2/R, 3/B, 4/N/K)
func handle_input(event: InputEvent) -> bool:
	if not is_open():
		return false
	if event is InputEventKey and event.pressed and not event.echo:
		var code: Key = event.keycode if event.keycode != KEY_NONE else event.physical_keycode
		match code:
			KEY_1, KEY_Q:
				_choose("queen")
				return true
			KEY_2, KEY_R:
				_choose("rook")
				return true
			KEY_3, KEY_B:
				_choose("bishop")
				return true
			KEY_4, KEY_N, KEY_K:
				_choose("knight")
				return true
	return false

