class_name CCTVOverlay
extends CanvasLayer

## CCTV Surveillance Camera Overlay
## Воспроизводит интерфейс камеры видеонаблюдения со сканлайнами,
## таймкодом и пульсирующей записью REC.

@onready var root_control: Control = null
@onready var rec_dot: Label = null
@onready var timestamp_label: Label = null
var _time_passed: float = 0.0
var _is_active: bool = false

func _ready() -> void:
	layer = 20
	visible = false
	_build_ui()

func _build_ui() -> void:
	root_control = Control.new()
	root_control.name = "CCTVContainer"
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root_control)
	
	# Тонкая зеленовато-красная тонировка по краям
	var vignette = ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.color = Color(0.12, 0.02, 0.02, 0.25)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(vignette)
	
	# Верхний бар: REC и Название камеры
	var top_margin = MarginContainer.new()
	top_margin.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_margin.add_theme_constant_override("margin_left", 36)
	top_margin.add_theme_constant_override("margin_top", 28)
	top_margin.add_theme_constant_override("margin_right", 36)
	top_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(top_margin)
	
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	top_margin.add_child(hbox)
	
	rec_dot = Label.new()
	rec_dot.text = "● REC"
	rec_dot.add_theme_font_size_override("font_size", 18)
	rec_dot.add_theme_color_override("font_color", Color(1.0, 0.15, 0.15, 1.0))
	hbox.add_child(rec_dot)
	
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(24, 0)
	hbox.add_child(spacer)
	
	var cam_name = Label.new()
	cam_name.text = "CAM-01 [CORE BUNKER // AUTO-TRACKING]"
	cam_name.add_theme_font_size_override("font_size", 16)
	cam_name.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 0.85))
	hbox.add_child(cam_name)
	
	# Нижний бар: Таймкод и Статус
	var bottom_margin = MarginContainer.new()
	bottom_margin.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_margin.add_theme_constant_override("margin_left", 36)
	bottom_margin.add_theme_constant_override("margin_bottom", 28)
	bottom_margin.add_theme_constant_override("margin_right", 36)
	bottom_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(bottom_margin)
	
	var hbox_bottom = HBoxContainer.new()
	bottom_margin.add_child(hbox_bottom)
	
	timestamp_label = Label.new()
	timestamp_label.text = "00:00:00:00"
	timestamp_label.add_theme_font_size_override("font_size", 16)
	timestamp_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 0.8))
	hbox_bottom.add_child(timestamp_label)
	
	var spacer_b = Control.new()
	spacer_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox_bottom.add_child(spacer_b)
	
	var status_label = Label.new()
	status_label.text = "SIGNAL: LOSS IMMINENT"
	status_label.add_theme_font_size_override("font_size", 14)
	status_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3, 0.9))
	hbox_bottom.add_child(status_label)

func _process(delta: float) -> void:
	if not _is_active:
		return
	_time_passed += delta
	
	# Мигание точки REC каждые 0.6 сек
	if rec_dot:
		rec_dot.visible = fmod(_time_passed, 1.2) < 0.6
		
	# Обновление таймкода
	if timestamp_label:
		var mins = int(_time_passed / 60.0)
		var secs = int(fmod(_time_passed, 60.0))
		var ms = int(fmod(_time_passed * 100.0, 100.0))
		timestamp_label.text = "%02d:%02d:%02d" % [mins, secs, ms]

func show_overlay(duration: float = 4.0) -> void:
	_is_active = true
	visible = true
	_time_passed = 0.0
	root_control.modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(root_control, "modulate:a", 1.0, 0.35)
	
	if duration > 0.0:
		var hide_timer = get_tree().create_timer(duration)
		hide_timer.timeout.connect(hide_overlay)

func hide_overlay() -> void:
	var tween = create_tween()
	tween.tween_property(root_control, "modulate:a", 0.0, 0.5)
	tween.tween_callback(func():
		_is_active = false
		visible = false
	)
