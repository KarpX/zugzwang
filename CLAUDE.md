# CLAUDE.md — Руководство разработчика для проекта «Белый Король»

> Проект: **Белый Король (White King / Zugzwang)**  
> Движок: **Godot 4.7 Forward+ (3D)**  
> Формат: **72-часовой гейм-джем**  
> Главная цель: Психологический триллер / шахматная антивоенная драма в бункере.

---

## Быстрые команды (Quick Reference)

### Запуск и тестирование через Godot CLI (macOS)
```bash
# Псевдоним или прямой путь к бинарнику:
# /Applications/Godot.app/Contents/MacOS/Godot

# Запуск главной сцены
/Applications/Godot.app/Contents/MacOS/Godot --path .

# Запуск изолированной тестовой сцены шахмат
/Applications/Godot.app/Contents/MacOS/Godot --path . scenes/chess/chess_table.tscn

# Запуск изолированной сцены бункера
/Applications/Godot.app/Contents/MacOS/Godot --path . scenes/bunker/bunker_room.tscn

# Запуск headless тестов GDScript
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s tests/run_tests.gd
```

### Интерактивная работа через Godot MCP (порт 6505)
Подробное руководство: [`docs/GODOT_MCP.md`](docs/GODOT_MCP.md)
Ключевые инструменты MCP:
- `godot:validate_script(path="res://...")` — обязательная проверка синтаксиса GDScript перед коммитом.
- `godot:rescan_filesystem()` — обновление дерева файлов редактора после правок на диске.
- `godot:scene_tree_dump()` / `read_scene` — инспекция дерева открытой сцены или сцены на диске.
- `godot:run_scene(scene_path="...", wait_for_runtime=true)` — запуск игры с ожиданием подключения helper-рантайма.
- `godot:send_input(event=...)` — посылка действий (WASD, клики мыши, Action).
- `godot:query_runtime_node(node_path="...", properties=[...])` — чтение живого состояния ноды в запущенной игре.
- `godot:take_screenshot()` — снятие скриншота запущенной игры.
- `godot:stop_scene()` — остановка игры.
- `godot:get_errors()` / `get_console_log(limit=50)` — просмотр ошибок и вывода консоли.

---

## Архитектурные правила

1. **Signal Bus First (`EventBus.gd`)**:
   - Все события между модулями (шахматы, бункер, аудио, UI) передаются **только** через синглтон `EventBus`.
   - Никогда не используйте относительные пути `$../../` между модулями разных разработчиков.
2. **Зоны ответственности**:
   - `Dev 1` (Шахматы и ИИ): `scenes/chess/`, `scripts/chess/`, `tests/chess/`
   - `Dev 2` (Бункер, Игрок, Разрушение): `scenes/bunker/`, `scenes/player/`, `scripts/world/`
   - `Dev 3` (Аудио, Шейдеры, UI): `scenes/ui/`, `scenes/effects/`, `shaders/`, `assets/audio/`
3. **GDScript 2.0 Стандарты**:
   - Обязательная статическая типизация: `var pos: Vector2i = Vector2i.ZERO`
   - Параметры в инспектор через `@export`, `@export_range`
   - Плавные перемещения через `create_tween().set_trans(...)`
   - Никаких "тяжелых" вычислений в `_process` — используйте реактивные сигналы `EventBus`.

---

## Подробная документация
- Полный дизайн-документ (GDD): [`docs/GDD.md`](docs/GDD.md)
- Инструкция для ИИ-агентов: [`AGENTS.md`](AGENTS.md)
- Правила архитектуры: [`.agents/rules/signal-bus-architecture.md`](.agents/rules/signal-bus-architecture.md)
