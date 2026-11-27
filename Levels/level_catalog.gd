extends RefCounted

const ROOT := "res://Levels"
const PARSER = preload("res://Levels/level_parser.gd")

static func chapters() -> Array[Dictionary]:
  var entries: Array[Dictionary] = []
  for folder in DirAccess.get_directories_at(ROOT):
    var directory := ROOT.path_join(folder)
    var marker := directory.path_join(".chapter")
    if FileAccess.file_exists(marker):
      entries.append(_entry(directory, marker, folder, true))
  entries.sort_custom(_comes_before)
  return entries

static func levels(directory: String) -> Array[Dictionary]:
  var entries: Array[Dictionary] = []
  if not DirAccess.dir_exists_absolute(directory): return entries
  for file in DirAccess.get_files_at(directory):
    if file.get_extension().to_lower() == "level":
      var path := directory.path_join(file)
      entries.append(_entry(path, path, file.get_basename()))
  entries.sort_custom(_comes_before)
  return entries

static func _entry(path: String, metadata_path: String, fallback_title: String, chapter := false) -> Dictionary:
  var entry := {"path": path, "title": fallback_title}
  var source := FileAccess.get_file_as_string(metadata_path)
  for field in PARSER.find_metadata(PARSER.mask_comments(source), chapter):
    var key := field.get_string(1).to_lower()
    var value := field.get_string(2).strip_edges()
    if key == "title":
      value = value.trim_prefix('"').trim_suffix('"')
      entry.title = fallback_title if value.is_empty() else value
    elif key == "order" and value.is_valid_int():
      entry.order = int(value)
  return entry

static func _comes_before(a: Dictionary, b: Dictionary) -> bool:
  if a.has("order") != b.has("order"): return a.has("order")
  if a.has("order") and a.order != b.order: return a.order < b.order
  var by_title: int = a.title.nocasecmp_to(b.title)
  if by_title != 0: return by_title < 0
  return a.path < b.path
