extends Control

const PARSER = preload("res://Levels/level_parser.gd")
const UI = preload("res://MainScene/workspace_theme.gd")

var levels: VBoxContainer
var known_paths: Array[String] = []

func _ready() -> void:
  theme = UI.theme()
  var background := ColorRect.new()
  background.color = UI.BACKGROUND
  background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
  add_child(background)
  var frame := MarginContainer.new()
  frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
  frame.offset_left = 28
  frame.offset_right = -28
  frame.offset_top = 24
  frame.offset_bottom = -24
  add_child(frame)
  var panel := PanelContainer.new()
  panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
  frame.add_child(panel)
  var fit := func() -> void: panel.custom_minimum_size.x = minf(580.0, frame.size.x)
  frame.resized.connect(fit)
  fit.call()
  var margin := UI.margin(18)
  panel.add_child(margin)
  var box := VBoxContainer.new()
  box.add_theme_constant_override("separation", 13)
  margin.add_child(box)
  var title := Label.new()
  title.text = "Vertex"
  UI.heading(title, 32)
  box.add_child(title)
  var subtitle := Label.new()
  subtitle.text = "Levels"
  UI.heading(subtitle, 19)
  box.add_child(subtitle)
  var list := ScrollContainer.new()
  list.size_flags_vertical = Control.SIZE_EXPAND_FILL
  list.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
  box.add_child(list)
  levels = VBoxContainer.new()
  levels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  levels.add_theme_constant_override("separation", 8)
  list.add_child(levels)
  _refresh_levels()
  get_window().focus_entered.connect(_refresh_levels)
  var actions := HFlowContainer.new()
  box.add_child(actions)
  var editor := Button.new()
  editor.name = "LevelEditor"
  editor.text = "Level editor"
  editor.theme_type_variation = "PrimaryButton"
  editor.custom_minimum_size.y = 44
  editor.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://MainScene/level_editor.tscn"))
  editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  actions.add_child(editor)
  if OS.has_feature("pc"):
    var folder := UI.button(actions, "Custom levels folder", _show_custom_levels)
    folder.custom_minimum_size.y = 44
    folder.tooltip_text = "Open the folder where Vertex looks for your custom levels"

func _refresh_levels() -> void:
  var paths := Global.level_paths()
  if paths == known_paths and levels.get_child_count() > 0: return
  known_paths = paths
  for child in levels.get_children():
    levels.remove_child(child)
    child.queue_free()
  var custom_section := false
  for path in paths:
    var parsed: Dictionary = PARSER.parse(FileAccess.get_file_as_string(path))
    var name: String = str(parsed.get("title", ""))
    if name.is_empty(): name = path.get_file().trim_suffix(".level")
    var button := Button.new()
    button.custom_minimum_size.y = 49
    button.alignment = HORIZONTAL_ALIGNMENT_LEFT
    button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    var custom := path.begins_with("user://")
    if custom and not custom_section:
      custom_section = true
      var section := Label.new()
      section.text = "Custom levels"
      UI.heading(section, 17)
      levels.add_child(section)
    var stars: int = Global.best_stars(path)
    button.text = name
    button.tooltip_text = str(parsed.get("hint", ""))
    if parsed.has("error"):
      button.text = path.get_file() + "  (invalid)"
      button.tooltip_text = str(parsed.error)
      button.disabled = true
    else:
      button.pressed.connect(_open_level.bind(path))
    var row := HBoxContainer.new()
    levels.add_child(row)
    button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(button)
    var progress := Label.new()
    progress.text = "★".repeat(stars) + "☆".repeat(3 - stars)
    progress.add_theme_color_override("font_color", UI.GOLD)
    progress.tooltip_text = "%d of 3 stars earned" % stars
    progress.mouse_filter = Control.MOUSE_FILTER_STOP
    row.add_child(progress)
  if paths.is_empty():
    var empty := Label.new()
    empty.text = "No levels"
    levels.add_child(empty)

func _show_custom_levels() -> void:
  var error := Global.ensure_custom_levels()
  if error == OK: error = OS.shell_open(ProjectSettings.globalize_path(Global.CUSTOM_LEVELS))
  if error != OK:
    var dialog := AcceptDialog.new()
    UI.setup_dialog(dialog, self, "Could not open level folder")
    dialog.dialog_text = error_string(error)
    dialog.visibility_changed.connect(func() -> void:
      if not dialog.visible: dialog.queue_free()
    )
    dialog.popup_centered()

func _open_level(path: String) -> void:
  Global.selected_level = path
  get_tree().change_scene_to_file("res://MainScene/level_game.tscn")
