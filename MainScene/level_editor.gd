extends Control

const PARSER = preload("res://Levels/level_parser.gd")
const CATALOG = preload("res://Buildings/building_catalog.gd")
const BOARD = preload("res://MainScene/editor_board.gd")
const NEW_LEVEL := "9 x 9;\n\ngoal: {electron: 1/s, 2/s, 3/s};\n\n"

var source: TextEdit
var board: Control
var status: Label
var selected_label: Label
var properties: LineEdit
var property_form: VBoxContainer
var property_fields: Array[LineEdit] = []
var property_prefix := ""
var property_suffix := ""
var tool_select: OptionButton
var width_input: SpinBox
var height_input: SpinBox
var file_dialog: FileDialog
var confirm: ConfirmationDialog
var path := ""
var saved_text := NEW_LEVEL
var pending_action := ""
var blocks: Array[Dictionary] = []
var selected_block := -1
var updating := false
var parsed: Dictionary = {}

func _ready() -> void:
  get_tree().auto_accept_quit = false
  _build_ui()
  _set_source(NEW_LEVEL)

func _exit_tree() -> void:
  get_tree().auto_accept_quit = true

func _notification(what: int) -> void:
  if what == NOTIFICATION_WM_CLOSE_REQUEST:
    _request_action("quit")

func _build_ui() -> void:
  var background := ColorRect.new()
  background.color = Color("111825")
  background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
  add_child(background)
  var margin := MarginContainer.new()
  margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
  for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
    margin.add_theme_constant_override(side, 12)
  add_child(margin)
  var column := VBoxContainer.new()
  margin.add_child(column)
  var bar := HBoxContainer.new()
  column.add_child(bar)
  _button(bar, "New", func() -> void: _request_action("new"))
  _button(bar, "Open…", func() -> void: _request_action("open"))
  _button(bar, "Save", _save)
  _button(bar, "Save as…", _save_as)
  _button(bar, "Level select", func() -> void: _request_action("back"))
  status = Label.new()
  status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
  bar.add_child(status)
  var split := HSplitContainer.new()
  split.size_flags_vertical = Control.SIZE_EXPAND_FILL
  column.add_child(split)
  var left := VBoxContainer.new()
  left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  split.add_child(left)
  var controls := HBoxContainer.new()
  left.add_child(controls)
  controls.add_child(_label("Grid"))
  width_input = _spin(controls)
  controls.add_child(_label("×"))
  height_input = _spin(controls)
  width_input.value_changed.connect(_resize_board)
  height_input.value_changed.connect(_resize_board)
  controls.add_child(_label("  Tool"))
  tool_select = OptionButton.new()
  tool_select.add_item("Select / move")
  var kinds: Array = CATALOG.SCENES.keys()
  kinds.sort()
  for kind in kinds: tool_select.add_item(str(kind).capitalize())
  controls.add_child(tool_select)
  tool_select.item_selected.connect(func(_index: int) -> void: _select_block(-1))
  var hint := _label("Select a building, then click an empty cell to move it. Right-click to delete.")
  hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
  left.add_child(hint)
  var scroll := ScrollContainer.new()
  scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
  scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  left.add_child(scroll)
  board = BOARD.new()
  scroll.add_child(board)
  board.cell_clicked.connect(_board_click)
  for kind in CATALOG.SCENES:
    var instance: Node = CATALOG.SCENES[kind].instantiate()
    var sprite := instance.get_node_or_null("Sprite2D") as Sprite2D
    if sprite != null and sprite.texture != null: board.icons[kind] = sprite.texture
    instance.free()
  var inspector := VBoxContainer.new()
  inspector.custom_minimum_size.x = 390
  inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  split.add_child(inspector)
  selected_label = _label("Selected: none")
  inspector.add_child(selected_label)
  property_form = VBoxContainer.new()
  inspector.add_child(property_form)
  properties = LineEdit.new()
  properties.placeholder_text = "Full declaration"
  inspector.add_child(properties)
  var property_buttons := HBoxContainer.new()
  inspector.add_child(property_buttons)
  _button(property_buttons, "Apply properties", _apply_properties)
  _button(property_buttons, "Delete selected", _delete_selected)
  var source_label := _label("Level source · goals, inventory and advanced properties")
  source_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
  inspector.add_child(source_label)
  source = TextEdit.new()
  source.size_flags_vertical = Control.SIZE_EXPAND_FILL
  source.custom_minimum_size.y = 220
  source.text_changed.connect(_source_changed)
  inspector.add_child(source)
  file_dialog = FileDialog.new()
  file_dialog.access = FileDialog.ACCESS_FILESYSTEM
  file_dialog.filters = PackedStringArray(["*.level ; Level files"])
  file_dialog.file_selected.connect(_file_selected)
  add_child(file_dialog)
  confirm = ConfirmationDialog.new()
  confirm.dialog_text = "Discard unsaved changes?"
  confirm.confirmed.connect(_perform_pending_action)
  add_child(confirm)

