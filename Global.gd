extends Node

var selected_level: String = ""

const PROGRESS_FILE := "user://level_progress.cfg"

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
  for directory in ["res://Levels", "user://levels"]:
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
