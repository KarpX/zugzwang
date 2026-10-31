# Signal Bus Architecture (`EventBus.gd`)

## 1. Концепция
В 72-часовом гейм-джеме команда из 3 программистов рискует потратить половину времени на решение конфликтов в `.tscn` файлах и спагетти-связи между нодами.
Чтобы исключить эту проблему, используется строгий паттерн **Signal Bus**:

```
[Шахматная система]  ──emit──>  [ EventBus Autoload ]  ──receive──>  [ Бункер / Разрушение ]
                                         │
                                         └──receive──>  [ Звук / Шейдеры / UI ]
```

## 2. Спецификация сигналов `EventBus`

### Шахматы (Dev 1)
- `piece_moved(from_pos: Vector2i, to_pos: Vector2i)`: перемещение любой фигуры.
- `piece_captured(piece_type: String, is_white: bool)`: взятие фигуры.
- `game_over(winner: String)`: завершение матча ("white", "black", "breach").
- `player_made_action()`: любое осознанное действие игрока (сброс таймера стука в дверь).
- `square_selected(board_pos: Vector2i)` / `square_deselected()`: выбор клетки на доске.

### Бункер и Игрок (Dev 2)
- `camera_mode_changed(is_board_mode: bool)`: переключение между ходьбой и столом.
- `door_knock_triggered(knock_level: int)`: стук в дверь (1, 2, 3 = выбивание двери).
- `collapse_sequence_started()`: запуск финального падения стен в пустоту.

### Эскалация (Автоматически в EventBus)
- `escalation_stage_changed(stage: int, total_losses: int)`:
  - Стадия 1 (0-3 потерь): Затишье
  - Стадия 2 (4-7 потерь): Тревога
  - Стадия 3 (8-11 потерь): Осада
  - Стадия 4 (12+ потерь или мат): Коллапс

## 3. Антипаттерны (Строго запрещено!)
- Запрещено: `$../../ChessBoard/Pieces/Pawn` из скрипта игрока.
- Запрещено: `get_node("/root/Room/Camera3D")` из шахматного контроллера.
- Разрешено: `EventBus.player_made_action.emit()`
- Разрешено: `EventBus.piece_captured.connect(_on_piece_captured)`

