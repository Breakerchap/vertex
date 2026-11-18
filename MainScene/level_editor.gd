extends Control

const PARSER = preload("res://Levels/level_parser.gd")
const PALETTE = preload("res://MainScene/building_palette.gd")
const CATALOG = preload("res://Buildings/building_catalog.gd")
const GAME = preload("res://MainScene/level_game.tscn")
const NEW_LEVEL := "9 x 9;\n\ngoal: {electron: 1/s, 2/s, 3/s};\n\n"

var source: TextEdit
var game
var editor_panel: PanelContainer
var inspector_panel: PanelContainer
var inspector_heading: Label
var test_game: Node2D
var inspector_dialog: AcceptDialog
var source_dialog: AcceptDialog
var source_error: Label
var status: Label
var selected_label: Label
var properties: LineEdit
var property_form: VBoxContainer
var property_fields: Array[LineEdit] = []
var property_prefix := ""
var property_suffix := ""
var tool_select: OptionButton
var palette: PanelContainer
var width_input: SpinBox
var height_input: SpinBox
var file_dialog: FileDialog
var confirm: ConfirmationDialog
var path := ""
var saved_text := NEW_LEVEL
var pending_action := ""
var blocks: Array[Dictionary] = []
var selected_block := -1
var selected_cell := Vector2i(-1, -1)
var visual_fields := {}
var visual_form: VBoxContainer
var settings_error: Label
var property_error: Label
var settings_dialog: AcceptDialog
var title_input: LineEdit
var hint_input: LineEdit
var goal_rows: VBoxContainer
var inventory_fields := {}
var updating := false
var source_snapshot := ""
var undo_stack: Array[String] = []
var redo_stack: Array[String] = []
var restoring_source := false
var parsed: Dictionary = {}

func _ready() -> void:
  get_tree().auto_accept_quit = false
  _build_ui()
  _set_source(NEW_LEVEL)
  undo_stack.clear()
  source_snapshot = source.text

func _exit_tree() -> void:
  get_tree().auto_accept_quit = true

func _unhandled_key_input(event: InputEvent) -> void:
  if is_instance_valid(test_game): return
  if event is InputEventKey and event.pressed and not event.echo and not game.simulating:
    if event.ctrl_pressed:
      if event.keycode == KEY_S:
        if event.shift_pressed: _save_as()
        else: _save()
      elif event.keycode == KEY_Z:
        if event.shift_pressed: _redo_editor()
        else: _undo_editor()
      elif event.keycode == KEY_Y: _redo_editor()
      return
    if event.keycode == KEY_R: _rotate_block()
    elif event.keycode == KEY_DELETE: _delete_selected()
    elif event.keycode == KEY_ESCAPE: _select_move_tool()

func _notification(what: int) -> void:
  if what == NOTIFICATION_WM_CLOSE_REQUEST:
    _request_action("quit")

