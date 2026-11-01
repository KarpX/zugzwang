class_name ChessDebugHUD
extends RefCounted

## Отладочный HUD для шахматного модуля Zugzwang
## Отображает состояние партии, текущий режим сложности, скорость ходов, оценку ИИ и статус бункера.

const ChessLogicScript = preload("res://scripts/chess/chess_logic.gd")
const ChessBotScript = preload("res://scripts/chess/chess_bot.gd")

var parent_node: Node3D = null
var debug_hud_canvas: CanvasLayer = null
var debug_hud_panel: PanelContainer = null
var debug_hud_label: RichTextLabel = null
var is_hud_visible: bool = true

func setup(parent: Node3D) -> void:
	parent_node = parent
	_setup_canvas()

func toggle_visibility() -> void:
	is_hud_visible = not is_hud_visible
	if debug_hud_canvas != null and is_instance_valid(debug_hud_canvas):
		debug_hud_canvas.visible = is_hud_visible

func set_visible(vis: bool) -> void:
	is_hud_visible = vis
	if debug_hud_canvas != null and is_instance_valid(debug_hud_canvas):
		debug_hud_canvas.visible = is_hud_visible

func is_visible() -> bool:
	return is_hud_visible

func _setup_canvas() -> void:
	if parent_node == null or not parent_node.is_inside_tree():
		return
	if debug_hud_canvas != null and is_instance_valid(debug_hud_canvas):
		return
		
	var canvas = CanvasLayer.new()
	canvas.name = "DebugHUDCanvas"
	canvas.layer = 12
	parent_node.add_child(canvas)
	debug_hud_canvas = canvas
	
	var panel = PanelContainer.new()
	panel.name = "DebugPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 16.0
	panel.offset_top = 16.0
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.12, 0.88)
	style.border_color = Color(0.2, 0.7, 0.9, 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 14.0
	style.content_margin_top = 10.0
	style.content_margin_right = 14.0
	style.content_margin_bottom = 10.0
	panel.add_theme_stylebox_override("panel", style)
	canvas.add_child(panel)
	debug_hud_panel = panel
	
	var label = RichTextLabel.new()
	label.name = "DebugLabel"
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.custom_minimum_size = Vector2(340, 190)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	debug_hud_label = label

## Обновление текстового содержимого отладочной панели
func update(logic: RefCounted,
		is_fast_mode: bool,
		is_ai_calculating: bool,
		is_ai_thinking: bool,
		bus: Node) -> void:
	if not is_hud_visible:
		return
	if debug_hud_label == null:
		_setup_canvas()
	if debug_hud_label == null:
		return
		
	var pt: int = logic.get("playthrough") if logic else 1
	var pt_color: String = "#ff5555" if pt == 1 else "#55ff88"
	var pt_name: String = "МАТЧ 1: ХИЩНЫЙ ИИ (Hard)" if pt == 1 else "МАТЧ 2: ПОДДАВКИ (Medium)"
	
	var speed_text: String = "[color=#ffd700]⚡ 0.05с (БЫСТРО)[/color]" if is_fast_mode else "[color=#aaaaaa]0.8с (Норма)[/color]"
	var turn_text: String = "[color=#ffffff]Белые (Игрок)[/color]" if (logic and logic.get("is_white_turn") == true) else "[color=#ff8888]Черные (ИИ)[/color]"
	var ai_status: String = "[color=#88ff88]Ожидание[/color]"
	if is_ai_calculating:
		ai_status = "[color=#ffaa00]⚡ Просчет (в полете)...[/color]"
	elif is_ai_thinking:
		ai_status = "[color=#ff5555]Ходит...[/color]"
	
	var w_mat: int = 0
	var b_mat: int = 0
	if logic:
		for x in range(8):
			for y in range(8):
				var p = logic.get_piece(Vector2i(x, y))
				if p != null and p.get("type", "") != "king":
					var val: int = ChessLogicScript.PIECE_VALUES.get(p.get("type", ""), 0)
					if p.get("is_white", false):
						w_mat += val
					else:
						b_mat += val
	var diff: int = w_mat - b_mat
	var diff_str: String = ("+" if diff > 0 else "") + str(diff)
	var diff_color: String = "#88ffaa" if diff > 0 else ("#ff8888" if diff < 0 else "#cccccc")
	
	var losses: int = bus.get("total_losses") if (bus and "total_losses" in bus) else 0
	var stage: int = bus.get("current_stage") if (bus and "current_stage" in bus) else 1
	
	var bot_info: Dictionary = ChessBotScript.last_search_info
	var eval_score: float = bot_info.get("score", 0.0)
	var search_depth: int = bot_info.get("depth", 0)
	
	var text: String = "[b][color=#33ccff]⚙ ОТЛАДКА ШАХМАТ (ZUGZWANG)[/color][/b]\n"
	text += "Режим: [color=%s][b]%s[/b][/color]\n" % [pt_color, pt_name]
	text += "Скорость ходов: %s\n" % speed_text
	text += "Ход #%d: %s | ИИ: %s\n" % [logic.get("move_count") if logic else 0, turn_text, ai_status]
	text += "Материал: Белые %d | Черные %d ([color=%s]%s[/color])\n" % [w_mat, b_mat, diff_color, diff_str]
	text += "Оценка ИИ: [color=#88ffaa]%.1f cp[/color] (глубина %d)\n" % [eval_score, search_depth]
	text += "Бункер: Потери %d/16 | Стадия тревоги %d/4\n" % [losses, stage]
	text += "[color=#445566]──────────────────────────────────[/color]\n"
	text += "[color=#bbccdd][b][F1][/b] Матч 1 | [b][F2][/b] Матч 2 | [b][F3][/b] Скорость | [b][F4][/b] Скрыть[/color]"
	
	debug_hud_label.text = text
