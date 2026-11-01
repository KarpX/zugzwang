extends CharacterBody3D

@export var speed: float = 7.0
@export var jump_velocity: float = 4.5
@export var sensitivity: float = 0.003
@export var table_interact_distance: float = 4.2
@export var table_world_center: Vector3 = Vector3(16.0, 0.0, 20.0)
@export_range(1.0, 15.0, 0.5) var queen_panic_duration: float = 3.5
@export_range(0.5, 4.0, 0.25) var panic_fade_out_time: float = 1.5

@onready var head: Node3D = get_node_or_null("head") as Node3D
@onready var camera: Camera3D = get_node_or_null("head/Camera3D") as Camera3D
@onready var player_steps: AudioStreamPlayer3D = get_node_or_null("PlayerSteps") as AudioStreamPlayer3D
@onready var breath_player: AudioStreamPlayer3D = get_node_or_null("head/AudioStreamPlayer3D") as AudioStreamPlayer3D

# Виньетка паники и тяжелое дыхание
var _vignette_rect: ColorRect = null
var _vignette_material: ShaderMaterial = null
var _vignette_tween: Tween = null
var _breath_tween: Tween = null
var is_heavy_breathing: bool = false

# Режимы управления
var is_board_mode: bool = false
var can_move: bool = true       # Вращение камеры мышью
var can_walk: bool = true       # Перемещение WASD
var is_near_table: bool = false
var is_defeat_locked: bool = false

var _initial_transform: Transform3D = Transform3D.IDENTITY
var _initial_head_rotation_x: float = 0.0
var _cam_tween: Tween = null
var _initial_cam_transform: Transform3D = Transform3D.IDENTITY
var _radio_subtitle_label: Label = null
var _radio_tween: Tween = null
var _delayed_shake_tween: Tween = null
var _chess_board_node: Node3D = null
var _unused_radio_reports: Dictionary = {}
var _unused_radio_reports_black: Dictionary = {}

const RADIO_REPORTS_WHITE: Dictionary = {
	"pawn": [
		"«1-е отделение 3-го взвода перестало выходить на связь...»",
		"«Окоп 14 засыпан землей после артудара. Живых нет.»",
		"«Рядовой погиб на переправе под перекрестным огнем.»",
		"«Позиция \"Высота-8\" молчит. Дозор не отвечает на запросы.»",
		"«Стрелковая рота прижата к болоту. Боекомплект пуст... тишина.»",
		"«Блиндаж на восточной опушке смят прямым попаданием тяжелого снаряда.»",
		"«Штурмовая группа осталась в нейтральной полосе. Эвакуация сорвана.»",
		"«Снайпер снял наблюдателя на вышке. Линия обзора потеряна.»",
		"«Блокпост №3 разбит в щепки. Защитники приняли бой до конца.»",
		"«Взвод связистов погиб при восстановлении кабеля под минометами.»",
		"«Опорный пункт у реки смят бронетехникой противника.»",
		"«Санитарный транспорт расстрелян на трассе... выживших нет.»"
	],
	"knight": [
		"«Разведгруппа \"Сокол\" накрыта кассетным ударом в секторе B!»",
		"«Бронемашина связи уничтожена дроном-камикадзе. Координат нет!»",
		"«Танковый взвод флангового прикрытия сожжен в засаде у лесополосы!»",
		"«Мобильный резерв отрезан на перекрестке и ведет бой в полном окружении!»",
		"«Экипаж головного БТР вызвал огонь на себя. Сигнал маяка оборвался.»",
		"«Кавалерийский прорыв захлебнулся на минном поле под шквальным огнем!»"
	],
	"bishop": [
		"«Артиллерийский расчет батареи \"Север\" уничтожен контрбатарейным огнем!»",
		"«Наводчики погибли на передовом пункте. Мы ослепли на восточном фланге!»",
		"«Станция радиолокации разгромлена высокоточной ракетой противника!»",
		"«Офицеры управления огнем дивизиона накрыты управляемой авиабомбой!»",
		"«Снайперская пара на водонапорной башне ликвидирована сбросом с воздуха.»",
		"«Батарея тяжелых гаубиц раздавлена гусеницами прорвавшейся бронегруппы!»"
	],
	"rook": [
		"«ДОТ-4 пробит бетонобойным снарядом! Весь гарнизон погиб!»",
		"«Укрепрайон \"Цитадель\" пал! Враг прорвал главную долговременную линию обороны!»",
		"«Железобетонный форт \"Бастион\" обрушен фугасами. Защитников погребло в казематах!»",
		"«Опорный узел сектора Юг выжжен термитным зарядом. Внутри расплавленный металл!»",
		"«Бронепоезд прикрытия сошел с рельсов после подрыва эстакады. Рубеж открыт!»",
		"«Главный противотанковый вал перепахан авиацией. Тяжелые орудия замолчали!»"
	],
	"queen": [
		"«ШТАБ АРМИИ УНИЧТОЖЕН ПРЯМЫМ ПОПАДАНИЕМ! КОМАНДОВАНИЯ БОЛЬШЕ НЕТ!»",
		"«ПОЛНЫЙ РАЗГРОМ! ВСЕМ ПОДРАЗДЕЛЕНИЯМ — ДЕЙСТВОВАТЬ САМОСТОЯТЕЛЬНО!»",
		"«ГЕНЕРАЛЫ ПОГИБЛИ В БУНКЕРЕ СВЯЗИ! АРМИЯ ОБЕЗГЛАВЛЕНА, ФРОНТ РУШИТСЯ!»",
		"«ЦЕНТРАЛЬНЫЙ УЗЕЛ УПРАВЛЕНИЯ СТЕРТ С ЛИЦА ЗЕМЛИ! МЫ ПРЕДАНЫ И ОСТАЛИСЬ ОДНИ!»"
	],
	"king": [
		"«БУНКЕР ГЛАВНОКОМАНДУЮЩЕГО ВЗЯТ В ПЛОТНОЕ КОЛЬЦО! ДВЕРЬ ВЫБИТА...»"
	]
}