func _build_ui() -> void:
  mouse_filter = Control.MOUSE_FILTER_IGNORE
  game = GAME.instantiate()
  game.editor_preview = true
  add_child(game)
  game.editor_cell_clicked.connect(_board_click)
  game.editor_cell_dragged.connect(_move_block)

  var hud := CanvasLayer.new()
  add_child(hud)
  var panel := PanelContainer.new()
  editor_panel = panel
  hud.add_child(panel)
  panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
  panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
  panel.offset_left = 16
  panel.offset_right = -272
  panel.offset_top = -174
  panel.offset_bottom = -16
  panel.resized.connect(_update_camera_inset)
  var margin := MarginContainer.new()
  for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
    margin.add_theme_constant_override(side, 8)
  panel.add_child(margin)
  var column := VBoxContainer.new()
  column.add_theme_constant_override("separation", 8)
  margin.add_child(column)
  var bar := HFlowContainer.new()
  bar.add_theme_constant_override("separation", 6)
  column.add_child(bar)
  _button(bar, "New", func() -> void: _request_action("new"))
  _button(bar, "Open...", func() -> void: _request_action("open"))
  _button(bar, "Save", _save)
  _button(bar, "Save as...", _save_as)
  _button(bar, "Undo", _undo_editor)
  _button(bar, "Redo", _redo_editor)
  _button(bar, "Playtest", _start_playtest)
  _button(bar, "Level select", func() -> void: _request_action("back"))
  status = Label.new()
  status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
  status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
  bar.add_child(status)
  var controls := HFlowContainer.new()
  controls.add_theme_constant_override("separation", 6)
  column.add_child(controls)
  controls.add_child(_label("Grid"))
  width_input = _spin(controls)
  controls.add_child(_label("x"))
  height_input = _spin(controls)
  width_input.value_changed.connect(_resize_board)
  height_input.value_changed.connect(_resize_board)
  tool_select = OptionButton.new()
  tool_select.add_item("Select / move")
  var kinds: Array = CATALOG.SCENES.keys()
  kinds.sort()
  for kind in kinds: tool_select.add_item(str(kind).capitalize())
  tool_select.hide()
  controls.add_child(tool_select)
  tool_select.item_selected.connect(func(_index: int) -> void: _select_block(-1))
  _button(controls, "Select / move", _select_move_tool)
  palette = PALETTE.new()
  palette.infinite = true
  hud.add_child(palette)
  game.external_palette = palette
  palette.mode_changed.connect(func(enabled: bool) -> void:
    if not enabled: _select_move_tool()
  )
  palette.kind_selected.connect(_select_palette_kind)
  palette.kind_dropped.connect(_drop_palette_kind)
  _button(controls, "Level settings...", _open_settings)
  _button(controls, "Rotate [R]", _rotate_block)
  _button(controls, "Properties...", func() -> void: inspector_dialog.popup_centered())
  _button(controls, "Delete", _delete_selected)
  _button(controls, "Source...", func() -> void: source_dialog.popup_centered_ratio(0.65))
  _button(controls, "Reset preview", func() -> void: game._load_initial_board())
  selected_label = _label("Nothing selected")
  column.add_child(selected_label)

  inspector_panel = PanelContainer.new()
  hud.add_child(inspector_panel)
  inspector_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
  inspector_panel.offset_left = -256
  inspector_panel.offset_right = -16
  inspector_panel.offset_top = 115
  inspector_panel.offset_bottom = -16
  var inspector_margin := MarginContainer.new()
  for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
    inspector_margin.add_theme_constant_override(side, 10)
  inspector_panel.add_child(inspector_margin)
  var inspector_column := VBoxContainer.new()
  inspector_column.add_theme_constant_override("separation", 10)
  inspector_margin.add_child(inspector_column)
  inspector_heading = _label("Selected building")
  inspector_column.add_child(inspector_heading)
  _button(inspector_column, "Back to tools [Esc]", _select_move_tool)
  var inspector_scroll := ScrollContainer.new()
  inspector_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
  inspector_column.add_child(inspector_scroll)
  visual_form = VBoxContainer.new()
  visual_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  inspector_scroll.add_child(visual_form)
  _button(inspector_column, "Delete selected [Del]", _delete_selected)
  inspector_panel.hide()

  inspector_dialog = AcceptDialog.new()
  inspector_dialog.title = "Properties"
  inspector_dialog.min_size = Vector2i(420, 250)
  add_child(inspector_dialog)
  var inspector := VBoxContainer.new()
  inspector.add_theme_constant_override("separation", 8)
  inspector_dialog.add_child(inspector)
  property_form = VBoxContainer.new()
  inspector.add_child(property_form)
  properties = LineEdit.new()
  properties.placeholder_text = "Declaration"
  inspector.add_child(properties)
  property_error = _label("")
  inspector.add_child(property_error)
  _button(inspector, "Apply declaration", _apply_properties)

  source_dialog = AcceptDialog.new()
  source_dialog.title = "Level source"
  add_child(source_dialog)
  source = CodeEdit.new()
  source.set_draw_line_numbers(true)
  var highlighter := CodeHighlighter.new()
  highlighter.number_color = Color("e6b66c")
  highlighter.symbol_color = Color("a6c8e8")
  highlighter.add_color_region("#", "", Color("8192a4"), true)
  for word in ["goal", "inventory", "emitter", "detector", "mirror", "wall", "magnet", "magnetic_field"]:
    highlighter.add_keyword_color(word, Color("7bd9bd"))
  for word in ["x", "y", "fixed", "rate", "AND", "OR"]:
    highlighter.add_keyword_color(word, Color("b5a6f1"))
  source.syntax_highlighter = highlighter
  source.custom_minimum_size = Vector2(500, 350)
  source.text_changed.connect(_source_changed)
  source_dialog.add_child(source)
  source_error = _label("")
  source_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
  source_dialog.add_child(source_error)
  settings_dialog = AcceptDialog.new()
  settings_dialog.title = "Level settings"
  settings_dialog.min_size = Vector2i(580, 480)
  add_child(settings_dialog)
  var settings_column := VBoxContainer.new()
  settings_dialog.add_child(settings_column)
  settings_column.add_child(_label("Level title"))
  title_input = LineEdit.new()
  title_input.placeholder_text = "e.g. First Contact"
  settings_column.add_child(title_input)
  settings_column.add_child(_label("Short objective hint (avoid spoilers)"))
  hint_input = LineEdit.new()
  hint_input.placeholder_text = "e.g. Guide a photon into the detector"
  settings_column.add_child(hint_input)
  settings_column.add_child(_label("Goals: each solution must satisfy all its conditions"))
  var goals_scroll := ScrollContainer.new()
  goals_scroll.custom_minimum_size.y = 160
  goals_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
  settings_column.add_child(goals_scroll)
  goal_rows = VBoxContainer.new()
  goal_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  goals_scroll.add_child(goal_rows)
  _button(settings_column, "+ Add alternative solution", func() -> void: _add_goal_group())
  settings_column.add_child(_label("Starting inventory"))
  for kind in CATALOG.SCENES:
    var row := HBoxContainer.new()
    settings_column.add_child(row)
    var label := _label(str(kind).capitalize())
    label.custom_minimum_size.x = 120
    row.add_child(label)
    var count := _spin(row)
    count.min_value = 0
    count.max_value = 999
    inventory_fields[kind] = count
  settings_error = _label("")
  settings_column.add_child(settings_error)
  _button(settings_column, "Apply settings", _apply_settings)
  file_dialog = FileDialog.new()
  file_dialog.access = FileDialog.ACCESS_FILESYSTEM
  file_dialog.filters = PackedStringArray(["*.level ; Level files"])
  file_dialog.file_selected.connect(_file_selected)
  add_child(file_dialog)
  confirm = ConfirmationDialog.new()
  confirm.dialog_text = "Discard unsaved changes?"
  confirm.confirmed.connect(_perform_pending_action)
  add_child(confirm)

