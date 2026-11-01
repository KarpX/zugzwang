class_name ObservationMonitor
extends Node3D

## Контроллер CRT-терминала в секретной комнате наблюдения
## Рендерит терминал исключительно на экране 3D-монитора (без фуллскрина).
## При нажатии [ E ] камера плавно подлетает и смотрит точно на монитор под прямым углом (90°),
## при этом игрок продолжает видеть всю комнату, стол и бегущий по экрану текст.

signal terminal_started
signal revelation_finished

@export var screen_mesh: MeshInstance3D
@export var viewport: SubViewport
@export var terminal_text: RichTextLabel
@export var terminal_label: Control
@export var hum_audio: AudioStreamPlayer3D
@export var type_sound: AudioStream = preload("res://assets/sounds/type_sound.ogg")

## Максимальная дистанция (в метрах) от экрана монитора для возможности взаимодействия
@export_range(1.0, 8.0, 0.1) var max_interact_distance: float = 3.2

## Минимальный скалярный косинус угла взгляда (0.80 ≈ отклонение не более 36°)
@export_range(0.5, 0.99, 0.01) var min_look_dot: float = 0.80

var is_awaiting_input: bool = true
var is_terminal_running: bool = false

var _cursor_visible: bool = true
var _cursor_timer: float = 0.0
var _keystroke_player: AudioStreamPlayer = null

const IDLE_PROMPT: String = (
	"> ТЕРМИНАЛ СВЯЗИ УЗЛА «ZUGZWANG-0»\n" +
	"> ВХОД ВЫПОЛНЕН: ОБЪЕКТ-0\n\n" +
	"> ДЛЯ ПРОДОЛЖЕНИЯ НАЖМИТЕ [ E ] "
)

const PHASE_1_LINES: Array[String] = [
	"[INPUT]: KEY_E DETECTED",
	"[SYSTEM]: ATTACHING TTY SESSION /dev/tty0",
	"[AUTH]: OVERRIDE CLEARANCE: MAXIMUM (ROOT_MILITARY)",
	"> EXECUTE /sys/bin/exchange_protocol.sh --force --target=auto"
]

const PHASE_2_LINES: Array[String] = [
	"[LOAD] libkernel_core.so (addr: 0x7fff0010) .................... [ OK ]",
	"[LOAD] libcrypt_military_v4.so ................................ [ OK ]",
	"[LOAD] libchess_matrix_8x8.so ................................. [ OK ]",
	"[LOAD] libwhite_telemetry.so .................................. [ OK ]",
	"[LOAD] libtactical_exchange.so ................................ [ OK ]",
	"[LOAD] libneural_feedback_loop.so ............................. [ OK ]",
	"",
	"[DIAGNOSTICS]:",
	"  -> Main Processing Core: 8x Vector Array .................... [ ONLINE ]",
	"  -> Secure Communication Line: 4625 kHz ...................... [ LOST ]",
	"  -> Vital Biosensors: Subject #0 ............................. [ DETECTED ]",
	"  -> Life Support Override: Bunker Chamber-1 .................. [ ARMED ]",
	"  -> Chess Evaluation Engine: Minimax v2.4 .................... [ READY ]",
	"",
	"[EVALUATION MATRICES LOADED]:",
	"  -> Pawn: 1.0 | Knight: 3.0 | Bishop: 3.0 | Rook: 5.0 | Queen: 10.0",
	"  -> Priority: SACRIFICIAL_FLAG_SET"
]

const PHASE_3_LINES: Array[String] = [
	"============================================================",
	"              ПРОТОКОЛ РАЗМЕНА «ZUGZWANG»",
	"============================================================",
	"> ТЕКУЩИЙ СТАТУС ФРОНТА: ПОЛНОЕ УНИЧТОЖЕНИЕ ПРОТИВНИКА",
	"> ОСТАТОК ЖИВОЙ СИЛЫ ВРАГА: 0",
	"> ЦЕНА ПОБЕДЫ: КРИТИЧЕСКИЙ ДЕФИЦИТ ФИГУР",
	"> ",
	"> ИНИЦИАЛИЗАЦИЯ ФИНАЛЬНОГО ХОДА:",
	"  -> ТРЕБУЕТСЯ: РАЗМЕН ПОСЛЕДНЕЙ ФИГУРЫ",
	"  -> ЦЕЛЬ ДЛЯ ВЗЯТИЯ: СУБЪЕКТ В БУНКЕРЕ",
	"> ",
	"> ПОДТВЕРЖДЕНИЕ ПРИКАЗА ВЕРХОВНОГО ШТАБА ..."
]