const RADIO_REPORTS_BLACK: Dictionary = {
	"pawn": [
		"«Первая цепь наступления противника рассеяна артиллерией.»",
		"«Вражеская пехота залегла под пулеметным огнем.»",
		"«Передовые группы противника несут критические потери на фланге.»",
		"«Батальон врага остановлен на противотанковом рву.»",
		"«Вражеская рота отступает, бросая тяжелое вооружение.»",
		"«Вражеские позиции на переднем крае перепаханы гаубицами.»"
	],
	"knight": [
		"«Авангард противника попал в огневой мешок на шоссе.»",
		"«Колонна снабжения противника сожжена дотла.»",
		"«Мобильная бронегруппа врага разбита в приграничном районе!»",
		"«Моторизованный полк потерял связь со штабом направления!»",
		"«Разведывательный батальон противника попал в окружение!»"
	],
	"bishop": [
		"«Подавлена дальнобойная батарея противника на высоте 204.»",
		"«Вражеский пункт управления огнем уничтожен.»",
		"«Станция радиоэлектронной борьбы врага выведена из строя!»",
		"«Тяжелые расчеты противника разбиты прямым попаданием!»"
	],
	"rook": [
		"«ТЯЖЕЛЫЙ БРОНЕТАРАН ВРАГА РАЗОРВАН В КЛОЧЬЯ! ВЗРЫВ БОЕКОМПЛЕКТА!»",
		"«Опорная крепость противника превращена в лунный кратер.»",
		"«Главный рубеж обороны противника сокрушен! Провал фронта!»",
		"«Железобетонный форт противника полностью разрушен авиаударом!»"
	],
	"queen": [
		"«ГЛАВНЫЙ БУНКЕР КОМАНДОВАНИЯ ВРАГА УНИЧТОЖЕН СТРАТЕГИЧЕСКИМ УДАРОМ!»",
		"«У них паника в эфире! Вражеский фронт распадается на части!.. Но какой ценой?..»",
		"«ГЕНЕРАЛЬНЫЙ ШТАБ ПРОТИВНИКА СТЕРТ С ЛИЦА ЗЕМЛИ! У НИХ ПОЛНЫЙ ХАОС!»"
	],
	"king": [
		"«ВСЕ ЧАСТОТЫ ПРОТИВНИКА ЗАМОЛКЛИ. ВРАГ УНИЧТОЖЕН. МИР СГОРЕЛ...»"
	]
}

# Параметры тряски камеры (Screen Shake при взятиях и стуках без искажения осей вращения)
var _trauma: float = 0.0
var _shake_decay: float = 2.8        # Базовая скорость затухания
var _current_shake_decay: float = 2.8
var _base_max_shake_offset: float = 0.045 # Базовое смещение в метрах
var _current_max_shake_offset: float = 0.045

func _get_event_bus() -> Node:
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/EventBus")