func _button(parent: Node, text_value: String, action: Callable) -> void:
  var button := Button.new()
  button.text = text_value
  button.pressed.connect(action)
  parent.add_child(button)

func _label(text_value: String) -> Label:
  var label := Label.new()
  label.text = text_value
  return label

func _spin(parent: Node) -> SpinBox:
  var spin := SpinBox.new()
  spin.min_value = 1
  spin.max_value = 200
  spin.custom_minimum_size.x = 75
  parent.add_child(spin)
  return spin

func _set_source(value: String) -> void:
  source.text = value
  _source_changed()

func _source_changed() -> void:
  if updating: return
  _select_block(-1)
  parsed = PARSER.parse(source.text)
  blocks.clear()
  if parsed.has("error"):
    board.set_level({})
    status.text = "Invalid: " + str(parsed.error)
    return
  updating = true
  width_input.value = parsed.width
  height_input.value = parsed.height
  updating = false
  _index_blocks()
  board.set_level(parsed)
  status.text = (path.get_file() if not path.is_empty() else "Untitled") + ("  • unsaved" if source.text != saved_text else "")

# Mask comments without changing offsets so editing preserves the original text.
func _index_blocks() -> void:
  var lines := PackedStringArray()
  for line in source.text.split("\n"):
    var comment := line.find("#")
    lines.append(line if comment < 0 else line.substr(0, comment) + " ".repeat(line.length() - comment))
  var masked := "\n".join(lines)
  var pattern := RegEx.new()
  pattern.compile("(?is)\\b([a-z_][a-z_0-9]*)\\s*:\\s*\\{[^}]*\\}")
  for result in pattern.search_all(masked):
    var kind := result.get_string(1).to_lower()
    if kind == "magnetic_field": kind = "magnet"
    if not CATALOG.SCENES.has(kind): continue
    var text := source.text.substr(result.get_start(), result.get_end() - result.get_start())
    var fragment: Dictionary = PARSER.parse("%d x %d; goal: {electron: 1, 1, 1};\n%s" % [parsed.width, parsed.height, text])
    if fragment.has("error") or fragment.buildings.is_empty(): continue
    blocks.append({"start": result.get_start(), "end": result.get_end(), "text": text, "entries": fragment.buildings})

func _resize_board(_value: float) -> void:
  if updating: return
  var regex := RegEx.new()
  regex.compile("(?i)(\\d+)\\s*x\\s*(\\d+)")
  var found := regex.search(source.text)
  if found == null: return
  _set_source(source.text.substr(0, found.get_start()) + "%d x %d" % [int(width_input.value), int(height_input.value)] + source.text.substr(found.get_end()))

func _board_click(cell: Vector2i, button: int) -> void:
  var hit := -1
  for i in range(blocks.size()):
    for entry in blocks[i].entries:
      if Vector2i(entry.x, entry.y) == cell: hit = i
  if button == MOUSE_BUTTON_RIGHT:
    if hit >= 0:
      _select_block(hit, cell)
      _delete_selected()
    return
  if button != MOUSE_BUTTON_LEFT: return
  if tool_select.selected > 0:
    if hit >= 0:
      status.text = "That cell is occupied."
      return
    var kinds: Array = CATALOG.SCENES.keys()
    kinds.sort()
    var kind: String = kinds[tool_select.selected - 1]
    var extra := ""
    if kind == "emitter": extra = ", E, [electron], rate=1"
    elif kind == "detector": extra = ", [photon]"
    var declaration := "%s: {x=%d, y=%d%s};\n" % [kind, cell.x, cell.y, extra]
    _set_source(source.text.trim_suffix("\n") + "\n" + declaration)
    return
  if hit >= 0:
    _select_block(hit, cell)
  elif selected_block >= 0:
    var block: Dictionary = blocks[selected_block]
    if block.entries.size() != 1:
      status.text = "Edit coordinates in the declaration to change a range."
      return
    var x_regex := RegEx.new()
    var y_regex := RegEx.new()
    x_regex.compile("(?i)\\bx\\s*=\\s*-?\\d+")
    y_regex.compile("(?i)\\by\\s*=\\s*-?\\d+")
    var replacement := x_regex.sub(block.text, "x=%d" % cell.x)
    replacement = y_regex.sub(replacement, "y=%d" % cell.y)
    _replace_block(selected_block, replacement)