const PHASE_5_LINES: Array[String] = [
	"",
	"[ ОШИБКА ИДЕНТИФИКАЦИИ ]:",
	"СУБЪЕКТ НЕ ЯВЛЯЕТСЯ ГЛАВНОКОМАНДУЮЩИМ.",
	"",
	"ДАННЫЕ ПАРТИИ:",
	"«ТЫ НИКОГДА НЕ БЫЛ ИГРОКОМ.",
	" ТЫ НИКОГДА НЕ ДВИГАЛ ФИГУРЫ.",
	" ТЫ НИКОГДА НЕ ПРИНИМАЛ РЕШЕНИЙ.",
	"",
	" ТЫ ВСЕГДА БЫЛ ЛИШЬ ПЕШКОЙ.",
	" ДЕШЕВОЙ ФИГУРОЙ НА ЧУЖОЙ ДОСКЕ.»",
	"",
	"> ПАРТИЯ ЗАВЕРШЕНА.",
	"> ЖЕРТВА ПРИНЯТА."
]

const PHASE_6_LINES: Array[String] = [
	"",
	"[TERMINATION PROTOCOL EXECUTED]",
	"[VITAL SIGNS: FAILING...]",
	"[PULSE: 0]",
	"[SIGNAL DISCONNECTED]"
]

func _ready() -> void:
	_setup_screen_material()
	_update_idle_prompt()
	_setup_keystroke_audio()
	if hum_audio:
		hum_audio.play()

func _setup_screen_material() -> void:
	if screen_mesh == null:
		screen_mesh = get_node_or_null("ScreenMesh") as MeshInstance3D
	if viewport == null:
		viewport = get_node_or_null("SubViewport") as SubViewport
		
	if terminal_text == null and viewport:
		terminal_text = viewport.get_node_or_null("MonitorUI/Margin/TerminalText") as RichTextLabel
		if terminal_text == null:
			terminal_text = viewport.find_child("TerminalText", true, false) as RichTextLabel
			
	if terminal_label == null:
		terminal_label = terminal_text
			
	if screen_mesh and viewport:
		var mat = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_texture = viewport.get_texture()
		screen_mesh.material_override = mat

func _setup_keystroke_audio() -> void:
	if _keystroke_player == null and is_inside_tree():
		_keystroke_player = AudioStreamPlayer.new()
		_keystroke_player.name = "KeystrokePlayer"
		_keystroke_player.bus = &"Sound"
		_keystroke_player.max_polyphony = 6
		add_child(_keystroke_player)
		
		if type_sound != null:
			_keystroke_player.stream = type_sound
		else:
			# Синтез отчетливого механического клика клавиши CRT-терминала
			var sample_rate: int = 44100
			var duration: float = 0.022
			var total_samples: int = int(duration * sample_rate)
			var pcm = PackedByteArray()
			pcm.resize(total_samples * 2)
			
			for i in range(total_samples):
				var t: float = float(i) / float(sample_rate)
				var snap: float = sin(t * TAU * 2200.0) * exp(-t * 260.0)
				var body: float = sin(t * TAU * 780.0) * exp(-t * 140.0) * 0.55
				var sample_f: float = clampf((snap + body) * 0.8, -1.0, 1.0)
				var sample_i: int = int(sample_f * 32767.0)
				pcm.encode_s16(i * 2, sample_i)
				
			var wav = AudioStreamWAV.new()
			wav.format = AudioStreamWAV.FORMAT_16_BITS
			wav.mix_rate = sample_rate
			wav.data = pcm
			_keystroke_player.stream = wav

func _play_keystroke_sound(is_space: bool = false) -> void:
	if _keystroke_player == null or not is_inside_tree():
		return
	if is_space:
		_keystroke_player.pitch_scale = randf_range(0.75, 0.88)
		_keystroke_player.volume_db = -10.0
	else:
		_keystroke_player.pitch_scale = randf_range(0.85, 1.25)
		_keystroke_player.volume_db = -4.0
	_keystroke_player.play()

func _process(delta: float) -> void:
	if is_awaiting_input and not is_terminal_running:
		_cursor_timer += delta
		if _cursor_timer >= 0.5:
			_cursor_timer = 0.0
			_cursor_visible = not _cursor_visible
			_update_idle_prompt()

