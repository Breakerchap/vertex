extends Node

var selected_level: String = ""

const PROGRESS_FILE := "user://level_progress.cfg"
const CUSTOM_LEVELS := "user://levels"

func _ready() -> void:
  if not OS.has_feature("pc") or DisplayServer.get_name() == "headless" or Engine.is_embedded_in_editor(): return
  var window := get_window()
  var screen := window.current_screen
  var usable := DisplayServer.screen_get_usable_rect(screen)
  if not usable.has_area(): return
  var scale := DisplayServer.screen_get_max_scale() if OS.has_feature("macos") else 1.0
  var current_size := window.size
  var limit := Vector2i(Vector2(usable.size) * 0.9)
  window.min_size = Vector2i(Vector2(800, 500) * scale).min(limit)
  if window.mode != Window.MODE_WINDOWED or current_size != window.content_scale_size: return
  var preferred := Vector2(window.content_scale_size) * scale
  var fit := minf(1.0, minf(limit.x / preferred.x, limit.y / preferred.y))
  var initial_size := Vector2i(preferred * fit)
  if initial_size != window.size:
    window.size = initial_size
    window.position = usable.position + Vector2i(Vector2(usable.size - window.size) * 0.5)

func ensure_custom_levels() -> Error:
  return DirAccess.make_dir_recursive_absolute(CUSTOM_LEVELS)

func best_stars(level_path: String) -> int:
  var progress := ConfigFile.new()
  if progress.load(PROGRESS_FILE) != OK: return 0
  return _stored_stars(progress, level_path)

func record_best_stars(level_path: String, stars: int) -> void:
  var progress := ConfigFile.new()
  var loaded := progress.load(PROGRESS_FILE) == OK
  var previous := _stored_stars(progress, level_path) if loaded else 0
  if stars > previous:
    progress.set_value("stars", level_path, clampi(stars, 0, 3))
    var error := progress.save(PROGRESS_FILE)
    if error != OK: push_warning("Could not save level progress: " + error_string(error))

func _stored_stars(progress: ConfigFile, level_path: String) -> int:
  return clampi(int(progress.get_value("stars", level_path, 0)), 0, 3)

func level_paths() -> Array[String]:
  var result: Array[String] = []
  for directory in ["res://Levels", CUSTOM_LEVELS]:
    if not DirAccess.dir_exists_absolute(directory): continue
    var files := DirAccess.get_files_at(directory)
    files.sort()
    for file in files:
      if file.to_lower().ends_with(".level"):
        result.append(directory + "/" + file)
  return result

func next_level_path(current: String) -> String:
  var paths := level_paths()
  var index := paths.find(current)
  if index < 0: return ""
  for i in range(index + 1, paths.size()):
    if not LevelParser.parse(FileAccess.get_file_as_string(paths[i])).has("error"):
      return paths[i]
  return ""
