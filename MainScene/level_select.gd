extends Control

const PARSER = preload("res://Levels/level_parser.gd")

func _ready() -> void:
  var background := ColorRect.new()
  background.color = Color("111825")
  background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
  add_child(background)
  var center := CenterContainer.new()
  center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
  add_child(center)
  var box := VBoxContainer.new()
  box.custom_minimum_size = Vector2(520, 0)
  box.add_theme_constant_override("separation", 12)
  center.add_child(box)
  var title := Label.new()
  title.text = "VERTEX"
  title.add_theme_font_size_override("font_size", 40)
  title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
  box.add_child(title)
  var subtitle := Label.new()
  subtitle.text = "Select a level"
  subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
  box.add_child(subtitle)
  var list := ScrollContainer.new()
  list.custom_minimum_size = Vector2(520, 300)
  box.add_child(list)
  var levels := VBoxContainer.new()
  levels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  levels.add_theme_constant_override("separation", 8)
  list.add_child(levels)
  var count := 0
  DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://levels"))
  for path in Global.level_paths():
    count += 1
    var parsed: Dictionary = PARSER.parse(FileAccess.get_file_as_string(path))
    var name: String = str(parsed.get("title", ""))
    if name.is_empty(): name = path.get_file().trim_suffix(".level")
    var button := Button.new()
    button.custom_minimum_size.y = 48
    var custom := path.begins_with("user://")
    var stars: int = Global.best_stars(path)
    button.text = "%s   %s%s" % [name, "★".repeat(stars) + "☆".repeat(3 - stars), "  (custom)" if custom else ""]
    button.tooltip_text = str(parsed.get("hint", ""))
    if parsed.has("error"):
      button.text = path.get_file() + "  (invalid)"
      button.tooltip_text = str(parsed.error)
      button.disabled = true
    else:
      button.pressed.connect(_open_level.bind(path))
    levels.add_child(button)
  if count == 0:
    var empty := Label.new()
    empty.text = "No .level files found in Levels/."
    levels.add_child(empty)
  var editor := Button.new()
  editor.text = "Level editor"
  editor.custom_minimum_size.y = 44
  editor.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://MainScene/level_editor.tscn"))
  box.add_child(editor)

func _open_level(path: String) -> void:
  Global.selected_level = path
  get_tree().change_scene_to_file("res://MainScene/level_game.tscn")