func _update_idle_prompt() -> void:
	var cursor_str = "_" if _cursor_visible else " "
	if terminal_text:
		terminal_text.text = IDLE_PROMPT + cursor_str
	elif terminal_label and "text" in terminal_label:
		terminal_label.text = IDLE_PROMPT + cursor_str

func enable_terminal_input() -> void:
	is_awaiting_input = true
	_update_idle_prompt()

## Проверка: находится ли игрок вблизи монитора и смотрит ли он точно на него
func is_player_looking_at_monitor() -> bool:
	var player = _get_player()
	if player == null or not is_instance_valid(player):
		return false
		
	var cam: Camera3D = null
	if player.has_node("head/Camera3D"):
		cam = player.get_node("head/Camera3D") as Camera3D
	if cam == null:
		for c in player.find_children("", "Camera3D", true, false):
			cam = c as Camera3D
			break
	if cam == null and is_inside_tree():
		cam = get_viewport().get_camera_3d()
		
	var target_mesh = screen_mesh if screen_mesh else self
	var screen_pos: Vector3 = target_mesh.global_position if target_mesh.is_inside_tree() else target_mesh.position
	var player_pos: Vector3 = player.global_position if player.is_inside_tree() else player.position
	
	# 1. Проверка дистанции: игрок должен находиться вблизи монитора
	var horiz_dist: float = Vector2(player_pos.x - screen_pos.x, player_pos.z - screen_pos.z).length()
	if horiz_dist > max_interact_distance:
		return false
		
	# 2. Проверка взгляда: вектор камеры должен быть направлен прямо на монитор
	if cam:
		var cam_forward: Vector3 = -cam.global_transform.basis.z.normalized() if cam.is_inside_tree() else -cam.transform.basis.z.normalized()
		var cam_pos: Vector3 = cam.global_position if cam.is_inside_tree() else (player_pos + cam.position)
		var dir_to_screen: Vector3 = (screen_pos - cam_pos).normalized()
		var dot: float = cam_forward.dot(dir_to_screen)
		if dot < min_look_dot:
			return false
	else:
		return false
			
	return true

func _unhandled_input(event: InputEvent) -> void:
	if not is_awaiting_input or is_terminal_running:
		return
		
	var is_interact: bool = event.is_action_pressed("Interact")
	if not is_interact and event is InputEventKey:
		if event.pressed and not event.echo and event.keycode == KEY_E:
			is_interact = true
			
	if is_interact:
		if not is_player_looking_at_monitor():
			return
		if is_inside_tree():
			get_viewport().set_input_as_handled()
		start_terminal_sequence()

func _get_player() -> Node:
	if is_inside_tree() and get_tree():
		for p in get_tree().get_nodes_in_group("player"):
			if is_instance_valid(p) and not p.is_queued_for_deletion():
				return p
	var parent_node = get_parent()
	if parent_node:
		for child in parent_node.get_children():
			if is_instance_valid(child) and not child.is_queued_for_deletion() and child.is_in_group("player"):
				return child
		var p = parent_node.find_child("player", true, false)
		if is_instance_valid(p) and not p.is_queued_for_deletion():
			return p
	return get_node_or_null("../../player")

## Точка входа для запуска откровения (сохранена для обратной совместимости)
func start_revelation() -> void:
	start_terminal_sequence()

## Запуск перехода: подлет камеры под прямым углом и запуск протокола прямо на мониторе
func start_terminal_sequence() -> void:
	if is_terminal_running:
		return
	is_terminal_running = true
	is_awaiting_input = false
	
	terminal_started.emit()
	_lock_player(true)
	_setup_keystroke_audio()
	
	# Плавный подлет камеры точно к монитору под прямым углом
	await _fly_camera_to_monitor()
	
	if terminal_text:
		terminal_text.text = ""
	elif terminal_label and "text" in terminal_label:
		terminal_label.text = ""
		
	_run_terminal_phases()

func _lock_player(locked: bool) -> void:
	var player = _get_player()
	if player and is_instance_valid(player):
		if "can_walk" in player:
			player.can_walk = not locked
		if "can_move" in player:
			player.can_move = not locked

