class_name IntroDisclaimerOverlay
extends CanvasLayer

## Атмосферный экран дисклеймера и оперативного брифинга перед началом игры.
## Отображается при каждом запуске:
## 1. Дисклеймер: "Все действия выдуманы и не связаны с реальностью. Любые совпадения случайны."
## 2. Описание дел: "Вы – генерал-майор подразделения N. Вам необходимо выиграть сражение."
## Поддерживает ручной пропуск по клику/клавишам и автопереход по таймеру.

signal intro_completed()

enum Stage {
	DISCLAIMER = 0,
	BRIEFING = 1,
	FINISHING = 2
}

const TYPE_SOUND: AudioStream = preload("res://assets/sounds/type_sound.ogg")

@export var auto_advance_delay: float = 10.0
@export var input_debounce_time: float = 0.5

var current_stage: Stage = Stage.DISCLAIMER
var _is_transitioning: bool = false
var _can_accept_input: bool = false
var _stage_token: int = 0

# UI ноды
var _backdrop: ColorRect = null
var _content_box: Control = null
var _category_label: Label = null
var _divider: ColorRect = null
var _body_label: Label = null
var _hint_label: Label = null
var _audio_player: AudioStreamPlayer = null
var _pulse_tween: Tween = null
var _fade_tween: Tween = null

func _init() -> void:
	layer = 40 # Поверх всех 3D-камер, HUD и остальных оверлеев

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_notify_bus_started()
	_setup_audio()
	_build_ui()
	_show_stage(Stage.DISCLAIMER)

func _notify_bus_started() -> void:
	var bus = _get_event_bus()
	if bus:
		bus.is_intro_active = true
		if bus.has_signal("intro_sequence_started"):
			bus.intro_sequence_started.emit()

func _notify_bus_finished() -> void:
	var bus = _get_event_bus()
	if bus:
		bus.is_intro_active = false
		if bus.has_signal("intro_sequence_finished"):
			bus.intro_sequence_finished.emit()

func _get_event_bus() -> Node:
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/EventBus")

func _setup_audio() -> void:
	_audio_player = AudioStreamPlayer.new()
	_audio_player.name = "IntroSfxPlayer"
	_audio_player.bus = &"Sound"
	_audio_player.volume_db = -2.0
	if TYPE_SOUND != null:
		_audio_player.stream = TYPE_SOUND
	add_child(_audio_player)

func _play_sfx() -> void:
	if _audio_player and _audio_player.stream != null:
		_audio_player.pitch_scale = randf_range(0.92, 1.08)
		_audio_player.play()

func _build_ui() -> void:
	# 1. Полноэкранный темный фон
	_backdrop = ColorRect.new()
	_backdrop.name = "Backdrop"
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.color = Color(0.03, 0.03, 0.04, 1.0)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_backdrop)

	# 2. Контейнер контента
	_content_box = Control.new()
	_content_box.name = "ContentBox"
	_content_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_content_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.add_child(_content_box)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_box.add_child(center)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 80)
	margin.add_theme_constant_override("margin_right", 80)
	margin.add_theme_constant_override("margin_top", 60)
	margin.add_theme_constant_override("margin_bottom", 60)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 22)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(vbox)

	# Заголовок раздела
	_category_label = Label.new()
	_category_label.name = "CategoryLabel"
	_category_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_category_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_category_label.add_theme_font_size_override("font_size", 20)
	_category_label.add_theme_constant_override("shadow_offset_y", 2)
	_category_label.add_theme_constant_override("shadow_outline_size", 3)
	vbox.add_child(_category_label)

	# Разделительная полоса
	var div_container = CenterContainer.new()
	div_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(div_container)

	_divider = ColorRect.new()
	_divider.name = "Divider"
	_divider.custom_minimum_size = Vector2(340, 2)
	_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	div_container.add_child(_divider)

	# Основной текст
	_body_label = Label.new()
	_body_label.name = "BodyLabel"
	_body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.custom_minimum_size = Vector2(780, 0)
	_body_label.add_theme_font_size_override("font_size", 25)
	_body_label.add_theme_color_override("font_color", Color(0.92, 0.90, 0.85, 0.98))
	_body_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.95))
	_body_label.add_theme_constant_override("shadow_offset_y", 2)
	_body_label.add_theme_constant_override("shadow_outline_size", 4)
	vbox.add_child(_body_label)

	# Отступ перед подсказкой
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 18)
	vbox.add_child(spacer)

	# Подсказка по переходу
	_hint_label = Label.new()
	_hint_label.name = "HintLabel"
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 15)
	_hint_label.add_theme_color_override("font_color", Color(0.68, 0.68, 0.68, 0.8))
	_hint_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	_hint_label.add_theme_constant_override("shadow_offset_y", 1)
	vbox.add_child(_hint_label)

