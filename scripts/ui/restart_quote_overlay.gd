class_name RestartQuoteOverlay
extends CanvasLayer

## Атмосферный экран с загадочной цитатой при пробуждении после поражения/пата.
## Плавно проявляется по центру экрана, побуждая игрока продолжить партию.

@onready var container: Control = null
@onready var quote_label: Label = null
@onready var bg_rect: ColorRect = null

func _ready() -> void:
	layer = 25 # Поверх стандартных интерфейсов
	var bus: Node = get_node_or_null("/root/EventBus") if is_inside_tree() else null
	if bus == null or not ("restart_quote" in bus) or bus.restart_quote.is_empty():
		return
		
	var quote_text: String = bus.restart_quote
	bus.restart_quote = "" # Очищаем после извлечения
	display_quote(quote_text)

## Отображение загадочной цитаты с анимацией появления и затухания
func display_quote(text: String) -> void:
	_create_ui(text)
	_play_fade_sequence()

func _create_ui(text: String) -> void:
	container = Control.new()
	container.name = "QuoteContainer"
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.modulate = Color(1.0, 1.0, 1.0, 0.0) # Начальная невидимость
	add_child(container)
	
	# Полупрозрачная подложка
	bg_rect = ColorRect.new()
	bg_rect.name = "Background"
	bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_rect.color = Color(0.0, 0.0, 0.0, 0.7)
	bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(bg_rect)
	
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(center)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_right", 60)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 24)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(vbox)
	
	quote_label = Label.new()
	quote_label.name = "QuoteLabel"
	quote_label.text = text
	quote_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quote_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	quote_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quote_label.custom_minimum_size = Vector2(700, 0)
	quote_label.add_theme_font_size_override("font_size", 22)
	quote_label.add_theme_color_override("font_color", Color(0.92, 0.88, 0.80, 0.95))
	quote_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	quote_label.add_theme_constant_override("shadow_offset_x", 1)
	quote_label.add_theme_constant_override("shadow_offset_y", 2)
	quote_label.add_theme_constant_override("shadow_outline_size", 4)
	vbox.add_child(quote_label)

func _play_fade_sequence() -> void:
	var tween: Tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# 1. Плавное проявление (1.4с)
	tween.tween_property(container, "modulate:a", 1.0, 1.4)
	# 2. Пауза для чтения (3.8с)
	tween.tween_interval(3.8)
	# 3. Плавное растворение в бункер (1.8с)
	tween.tween_property(container, "modulate:a", 0.0, 1.8)
	tween.tween_callback(queue_free)
