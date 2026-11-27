extends Control

const PARSER = preload("res://Levels/level_parser.gd")
const CATALOG = preload("res://Levels/level_catalog.gd")
const UI = preload("res://MainScene/workspace_theme.gd")
const MEDALS = preload("res://MainScene/medal_display.gd")

var list: ScrollContainer
var rows: VBoxContainer
var subtitle: Label
var back: Button
var chapter_path := ""
var known_entries: Array[Dictionary] = []

func _ready() -> void:
  chapter_path = Global.selected_level.get_base_dir()
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
  var header := HBoxContainer.new()
  box.add_child(header)
  back = UI.button(header, "Chapters", _open_chapter.bind(""))
  subtitle = Label.new()
  UI.heading(subtitle, 19)
  subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  subtitle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
  header.add_child(subtitle)
  list = UI.vertical_scroll()
  list.size_flags_vertical = Control.SIZE_EXPAND_FILL
  box.add_child(list)
  rows = VBoxContainer.new()
  rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  rows.add_theme_constant_override("separation", 8)
  list.add_child(rows)
  _refresh()
  get_window().focus_entered.connect(_refresh)
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

func _refresh() -> void:
  var chapters := CATALOG.chapters()
  chapters.append({"title": "Custom levels", "path": Global.CUSTOM_LEVELS})
  var chapter_title := ""
  for chapter in chapters:
    if chapter.path == chapter_path:
      chapter_title = chapter.title
      break
  if chapter_title.is_empty(): chapter_path = ""
  back.visible = not chapter_path.is_empty()
  subtitle.text = "Chapters" if chapter_path.is_empty() else chapter_title
  var entries := chapters if chapter_path.is_empty() else CATALOG.levels(chapter_path)
  if entries == known_entries and rows.get_child_count() > 0: return
  known_entries = entries
  for child in rows.get_children():
    rows.remove_child(child)
    child.queue_free()
  for entry in entries:
    if chapter_path.is_empty():
      var button := UI.button(rows, entry.title, _open_chapter.bind(entry.path))
      _style_list_button(button)
    else:
      _add_level(entry.path, entry.title)
  if entries.is_empty(): rows.add_child(UI.label("No levels"))

func _style_list_button(button: Button) -> void:
  button.custom_minimum_size.y = 49
  button.alignment = HORIZONTAL_ALIGNMENT_LEFT
  button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

func _add_level(path: String, title: String) -> void:
  var parsed: Dictionary = PARSER.parse(FileAccess.get_file_as_string(path))
  var row := HBoxContainer.new()
  rows.add_child(row)
  var button := UI.button(row, title, _open_level.bind(path))
  _style_list_button(button)
  button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  if parsed.has("error"):
    button.text = path.get_file() + "  (invalid)"
    button.tooltip_text = str(parsed.error)
    button.disabled = true
    return
  var progress := Global.level_progress(path)
  var clear_mark := UI.label("✓" if progress.completed else "")
  clear_mark.custom_minimum_size.x = 18
  clear_mark.tooltip_text = "Level cleared" if progress.completed else "Level uncleared"
  clear_mark.mouse_filter = Control.MOUSE_FILTER_PASS
  row.add_child(clear_mark)
  row.add_child(MEDALS.strip(progress.medals, 28))

func _open_chapter(path: String) -> void:
  chapter_path = path
  Global.selected_level = ""
  list.scroll_vertical = 0
  _refresh()

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