func _select_move_tool() -> void:
  game.editor_brush = ""
  tool_select.select(0)
  palette.selected = ""
  palette.refresh()
  _select_block(-1)

func _select_palette_kind(kind: String) -> void:
  game.editor_brush = kind
  var kinds: Array = CATALOG.SCENES.keys()
  kinds.sort()
  tool_select.select(kinds.find(kind) + 1)
  palette.selected = kind
  palette.refresh()
  _select_block(-1)

func _drop_palette_kind(kind: String, screen_position: Vector2) -> void:
  if game.simulating or parsed.has("error") or parsed.is_empty(): return
  var point: Vector2 = game.get_canvas_transform().affine_inverse() * screen_position / game.CELL
  var cell := Vector2i(roundi(point.x), parsed.height - 1 - roundi(point.y))
  if cell.x < 0 or cell.y < 0 or cell.x >= parsed.width or cell.y >= parsed.height: return
  _place_editor_kind(kind, cell)

func _update_camera_inset() -> void:
  if not is_instance_valid(game) or not is_instance_valid(editor_panel): return
  game.editor_bottom_inset = editor_panel.size.y + 16.0
  game._fit_camera()

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
  if source.text != source_snapshot:
    if not restoring_source:
      undo_stack.append(source_snapshot)
      if undo_stack.size() > 100: undo_stack.pop_front()
      redo_stack.clear()
    source_snapshot = source.text
  _select_block(-1)
  parsed = PARSER.parse(source.text)
  blocks.clear()
  if parsed.has("error"):
    source_error.text = "Source error: " + str(parsed.error)
    status.text = "Invalid: " + str(parsed.error) + "  (showing last valid board)"
    return
  source_error.text = ""
  updating = true
  width_input.value = parsed.width
  height_input.value = parsed.height
  updating = false
  _index_blocks()
  game.show()
  game.level = parsed
  game._load_initial_board()
  game._fit_camera()
  var warnings := _level_warnings(parsed)
  status.text = (path.get_file() if not path.is_empty() else "Untitled") + ("  • unsaved" if source.text != saved_text else "") + ("  • %d warning(s)" % warnings.size() if not warnings.is_empty() else "")
  status.tooltip_text = "\n".join(warnings)
  source_error.text = "\n".join(warnings)

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
  if parsed.has("error"): return
  var hit := -1
  for i in range(blocks.size()):
    for entry in blocks[i].entries:
      if Vector2i(entry.x, entry.y) == cell: hit = i
  if button == MOUSE_BUTTON_RIGHT:
    if hit >= 0: _select_block(hit, cell)
    return
  if button != MOUSE_BUTTON_LEFT: return
  if hit >= 0:
    if palette.click_mode:
      tool_select.select(0)
      palette.selected = ""
      palette.refresh()
    _select_block(hit, cell)
    return
  if palette.click_mode and tool_select.selected > 0:
    var kinds: Array = CATALOG.SCENES.keys()
    kinds.sort()
    _place_editor_kind(kinds[tool_select.selected - 1], cell)
    return
  if selected_block >= 0 and selected_cell != cell:
    _move_block(selected_cell, cell)
    return
  _select_block(-1)
  return

