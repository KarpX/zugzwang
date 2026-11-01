class_name EventBusAutoload
extends Node

## EventBus — Центральная шина сигналов проекта «Белый Король» (White King)
## Архитектурное ядро для предотвращения git-конфликтов между Dev 1, Dev 2 и Dev 3.
## Зарегистрирован как Autoload (синглтон `EventBus`).

# ==============================================================================
# 1. ШАХМАТНЫЕ СИГНАЛЫ (Эмитятся Dev 1: Chess System)
# ==============================================================================

## Вызывается при любом успешном перемещении фигуры
signal piece_moved(from_pos: Vector2i, to_pos: Vector2i)

## Вызывается при взятии фигуры любой из сторон
## piece_type: "pawn", "knight", "bishop", "rook", "queen", "king"
## is_white: true для белой фигуры, false для черной
signal piece_captured(piece_type: String, is_white: bool)

## Окончание игры: "white" (мат черным), "black" (мат белым), "breach" (выбили дверь)
signal game_over(winner: String)

## Вызывается при перезапуске партии и сбросе расстановки фигур
signal game_reset(playthrough: int)

## Вызывается при любом осознанном действии игрока (сброс таймера стука в дверь)
signal player_made_action()

## Изменение выбранной клетки на доске (для UI подсказок и звука клика)
signal square_selected(board_pos: Vector2i)
signal square_deselected()


# ==============================================================================
# 2. СИГНАЛЫ ОКРУЖЕНИЯ И ИГРОКА (Эмитятся Dev 2: Bunker & Player)
# ==============================================================================

## Смена режима камеры: true — за шахматным столом, false — свободная ходьба
signal camera_mode_changed(is_board_mode: bool)

## Стуки в дверь бункера:
## knock_level 1 (25 сек бездействия): одиночный удар снаружи
## knock_level 2 (45 сек бездействия): серия яростных ударов
## knock_level 3 (60 сек бездействия): дверь выбита, штурм бункера
signal door_knock_triggered(knock_level: int)

## Запуск финальной катсцены обрушения стен
signal collapse_sequence_started()

## Перебой со светом (индекс звука 0..3 и длительность перебоя в секундах)
signal lamp_flicker_triggered(sound_index: int, duration: float)

## Завершение анимации перебоя со светом (свет полностью восстановлен)
signal lamp_trouble_finished()

## Сигналы вступительного дисклеймера и брифинга
signal intro_sequence_started()
signal intro_sequence_finished()

## Сигналы финала и концовок
signal ending_sequence_started(ending_type: String)
signal white_victory_door_opened()
signal secret_room_entered()


# ==============================================================================
# 3. ЭСКАЛАЦИЯ КОМНАТЫ (4 стадии разрушения)
# ==============================================================================

## Стадия разрушения бункера (1: Затишье [0-3], 2: Тревога [4-7], 3: Осада [8-11], 4: Коллапс [12+])
signal escalation_stage_changed(stage: int, total_losses: int)

## Обновление очков ценности армий (is_white, new_score от 40 до 0)
signal score_updated(is_white: bool, new_score: int)


# ==============================================================================
# 4. СОБЫТИЯ ВНЕШНЕГО МИРА (Потери врага / Черные фигуры)
# ==============================================================================

## Потеря фигуры врага (piece_type, оставшийся black_score от 40 до 0)
signal enemy_loss_triggered(piece_type: String, black_score: int)

## Макро-стадия эскалации внешнего мира (0: Затишье [40-31], 1: Дыхание фронта [<=30], 2: Пожар [<=20], 3: Мертвый эфир [<=10], 4: Пустыня [<=3])
signal outside_stage_changed(stage: int, black_score: int)

## Сейсмический импульс / подземный толчок от взрывов снаружи
signal seismic_shock_triggered(intensity: float, is_subterranean: bool)

## Световой отблеск под дверью и вентиляцией от взрывов снаружи
signal door_light_flash(color: Color, duration: float, intensity: float)


# ==============================================================================
# 5. РАДИО И ГОЛОСОВОЙ ЭФИР (Radio & Voice Transmission)
# ==============================================================================

## Запрос на воспроизведение радио-сообщения (текст фразы, принадлежность белым/черным)
signal radio_phrase_triggered(text: String, is_white: bool)

## Старт радиоэфира с передачей фактической длительности аудиопотока для синхронизации
signal radio_transmission_started(text: String, stream: AudioStream, duration: float)

