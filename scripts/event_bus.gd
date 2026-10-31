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


# ==============================================================================
# 3. ЭСКАЛАЦИЯ КОМНАТЫ (4 стадии разрушения)
# ==============================================================================

## Стадия разрушения бункера (1: Затишье [0-3], 2: Тревога [4-7], 3: Осада [8-11], 4: Коллапс [12+])
signal escalation_stage_changed(stage: int, total_losses: int)


# ==============================================================================
# 4. СОСТОЯНИЕ И СЧЕТЧИКИ (State Helpers)
# ==============================================================================

var total_losses: int = 0
var white_losses: int = 0
var black_losses: int = 0
var current_stage: int = 1
var is_in_board_mode: bool = false
var is_game_finished: bool = false
var is_lamp_trouble_active: bool = false

func _ready() -> void:
	# Подключаем внутренний учет потерь к сигналу взятия фигуры
	piece_captured.connect(_on_piece_captured)
	game_over.connect(_on_game_over)
	lamp_flicker_triggered.connect(func(_idx, _dur): is_lamp_trouble_active = true)
	lamp_trouble_finished.connect(func(): is_lamp_trouble_active = false)

func _on_piece_captured(_piece_type: String, is_white: bool) -> void:
	total_losses += 1
	if is_white:
		white_losses += 1
	else:
		black_losses += 1
	
	_update_escalation_stage()

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
func reset_game_state(playthrough: int = 1) -> void:
	total_losses = 0
	white_losses = 0
	black_losses = 0
	current_stage = 1
	is_game_finished = false
	game_reset.emit(playthrough)
	is_lamp_trouble_active = false