func _select_block(index: int, cell: Vector2i = Vector2i(-1, -1)) -> void:
  selected_block = index
  board.selected = cell
  board.queue_redraw()
  if index < 0:
    selected_label.text = "Selected: none"
    properties.text = ""
    properties.editable = false
    _clear_property_form()
  else:
    selected_label.text = "Selected: %s at %d, %d" % [blocks[index].entries[0].kind, cell.x, cell.y]
    properties.text = blocks[index].text.replace("\n", " ")
    properties.editable = true
    _build_property_form(properties.text)

func _clear_property_form() -> void:
  property_fields.clear()
  for child in property_form.get_children():
    property_form.remove_child(child)
    child.queue_free()

# Generate fields from the declaration itself so added properties are editable
# without the editor needing a separate list of mechanics.
func _build_property_form(declaration: String) -> void:
  _clear_property_form()
  var start := declaration.find("{")
  var end := declaration.rfind("}")
  if start < 0 or end <= start: return
  property_prefix = declaration.substr(0, start + 1)
  property_suffix = declaration.substr(end)
  var body := declaration.substr(start + 1, end - start - 1)
  var parts: Array[String] = []
  var depth := 0
  var part_start := 0
  for i in range(body.length()):
    var character := body.substr(i, 1)
    if character in ["[", "("]: depth += 1
    elif character in ["]", ")"]: depth -= 1
    elif character == "," and depth == 0:
      parts.append(body.substr(part_start, i - part_start).strip_edges())
      part_start = i + 1
  parts.append(body.substr(part_start).strip_edges())
  for part in parts:
    if part.is_empty(): continue
    var row := HBoxContainer.new()
    property_form.add_child(row)
    var label := _label(part.get_slice("=", 0).strip_edges().capitalize() if "=" in part else "Option")
    label.custom_minimum_size.x = 100
    row.add_child(label)
    var field := LineEdit.new()
    field.text = part
    field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    field.text_changed.connect(_property_field_changed)
    row.add_child(field)
    property_fields.append(field)

func _property_field_changed(_value: String) -> void:
  var parts: Array[String] = []
  for field in property_fields: parts.append(field.text.strip_edges())
  properties.text = property_prefix + " " + ", ".join(parts) + " " + property_suffix

func _replace_block(index: int, replacement: String) -> void:
  var block: Dictionary = blocks[index]
  _set_source(source.text.substr(0, block.start) + replacement + source.text.substr(block.end))

func _apply_properties() -> void:
  if selected_block < 0: return
  _replace_block(selected_block, properties.text)

func _delete_selected() -> void:
  if selected_block < 0: return
  if blocks[selected_block].entries.size() > 1:
    status.text = "This declaration is a range; edit it in the source to remove individual cells."
    return
  _replace_block(selected_block, "")

func _request_action(action: String) -> void:
  pending_action = action
  if source.text != saved_text:
    confirm.popup_centered()
  else:
    _perform_pending_action()

func _perform_pending_action() -> void:
  match pending_action:
    "new":
      path = ""
      saved_text = NEW_LEVEL
      _set_source(NEW_LEVEL)
    "open":
      file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
      file_dialog.current_dir = ProjectSettings.globalize_path("res://Levels")
      file_dialog.popup_centered_ratio(0.8)
    "back": get_tree().change_scene_to_file("res://MainScene/level_select.tscn")
    "quit": get_tree().quit()

func _save() -> void:
  if path.is_empty(): _save_as()
  else: _write_file(path)

func _save_as() -> void:
  DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://levels"))
  file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
  file_dialog.current_dir = ProjectSettings.globalize_path("user://levels")
  file_dialog.current_file = path.get_file() if not path.is_empty() else "new-level.level"
  file_dialog.popup_centered_ratio(0.8)

func _file_selected(selected_path: String) -> void:
  if file_dialog.file_mode == FileDialog.FILE_MODE_SAVE_FILE:
    if not selected_path.to_lower().ends_with(".level"): selected_path += ".level"
    _write_file(selected_path)
  else:
    var file := FileAccess.open(selected_path, FileAccess.READ)
    if file == null:
      status.text = "Could not open file: " + error_string(FileAccess.get_open_error())
      return
    path = selected_path
    saved_text = file.get_as_text()
    _set_source(saved_text)

func _write_file(target: String) -> void:
  var data: Dictionary = PARSER.parse(source.text)
  if data.has("error"):
    status.text = "Cannot save: " + str(data.error)
    return
  var file := FileAccess.open(target, FileAccess.WRITE)
  if file == null:
    status.text = "Could not save file: " + error_string(FileAccess.get_open_error())
    return
  file.store_string(source.text)
  file.flush()
  if file.get_error() != OK:
    status.text = "Could not write file: " + error_string(file.get_error())
    return
  path = target
  saved_text = source.text
  _source_changed()