func _ready() -> void:
	add_to_group("player")
	_initial_transform = global_transform
	if head != null:
		_initial_head_rotation_x = head.rotation.x
	if camera != null:
		_initial_cam_transform = camera.transform
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_setup_hud()
	_find_chess_board()
	_setup_audio_listener()
	
	var bus = _get_event_bus()
	if bus:
		if bus.is_intro_active:
			can_move = false
			can_walk = false
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if bus.has_signal("intro_sequence_finished"):
			bus.intro_sequence_finished.connect(_on_intro_finished)
		if bus.has_signal("piece_captured"):
			bus.piece_captured.connect(_on_piece_captured)
		if bus.has_signal("door_knock_triggered"):
			bus.door_knock_triggered.connect(_on_door_knock_triggered)
		if bus.has_signal("seismic_shock_triggered"):
			bus.seismic_shock_triggered.connect(_on_seismic_shock_triggered)
		if bus.has_signal("outside_stage_changed"):
			bus.outside_stage_changed.connect(_on_outside_stage_changed)
		if bus.has_signal("radio_transmission_started"):
			bus.radio_transmission_started.connect(_on_radio_transmission_started)
		if bus.has_signal("game_over"):
			bus.game_over.connect(_on_game_over)
		if bus.has_signal("game_reset"):
			bus.game_reset.connect(_on_game_reset)
			
	_init_breath_player()

func _setup_audio_listener() -> void:
	if camera != null and camera.get_node_or_null("AudioListener3D") == null:
		var listener = AudioListener3D.new()
		listener.name = "AudioListener3D"
		camera.add_child(listener)
		listener.make_current()

func _setup_hud() -> void:
	var canvas = CanvasLayer.new()
	canvas.name = "PlayerHUD"
	canvas.layer = 20 # Поверх 3D-графики и спецэффектов
	add_child(canvas)
	
	var root_ctrl = Control.new()
	root_ctrl.name = "HudRoot"
	root_ctrl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(root_ctrl)

	# Полноэкранная виньетка паники и тяжелого дыхания
	_vignette_rect = ColorRect.new()
	_vignette_rect.name = "PanicVignette"
	_vignette_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette_rect.color = Color(1.0, 1.0, 1.0, 1.0)
	
	if ResourceLoader.exists("res://shaders/vignette.gdshader"):
		var vignette_shader = load("res://shaders/vignette.gdshader")
		if vignette_shader is Shader:
			_vignette_material = ShaderMaterial.new()
			_vignette_material.shader = vignette_shader
			_vignette_material.set_shader_parameter("vignette_opacity", 0.0)
			_vignette_material.set_shader_parameter("vignette_intensity", 1.15)
			_vignette_rect.material = _vignette_material
			
	root_ctrl.add_child(_vignette_rect)

	# Радио-сводка военных потерь (субтитры внизу экрана с контрастной обводкой)
	_radio_subtitle_label = Label.new()
	_radio_subtitle_label.name = "RadioSubtitle"
	_radio_subtitle_label.text = ""
	_radio_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_radio_subtitle_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_radio_subtitle_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_radio_subtitle_label.offset_left = 60.0
	_radio_subtitle_label.offset_right = -60.0
	_radio_subtitle_label.offset_top = -150.0
	_radio_subtitle_label.offset_bottom = -70.0
	_radio_subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_radio_subtitle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_radio_subtitle_label.modulate.a = 0.0

	var settings = LabelSettings.new()
	settings.font_size = 23
	settings.font_color = Color(1.0, 0.88, 0.35, 1.0)
	# Мощная четкая черная обводка для безупречной читаемости на любом фоне
	settings.outline_size = 8
	settings.outline_color = Color(0.02, 0.02, 0.02, 1.0)
	settings.shadow_size = 4
	settings.shadow_color = Color(0.0, 0.0, 0.0, 0.95)
	settings.shadow_offset = Vector2(2, 2)
	_radio_subtitle_label.label_settings = settings

	root_ctrl.add_child(_radio_subtitle_label)

func _find_chess_board() -> void:
	if not is_inside_tree():
		return
	var tree = get_tree()
	if tree:
		var boards = tree.get_nodes_in_group("chess_board")
		if boards.size() > 0:
			_chess_board_node = boards[0]
			return
	_chess_board_node = get_node_or_null("../TableStatic/Table/ChessBoard")

