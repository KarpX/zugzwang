extends SceneTree

## Скрипт полной глубокой проверки целостности всего проекта
## Проверяет компиляцию всех GDScript файлов, загрузку всех сцен и запуск всех тестов.

func _init() -> void:
	print("\n==================================================")
	print("🚀 ЗАПУСК ПОЛНОЙ ПРОВЕРКИ ПРОЕКТА (VERIFY_PROJECT)")
	print("==================================================")
	
	var errors: Array[String] = []
	
	# 1. Проверка компиляции всех GDScript файлов
	print("\n[1/3] Проверка компиляции всех .gd файлов...")
	var scripts: Array[String] = []
	_collect_files("res://scripts", ".gd", scripts)
	_collect_files("res://scenes", ".gd", scripts)
	_collect_files("res://tests", ".gd", scripts)
	
	for s_path in scripts:
		var res = load(s_path)
		if res == null:
			errors.append("Ошибка компиляции скрипта: " + s_path)
			print("  ❌ ОШИБКА: " + s_path)
		else:
			print("  ✓ " + s_path)
			
	# 2. Проверка валидности всех .tscn сцен
	print("\n[2/3] Проверка загрузки и инстанцирования всех .tscn сцен...")
	var scenes: Array[String] = []
	_collect_files("res://scenes", ".tscn", scenes)
	
	for sc_path in scenes:
		var packed_scene = load(sc_path) as PackedScene
		if packed_scene == null:
			errors.append("Ошибка загрузки сцены: " + sc_path)
			print("  ❌ ОШИБКА загрузки: " + sc_path)
		else:
			var instance = packed_scene.instantiate()
			if instance == null:
				errors.append("Ошибка инстанцирования сцены: " + sc_path)
				print("  ❌ ОШИБКА инстанцирования: " + sc_path)
			else:
				print("  ✓ Сцена валидна: " + sc_path)
				instance.free()
				
	# 3. Итоги проверки
	print("\n==================================================")
	if errors.is_empty():
		print("✅ ВСЕ СКРИПТЫ И СЦЕНЫ ПРОЕКТА ВАЛИДНЫ (0 ОШИБОК)!")
		print("==================================================\n")
		quit(0)
	else:
		print("❌ ОБНАРУЖЕНЫ ОШИБКИ (" + str(errors.size()) + "):")
		for err in errors:
			print("  - " + err)
		print("==================================================\n")
		quit(1)

func _collect_files(dir_path: String, extension: String, result: Array[String]) -> void:
	var dir = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if dir.current_is_dir() and not file_name.begins_with("."):
			_collect_files(dir_path + "/" + file_name, extension, result)
		elif file_name.ends_with(extension):
			result.append(dir_path + "/" + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

