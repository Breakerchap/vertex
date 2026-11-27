extends Node

var selected_level: String = ""

const PROGRESS_FILE := "user://level_progress.cfg"
const CUSTOM_LEVELS := "user://levels"

var desktop_view_size: Vector2i

func _ready() -> void:
  migrate_custom_level_rates()
  desktop_view_size = get_window().content_scale_size
  get_window().size_changed.connect(_update_window_scale)
  _update_window_scale()
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

func _update_window_scale() -> void:
  var window := get_window()
  if window.size.x <= 0 or window.size.y <= 0: return
  var aspect := float(window.size.x) / window.size.y
  var target := desktop_view_size
  if aspect < 1.15:
    target = Vector2i(480, roundi(480.0 / aspect))
  elif OS.has_feature("mobile") or DisplayServer.is_touchscreen_available():
    target = Vector2i(roundi(540.0 * aspect), 540)
  if target != window.content_scale_size:
    window.content_scale_size = target

func ensure_custom_levels() -> Error:
  return DirAccess.make_dir_recursive_absolute(CUSTOM_LEVELS)

## Migrate writable custom levels once, keeping the original beside them.
func migrate_custom_level_rates() -> void:
  if not DirAccess.dir_exists_absolute(CUSTOM_LEVELS): return
  for name in DirAccess.get_files_at(CUSTOM_LEVELS):
    if name.to_lower().ends_with(".level"):
      migrate_level_file(CUSTOM_LEVELS.path_join(name))

func migrate_level_file(path: String) -> bool:
  var original := FileAccess.get_file_as_string(path)
  var updated := LevelParser.migrate_rates(original)
  if updated == original: return false
  # Keep the earlier pre-tick backup intact if this file was migrated before.
  var backup := path + ".pre-period.bak"
  if not FileAccess.file_exists(backup):
    var copied := DirAccess.copy_absolute(path, backup)
    if copied != OK:
      push_warning("Could not back up level before rate migration: " + path)
      return false
  var temporary := path + ".rate-migration.tmp"
  var file := FileAccess.open(temporary, FileAccess.WRITE)
  if file == null:
    push_warning("Could not write migrated level: " + path)
    return false
  file.store_string(updated)
  file.flush()
  var write_error := file.get_error()
  file.close()
  if write_error != OK or FileAccess.get_file_as_string(temporary) != updated:
    DirAccess.remove_absolute(temporary)
    push_warning("Could not verify migrated level: " + path)
    return false
  if DirAccess.rename_absolute(temporary, path) != OK:
    DirAccess.remove_absolute(temporary)
    push_warning("Could not replace level with its migrated copy: " + path)
    return false
  return true

func level_progress(level_path: String) -> Dictionary:
  var progress := ConfigFile.new()
  progress.load(PROGRESS_FILE)
  return _stored_progress(progress, level_path)

func record_level_progress(level_path: String, medals: Array[String]) -> void:
  if level_path.is_empty(): return
  var progress := ConfigFile.new()
  progress.load(PROGRESS_FILE)
  var previous := _stored_progress(progress, level_path)
  var earned: Array = previous.medals
  var count := earned.size()
  for medal in medals:
    if medal not in earned: earned.append(medal)
  if previous.completed and count == earned.size(): return
  progress.set_value("levels", level_path, {"completed": true, "medals": earned})
  var error := progress.save(PROGRESS_FILE)
  if error != OK: push_warning("Could not save level progress: " + error_string(error))

func _stored_progress(progress: ConfigFile, level_path: String) -> Dictionary:
  if progress.has_section_key("levels", level_path): return progress.get_value("levels", level_path)
  return {"completed": int(progress.get_value("stars", level_path, 0)) > 0, "medals": []}

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