func _select_block(index: int, cell: Vector2i = Vector2i(-1, -1)) -> void:
  selected_block = index
  selected_cell = cell
  game.selected_building = game._building_at(cell) if index >= 0 else null
  if is_instance_valid(inspector_panel): inspector_panel.visible = index >= 0
  if is_instance_valid(palette): palette.visible = index < 0
  if index < 0:
    selected_label.text = "Nothing selected"
    _build_visual_form()
    properties.text = ""
    properties.editable = false
    _clear_property_form()
  else:
    selected_label.text = "Selected: %s at %d, %d" % [blocks[index].entries[0].kind, cell.x, cell.y]
    inspector_heading.text = "%s  (%d, %d)" % [str(blocks[index].entries[0].kind).capitalize(), cell.x, cell.y]
    properties.text = blocks[index].text.replace("\n", " ")
    properties.editable = true
    _build_property_form(properties.text)
    _build_visual_form()

func _place_editor_kind(kind: String, cell: Vector2i) -> void:
  if game._building_at(cell) != null:
    status.text = "That cell is occupied."
    return
  var extra := ""
  if kind == "emitter": extra = ", E, [electron], rate=1"
  elif kind == "detector": extra = ", [photon]"
  _set_source(source.text.trim_suffix("\n") + "\n%s: {x=%d, y=%d%s};\n" % [kind, cell.x, cell.y, extra])
  _select_at(cell)