func _unhandled_input(event: InputEvent) -> void:
	if is_defeat_locked:
		return

	# 1. Вращение камеры от первого лица (только в свободном режиме ходьбы)
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if can_move:
			rotate_y(-event.relative.x * sensitivity)
			head.rotate_x(-event.relative.y * sensitivity)
			head.rotation.x = clamp(head.rotation.x, deg_to_rad(-85), deg_to_rad(85))

	# 2. Взаимодействие со столом по клавише [E]
	var is_interact_pressed: bool = event.is_action_pressed("Interact")
	if not is_interact_pressed and event is InputEventKey:
		if event.pressed and not event.echo and event.keycode == KEY_E:
			is_interact_pressed = true
			
	if is_interact_pressed:
		if is_board_mode:
			exit_board_mode()
		elif is_near_table:
			enter_board_mode()

	# 3. Выход из-за стола по Escape
	if event.is_action_pressed("ui_cancel") and is_board_mode:
		exit_board_mode()

func _process(delta: float) -> void:
	_update_camera_shake(delta)

## Применение импульса тряски экрана (Screen Shake)
func apply_camera_shake(amount: float = 0.6, decay_rate: float = 2.8, max_offset: float = 0.045) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)
	_current_shake_decay = decay_rate
	_current_max_shake_offset = maxf(_current_max_shake_offset, max_offset)

## Показ радио-сводки военных потерь (субтитры внизу экрана без повторений)
## is_white: true — потери Белых (свои), false — радиоперехват потерь Черных (враг)
func show_radio_report(piece_type: String, is_white: bool = true) -> void:
	if _radio_subtitle_label == null or not is_inside_tree():
		return
		
	var pool_dict: Dictionary = RADIO_REPORTS_WHITE if is_white else RADIO_REPORTS_BLACK
	var unused_dict: Dictionary = _unused_radio_reports if is_white else _unused_radio_reports_black
	
	var pool: Array = pool_dict.get(piece_type, [])
	if pool.is_empty():
		return
		
	# Ротация уникальных строк без повторов подряд
	if not unused_dict.has(piece_type) or unused_dict[piece_type].is_empty():
		var copy: Array = pool.duplicate()
		copy.shuffle()
		unused_dict[piece_type] = copy
		
	var queue: Array = unused_dict[piece_type]
	var text_line: String = queue.pop_back()
	
	if not is_white and not text_line.begins_with("«(Перехват)"):
		text_line = "«(Перехват) " + text_line.trim_prefix("«")
	
	# Цветовая кодировка степени тревоги в зависимости от ранга фигуры и стороны
	if _radio_subtitle_label.label_settings != null:
		if is_white:
			match piece_type:
				"queen":
					_radio_subtitle_label.label_settings.font_color = Color(1.0, 0.28, 0.28, 1.0)
				"rook":
					_radio_subtitle_label.label_settings.font_color = Color(1.0, 0.65, 0.25, 1.0)
				"knight", "bishop":
					_radio_subtitle_label.label_settings.font_color = Color(1.0, 0.88, 0.35, 1.0)
				_:
					_radio_subtitle_label.label_settings.font_color = Color(0.95, 0.90, 0.75, 1.0)
		else:
			# Радиоперехваты эфира противника: отличительный технологичный спектр
			match piece_type:
				"queen":
					_radio_subtitle_label.label_settings.font_color = Color(1.0, 0.40, 0.35, 1.0)
				"rook":
					_radio_subtitle_label.label_settings.font_color = Color(1.0, 0.70, 0.20, 1.0)
				"knight", "bishop":
					_radio_subtitle_label.label_settings.font_color = Color(0.40, 0.88, 0.95, 1.0)
				_:
					_radio_subtitle_label.label_settings.font_color = Color(0.50, 0.95, 0.65, 1.0)
			
	_display_radio_text(text_line, is_white)

## Прямой вывод радиоперехвата эфира противника
func show_enemy_radio_intercept(piece_type: String) -> void:
	show_radio_report(piece_type, false)

## Вывод произвольного радио-сообщения (для макро-стадий и сюжетных моментов)
func show_custom_radio_message(msg: String, color: Color = Color(0.50, 0.95, 0.65, 1.0)) -> void:
	if _radio_subtitle_label == null or not is_inside_tree():
		return
	if _radio_subtitle_label.label_settings != null:
		_radio_subtitle_label.label_settings.font_color = color
	_display_radio_text(msg, false)

func _display_radio_text(text_line: String, is_white: bool = true) -> void:
	_radio_subtitle_label.text = text_line
	_radio_subtitle_label.visible_ratio = 1.0
	_radio_subtitle_label.modulate.a = 0.25
	
	var bus = _get_event_bus()
	if bus and bus.has_signal("radio_phrase_triggered"):
		bus.radio_phrase_triggered.emit(text_line, is_white)
	else:
		_start_subtitle_animation(text_line, 3.5)

