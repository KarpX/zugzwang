class_name DefeatScreen
extends CanvasLayer

## DefeatScreen — Полноэкранный резкий чёрный экран с текстом поражения.
## Появляется моментально без затуханий сразу после окончания нагнетающего звука.
## Под прикрытием чёрного экрана комната, свет, фигуры и игрок полностью восстанавливаются.
## Затем экран плавно исчезает, возвращая игроку свободное управление.

signal restoration_requested()
signal screen_dismissed()

var _bg_rect: ColorRect = null
var _container: Control = null
var _title_label: Label = null
var _quote_label: Label = null
var _hint_label: Label = null

var _is_dismissing: bool = false
var _auto_dismiss_timer: SceneTreeTimer = null
var _on_restoration_callback: Callable = Callable()
var _on_completed_callback: Callable = Callable()

func _init() -> void:
	layer = 35 # Поверх всех игровых камер, HUD и эффектов

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()

## Построение элементов интерфейса
func _build_ui() -> void:
	if _container != null:
		return
		
	# Базовый контейнер на весь экран
	_container = Control.new()
	_container.name = "DefeatContainer"
	_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_container.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_container)
	
	# Непроницаемый чёрный фон
	_bg_rect = ColorRect.new()
	_bg_rect.name = "BlackBackground"
	_bg_rect.color = Color(0.0, 0.0, 0.0, 1.0)
	_bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_container.add_child(_bg_rect)
	
	# Центральный контейнер с текстом
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.add_child(center)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_right", 60)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 24)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(vbox)
	
	# Заголовок поражения
	_title_label = Label.new()
	_title_label.name = "TitleLabel"
	_title_label.text = "П О Р А Ж Е Н И Е"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 36)
	_title_label.add_theme_color_override("font_color", Color(0.86, 0.12, 0.12, 1.0))
	_title_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.95))
	_title_label.add_theme_constant_override("shadow_offset_y", 2)
	_title_label.add_theme_constant_override("shadow_outline_size", 4)
	vbox.add_child(_title_label)
	
	# Декоративный разделитель
	var divider_box = CenterContainer.new()
	divider_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(divider_box)
	
	var divider = ColorRect.new()
	divider.custom_minimum_size = Vector2(280, 2)
	divider.color = Color(0.48, 0.12, 0.12, 0.75)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	divider_box.add_child(divider)
	
	# Цитата о поражении / неизбежности войны
	_quote_label = Label.new()
	_quote_label.name = "QuoteLabel"
	_quote_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_quote_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_quote_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quote_label.custom_minimum_size = Vector2(760, 0)
	_quote_label.add_theme_font_size_override("font_size", 22)
	_quote_label.add_theme_color_override("font_color", Color(0.88, 0.85, 0.78, 0.95))
	_quote_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	_quote_label.add_theme_constant_override("shadow_offset_y", 1)
	_quote_label.add_theme_constant_override("shadow_outline_size", 3)
	vbox.add_child(_quote_label)
	
	# Ненавязчивая подсказка
	_hint_label = Label.new()
	_hint_label.name = "HintLabel"
	_hint_label.text = "Фигуры расставлены заново. Сделайте следующий ход."
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 14)
	_hint_label.add_theme_color_override("font_color", Color(0.55, 0.52, 0.48, 0.65))
	vbox.add_child(_hint_label)

## Отображение резкого чёрного экрана
## [param quote_text]: Текст поражения / цитата
## [param display_duration]: Время показа экрана перед автоматическим исчезновением
## [param on_restoration]: Колбэк для восстановления сцены под прикрытием чёрного экрана
## [param on_completed]: Колбэк по окончании исчезновения экрана (возврат управления игроку)
## [param title_text]: Заголовок экрана (по умолчанию "П О Р А Ж Е Н И Е")
## [param hint_text]: Нижняя подсказка игроку
func show_defeat(
	quote_text: String = "",
	display_duration: float = 3.5,
	on_restoration: Callable = Callable(),
	on_completed: Callable = Callable(),
	title_text: String = "П О Р А Ж Е Н И Е",
	hint_text: String = "Фигуры расставлены заново. Сделайте следующий ход."
) -> void:
	_on_restoration_callback = on_restoration
	_on_completed_callback = on_completed
	
	_build_ui()
	
	if not title_text.is_empty() and _title_label != null:
		_title_label.text = title_text
	if not quote_text.is_empty() and _quote_label != null:
		_quote_label.text = quote_text
	if not hint_text.is_empty() and _hint_label != null:
		_hint_label.text = hint_text
		
	# РЕЗКОЕ появление: прозрачность моментально 1.0 (никаких плавных затуханий перед появлением)
	if _container != null:
		_container.modulate = Color(1.0, 1.0, 1.0, 1.0)
	visible = true
	
	# Моментальный вызов восстановления сцены ПОД чёрным экраном
	if not _on_restoration_callback.is_null():
		_on_restoration_callback.call()
	restoration_requested.emit()
	
	# Таймер удержания экрана для прочтения текста
	if is_inside_tree() and display_duration > 0.0:
		_auto_dismiss_timer = get_tree().create_timer(display_duration)
		_auto_dismiss_timer.timeout.connect(_dismiss_screen)

## Разрешаем игроку пропустить экран нажатием пробела, Enter или кликом мыши
func _unhandled_input(event: InputEvent) -> void:
	if _is_dismissing:
		return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_select"):
		_dismiss_screen()
	elif event is InputEventMouseButton and event.pressed:
		_dismiss_screen()

## Плавное исчезновение экрана и завершение
func _dismiss_screen() -> void:
	if _is_dismissing:
		return
	_is_dismissing = true
	
	if _container != null and is_inside_tree():
		var tween: Tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(_container, "modulate:a", 0.0, 0.65)
		tween.tween_callback(func():
			if not _on_completed_callback.is_null():
				_on_completed_callback.call()
			screen_dismissed.emit()
			queue_free()
		)
	else:
		if not _on_completed_callback.is_null():
			_on_completed_callback.call()
		screen_dismissed.emit()
		queue_free()