func _select_at(cell: Vector2i) -> void:
  for i in range(blocks.size()):
    for entry in blocks[i].entries:
      if Vector2i(entry.x, entry.y) == cell:
        _select_block(i, cell)
        return

func _single_declaration(text_value: String, cell: Vector2i) -> String:
  var x_regex := RegEx.new()
  var y_regex := RegEx.new()
  x_regex.compile("(?i)\\bx\\s*=\\s*-?\\d+(?:\\.\\.-?\\d+)?")
  y_regex.compile("(?i)\\by\\s*=\\s*-?\\d+(?:\\.\\.-?\\d+)?")
  return y_regex.sub(x_regex.sub(text_value, "x=%d" % cell.x), "y=%d" % cell.y)

func _replace_selected_cell(replacement: String) -> void:
  if selected_block < 0: return
  var block: Dictionary = blocks[selected_block]
  var declarations: PackedStringArray = []
  for entry in block.entries:
    var cell := Vector2i(entry.x, entry.y)
    if cell == selected_cell:
      if not replacement.is_empty(): declarations.append(replacement.trim_suffix(";"))
    else:
      declarations.append(_single_declaration(block.text, cell).trim_suffix(";"))
  _replace_block(selected_block, ";\n".join(declarations))

func _move_block(from_cell: Vector2i, to_cell: Vector2i) -> void:
  if parsed.has("error"): return
  if to_cell.x < 0 or to_cell.y < 0 or to_cell.x >= parsed.width or to_cell.y >= parsed.height: return
  if from_cell == to_cell or game._building_at(to_cell) != null: return
  _select_at(from_cell)
  if selected_block < 0: return
  var replacement := _single_declaration(blocks[selected_block].text, to_cell)
  _replace_selected_cell(replacement)
  _select_at(to_cell)

func _rotate_block() -> void:
  if selected_block < 0: return
  var entry: Dictionary = blocks[selected_block].entries[0]
  if entry.kind not in ["mirror", "emitter", "magnet"]: return
  _build_visual_form()
  if entry.kind == "magnet":
    visual_fields.polarity.select(1 - visual_fields.polarity.selected)
  else:
    visual_fields.facing.select((visual_fields.facing.selected + 1) % 8)
  _apply_visual_properties()

func _visual_row(label_text: String, control: Control) -> void:
  var row := HBoxContainer.new()
  visual_form.add_child(row)
  var label := _label(label_text)
  label.custom_minimum_size.x = 108
  row.add_child(label)
  control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  row.add_child(control)