func _on_radio_transmission_started(text_line: String, _stream: AudioStream, duration: float) -> void:
	_start_subtitle_animation(text_line, duration)

func _start_subtitle_animation(text_line: String, anim_duration: float) -> void:
	if _radio_subtitle_label == null:
		return

	var bus = _get_event_bus()
	if _radio_tween and _radio_tween.is_valid():
		_radio_tween.kill()
		if bus:
			bus.is_radio_text_visible = false

	if bus:
		bus.is_radio_text_visible = true

	_radio_subtitle_label.text = text_line
	_radio_subtitle_label.visible_ratio = 0.0
	_radio_subtitle_label.modulate.a = 0.25
	
	_radio_tween = create_tween().set_trans(Tween.TRANS_LINEAR)
	# 1. Быстрое проявление подложки текста
	_radio_tween.tween_property(_radio_subtitle_label, "modulate:a", 1.0, 0.10)
	
	# 2. Анимация печати текста — ровно пока идет эта печать, вырисовывается текст и блокируются ходы
	_radio_tween.parallel().tween_property(_radio_subtitle_label, "visible_ratio", 1.0, anim_duration)
	
	# Как только текст перестал вырисовываться — немедленно разрешаем делать ходы!
	_radio_tween.tween_callback(func():
		var b = _get_event_bus()
		if b:
			b.is_radio_text_visible = false
			if b.has_signal("radio_transmission_finished"):
				b.radio_transmission_finished.emit()
	)
	
	# 3. Полностью напечатанный текст остаётся для чтения еще на 2.5 секунды (ходы уже разрешены)
	_radio_tween.tween_interval(2.5)
	
	# 4. Плавное затухание текста
	_radio_tween.tween_property(_radio_subtitle_label, "modulate:a", 0.0, 0.60)

func _on_intro_finished() -> void:
	if not is_board_mode:
		can_move = true
		can_walk = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## Обработчик взятия фигуры (сотрясение комнаты и радио-сводка потерь)
func _on_piece_captured(piece_type: String, is_white: bool) -> void:
	var piece_key: String = piece_type.to_lower()
	if is_white:
		match piece_key:
			"pawn":
				apply_camera_shake(0.20, 3.2, 0.035)
			"knight", "bishop":
				apply_camera_shake(0.40, 2.5, 0.055)
			"rook":
				apply_camera_shake(0.65, 2.0, 0.085)
			"queen":
				# Катастрофа при потере Ферзя: мощнейшая тряска (максимальная травма, долгое затухание, смещение 15 см)
				apply_camera_shake(1.0, 0.85, 0.15)
				# Страшное событие: потеря королевы включает тяжелое дыхание и виньетку
				start_heavy_breathing(queen_panic_duration, 0.80)
			_:
				apply_camera_shake(0.30, 2.8, 0.045)
		show_radio_report(piece_key, true)
	else:
		_handle_enemy_piece_loss(piece_key)

## Обработка потерь Черных (Враг): радиоперехват + сейсмические эффекты согласно EVENTS_DESIGN.md
func _handle_enemy_piece_loss(piece_key: String) -> void:
	if _delayed_shake_tween and _delayed_shake_tween.is_valid():
		_delayed_shake_tween.kill()
		_delayed_shake_tween = null
		
	var bus = _get_event_bus()
	var current_out_stage: int = bus.outside_stage if (bus and "outside_stage" in bus) else 0
	
	if piece_key == "queen":
		# Гибель вражеского Ферзя — ключевое стратегическое событие партии, всегда транслируется в эфир
		show_radio_report("queen", false)
	elif current_out_stage >= 4:
		show_custom_radio_message("« В радиоэфире мертвая тишина. Больше некому выходить на связь.»", Color(0.70, 0.70, 0.75, 1.0))
	elif current_out_stage >= 3:
		# На стадии III человеческие голоса исчезают, в эфире автоматическая номерная станция
		show_custom_radio_message("« [ЭФИР 4625 кГц] ... 74 102 СЛОВО 89 21 ... МОНОТОННЫЙ ЗУММЕР ...»", Color(0.85, 0.85, 0.95, 1.0))
	else:
		show_radio_report(piece_key, false)

	match piece_key:
		"pawn":
			# Едва уловимая вибрация пола спустя 0.6 секунды после взятия
			_delayed_shake_tween = create_tween()
			_delayed_shake_tween.tween_interval(0.6)
			_delayed_shake_tween.tween_callback(func(): apply_camera_shake(0.15, 3.5, 0.025))
		"knight":
			# Дрожь стальной двери бункера и отдача
			apply_camera_shake(0.28, 2.6, 0.045)
		"bishop":
			# Низкочастотный подземный толчок
			apply_camera_shake(0.40, 2.2, 0.065)
		"rook":
			# Ударная волна бьет снаружи в стену — всю комнату сотрясает
			apply_camera_shake(0.70, 1.8, 0.095)
		"queen":
			# Стратегический удар: Мертвая тишина на 1.2 секунды... Затем монолитный 3-секундный подземный гул
			_delayed_shake_tween = create_tween()
			_delayed_shake_tween.tween_interval(1.2)
			_delayed_shake_tween.tween_callback(func(): apply_camera_shake(1.0, 0.70, 0.16))
		_:
			apply_camera_shake(0.30, 2.8, 0.045)

