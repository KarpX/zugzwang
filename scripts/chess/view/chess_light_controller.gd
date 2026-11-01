class_name ChessLightController
extends RefCounted

## Контроллер динамического освещения шахматной доски
## Управляет световыми эффектами, мерцанием и перебоями освещения доски (синхронно с подвесной лампой бункера).

var board_light: OmniLight3D = null
var _board_light_tween: Tween = null

func setup(light: OmniLight3D) -> void:
	board_light = light

func reset_light() -> void:
	if _board_light_tween and _board_light_tween.is_valid():
		_board_light_tween.kill()
		_board_light_tween = null
	if board_light != null:
		board_light.light_energy = 1.0

## Синхронизация подсветки доски с перебоем света подвесной лампы
func play_flicker(sound_idx: int, parent_node: Node) -> void:
	if board_light == null or parent_node == null or not parent_node.is_inside_tree():
		return
	if _board_light_tween and _board_light_tween.is_valid():
		_board_light_tween.kill()
		
	_board_light_tween = parent_node.create_tween().set_trans(Tween.TRANS_LINEAR)
	match sound_idx:
		0: # lamp_troubles_1 (1.385s)
			_board_light_tween.tween_property(board_light, "light_energy", 0.05, 0.02)
			_board_light_tween.tween_property(board_light, "light_energy", 1.50, 0.02)
			_board_light_tween.tween_property(board_light, "light_energy", 0.00, 0.04)
			_board_light_tween.tween_interval(0.38)
			_board_light_tween.tween_property(board_light, "light_energy", 0.35, 0.04)
			_board_light_tween.tween_property(board_light, "light_energy", 0.20, 0.10)
			_board_light_tween.tween_property(board_light, "light_energy", 0.55, 0.10)
			_board_light_tween.tween_property(board_light, "light_energy", 0.30, 0.10)
			_board_light_tween.tween_property(board_light, "light_energy", 0.60, 0.06)
			_board_light_tween.tween_property(board_light, "light_energy", 1.35, 0.06)
			_board_light_tween.tween_property(board_light, "light_energy", 0.05, 0.04)
			_board_light_tween.tween_property(board_light, "light_energy", 0.15, 0.07)
			_board_light_tween.tween_property(board_light, "light_energy", 0.50, 0.07)
			_board_light_tween.tween_property(board_light, "light_energy", 0.75, 0.08)
			_board_light_tween.tween_property(board_light, "light_energy", 1.45, 0.05)
			_board_light_tween.tween_property(board_light, "light_energy", 0.90, 0.07)
			_board_light_tween.tween_property(board_light, "light_energy", 1.00, 0.085).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		1: # lamp_troubles_2 (1.846s)
			_board_light_tween.tween_property(board_light, "light_energy", 1.50, 0.01)
			_board_light_tween.tween_property(board_light, "light_energy", 0.05, 0.02)
			_board_light_tween.tween_property(board_light, "light_energy", 0.00, 0.05)
			_board_light_tween.tween_property(board_light, "light_energy", 0.35, 0.03)
			_board_light_tween.tween_property(board_light, "light_energy", 0.20, 0.09)
			_board_light_tween.tween_property(board_light, "light_energy", 0.45, 0.10)
			_board_light_tween.tween_property(board_light, "light_energy", 0.25, 0.10)
			_board_light_tween.tween_property(board_light, "light_energy", 1.65, 0.02)
			_board_light_tween.tween_property(board_light, "light_energy", 0.00, 0.05)
			_board_light_tween.tween_interval(0.53)
			_board_light_tween.tween_property(board_light, "light_energy", 1.40, 0.01)
			_board_light_tween.tween_property(board_light, "light_energy", 0.35, 0.03)
			_board_light_tween.tween_property(board_light, "light_energy", 0.60, 0.11)
			_board_light_tween.tween_property(board_light, "light_energy", 0.40, 0.10)
			_board_light_tween.tween_property(board_light, "light_energy", 0.70, 0.10)
			_board_light_tween.tween_property(board_light, "light_energy", 0.10, 0.12)
			_board_light_tween.tween_property(board_light, "light_energy", 1.50, 0.09)
			_board_light_tween.tween_property(board_light, "light_energy", 0.85, 0.09)
			_board_light_tween.tween_property(board_light, "light_energy", 1.00, 0.196).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		2: # lamp_troubles_3 (1.385s)
			_board_light_tween.tween_property(board_light, "light_energy", 0.05, 0.01)
			_board_light_tween.tween_property(board_light, "light_energy", 1.40, 0.01)
			_board_light_tween.tween_property(board_light, "light_energy", 0.00, 0.03)
			_board_light_tween.tween_interval(0.29)
			_board_light_tween.tween_property(board_light, "light_energy", 1.65, 0.01)
			_board_light_tween.tween_property(board_light, "light_energy", 0.45, 0.05)
			_board_light_tween.tween_property(board_light, "light_energy", 0.20, 0.08)
			_board_light_tween.tween_property(board_light, "light_energy", 0.50, 0.08)
			_board_light_tween.tween_property(board_light, "light_energy", 0.00, 0.06)
			_board_light_tween.tween_interval(0.20)
			_board_light_tween.tween_property(board_light, "light_energy", 1.55, 0.01)
			_board_light_tween.tween_property(board_light, "light_energy", 0.60, 0.07)
			_board_light_tween.tween_property(board_light, "light_energy", 0.80, 0.10)
			_board_light_tween.tween_property(board_light, "light_energy", 1.15, 0.15)
			_board_light_tween.tween_property(board_light, "light_energy", 1.00, 0.235).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		3: # lamp_troubles_4 (2.308s)
			_board_light_tween.tween_property(board_light, "light_energy", 0.00, 0.01)
			_board_light_tween.tween_interval(0.56)
			_board_light_tween.tween_property(board_light, "light_energy", 1.75, 0.01)
			_board_light_tween.tween_property(board_light, "light_energy", 0.60, 0.04)
			_board_light_tween.tween_property(board_light, "light_energy", 0.35, 0.06)
			_board_light_tween.tween_property(board_light, "light_energy", 0.00, 0.03)
			_board_light_tween.tween_interval(0.53)
			_board_light_tween.tween_property(board_light, "light_energy", 1.50, 0.01)
			_board_light_tween.tween_property(board_light, "light_energy", 0.00, 0.03)
			_board_light_tween.tween_interval(0.68)
			_board_light_tween.tween_property(board_light, "light_energy", 0.35, 0.03)
			_board_light_tween.tween_property(board_light, "light_energy", 1.35, 0.06)
			_board_light_tween.tween_property(board_light, "light_energy", 0.70, 0.07)
			_board_light_tween.tween_property(board_light, "light_energy", 1.10, 0.08)
			_board_light_tween.tween_property(board_light, "light_energy", 1.00, 0.108).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		-2: # Rook outage (0.85s)
			_board_light_tween.tween_property(board_light, "light_energy", 0.0, 0.03)
			_board_light_tween.tween_interval(0.42)
			_board_light_tween.tween_property(board_light, "light_energy", 1.6, 0.05)
			_board_light_tween.tween_property(board_light, "light_energy", 0.85, 0.1)
			_board_light_tween.tween_property(board_light, "light_energy", 1.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		-3: # Queen catastrophic blackout (2.5s)
			_board_light_tween.tween_property(board_light, "light_energy", 0.0, 0.02)
			_board_light_tween.tween_interval(2.05)
			_board_light_tween.tween_property(board_light, "light_energy", 0.4, 0.04)
			_board_light_tween.tween_property(board_light, "light_energy", 0.05, 0.04)
			_board_light_tween.tween_property(board_light, "light_energy", 0.8, 0.05)
			_board_light_tween.tween_property(board_light, "light_energy", 0.2, 0.05)
			_board_light_tween.tween_property(board_light, "light_energy", 1.5, 0.07)
			_board_light_tween.tween_property(board_light, "light_energy", 1.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

