# Godot 4 & GDScript 2.0 Coding Standards

## 1. Статическая типизация
В GDScript 2.0 (Godot 4) строгая типизация обеспечивает автодополнение, раннее обнаружение ошибок и максимальную производительность компилятора:

```gdscript
# Правильно:
var current_turn_is_white: bool = true
var board_matrix: Array[Array] = []
var selected_square: Vector2i = Vector2i(-1, -1)

func is_cell_valid(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < 8 and pos.y >= 0 and pos.y < 8
```

## 2. Использование аннотаций
- `@export`: вынесение настроек в инспектор Godot для баланса игры без правки кода.
- `@export_range(min, max, step)`: безопасный диапазон для скоростей, таймеров и громкости.
- `@onready`: ссылки на дочерние ноды строго с указанием типа:
  ```gdscript
  @onready var anim_player: AnimationPlayer = $AnimationPlayer
  @onready var light: OmniLight3D = $OmniLight3D
  ```

## 3. Управление Tween (Godot 4)
В Godot 4 устарел `Tween.interpolate_property()`. Используется `create_tween()`:

```gdscript
var _active_tween: Tween = null

func smooth_move_to(target_pos: Vector3, duration: float = 0.3) -> void:
	if _active_tween and _active_tween.is_valid():
		_active_tween.kill()
	_active_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_active_tween.tween_property(self, "global_position", target_pos, duration)
```

## 4. Разделение физики и логики
- `_physics_process(delta)`: ТОЛЬКО физическое перемещение `CharacterBody3D` (`move_and_slide()`) и гравитация.
- `_process(delta)`: визуальные эффекты (раскачивание лампы по синусоиде, мерцание).
- `_unhandled_input(event)`: обработка кликов мыши, нажатий клавиш (чтобы UI мог перехватывать ввод).