## Реакция на внешние сейсмические толчки
func _on_seismic_shock_triggered(intensity: float, is_subterranean: bool) -> void:
	var decay: float = 1.8 if is_subterranean else 2.5
	var offset: float = 0.07 * intensity
	apply_camera_shake(clampf(intensity, 0.1, 1.0), decay, offset)

## Реакция радио на макро-стадии разрушения внешнего мира
func _on_outside_stage_changed(stage: int, _black_score: int) -> void:
	match stage:
		3:
			show_custom_radio_message("« [ЭФИР 4625 кГц] ... 74 102 СЛОВО 89 21 ... МОНОТОННЫЙ ЗУММЕР ...»", Color(0.85, 0.85, 0.95, 1.0))
		4:
			show_custom_radio_message("« В радиоэфире мертвая тишина. Больше некому выходить на связь.»", Color(0.70, 0.70, 0.75, 1.0))

## Обработчик стука в дверь бункера
func _on_door_knock_triggered(knock_level: int) -> void:
	apply_camera_shake(0.35 * float(knock_level), 2.2, 0.05 * float(knock_level))

## Реакция на исход партии (страшные события: поражение Белых)
func _on_game_over(winner: String) -> void:
	var win_key: String = winner.to_lower()
	if win_key == "black" or win_key == "breach" or win_key == "draw":
		is_defeat_locked = true
		can_walk = false
		can_move = false
		# Проигрыш Белых (мат или выбитая дверь бункера) — паника, тяжелое дыхание и глубокая виньетка
		start_heavy_breathing(-1.0, 0.85)

func _on_game_reset(_playthrough: int) -> void:
	if _radio_tween and _radio_tween.is_valid():
		_radio_tween.kill()
		_radio_tween = null
	if _radio_subtitle_label != null:
		_radio_subtitle_label.text = ""
		_radio_subtitle_label.modulate.a = 0.0
		_radio_subtitle_label.visible_ratio = 0.0
	var bus = _get_event_bus()
	if bus:
		bus.is_radio_text_visible = false
	stop_heavy_breathing(0.0)
	reset_to_start()

func _init_breath_player() -> void:
	if breath_player == null:
		breath_player = get_node_or_null("head/AudioStreamPlayer3D") as AudioStreamPlayer3D
	if breath_player == null and head != null:
		breath_player = AudioStreamPlayer3D.new()
		breath_player.name = "AudioStreamPlayer3D"
		breath_player.unit_size = 8.0
		breath_player.max_distance = 15.0
		head.add_child(breath_player)
	if breath_player:
		if breath_player.stream == null and ResourceLoader.exists("res://assets/sounds/breath.ogg"):
			breath_player.stream = load("res://assets/sounds/breath.ogg")
		breath_player.bus = &"Sound"

## Запуск тяжелого дыхания и виньетки при страшных событиях (потеря королевы, проигрыш белых)
func start_heavy_breathing(duration: float = 3.5, target_opacity: float = 0.80) -> void:
	is_heavy_breathing = true
	_init_breath_player()
	
	# 1. Запуск звука дыхания в голове игрока
	if breath_player:
		if _breath_tween and _breath_tween.is_valid():
			_breath_tween.kill()
		if not breath_player.playing:
			breath_player.volume_db = -18.0
			breath_player.play()
		_breath_tween = create_tween()
		_breath_tween.tween_property(breath_player, "volume_db", -1.0, 0.25)
			
	# 2. Активация виньетки паники
	if _vignette_material:
		if _vignette_tween and _vignette_tween.is_valid():
			_vignette_tween.kill()
		_vignette_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		var cur_op: float = float(_vignette_material.get_shader_parameter("vignette_opacity"))
		# Плавное нарастание виньетки в такт панической реакции
		_vignette_tween.tween_method(
			func(val: float): _vignette_material.set_shader_parameter("vignette_opacity", val),
			cur_op,
			target_opacity,
			1.2
		)
		if duration > 0.0:
			_vignette_tween.tween_interval(duration)
			_vignette_tween.tween_callback(func(): stop_heavy_breathing(panic_fade_out_time))