func _build_visual_form() -> void:
  for child in visual_form.get_children():
    visual_form.remove_child(child)
    child.queue_free()
  visual_fields.clear()
  property_error.text = ""
  if selected_block < 0: return
  var entry: Dictionary = blocks[selected_block].entries[0]
  if entry.kind in ["mirror", "emitter"]:
    var direction := OptionButton.new()
    for name in ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]: direction.add_item(name)
    direction.select(["E", "SE", "S", "SW", "W", "NW", "N", "NE"].find(entry.facing))
    _visual_row("Direction", direction)
    visual_fields.facing = direction
    direction.item_selected.connect(func(_index: int) -> void: _apply_visual_properties.call_deferred())
  if entry.kind == "magnet":
    var polarity := OptionButton.new()
    polarity.add_item("Positive")
    polarity.add_item("Negative")
    polarity.select(1 if str(entry.get("polarity", "+")) in ["negative", "-", "-1", "n"] else 0)
    _visual_row("Polarity", polarity)
    visual_fields.polarity = polarity
    polarity.item_selected.connect(func(_index: int) -> void: _apply_visual_properties.call_deferred())
  if entry.kind in ["emitter", "detector"]:
    var particles := LineEdit.new()
    particles.text = ", ".join(entry.particles)
    if entry.kind == "detector":
      var original: String = blocks[selected_block].text
      var left := original.find("[")
      var right := original.find("]", left)
      if left >= 0 and right > left: particles.text = original.substr(left + 1, right - left - 1)
    particles.placeholder_text = "e.g. electron, positron"
    _visual_row("Particles", particles)
    visual_fields.particles = particles
    particles.text_submitted.connect(func(_text: String) -> void: _apply_visual_properties.call_deferred())
    particles.focus_exited.connect(func() -> void: _apply_visual_properties.call_deferred())
  if entry.kind == "emitter":
    var rate := SpinBox.new()
    rate.min_value = 0.01
    rate.max_value = 1000
    rate.step = 0.1
    rate.value = float(entry.rate)
    _visual_row("Particles per second", rate)
    visual_fields.rate = rate
    rate.value_changed.connect(func(_value: float) -> void: _apply_visual_properties.call_deferred())
  var fixed_position := CheckBox.new()
  fixed_position.button_pressed = "p" in str(entry.fixed)
  _visual_row("Lock position", fixed_position)
  visual_fields.fixed_position = fixed_position
  fixed_position.toggled.connect(func(_value: bool) -> void: _apply_visual_properties.call_deferred())
  if entry.kind in ["mirror", "emitter", "magnet"]:
    var fixed_rotation := CheckBox.new()
    fixed_rotation.button_pressed = ("c" if entry.kind == "magnet" else "r") in str(entry.fixed)
    _visual_row("Lock rotation / polarity", fixed_rotation)
    visual_fields.fixed_rotation = fixed_rotation
    fixed_rotation.toggled.connect(func(_value: bool) -> void: _apply_visual_properties.call_deferred())

func _apply_visual_properties() -> void:
  if selected_block < 0: return
  var entry: Dictionary = blocks[selected_block].entries[0]
  var parts: PackedStringArray = ["x=%d" % selected_cell.x, "y=%d" % selected_cell.y]
  if visual_fields.has("facing"): parts.append(visual_fields.facing.get_item_text(visual_fields.facing.selected))
  if visual_fields.has("polarity"): parts.append("-" if visual_fields.polarity.selected == 1 else "+")
  if visual_fields.has("particles"): parts.append("[" + visual_fields.particles.text + "]")
  if visual_fields.has("rate"): parts.append("rate=%s" % str(visual_fields.rate.value))
  var fixed := "p" if visual_fields.fixed_position.button_pressed else ""
  if visual_fields.has("fixed_rotation") and visual_fields.fixed_rotation.button_pressed: fixed += "c" if entry.kind == "magnet" else "r"
  if not fixed.is_empty(): parts.append("fixed=" + fixed)
  for key in entry:
    if key not in ["kind", "x", "y", "facing", "fixed", "rate", "particles", "accepted", "polarity"]:
      parts.append("%s=%s" % [key, entry[key]])
  var replacement := "%s: {%s}" % [entry.kind, ", ".join(parts)]
  var candidate := PARSER.parse("%d x %d; goal: {electron: 1, 1, 1}; %s;" % [parsed.width, parsed.height, replacement])
  if candidate.has("error"):
    property_error.text = candidate.error
    return
  var cell := selected_cell
  _replace_selected_cell(replacement)
  _select_at(cell)

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
  var cell := selected_cell
  _replace_block(selected_block, properties.text)
  _select_at(cell)
  inspector_dialog.hide()

func _delete_selected() -> void:
  if selected_block < 0: return
  _replace_selected_cell("")

