# AGENTS.md — Настройки и инструкции для ИИ-агентов проекта «Белый Король»

> **Проект**: «Белый Король» (White King / Zugzwang)  
> **Стек**: Godot 4.7 Forward+ (3D, GDScript 2.0)  
> **Формат**: 72-часовой гейм-джем  
> **Команда**: 3 программиста (0 художников)  
> **Архитектурный стандарт**: ECC Universal (Everything Code / Agent Operating System)

---

## 1. High Concept и ключевая идея проекта

Игрок — главнокомандующий, запертый в сером железобетонном бункере 5x5 метров. В центре комнаты — грубый деревянный стол с шахматами, над которым нервно раскачивается одинокая лампа.

Игрок играет партию в шахматы против безликой войны (черные фигуры перемещаются сами со зловещим скрежетом). Каждая взятая фигура означает тысячи смертей и приближение фронта к бункеру. 

### Ключевая метафора
Война уничтожает всё вокруг независимо от того, кто «побеждает» на доске. Если побеждать — мир снаружи сгорает дотла. Если бездействовать — враг выбивает дверь бункера («The Knock»). В финале игрок осознает, что он сам лишь фигура на доске.

Подробный дизайн-документ находится в [`docs/GDD.md`](file:///Users/nikitaprime/GodotProjects/zugzwang/docs/GDD.md).

---

## 2. Архитектурная заповедь №1: Signal Bus (Zero-Git-Conflict)

Чтобы 3 разработчика и параллельные ИИ-агенты работали одновременно без конфликтов слияния в Git:

```
┌─────────────────────────────────────────────────────────────┐
│                    EventBus (Autoload)                      │
│                   res://scripts/event_bus.gd                │
└───────▲─────────────────────▲─────────────────────▲─────────┘
        │                     │                     │
┌───────┴─────────────┐┌──────┴─────────────┐┌──────┴─────────┐
│     Dev 1: Chess    ││    Dev 2: Bunker   ││  Dev 3: Audio  │
│  - scenes/chess/    ││  - scenes/bunker/  ││  - scenes/ui/  │
│  - scripts/chess/   ││  - scenes/player/  ││  - assets/sfx/ │
│  - tests/chess/     ││  - scripts/world/  ││  - shaders/    │
└─────────────────────┘└────────────────────┘└────────────────┘
```

### Железные правила изоляции:
1. **Никаких прямых ссылок (`get_node("../...")`, `$Node`) между модулями разных разработчиков!**
   - Dev 1 не имеет права обращаться к ноде бункера или звука.
   - Dev 2 не имеет права обращаться к ноде шахматной доски напрямую.
   - Dev 3 подписывается на сигналы `EventBus`, а не лезет внутрь логики фигур.
2. **Вся связь — исключительно через синглтон `EventBus`**:
   - `EventBus.piece_moved.emit(from_pos, to_pos)`
   - `EventBus.piece_captured.emit(piece_type, is_white)`
   - `EventBus.game_over.emit(winner)`
   - `EventBus.player_made_action.emit()`
   - `EventBus.escalation_stage_changed.emit(stage, total_losses)`
   - `EventBus.door_knock_triggered.emit(knock_level)`
   - `EventBus.camera_mode_changed.emit(is_board_mode)`
3. **Разделение файловой системы**:
   - Каждый Dev и агент пишет только в свою назначенную директорию.
   - Главная сборная сцена `scenes/room.tscn` только инстанцирует под-сцены (`scenes/bunker/bunker_room.tscn`, `scenes/chess/chess_table.tscn`, `scenes/ui/hud_overlay.tscn`).

---

## 3. Роли команды и специализированные субагенты

| Субагент | Зона ответственности | Рабочая директория | Сигналы EventBus |
|---|---|---|---|
| `@dev1-chess-ai` | Логика шахмат 8x8, генерация ходов, клик/рейкаст, жадный Minimax ИИ (частые размены), Tween-анимация фигур по доске. | `scenes/chess/`<br>`scripts/chess/`<br>`tests/chess/` | **Эмитит**: `piece_moved`, `piece_captured`, `game_over`, `square_selected`, `player_made_action` |
| `@dev2-bunker-world` | CSGBox3D геометрия бункера, контроллер игрока (ходьба + Tween камеры за стол), таймер бездействия (25с, 45с, 60с стук), 4 стадии разрушения бункера, финальный коллапс стен в пустыню. | `scenes/bunker/`<br>`scenes/player/`<br>`scripts/world/` | **Эмитит**: `door_knock_triggered`, `camera_mode_changed`, `collapse_sequence_started`<br>**Слушает**: `escalation_stage_changed`, `piece_captured`, `player_made_action` |
| `@dev3-audio-juice-ui` | Аудио-шина, CC0 звуки (стуки, скрежет фигур, радиопомехи, взрывы), экранные шейдеры (Film grain, Aberration, Vignette), Screen Shake при взятиях и стуках, радио-сводки (субтитры). | `scenes/ui/`<br>`scenes/effects/`<br>`shaders/`<br>`assets/audio/` | **Слушает**: `piece_captured`, `door_knock_triggered`, `escalation_stage_changed`, `piece_moved` |
| `@jam-architect` | Ревью архитектуры, защита неизменности `EventBus.gd`, разрешение git-конфликтов, запуск тестов, проверка готовности релизных билдов (Web / Windows). | Корень, `autoload/`, `project.godot` | Хранитель стандартов и релизных критериев |

---

## 4. Стандарты кода Godot 4 и GDScript 2.0

1. **Строгая статическая типизация**:
   - Все переменные и возвращаемые значения функций должны иметь тип:
     ```gdscript
     var board_pos: Vector2i = Vector2i.ZERO
     func make_move(from_pos: Vector2i, to_pos: Vector2i) -> bool:
     ```
2. **Экспорт параметров для геймдизайна**:
   - Используйте `@export`, `@export_range`, `@export_enum`:
     ```gdscript
     @export_range(1.0, 20.0, 0.5) var move_speed: float = 7.0
     @export var idle_knock_intervals: Array[float] = [25.0, 45.0, 60.0]
     ```
3. **Безопасная работа с Tween (Godot 4)**:
   - Всегда проверяйте или перезаписывайте активный твин:
     ```gdscript
     var _move_tween: Tween = null
     func animate_piece(target_pos: Vector3) -> void:
         if _move_tween and _move_tween.is_valid():
             _move_tween.kill()
         _move_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
         _move_tween.tween_property(self, "global_position", target_pos, 0.4)
     ```
4. **Не засоряйте `_process` и `_physics_process`**:
   - В `_physics_process` — только расчет движения `CharacterBody3D` (`move_and_slide()`).
   - Все события должны быть реактивными (сигналы, таймеры, `_unhandled_input`), а не проверяться каждый кадр через `if`.
5. **Арт без художников**:
   - Геометрия: Godot `CSGBox3D` / `CSGCombiner3D`.
   - Свет: 1 точечный/omni источник над столом (`shadow_enabled = true`).
   - Атмосфера: `WorldEnvironment` с Volumetric Fog + Post-processing шейдеры.

---

## 5. Интеграция с живым Godot MCP сервером

В проекте активен Godot MCP сервер (`addons/godot_mcp` на `ws://127.0.0.1:6505`). Подробное руководство по всем возможностям: [`docs/GODOT_MCP.md`](file:///Users/nikitaprime/GodotProjects/zugzwang/docs/GODOT_MCP.md).

Агенты обязаны использовать инструменты MCP перед коммитом изменений:

1. **Валидация скриптов и обновление файлов**:
   - Вызывайте `godot:validate_script(path="res://...")` для проверки синтаксиса GDScript в реальном движке.
   - Если файлы созданы внешним редактором, вызовите `godot:rescan_filesystem` для обновления дерева редактора.
2. **Инспекция и редактирование сцен**:
   - `godot:scene_tree_dump()` — дамп иерархии нод открытой сцены.
   - `godot:read_scene(path="res://...")` — чтение структуры `.tscn` с диска.
   - `godot:add_node`, `godot:set_node_properties`, `godot:instance_scene` — манипуляции нодами без открытия UI редактора.
   - `godot:classdb_query` — справка по свойствам, методам и сигналам любого встроенного класса Godot.
3. **Проверка ошибок выполнения**:
   - `godot:get_errors()` и `godot:get_console_log(limit=50)` для поиска падений, ошибок линковки и предупреждений движка.
4. **Интерактивный тестовый цикл (Runtime Testing Loop)**:
   - `godot:run_scene(scene_path="res://scenes/...", wait_for_runtime=true)` — запуск игры с ожиданием подключения `MCPRuntime`.
   - `godot:send_input(event=...)` — эмуляция действий игрока (WASD, клики мыши по фигурам, клавиша E).
   - `godot:query_runtime_node(node_path="/root/...", properties=[...])` — чтение живого состояния переменных в памяти запущенной игры.
   - `godot:take_screenshot()` — снятие скриншота игры для визуальной проверки освещения, тумана, UI и шейдеров.
   - `godot:stop_scene()` — чистая остановка процесса перед дальнейшим редактированием.

---

## 6. 72-часовой спринт-план (Почасовые контрольные точки)

### [День 1: 0–24 ч] — Фундамент
- [x] Создан синглтон `EventBus.gd` и зарегистрирован в `project.godot`.
- [ ] **Dev 1**: Сетка шахматной доски 8x8, правила ходов пешек и фигур, raycast-клик с подсветкой.
- [ ] **Dev 2**: 3D бункер (бетонные стены CSG, стол, лампа), контроллер первого лица + Tween посадки за стол.
- [ ] **Dev 3**: Настройка WorldEnvironment (объемный туман, кинематографичный свет), база звуков и шин (Master / SFX / Ambience).
- **Критерий готовности Дня 1**: Игрок может подойти к столу, сесть за него по `E` и сделать первый легальный ход белой пешкой.

### [День 2: 24–48 ч] — Интеграция и Эскалация
- [ ] **Dev 1**: ИИ черных с жадной эвристикой разменов, анимация скрежета фигур по доске.
- [ ] **Dev 2**: Таймер бездействия `DoorKnockTimer` (25с / 45с / 60с штурм), трещины на стенах при росте потерь.
- [ ] **Dev 3**: Радио-сообщения при взятиях ("Связь с 4-й ротой потеряна!"), тряска камеры (CameraShake3D), экранная тревога.
- **Критерий готовности Дня 2**: Полный игровой цикл: партия играется, паузы наказываются стуком в дверь, комната разрушается по стадиям I–IV.

### [День 3: 48–72 ч] — Финал, Полишинг и Релиз
- [ ] **Dev 1 & 2**: Финальная катсцена: обрушение стен бункера наружу при мате/взятии короля, показ пустоты.
- [ ] **Dev 3**: Финальный аудио-микс (гул, тишина при коллапсе, похоронный ветер), экран титров.
- [ ] **Jam Lead**: Экспорт релизных билдов (HTML5 / Windows / Linux), проверка на чистой машине, отправка на itch.io.
- **Критерий готовности Дня 3**: Готовый, оттестированный билд за 2 часа до дедлайна.

---

## 7. Git-дисциплина и конвенция коммитов

Ветка `dev` является интеграционной. Каждая фича разрабатывается в изолированной ветке:
- `feat/dev1-chess-rules`
- `feat/dev2-bunker-cracks`
- `feat/dev3-audio-foley`

Формат сообщений коммитов (ECC standard):
```
<type>(<scope>): <краткое описание на русском или английском>

Примеры:
feat(chess): реализована матрица 8x8 и валидация ходов пешек
feat(bunker): добавлен DoorKnockTimer на 25/45/60 секунд
feat(audio): добавлены звуки скрежета фигур и стука в стальную дверь
refactor(bus): обновлен payload сигнала escalation_stage_changed
```