## Остановка тяжелого дыхания и плавное исчезновение виньетки
func stop_heavy_breathing(fade_time: float = -1.0) -> void:
	var actual_fade: float = panic_fade_out_time if fade_time < 0.0 else fade_time
	is_heavy_breathing = false
	if _vignette_tween and _vignette_tween.is_valid():
		_vignette_tween.kill()
		
	if _vignette_material:
		var cur_op: float = float(_vignette_material.get_shader_parameter("vignette_opacity"))
		if cur_op > 0.0:
			if actual_fade <= 0.0:
				_vignette_material.set_shader_parameter("vignette_opacity", 0.0)
			else:
				_vignette_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
				_vignette_tween.tween_method(
					func(val: float): _vignette_material.set_shader_parameter("vignette_opacity", val),
					cur_op,
					0.0,
					actual_fade
				)
			
	if breath_player and breath_player.playing:
		if _breath_tween and _breath_tween.is_valid():
			_breath_tween.kill()
		if actual_fade <= 0.0:
			breath_player.stop()
		else:
			_breath_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			_breath_tween.tween_property(breath_player, "volume_db", -40.0, actual_fade)
			_breath_tween.tween_callback(breath_player.stop)

func get_vignette_opacity() -> float:
	if _vignette_material:
		return float(_vignette_material.get_shader_parameter("vignette_opacity"))
	return 0.0

## Обновление тряски камеры со спадом (только h_offset и v_offset в экранном пространстве, без изменения осей вращения)
func _update_camera_shake(delta: float) -> void:
	if _trauma <= 0.0:
		if camera != null:
			camera.h_offset = 0.0
			camera.v_offset = 0.0
		_current_shake_decay = _shake_decay
		_current_max_shake_offset = _base_max_shake_offset
		return
		
	_trauma = maxf(0.0, _trauma - _current_shake_decay * delta)
	var shake_power: float = _trauma * _trauma
	
	if camera != null:
		camera.h_offset = randf_range(-1.0, 1.0) * _current_max_shake_offset * shake_power
		camera.v_offset = randf_range(-1.0, 1.0) * _current_max_shake_offset * shake_power

