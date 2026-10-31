# Zero-Git-Conflict Protocol (72h Game Jam)

## 1. Проблема
В Godot файлы `.tscn` (текстовые сцены) генерируют неразрешимые конфликты слияния при параллельном редактировании одной сцены несколькими разработчиками.

## 2. Изоляция файловой структуры

```
 zugzwang/
 ├── autoload/
 │   └── event_bus.gd             # ТОЛЬКО по согласованию всей команды!
 ├── scenes/
 │   ├── chess/                   # Dev 1 ONLY (шахматная доска, фигуры, клетки)
 │   ├── bunker/                  # Dev 2 ONLY (стены бункера, дверь, лампа, стол)
 │   ├── player/                  # Dev 2 ONLY (контроллер от первого лица)
 │   ├── ui/                      # Dev 3 ONLY (HUD, субтитры, титры)
 │   ├── effects/                 # Dev 3 ONLY (шейдеры постобработки, частицы)
 │   └── room.tscn                # Сборная сцена: ТОЛЬКО инстанцирование под-сцен
 ├── scripts/
 │   ├── chess/                   # Dev 1 ONLY
 │   ├── world/                   # Dev 2 ONLY
 │   └── audio/                   # Dev 3 ONLY
 └── assets/
     ├── chess/                   # 3D модели фигур
     ├── bunker/                  # Текстуры/материалы бункера
     └── audio/                   # SFX и фоны (Dev 3)
```

## 3. Правила работы с ветками
- Ветка `dev` — стабильная интеграционная ветка.
- Ветки фич:
  - `feat/dev1-chess-*`
  - `feat/dev2-bunker-*`
  - `feat/dev3-audio-ui-*`
- Перед мерджем в `dev`:
  1. `git fetch origin dev`
  2. `git rebase origin/dev`
  3. Проверка запуска через Godot CLI: `godot --path .` или запуск под-сцены.