func _show_stage(stage: Stage) -> void:
	current_stage = stage
	_can_accept_input = false
	_is_transitioning = true
	_stage_token += 1
	var token: int = _stage_token

	if _content_box:
		_content_box.modulate.a = 0.0

	match stage:
		Stage.DISCLAIMER:
			_category_label.text = "[ Д И С К Л Е Й М Е Р ]"
			_category_label.add_theme_color_override("font_color", Color(0.85, 0.38, 0.38, 1.0))
			_category_label.add_theme_color_override("font_shadow_color", Color(0.2, 0.05, 0.05, 0.9))
			_divider.color = Color(0.65, 0.22, 0.22, 0.75)
			_body_label.text = "Данная игра является художественным произведением. Все персонажи, организации и события вымышлены. Любые совпадения с реальными людьми (живыми или умершими), местами или событиями носят исключительно случайный характер."
			_hint_label.text = "[ Пробел / ЛКМ / Enter — продолжить ]"

		Stage.BRIEFING:
			_category_label.text = "[ О П И С А Н И Е   Д Е Л ]"
			_category_label.add_theme_color_override("font_color", Color(0.92, 0.82, 0.45, 1.0))
			_category_label.add_theme_color_override("font_shadow_color", Color(0.2, 0.15, 0.05, 0.9))
			_divider.color = Color(0.75, 0.62, 0.25, 0.75)
			_body_label.text = "Вы – генерал-майор подразделения N.\nВаша задача – одержать победу в сражении."
			_hint_label.text = "[ Пробел / ЛКМ / Enter — заступить на пост ]"

	_play_sfx()
	_animate_content_in(token)

func _animate_content_in(token: int) -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()

	_fade_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_fade_tween.tween_property(_content_box, "modulate:a", 1.0, 0.45)
	_fade_tween.tween_callback(func():
		_is_transitioning = false
		_start_pulse_animation()
	)

	# Защита от случайного нажатия при старте
	var tree: SceneTree = get_tree()
	if tree:
		tree.create_timer(input_debounce_time).timeout.connect(func():
			if token == _stage_token:
				_can_accept_input = true
		)
		
		# Автопереход при бездействии
		tree.create_timer(auto_advance_delay).timeout.connect(func():
			if token == _stage_token:
				_on_auto_advance_timeout()
		)

func _start_pulse_animation() -> void:
	if _pulse_tween and _pulse_tween.is_valid():
		_pulse_tween.kill()
	if _hint_label == null:
		return

	_pulse_tween = create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse_tween.tween_property(_hint_label, "modulate:a", 0.4, 1.1)
	_pulse_tween.tween_property(_hint_label, "modulate:a", 0.95, 1.1)

func _advance() -> void:
	if not _can_accept_input or _is_transitioning or current_stage == Stage.FINISHING:
		return

	_can_accept_input = false
	_is_transitioning = true

	if current_stage == Stage.DISCLAIMER:
		_transition_to_stage(Stage.BRIEFING)
	elif current_stage == Stage.BRIEFING:
		_finish_intro()

func _transition_to_stage(next_stage: Stage) -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	if _pulse_tween and _pulse_tween.is_valid():
		_pulse_tween.kill()

	_fade_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_fade_tween.tween_property(_content_box, "modulate:a", 0.0, 0.25)
	_fade_tween.tween_callback(func():
		_show_stage(next_stage)
	)

func _finish_intro() -> void:
	current_stage = Stage.FINISHING
	_is_transitioning = true
	_can_accept_input = false

	if _pulse_tween and _pulse_tween.is_valid():
		_pulse_tween.kill()
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()

	_play_sfx()

	# Плавное проявление бункера (затухание черного фона)
	_fade_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_fade_tween.parallel().tween_property(_content_box, "modulate:a", 0.0, 0.5)
	_fade_tween.tween_property(_backdrop, "modulate:a", 0.0, 1.1)
	_fade_tween.tween_callback(func():
		_notify_bus_finished()
		intro_completed.emit()
		queue_free()
	)

func _on_auto_advance_timeout() -> void:
	if not is_inside_tree() or current_stage == Stage.FINISHING or _is_transitioning:
		return
	_can_accept_input = true
	_advance()

func _input(event: InputEvent) -> void:
	if not _can_accept_input or _is_transitioning or current_stage == Stage.FINISHING:
		return

	# Реакция на ЛКМ
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			get_viewport().set_input_as_handled()
			_advance()
			return

	# Реакция на клавиатуру (Пробел, Enter, E, Любая клавиша действия)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_E, KEY_ESCAPE] or event.is_action_pressed("Interact") or event.is_action_pressed("ui_accept"):
			get_viewport().set_input_as_handled()
			_advance()
			return