func _physics_process(delta: float) -> void:
	# Гравитация
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Проверка дистанции до шахматного стола (в горизонтальной плоскости XZ)
	if not is_board_mode:
		var current_pos: Vector3 = global_position if is_inside_tree() else position
		var horiz_dist: float = Vector2(current_pos.x, current_pos.z).distance_to(Vector2(table_world_center.x, table_world_center.z))
		is_near_table = (horiz_dist <= table_interact_distance)

	if not can_walk:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)
		move_and_slide()
		_update_footsteps(Vector2.ZERO)
		return

	# Перемещение WASD
	var input_dir := Input.get_vector("Left", "Right", "Forward", "Back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	move_and_slide()
	_update_footsteps(input_dir)

## Обновление звука шагов: играет при движении и останавливается при остановке
func _update_footsteps(input_dir: Vector2) -> void:
	if player_steps == null:
		return
	
	var has_input: bool = not input_dir.is_zero_approx()
	var horizontal_speed_sq: float = Vector2(velocity.x, velocity.z).length_squared()
	var is_moving: bool = can_walk and is_on_floor() and has_input and (horizontal_speed_sq > 0.1)
	
	if is_moving:
		if not player_steps.playing:
			player_steps.play()
	else:
		if player_steps.playing:
			player_steps.stop()

## Плавный переход камеры за шахматный стол с гарантированным нулевым креном (roll = 0.0)
func enter_board_mode() -> void:
	if is_defeat_locked:
		return
	if is_board_mode:
		return
	if head == null:
		head = get_node_or_null("head")
	if camera == null:
		camera = get_node_or_null("head/Camera3D")
	if _chess_board_node == null:
		_find_chess_board()
	if _chess_board_node == null:
		return
		
	var cam_marker: Marker3D = _chess_board_node.get_node_or_null("CameraPoint")
	if not cam_marker:
		return
		
	is_board_mode = true
	can_walk = false
	can_move = false
	if player_steps != null and player_steps.playing:
		player_steps.stop()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	if camera != null:
		if _cam_tween and _cam_tween.is_valid():
			_cam_tween.kill()
		_cam_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		
		# Сбрасываем смещения экрана от тряски
		_trauma = 0.0
		camera.h_offset = 0.0
		camera.v_offset = 0.0
		
		var start_trans: Transform3D = camera.global_transform
		var start_origin: Vector3 = start_trans.origin
		var target_origin: Vector3 = cam_marker.global_position
		
		var start_basis: Basis = start_trans.basis.orthonormalized()
		var target_basis: Basis = cam_marker.global_transform.basis.orthonormalized()
		
		var start_euler: Vector3 = start_basis.get_euler(EULER_ORDER_YXZ)
		var target_euler: Vector3 = target_basis.get_euler(EULER_ORDER_YXZ)
		
		var start_yaw: float = start_euler.y
		var diff_yaw: float = wrapf(target_euler.y - start_euler.y, -PI, PI)
		var start_pitch: float = start_euler.x
		var target_pitch: float = target_euler.x
		
		# Плавно выравниваем ориентацию тела и головы игрока строго по столу
		var start_player_yaw: float = rotation.y
		var diff_player_yaw: float = wrapf(target_euler.y - start_player_yaw, -PI, PI)
		var start_head_pitch: float = head.rotation.x if head != null else 0.0
		
		_cam_tween.tween_method(func(t: float):
			var cur_origin: Vector3 = start_origin.lerp(target_origin, t)
			var cur_yaw: float = start_yaw + diff_yaw * t
			var cur_pitch: float = lerpf(start_pitch, target_pitch, t)
			# roll строго равен 0.0, масштаб строго (1, 1, 1)
			var cur_basis: Basis = Basis.from_euler(Vector3(cur_pitch, cur_yaw, 0.0), EULER_ORDER_YXZ)
			camera.global_transform = Transform3D(cur_basis, cur_origin)
			
			rotation.y = start_player_yaw + diff_player_yaw * t
			if head != null:
				head.rotation.x = lerpf(start_head_pitch, 0.0, t)
		, 0.0, 1.0, 0.75)
		
		_cam_tween.chain().tween_callback(func():
			if camera != null and cam_marker != null and is_instance_valid(cam_marker):
				var norm_target_basis: Basis = Basis.from_euler(Vector3(target_pitch, target_euler.y, 0.0), EULER_ORDER_YXZ)
				camera.global_transform = Transform3D(norm_target_basis, cam_marker.global_position)
		)
	
	var bus = _get_event_bus()
	if bus:
		bus.camera_mode_changed.emit(true)
		bus.player_made_action.emit()
	elif _chess_board_node.has_method("_on_camera_mode_changed"):
		_chess_board_node._on_camera_mode_changed(true)

## Возврат камеры обратно к телу персонажа
func exit_board_mode() -> void:
	if is_defeat_locked:
		return
	if not is_board_mode:
		return
		
	is_board_mode = false
	can_walk = true
	can_move = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	if camera != null:
		if _cam_tween and _cam_tween.is_valid():
			_cam_tween.kill()
		_cam_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		_cam_tween.tween_property(camera, "transform", _initial_cam_transform, 0.65)
		_cam_tween.chain().tween_callback(func():
			if camera != null:
				camera.transform = _initial_cam_transform
		)
	
	var bus = _get_event_bus()
	if bus:
		bus.camera_mode_changed.emit(false)
		bus.player_made_action.emit()
	elif _chess_board_node and _chess_board_node.has_method("_on_camera_mode_changed"):
		_chess_board_node._on_camera_mode_changed(false)

## Сброс игрока на стартовую точку бункера (координаты спавна, ориентация, камера)
func reset_to_start() -> void:
	if _cam_tween and _cam_tween.is_valid():
		_cam_tween.kill()
		_cam_tween = null
		
	if _initial_transform != Transform3D.IDENTITY:
		global_transform = _initial_transform
		
	velocity = Vector3.ZERO
	
	if head != null:
		head.rotation.x = _initial_head_rotation_x
		head.rotation.y = 0.0
		head.rotation.z = 0.0
		
	if camera != null:
		camera.transform = _initial_cam_transform
		camera.h_offset = 0.0
		camera.v_offset = 0.0
		
	is_board_mode = false
	is_near_table = false
	
	if is_defeat_locked:
		can_walk = false
		can_move = false
	else:
		can_walk = true
		can_move = true
		
	if player_steps != null and player_steps.playing:
		player_steps.stop()
		
	stop_heavy_breathing(0.0)

## Разблокировка управления игроком после исчезновения экрана поражения
func unlock_after_defeat() -> void:
	is_defeat_locked = false
	can_walk = true
	can_move = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