# Goal panels express OR between alternatives and AND within each one.
func _add_goal_group(conditions: Dictionary = {}) -> void:
  var group := PanelContainer.new()
  goal_rows.add_child(group)
  var column := VBoxContainer.new()
  group.add_child(column)
  var header := HBoxContainer.new()
  column.add_child(header)
  header.add_child(_label("Solution %d  (all conditions)" % goal_rows.get_child_count()))
  var add := Button.new()
  add.text = "+ Condition"
  add.pressed.connect(func() -> void: _add_goal_row(group.get_meta("rows")))
  header.add_child(add)
  var remove := Button.new()
  remove.text = "Remove solution"
  remove.pressed.connect(func() -> void: group.queue_free())
  header.add_child(remove)
  var rows := VBoxContainer.new()
  column.add_child(rows)
  group.set_meta("rows", rows)
  if conditions.is_empty():
    _add_goal_row(rows)
  else:
    for target in conditions:
      _add_goal_row(rows, str(target), conditions[target])

func _add_goal_row(parent: VBoxContainer, target: String = "electron", values: Array = [1.0, 2.0, 3.0]) -> void:
  var row := HBoxContainer.new()
  parent.add_child(row)
  var target_input := LineEdit.new()
  target_input.text = target
  target_input.placeholder_text = "Particle or cost"
  target_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  target_input.tooltip_text = "Use a particle, cost, or [particle OR particle] expression"
  row.add_child(target_input)
  for value in values:
    var field := LineEdit.new()
    field.text = "inf" if is_inf(float(value)) else str(value)
    field.custom_minimum_size.x = 56
    field.tooltip_text = "Threshold for one, two or three stars (in that order)"
    row.add_child(field)
  _button(row, "×", func() -> void: row.queue_free())

func _open_settings() -> void:
  if parsed.has("error") or parsed.is_empty(): return
  for group in goal_rows.get_children():
    goal_rows.remove_child(group)
    group.queue_free()
  settings_error.text = ""
  title_input.text = str(parsed.get("title", ""))
  hint_input.text = str(parsed.get("hint", ""))
  for goal in parsed.goals:
    _add_goal_group(goal)
  for kind in inventory_fields:
    inventory_fields[kind].value = int(parsed.inventory.get(kind, 0))
  settings_dialog.popup_centered()

func _apply_settings() -> void:
  var declarations := ""
  var nonempty := 0
  for group in goal_rows.get_children():
    if group.is_queued_for_deletion(): continue
    var clauses := PackedStringArray()
    var rows: VBoxContainer = group.get_meta("rows")
    for row in rows.get_children():
      if row.is_queued_for_deletion(): continue
      var target: String = row.get_child(0).text.strip_edges()
      if target.is_empty():
        settings_error.text = "Each condition needs a target."
        return
      var values := PackedStringArray()
      for i in range(1, 4): values.append(row.get_child(i).text.strip_edges())
      clauses.append(target + ": " + ", ".join(values))
    if clauses.is_empty(): continue
    nonempty += 1
    declarations += "goal: {" + "; ".join(clauses) + "};\n"
  if nonempty == 0:
    settings_error.text = "Add at least one condition."
    return
  var inventory_parts := PackedStringArray()
  for kind in inventory_fields:
    var count := int(inventory_fields[kind].value)
    if count > 0: inventory_parts.append("%s=%d" % [kind, count])
  if not inventory_parts.is_empty():
    declarations += "inventory: {" + ", ".join(inventory_parts) + "};\n"
  var lines := PackedStringArray()
  for line in source.text.split("\n"):
    var trimmed := line.strip_edges().to_lower()
    if trimmed.begins_with("title:") or trimmed.begins_with("hint:"):
      continue
    var comment := line.find("#")
    lines.append(line if comment < 0 else line.substr(0, comment) + " ".repeat(line.length() - comment))
  var regex := RegEx.new()
  regex.compile("(?is)\\b(goal|inventory)\\s*:\\s*\\{[^}]*\\}\\s*;?")
  var matches := regex.search_all("\n".join(lines))
  var updated := source.text
  # Remove metadata lines from the original while retaining unrelated comments.
  var metadata_lines := PackedStringArray()
  for line in updated.split("\n"):
    var trimmed := line.strip_edges().to_lower()
    if not trimmed.begins_with("title:") and not trimmed.begins_with("hint:"):
      metadata_lines.append(line)
  updated = "\n".join(metadata_lines)
  # Recompute source offsets after metadata removal.
  lines.clear()
  for line in updated.split("\n"):
    var comment := line.find("#")
    lines.append(line if comment < 0 else line.substr(0, comment) + " ".repeat(line.length() - comment))
  matches = regex.search_all("\n".join(lines))
  for i in range(matches.size() - 1, -1, -1):
    updated = updated.substr(0, matches[i].get_start()) + updated.substr(matches[i].get_end())
  var metadata := ""
  if not title_input.text.strip_edges().is_empty():
    metadata += "title: " + title_input.text.strip_edges().replace(";", ",").replace("\n", " ") + ";\n"
  if not hint_input.text.strip_edges().is_empty():
    metadata += "hint: " + hint_input.text.strip_edges().replace(";", ",").replace("\n", " ") + ";\n"
  updated = metadata + updated + "\n" + declarations
  var result: Dictionary = PARSER.parse(updated)
  if result.has("error"):
    settings_error.text = str(result.error)
    return
  _set_source(updated)
  settings_dialog.hide()