## Окончание радиопередачи голоса
signal radio_transmission_finished()


# ==============================================================================
# 6. СОСТОЯНИЕ И СЧЕТЧИКИ (State Helpers)
# ==============================================================================

const PIECE_VALUES: Dictionary = {
	"pawn": 1,
	"knight": 3,
	"bishop": 3,
	"rook": 5,
	"queen": 10,
	"king": 0
}

var total_losses: int = 0
var white_losses: int = 0
var black_losses: int = 0
var white_score: int = 40
var black_score: int = 40
var current_stage: int = 1
var outside_stage: int = 0
var is_in_board_mode: bool = false
var is_game_finished: bool = false
var is_lamp_trouble_active: bool = false
var is_intro_active: bool = false

# Persistent state across scene reloads
var restart_quote: String = ""
var death_count: int = 0
var player_losses: int = 0
var current_playthrough: int = 1

const DEFEAT_QUOTES: Array[String] = [
	"«Смерть не освобождает от службы. Расставь фигуры заново.»",
	"«Ты помнишь каждый свой неверный шаг. Сделай следующий ход.»",
	"«Партия не завершена, пока ты помнишь правила. Попробуй снова.»",
	"«Каждый раз, когда ты падаешь, война начинается сначала.»",
	"«Король пал. Но доска осталась на месте. Играй.»"
]

const DRAW_QUOTES: Array[String] = [
	"«Война не принимает ничьих. Защищай короля до конца.»",
	"«Пат — это не мир. Это приговор обоим. Начни сначала.»"
]

func get_random_defeat_quote() -> String:
	return DEFEAT_QUOTES[randi() % DEFEAT_QUOTES.size()]

func get_random_draw_quote() -> String:
	return DRAW_QUOTES[randi() % DRAW_QUOTES.size()]

func _ready() -> void:
	# Подключаем внутренний учет потерь к сигналу взятия фигуры
	piece_captured.connect(_on_piece_captured)
	game_over.connect(_on_game_over)
	lamp_flicker_triggered.connect(func(_idx, _dur): is_lamp_trouble_active = true)
	lamp_trouble_finished.connect(func(): is_lamp_trouble_active = false)

func _on_piece_captured(piece_type: String, is_white: bool) -> void:
	total_losses += 1
	var piece_val: int = PIECE_VALUES.get(piece_type.to_lower(), 0)
	if is_white:
		white_losses += 1
		white_score = maxi(0, white_score - piece_val)
		score_updated.emit(true, white_score)
	else:
		black_losses += 1
		black_score = maxi(0, black_score - piece_val)
		score_updated.emit(false, black_score)
		enemy_loss_triggered.emit(piece_type.to_lower(), black_score)
		_update_outside_stage()
	
	_update_escalation_stage()

func _update_outside_stage() -> void:
	var new_outside_stage: int = 0
	if black_score <= 3:
		new_outside_stage = 4
	elif black_score <= 10:
		new_outside_stage = 3
	elif black_score <= 20:
		new_outside_stage = 2
	elif black_score <= 30:
		new_outside_stage = 1
	else:
		new_outside_stage = 0

	if new_outside_stage != outside_stage:
		outside_stage = new_outside_stage
		outside_stage_changed.emit(outside_stage, black_score)

func _update_escalation_stage() -> void:
	var new_stage: int = 1
	if total_losses >= 12:
		new_stage = 4
	elif total_losses >= 8:
		new_stage = 3
	elif total_losses >= 4:
		new_stage = 2
	else:
		new_stage = 1
		
	if new_stage != current_stage:
		current_stage = new_stage
		escalation_stage_changed.emit(current_stage, total_losses)

func _on_game_over(_winner: String) -> void:
	is_game_finished = true
	# Мат форсирует финальную стадию коллапса
	if current_stage < 4:
		current_stage = 4
		escalation_stage_changed.emit(current_stage, total_losses)

## Сброс состояния для перезапуска партии
func reset_game_state(playthrough: int = -1) -> void:
	if playthrough > 0:
		current_playthrough = playthrough
	total_losses = 0
	white_losses = 0
	black_losses = 0
	white_score = 40
	black_score = 40
	current_stage = 1
	outside_stage = 0
	is_game_finished = false
	is_lamp_trouble_active = false
	escalation_stage_changed.emit(1, 0)
	outside_stage_changed.emit(0, 40)
	game_reset.emit(current_playthrough)