## Медленный подлет камеры: строгий прямой угол (90°) к экрану с сохранением обзора комнаты
func _fly_camera_to_monitor() -> void:
	if not is_inside_tree():
		return
		
	var cam: Camera3D = null
	var player = _get_player()
	if player and player.has_node("head/Camera3D"):
		cam = player.get_node("head/Camera3D") as Camera3D
	if cam == null:
		cam = get_viewport().get_camera_3d()
		
	if cam == null or screen_mesh == null:
		return
		
	var screen_pos: Vector3 = screen_mesh.global_position
	# Точный перпендикуляр: X и Y строго по центру экрана (16.0, 7.105),
	# Z на 1.55м перед экраном. Игрок видит монитор, стол, стены бункера и свет лампы
	var target_pos: Vector3 = Vector3(screen_pos.x, screen_pos.y, screen_pos.z + 1.55)
	var target_rot: Vector3 = Vector3.ZERO # Взгляд строго вдоль -Z (перпендикулярно плоскости экрана)
	
	var fly_duration: float = 2.0
	var tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(cam, "global_position", target_pos, fly_duration)
	tween.tween_property(cam, "global_rotation", target_rot, fly_duration)
	
	await tween.finished

func _append_line(line: String) -> void:
	if terminal_text:
		terminal_text.append_text(line + "\n")
	elif terminal_label and "text" in terminal_label:
		terminal_label.text += line + "\n"

func _append_text(text: String) -> void:
	if terminal_text:
		terminal_text.append_text(text)
	elif terminal_label and "text" in terminal_label:
		terminal_label.text += text

## Печать строки красным цветом с легким дрожанием каждой буквы и звуком клавиш
func _type_shaking_red_line(line: String, char_delay: float = 0.028) -> void:
	if terminal_text == null:
		_append_line(line)
		return
		
	terminal_text.append_text("[color=#ff3333][shake rate=18.0 level=4 connected=0]")
	for ch in line:
		terminal_text.append_text(ch)
		if is_inside_tree():
			_play_keystroke_sound(ch == " ")
			await get_tree().create_timer(char_delay).timeout
	terminal_text.append_text("[/shake][/color]\n")

func _run_terminal_phases() -> void:
	# Фаза 1: Запуск скрипта
	for line in PHASE_1_LINES:
		_append_line(line)
		if is_inside_tree():
			await get_tree().create_timer(0.18).timeout
			
	if is_inside_tree():
		await get_tree().create_timer(0.25).timeout
		
	# Фаза 2: Быстрая загрузка библиотек и системных модулей
	for line in PHASE_2_LINES:
		_append_line(line)
		if is_inside_tree():
			await get_tree().create_timer(0.035).timeout
			
	if is_inside_tree():
		await get_tree().create_timer(0.3).timeout
		
	# Фаза 3: Протокол размена
	for line in PHASE_3_LINES:
		_append_line(line)
		if is_inside_tree():
			await get_tree().create_timer(0.10).timeout
			
	# Фаза 4: Подвисание системы (Lag / Suspense, 1.8 секунды)
	_append_text(" [ ПРОВЕРКА ] ... ")
	if is_inside_tree():
		await get_tree().create_timer(1.8).timeout
	_append_line("[ OK ]")
	
	if is_inside_tree():
		await get_tree().create_timer(0.3).timeout
		
	# Фаза 5: Откровение (Меньшая задержка, красный цвет, дрожащие буквы [shake], звук печати type_sound)
	for line in PHASE_5_LINES:
		if line.is_empty():
			_append_line("")
			if is_inside_tree():
				await get_tree().create_timer(0.12).timeout
		else:
			var is_punchline: bool = (
				line.contains("ПЕШКОЙ") or 
				line.contains("ДЕШЕВОЙ ФИГУРОЙ") or 
				line.contains("РАЗМЕНЯТЬ")
			)
			var delay: float = 0.085 if is_punchline else 0.028
			var pause_after: float = 0.45 if is_punchline else 0.14
			
			await _type_shaking_red_line(line, delay)
			if is_inside_tree():
				await get_tree().create_timer(pause_after).timeout
				
	if is_inside_tree():
		await get_tree().create_timer(0.6).timeout
		
	# Фаза 6: Смерть
	for line in PHASE_6_LINES:
		_append_line(line)
		if is_inside_tree():
			await get_tree().create_timer(0.22).timeout
			
	if is_inside_tree():
		await get_tree().create_timer(0.6).timeout
		
	revelation_finished.emit()