func _level_warnings(data: Dictionary) -> PackedStringArray:
  var warnings := PackedStringArray()
  if data.buildings.is_empty():
    warnings.append("There are no buildings on the board.")
  var has_emitter := false
  var has_detector := false
  var adjustable := false
  for entry in data.buildings:
    if entry.kind == "emitter": has_emitter = true
    if entry.kind == "detector": has_detector = true
    var flags := str(entry.get("fixed", ""))
    var lock_rotation := "c" if entry.kind == "magnet" else "r"
    if "p" not in flags or (entry.kind in ["mirror", "emitter", "magnet"] and lock_rotation not in flags):
      adjustable = true
  if not has_emitter: warnings.append("The board has no particle emitters.")
  if not has_detector: warnings.append("The board has no detector for output goals.")
  for kind in data.inventory:
    if int(data.inventory[kind]) > 0: adjustable = true
  if not adjustable: warnings.append("The player cannot change any building and has no inventory.")
  for goal in data.goals:
    for key in goal:
      var values: Array = goal[key]
      if key == "cost":
        if float(values[1]) > float(values[0]) or float(values[2]) > float(values[1]):
          warnings.append("Higher star tiers should have equal or lower cost limits.")
      elif float(values[1]) < float(values[0]) or float(values[2]) < float(values[1]):
        warnings.append("Higher star tiers should have equal or higher output targets.")
  return warnings

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

func _undo_editor() -> void:
  if undo_stack.is_empty() or is_instance_valid(test_game): return
  redo_stack.append(source.text)
  restoring_source = true
  _set_source(undo_stack.pop_back())
  restoring_source = false

func _redo_editor() -> void:
  if redo_stack.is_empty() or is_instance_valid(test_game): return
  undo_stack.append(source.text)
  restoring_source = true
  _set_source(redo_stack.pop_back())
  restoring_source = false

func _start_playtest() -> void:
  if parsed.has("error") or parsed.is_empty() or is_instance_valid(test_game):
    status.text = "Fix level syntax before playtesting."
    return
  game.hide()
  game.get_node("SimulationControls").visible = false
  editor_panel.hide()
  palette.hide()
  inspector_panel.hide()
  test_game = GAME.instantiate()
  test_game.level_override = parsed.duplicate(true)
  test_game.editor_playtest = true
  add_child(test_game)
  test_game.exit_playtest_requested.connect(_end_playtest)

func _end_playtest() -> void:
  if is_instance_valid(test_game): test_game.queue_free()
  test_game = null
  game.show()
  game.get_node("SimulationControls").visible = true
  editor_panel.show()
  inspector_panel.visible = selected_block >= 0
  palette.visible = selected_block < 0
  game._fit_camera()
