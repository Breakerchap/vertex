extends Control

const PARSER = preload("res://Levels/level_parser.gd")
const PALETTE = preload("res://MainScene/building_palette.gd")
const CATALOG = preload("res://Buildings/building_catalog.gd")
const GAME = preload("res://MainScene/level_game.tscn")
const PARTICLE_PICKER = preload("res://MainScene/particle_picker.gd")
const UI = preload("res://MainScene/workspace_theme.gd")
const NEW_LEVEL := "9 x 9;\n\ngoal: {electron: 1/step, 2/step, 3/step};\n\n"

enum AreaTool { NONE, BLOCK, UNBLOCK }

var source: CodeEdit
var game
var editor_panel: PanelContainer
var inspector_panel: PanelContainer
var inspector_heading: Label
var test_game
var editor_heading: Label
var inspector_dialog: AcceptDialog
var source_dialog: AcceptDialog
var source_error: Label
var status: Label
var property_form: VBoxContainer
var property_fields: Array[Control] = []
var property_prefix := ""
var property_suffix := ""
var palette: PanelContainer
var block_area_button: Button
var unblock_area_button: Button
var area_tool := AreaTool.NONE
var width_input: SpinBox
var height_input: SpinBox
var file_dialog: FileDialog
var confirm: ConfirmationDialog
var path := ""
var last_file_directory := ""
var return_to_source := false
var saved_text := NEW_LEVEL
var pending_action := ""
var blocks: Array[Dictionary] = []
var selected_block := -1
var selected_cell := Vector2i(-1, -1)
var selected_building: Node
var copied_declaration := ""
var copied_origin := Vector2i.ZERO
var pasting := false
var visual_fields := {}
var visual_form: VBoxContainer
var settings_error: Label
var property_error: Label
var declaration_error: Label
var edit_range := false
var settings_dialog: AcceptDialog
var title_input: LineEdit
var hint_input: LineEdit
var rotation_input: OptionButton
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
  _build_workspace()
  _build_dialogs()
  _set_source(NEW_LEVEL)
  undo_stack.clear()
  source_snapshot = source.text

func _exit_tree() -> void:
  get_tree().auto_accept_quit = true

func _unhandled_key_input(event: InputEvent) -> void:
  if is_instance_valid(test_game) or not (event is InputEventKey and event.pressed and not event.echo): return
  if UI.is_primary_shortcut(event):
    if game.simulating: return
    if event.keycode == KEY_S:
      if event.shift_pressed: _save_as()
      else: _save()
    elif event.keycode == KEY_Z:
      if event.shift_pressed: _redo_editor()
      else: _undo_editor()
    elif event.shift_pressed: return
    elif event.keycode == KEY_N: _request_action("new")
    elif event.keycode == KEY_O: _request_action("open")
    elif event.keycode == KEY_Y: _redo_editor()
    elif event.keycode == KEY_C: _copy_selected()
    elif event.keycode == KEY_V: _paste_at_cursor()
    else: return
  elif event.get_modifiers_mask() != 0: return
  elif event.keycode == KEY_ESCAPE:
    if game.simulating: _reset_preview()
    _select_move_tool()
  elif game.simulating: return
  elif event.keycode == KEY_Q: _rotate_block(-1)
  elif event.keycode in [KEY_E, KEY_R]: _rotate_block(1)
  elif event.keycode in [KEY_DELETE, KEY_BACKSPACE]: _delete_selected()
  else: return
  get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
  if what == NOTIFICATION_WM_CLOSE_REQUEST and is_instance_valid(confirm) and not confirm.visible:
    for dialog in [source_dialog, settings_dialog, inspector_dialog]:
      dialog.hide()
    _request_action("quit")

func _build_workspace() -> void:
  mouse_filter = Control.MOUSE_FILTER_IGNORE
  game = GAME.instantiate()
  game.editor_preview = true
  add_child(game)
  game.editor_sidebar_width = 290
  game.editor_cell_clicked.connect(_board_click)
  game.editor_cell_dragged.connect(_move_block)
  game.editor_area_selected.connect(_edit_build_area)

  var hud := CanvasLayer.new()
  add_child(hud)
  editor_heading = UI.label("Level editor")
  UI.heading(editor_heading, 21)
  editor_heading.set_anchors_preset(Control.PRESET_TOP_RIGHT)
  editor_heading.offset_left = -290
  editor_heading.offset_top = 23
  hud.add_child(editor_heading)
  var panel := PanelContainer.new()
  editor_panel = panel
  hud.add_child(panel)
  panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
  panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
  panel.offset_left = 16
  panel.offset_right = -306
  panel.offset_top = -137
  panel.offset_bottom = -16
  panel.theme = UI.theme()
  panel.resized.connect(_update_camera_inset)
  var margin := UI.margin(10)
  panel.add_child(margin)
  var column := VBoxContainer.new()
  column.add_theme_constant_override("separation", 8)
  margin.add_child(column)
  var bar := HFlowContainer.new()
  bar.add_theme_constant_override("separation", 6)
  column.add_child(bar)
  UI.button(bar, "New", func() -> void: _request_action("new")).tooltip_text = UI.shortcut_label("N")
  UI.button(bar, "Open…", func() -> void: _request_action("open")).tooltip_text = UI.shortcut_label("O")
  UI.button(bar, "Save", _save).tooltip_text = UI.shortcut_label("S")
  UI.button(bar, "Save as…", _save_as).tooltip_text = UI.shortcut_label("Shift+S")
  UI.button(bar, "Undo", _undo_editor).tooltip_text = UI.shortcut_label("Z")
  UI.button(bar, "Redo", _redo_editor).tooltip_text = UI.shortcut_label("Shift+Z")
  UI.button(bar, "Copy", _copy_selected).tooltip_text = "Copy the selected building (%s)" % UI.shortcut_label("C")
  UI.button(bar, "Paste", _start_paste).tooltip_text = "Click a cell to paste, or hover over it and press %s" % UI.shortcut_label("V")
  UI.button(bar, "Source…", _open_source)
  UI.button(bar, "Levels", func() -> void: _request_action("back"))
  status = Label.new()
  status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
  UI.muted(status)
  var controls := HFlowContainer.new()
  controls.add_theme_constant_override("separation", 6)
  column.add_child(controls)
  controls.add_child(UI.label("Grid"))
  width_input = _spin(controls)
  controls.add_child(UI.label("x"))
  height_input = _spin(controls)
  width_input.value_changed.connect(_resize_board)
  height_input.value_changed.connect(_resize_board)
  block_area_button = UI.button(controls, "Block area", _toggle_area_tool.bind(AreaTool.BLOCK))
  block_area_button.toggle_mode = true
  block_area_button.tooltip_text = "Drag across cells to block player building placement. Esc exits the tool."
  unblock_area_button = UI.button(controls, "Unblock area", _toggle_area_tool.bind(AreaTool.UNBLOCK))
  unblock_area_button.toggle_mode = true
  unblock_area_button.tooltip_text = "Drag across cells to allow player building placement. Esc exits the tool."
  palette = PALETTE.new()
  palette.infinite = true
  hud.add_child(palette)
  palette.offset_left = -290
  game.external_palette = palette
  palette.kind_selected.connect(_select_palette_kind)
  palette.kind_dropped.connect(_drop_palette_kind)
  UI.button(controls, "Level settings…", _open_settings)
  UI.button(controls, "Reset preview", _reset_preview)
  UI.button(controls, "Playtest", _start_playtest).theme_type_variation = "PrimaryButton"
  column.add_child(status)

  _build_inspector(hud)

func _build_inspector(hud: CanvasLayer) -> void:
  inspector_panel = PanelContainer.new()
  hud.add_child(inspector_panel)
  inspector_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
  inspector_panel.offset_left = -290
  inspector_panel.offset_right = -16
  inspector_panel.offset_top = 72
  inspector_panel.offset_bottom = -16
  inspector_panel.theme = UI.theme()
  var inspector_margin := UI.margin(12)
  inspector_panel.add_child(inspector_margin)
  var inspector_column := VBoxContainer.new()
  inspector_column.add_theme_constant_override("separation", 10)
  inspector_margin.add_child(inspector_column)
  inspector_heading = UI.label("Selected building")
  UI.heading(inspector_heading)
  inspector_column.add_child(inspector_heading)
  var inspector_actions := HFlowContainer.new()
  inspector_column.add_child(inspector_actions)
  UI.button(inspector_actions, "Tools", _select_move_tool)
  UI.button(inspector_actions, "Remove  " + UI.delete_key_label(), _delete_selected)
  var inspector_scroll := ScrollContainer.new()
  inspector_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
  inspector_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
  inspector_column.add_child(inspector_scroll)
  visual_form = VBoxContainer.new()
  visual_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  inspector_scroll.add_child(visual_form)
  property_error = UI.label("")
  property_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
  property_error.add_theme_color_override("font_color", UI.ERROR)
  inspector_column.add_child(property_error)
  UI.button(inspector_column, "Advanced properties…", _open_properties)
  inspector_panel.hide()

func _build_dialogs() -> void:
  inspector_dialog = AcceptDialog.new()
  inspector_dialog.ok_button_text = "Close"
  UI.setup_dialog(inspector_dialog, self, "Properties")
  var scroll := ScrollContainer.new()
  scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
  inspector_dialog.add_child(scroll)
  var inspector := VBoxContainer.new()
  inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  inspector.add_theme_constant_override("separation", 8)
  scroll.add_child(inspector)
  property_form = VBoxContainer.new()
  inspector.add_child(property_form)
  declaration_error = UI.label("")
  declaration_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
  declaration_error.add_theme_color_override("font_color", UI.ERROR)
  inspector.add_child(declaration_error)

  _build_source_dialog()
  _build_settings_dialog()
  _build_file_dialogs()

func _build_source_dialog() -> void:
  source_dialog = AcceptDialog.new()
  source_dialog.ok_button_text = "Close"
  UI.setup_dialog(source_dialog, self, "Level source")
  var column := VBoxContainer.new()
  source_dialog.add_child(column)
  source = CodeEdit.new()
  source.set_draw_line_numbers(true)
  var highlighter := CodeHighlighter.new()
  highlighter.number_color = Color("e6b66c")
  highlighter.symbol_color = Color("a6c8e8")
  highlighter.add_color_region("#", "", Color("8192a4"), true)
  for word in CATALOG.SCENES.keys() + ["goal", "inventory", "no_build", "magnetic_field", "mirror", "rotation"]:
    highlighter.add_keyword_color(word, Color("7bd9bd"))
  for word in ["x", "y", "fixed", "rate", "AND", "OR"]:
    highlighter.add_keyword_color(word, Color("b5a6f1"))
  source.syntax_highlighter = highlighter
  source.size_flags_vertical = Control.SIZE_EXPAND_FILL
  source.text_changed.connect(_source_changed)
  source.gui_input.connect(_handle_source_shortcut)
  column.add_child(source)
  source_error = UI.label("")
  source_error.max_lines_visible = 3
  source_error.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
  source_error.add_theme_color_override("font_color", UI.ERROR)
  column.add_child(source_error)

func _open_source() -> void:
  source_dialog.popup_centered_clamped(Vector2i(840, 560), 0.88)
  source.grab_focus()

func _handle_source_shortcut(event: InputEvent) -> void:
  if not (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_S and UI.is_primary_shortcut(event)): return
  source.accept_event()
  if event.shift_pressed: _save_as()
  else: _save()

func _build_settings_dialog() -> void:
  settings_dialog = AcceptDialog.new()
  settings_dialog.ok_button_text = "Cancel"
  UI.setup_dialog(settings_dialog, self, "Level settings")
  var settings_root := VBoxContainer.new()
  settings_dialog.add_child(settings_root)
  var settings_scroll := ScrollContainer.new()
  settings_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
  settings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
  settings_root.add_child(settings_scroll)
  var settings_column := VBoxContainer.new()
  settings_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  settings_scroll.add_child(settings_column)
  settings_column.add_child(UI.label("Level title"))
  title_input = LineEdit.new()
  title_input.placeholder_text = "e.g. First Contact"
  settings_column.add_child(title_input)
  settings_column.add_child(UI.label("Short objective hint (avoid spoilers)"))
  hint_input = LineEdit.new()
  hint_input.placeholder_text = "e.g. Guide a photon into the detector"
  settings_column.add_child(hint_input)
  settings_column.add_child(UI.label("Player rotation"))
  rotation_input = OptionButton.new()
  rotation_input.add_item("8 directions (45 degrees)", 8)
  rotation_input.add_item("4 directions (90 degrees)", 4)
  settings_column.add_child(rotation_input)
  var goal_title := UI.label("Goals")
  UI.heading(goal_title)
  settings_column.add_child(goal_title)
  var goal_help := UI.label("Meet every condition in any one solution to earn stars.")
  UI.muted(goal_help)
  settings_column.add_child(goal_help)
  goal_rows = VBoxContainer.new()
  goal_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  settings_column.add_child(goal_rows)
  UI.button(settings_column, "+ Add alternative solution", func() -> void: _add_goal_group())
  var inventory_title := UI.label("Starting inventory")
  UI.heading(inventory_title)
  settings_column.add_child(inventory_title)
  for kind in CATALOG.SCENES:
    var row := HBoxContainer.new()
    settings_column.add_child(row)
    var label := UI.label(str(kind).capitalize())
    label.custom_minimum_size.x = 120
    row.add_child(label)
    var count := _spin(row)
    count.min_value = 0
    inventory_fields[kind] = count
  settings_error = UI.label("")
  settings_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
  settings_error.add_theme_color_override("font_color", UI.ERROR)
  settings_root.add_child(settings_error)
  UI.button(settings_root, "Apply settings", _apply_settings).theme_type_variation = "PrimaryButton"

func _build_file_dialogs() -> void:
  file_dialog = FileDialog.new()
  file_dialog.access = FileDialog.ACCESS_FILESYSTEM
  file_dialog.use_native_dialog = true
  file_dialog.mode_overrides_title = false
  file_dialog.file_selected.connect(_file_selected)
  file_dialog.canceled.connect(_restore_source_after_file_dialog)
  UI.setup_dialog(file_dialog, self, "Open level")
  confirm = ConfirmationDialog.new()
  confirm.dialog_text = "Discard unsaved changes?"
  confirm.ok_button_text = "Discard changes"
  confirm.confirmed.connect(_perform_pending_action, CONNECT_DEFERRED)
  UI.setup_dialog(confirm, self, "Unsaved level")

func _select_move_tool() -> void:
  _select_palette_kind("")

func _select_palette_kind(kind: String) -> void:
  if area_tool != AreaTool.NONE: _set_area_tool(AreaTool.NONE)
  pasting = false
  palette.selected = kind
  palette.refresh()
  _select_block(-1)

func _drop_palette_kind(kind: String, screen_position: Vector2) -> void:
  if game.simulating or parsed.has("error") or parsed.is_empty(): return
  var cell: Vector2i = game.screen_to_cell(screen_position)
  if not game.is_cell_on_board(cell): return
  if area_tool != AreaTool.NONE: _set_area_tool(AreaTool.NONE)
  var facing: String = game._edge_facing(cell, game.get_canvas_transform().affine_inverse() * screen_position) if kind == "edge_wall" else "E"
  _place_editor_kind(kind, cell, facing)

func _update_camera_inset() -> void:
  if not is_instance_valid(game) or not is_instance_valid(editor_panel): return
  game.editor_bottom_inset = editor_panel.size.y + 16.0
  game._fit_camera()

func _reset_preview() -> void:
  game._load_initial_board()
  if selected_block >= 0:
    var entry: Dictionary = blocks[selected_block].entries[0]
    selected_building = game._building_at(selected_cell, entry.kind, entry.facing)
    game.selected_building = selected_building

func _spin(parent: Node) -> SpinBox:
  var spin := SpinBox.new()
  spin.min_value = 1
  spin.max_value = 200
  spin.allow_greater = true
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
  parsed = PARSER.parse(source.text)
  _select_block(-1)
  blocks.clear()
  block_area_button.disabled = parsed.has("error")
  unblock_area_button.disabled = block_area_button.disabled
  if parsed.has("error"):
    _set_area_tool(AreaTool.NONE)
    source_error.text = "Source error: " + str(parsed.error)
    source_error.tooltip_text = source_error.text
    status.text = "Invalid source • Showing last valid board"
    status.tooltip_text = str(parsed.error)
    status.add_theme_color_override("font_color", UI.ERROR)
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
  _update_level_status()

func _update_level_status() -> void:
  var warnings := _level_warnings(parsed)
  status.text = (path.get_file() if not path.is_empty() else "Untitled") + ("  • unsaved" if source.text != saved_text else "")
  if area_tool != AreaTool.NONE:
    var action := "block" if area_tool == AreaTool.BLOCK else "unblock"
    status.text += "  • Drag to %s an area. Esc exits." % action
  elif not warnings.is_empty():
    status.text += "  • %d warning(s)" % warnings.size()
  status.tooltip_text = "\n".join(warnings)
  status.add_theme_color_override("font_color", UI.MUTED)
  source_error.text = "\n".join(warnings)
  source_error.tooltip_text = source_error.text

# Mask comments without changing offsets so editing preserves the original text.
func _index_blocks() -> void:
  var masked := PARSER.mask_comments(source.text)
  for span in PARSER.find_blocks(masked):
    var kind := PARSER.building_kind(span.get_string(1))
    if not CATALOG.SCENES.has(kind):
      continue
    var building := PARSER.parse_building(kind, span.get_string(2), parsed.width, parsed.height, parsed.legacy_rates)
    if building.has("error") or building.entries.is_empty():
      continue
    var start := span.get_start()
    var text := source.text.substr(start, span.get_end(2) + 1 - start)
    blocks.append({"start": start, "end": span.get_end(), "text": text, "entries": building.entries})

func _resize_board(_value: float) -> void:
  if updating: return
  var found: RegExMatch = PARSER.find_dimensions(PARSER.mask_comments(source.text))
  if found == null: return
  var updated := source.text.left(found.get_start()) + "%d x %d" % [int(width_input.value), int(height_input.value)] + source.text.substr(found.get_end())
  var result := PARSER.parse(updated)
  if result.has("error"):
    status.text = result.error
    updating = true
    width_input.value = int(found.get_string(1))
    height_input.value = int(found.get_string(2))
    updating = false
    return
  _set_source(updated)

func _toggle_area_tool(tool: AreaTool) -> void:
  if game.simulating:
    block_area_button.set_pressed_no_signal(area_tool == AreaTool.BLOCK)
    unblock_area_button.set_pressed_no_signal(area_tool == AreaTool.UNBLOCK)
    return
  var next := AreaTool.NONE if area_tool == tool else tool
  _select_move_tool()
  _set_area_tool(next)

func _set_area_tool(tool: AreaTool) -> void:
  area_tool = tool
  block_area_button.set_pressed_no_signal(tool == AreaTool.BLOCK)
  unblock_area_button.set_pressed_no_signal(tool == AreaTool.UNBLOCK)
  game.area_selection_enabled = tool != AreaTool.NONE
  game.area_origin = Vector2i(-1, -1)
  game.drag_cell = Vector2i(-1, -1)
  if not parsed.has("error"): _update_level_status()

func _edit_build_area(selection: Rect2i) -> void:
  if parsed.has("error") or area_tool == AreaTool.NONE: return
  var restricting := area_tool == AreaTool.BLOCK
  var areas: Array = parsed.no_build_areas
  if restricting:
    for area in areas:
      if area.encloses(selection): return

  var spans: Array[RegExMatch] = []
  for span in PARSER.find_blocks(PARSER.mask_comments(source.text)):
    if span.get_string(1).to_lower() == "no_build": spans.append(span)
  var updated := source.text
  for index in range(areas.size() - 1, -1, -1):
    var area: Rect2i = areas[index]
    var overlap := area.intersection(selection)
    if not overlap.has_area(): continue
    var remaining := PackedStringArray()
    # Keep two horizontal strips and the sides between them.
    var strips := [
      Rect2i(area.position.x, area.position.y, area.size.x, overlap.position.y - area.position.y),
      Rect2i(area.position.x, overlap.end.y, area.size.x, area.end.y - overlap.end.y),
      Rect2i(area.position.x, overlap.position.y, overlap.position.x - area.position.x, overlap.size.y),
      Rect2i(overlap.end.x, overlap.position.y, area.end.x - overlap.end.x, overlap.size.y),
    ]
    for strip in strips:
      if strip.has_area(): remaining.append(_build_area_declaration(strip))
    var span := spans[index]
    updated = updated.left(span.get_start()) + "\n".join(remaining) + updated.substr(span.get_end())
  if restricting:
    updated = updated.trim_suffix("\n") + "\n" + _build_area_declaration(selection) + "\n"
  if updated != source.text: _set_source(updated)

func _build_area_declaration(area: Rect2i) -> String:
  var first := area.position
  var last := area.end - Vector2i.ONE
  var xs := str(first.x) if first.x == last.x else "%d..%d" % [first.x, last.x]
  var ys := str(first.y) if first.y == last.y else "%d..%d" % [first.y, last.y]
  return "no_build: {x=%s, y=%s};" % [xs, ys]

func _board_click(cell: Vector2i, button: int, target: Node = null, facing := "E") -> void:
  if parsed.has("error"): return
  if target == null: target = game._building_at(cell)
  if button == MOUSE_BUTTON_RIGHT:
    pasting = false
    if target != null: _select_building(target)
    else: _select_move_tool()
    return
  if button != MOUSE_BUTTON_LEFT: return
  if pasting:
    _paste_building(cell)
    return
  if not palette.selected.is_empty() and game._building_at(cell, palette.selected, facing) == null:
    _place_editor_kind(palette.selected, cell, facing)
    return
  if target != null:
    palette.selected = ""
    palette.refresh()
    _select_building(target)
    return
  if selected_block >= 0 and selected_cell != cell:
    _move_block(selected_cell, cell)
    return
  _select_block(-1)

func _select_building(building: Node) -> void:
  var entry: Dictionary = building.get_meta("entry")
  var cell: Vector2i = building.get_meta("cell")
  _select_at(cell, entry.kind, entry.facing)

func _select_block(index: int, cell: Vector2i = Vector2i(-1, -1)) -> void:
  edit_range = false
  selected_block = index
  selected_cell = cell
  selected_building = null
  if index >= 0:
    var entry: Dictionary = blocks[index].entries[0]
    selected_building = game._building_at(cell, entry.kind, entry.facing)
    inspector_heading.text = "%s  (%d, %d)" % [str(entry.kind).capitalize(), cell.x, cell.y]
  game.selected_building = selected_building
  if is_instance_valid(inspector_panel): inspector_panel.visible = index >= 0
  if is_instance_valid(palette): palette.visible = index < 0
  _build_visual_form()
  if index < 0: _clear_property_form()

func _place_editor_kind(kind: String, cell: Vector2i, facing := "E") -> void:
  if game._building_at(cell, kind, facing) != null:
    status.text = "That position is occupied."
    return
  var extra := ""
  if kind == "emitter": extra = ", E, rate=1/step"
  elif kind == "detector": extra = ", [photon]"
  elif kind == "edge_wall": extra = ", " + facing
  _set_source(source.text.trim_suffix("\n") + "\n%s: {x=%d, y=%d%s};\n" % [kind, cell.x, cell.y, extra])
  _select_at(cell, kind, facing)

func _select_at(cell: Vector2i, kind := "", facing := "E") -> void:
  var key := CATALOG.occupancy_key(kind, cell, facing)
  for index in range(blocks.size()):
    for entry in blocks[index].entries:
      var anchor := Vector2i(entry.x, entry.y)
      if CATALOG.occupancy_key(entry.kind, anchor, entry.facing) == key:
        _select_block(index, anchor)
        return

func _copy_selected() -> void:
  if selected_block < 0 or game.simulating: return
  var block: Dictionary = blocks[selected_block]
  var first: Dictionary = block.entries[0]
  copied_origin = Vector2i(first.x, first.y) if edit_range else selected_cell
  copied_declaration = block.text if edit_range else _single_declaration(block.text, selected_cell)
  if parsed.legacy_rates and first.kind == "emitter":
    copied_declaration = _explicit_emitter_rate(copied_declaration, first.rate)
  status.text = "Copied %s." % str(first.kind).replace("_", " ")

func _start_paste() -> void:
  if game.simulating or copied_declaration.is_empty(): return
  _select_move_tool()
  pasting = true
  status.text = "Click a cell to paste the copied building."

func _paste_at_cursor() -> void:
  if game.simulating or copied_declaration.is_empty(): return
  if area_tool != AreaTool.NONE: _set_area_tool(AreaTool.NONE)
  var cell: Vector2i = game._mouse_cell()
  if not game.is_cell_on_board(cell):
    _start_paste()
  elif not _paste_building(cell):
    pasting = true

func _paste_building(cell: Vector2i) -> bool:
  if copied_declaration.is_empty() or parsed.has("error"): return false
  var declaration := copied_declaration
  var offset := cell - copied_origin
  for axis in ["x", "y"]:
    var regex := RegEx.new()
    regex.compile("(?i)\\b" + axis + "\\s*=\\s*([+-]?\\d+)(?:\\.\\.([+-]?\\d+))?")
    var found := regex.search(PARSER.mask_comments(declaration))
    if found == null: return false
    var shift := offset.x if axis == "x" else offset.y
    var coordinates := "%s=%d" % [axis, int(found.get_string(1)) + shift]
    if not found.get_string(2).is_empty():
      coordinates += "..%d" % (int(found.get_string(2)) + shift)
    declaration = declaration.left(found.get_start()) + coordinates + declaration.substr(found.get_end())
  var updated := source.text.trim_suffix("\n") + "\n" + declaration.trim_suffix(";") + ";\n"
  var result := PARSER.parse(updated)
  if result.has("error"):
    status.text = result.error
    return false
  pasting = false
  var entry: Dictionary = result.buildings.back()
  _set_source(updated)
  _select_at(cell, entry.kind, entry.facing)
  return true

func _single_declaration(text_value: String, cell: Vector2i) -> String:
  var result := text_value
  for axis in ["x", "y"]:
    var regex := RegEx.new()
    regex.compile("(?i)\\b" + axis + "\\s*=\\s*[+-]?\\d+(?:\\.\\.[+-]?\\d+)?")
    var found := regex.search(PARSER.mask_comments(result))
    if found != null:
      var value := cell.x if axis == "x" else cell.y
      result = result.left(found.get_start()) + "%s=%d" % [axis, value] + result.substr(found.get_end())
  return result

func _replace_selected_cell(replacement: String) -> bool:
  if selected_block < 0: return false
  var block: Dictionary = blocks[selected_block]
  var declarations := PackedStringArray()
  if edit_range:
    if not replacement.is_empty(): declarations.append(replacement.trim_suffix(";"))
  else:
    for entry in block.entries:
      var cell := Vector2i(entry.x, entry.y)
      if cell == selected_cell:
        if not replacement.is_empty(): declarations.append(replacement.trim_suffix(";"))
      else:
        declarations.append(_single_declaration(block.text, cell).trim_suffix(";"))
  return _replace_block(selected_block, ";\n".join(declarations))

func _move_block(from_cell: Vector2i, to_cell: Vector2i) -> void:
  if parsed.has("error") or from_cell == to_cell: return
  if selected_cell != from_cell: _select_at(from_cell)
  if selected_block < 0 or selected_cell != from_cell: return
  if not game.is_cell_on_board(to_cell):
    _delete_selected()
    return
  var block: Dictionary = blocks[selected_block]
  var entry: Dictionary = block.entries[0]
  if game._building_at(to_cell, entry.kind, entry.facing) != null: return
  var replacement := _single_declaration(block.text, to_cell)
  if _replace_selected_cell(replacement): _select_at(to_cell, entry.kind, entry.facing)

func _rotate_block(turn: int = 1) -> void:
  if selected_block < 0 or game.simulating: return
  if visual_fields.has("polarity"):
    visual_fields.polarity.select(1 - visual_fields.polarity.selected)
  elif visual_fields.has("colour"):
    visual_fields.colour.select(posmod(visual_fields.colour.selected + turn, CATALOG.FILTER_COLOURS.size()))
  elif visual_fields.has("facing"):
    var field: OptionButton = visual_fields.facing
    var entry: Dictionary = blocks[selected_block].entries[0]
    var rotation := int(entry.get("rotation", parsed.rotation_steps))
    if visual_fields.has("rotation") and visual_fields.rotation.get_selected_id() != 0:
      rotation = visual_fields.rotation.get_selected_id()
    var orientation := CATALOG.DIRECTIONS.find(field.get_item_text(field.selected))
    var next := CATALOG.next_orientation(orientation, turn, 4 if entry.kind == "edge_wall" else rotation)
    field.select(CATALOG.CARDINALS.find(CATALOG.DIRECTIONS[next]) if entry.kind == "edge_wall" else next)
  else:
    return
  _apply_visual_properties()

func _visual_row(label_text: String, control: Control) -> void:
  var row := HBoxContainer.new()
  visual_form.add_child(row)
  var label := UI.label(label_text)
  label.custom_minimum_size.x = 92
  row.add_child(label)
  control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  row.add_child(control)

func _coordinate_row(axis: String, maximum: int, start: int, end: int) -> void:
  var inputs := HBoxContainer.new()
  for item in [start, end]:
    if inputs.get_child_count() > 0: inputs.add_child(UI.label("to"))
    var field := SpinBox.new()
    field.max_value = maximum
    field.value = item
    field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    field.get_line_edit().custom_minimum_size.x = 0
    inputs.add_child(field)
    visual_fields[axis if not visual_fields.has(axis) else axis + "_end"] = field
  _visual_row(axis.to_upper(), inputs)

func _build_visual_form() -> void:
  _clear_children(visual_form)
  visual_fields.clear()
  property_error.text = ""
  if selected_block < 0: return
  var block: Dictionary = blocks[selected_block]
  var entry: Dictionary = block.entries[0]
  if block.entries.size() > 1:
    var entire := CheckBox.new()
    entire.text = "Edit all %d cells in range" % block.entries.size()
    entire.button_pressed = edit_range
    entire.toggled.connect(func(value: bool) -> void:
      edit_range = value
      _build_visual_form()
    )
    visual_form.add_child(entire)
  var first := Vector2i(entry.x, entry.y) if edit_range else selected_cell
  var last_entry: Dictionary = block.entries.back()
  var last := Vector2i(last_entry.x, last_entry.y) if edit_range else selected_cell
  _coordinate_row("x", parsed.width - 1, first.x, last.x)
  _coordinate_row("y", parsed.height - 1, first.y, last.y)
  if (entry.kind in CATALOG.FACING_KINDS or entry.kind == "edge_wall") or entry.facing != "E":
    var direction := OptionButton.new()
    var directions: Array = CATALOG.CARDINALS if entry.kind == "edge_wall" else CATALOG.DIRECTIONS
    for name in directions: direction.add_item(name)
    direction.select(directions.find(entry.facing))
    _visual_row("Direction", direction)
    visual_fields.facing = direction
  if entry.kind in CATALOG.FACING_KINDS:
    var rotation := OptionButton.new()
    rotation.add_item("Level default", 0)
    rotation.add_item("8 directions", 8)
    rotation.add_item("4 directions", 4)
    rotation.select(rotation.get_item_index(entry.get("rotation", 0)))
    _visual_row("Rotation", rotation)
    visual_fields.rotation = rotation
  if entry.kind == "magnet":
    var polarity := OptionButton.new()
    polarity.add_item("Positive")
    polarity.add_item("Negative")
    polarity.select(1 if str(entry.get("polarity", "+")) in CATALOG.NEGATIVE_POLARITIES else 0)
    _visual_row("Polarity", polarity)
    visual_fields.polarity = polarity
  match entry.kind:
    "filter":
      _option_row("colour", "Colour", CATALOG.FILTER_COLOURS, entry.get("colour", "red"))
    "gate":
      var open := CheckBox.new()
      open.text = "Start open"
      open.button_pressed = entry.get("open", "false") == "true"
      visual_form.add_child(open)
      visual_fields.open = open
  if entry.kind in CATALOG.ROTATABLE_KINDS:
    var turns := HFlowContainer.new()
    visual_form.add_child(turns)
    if entry.kind == "magnet":
      UI.button(turns, "Flip polarity  Q / E", _rotate_block)
    elif entry.kind == "filter":
      UI.button(turns, "Change colour  E", _rotate_block)
    else:
      UI.button(turns, "↶  Q", _rotate_block.bind(-1)).tooltip_text = "Rotate counterclockwise"
      UI.button(turns, "↷  E", _rotate_block.bind(1)).tooltip_text = "Rotate clockwise"
  if entry.kind in ["emitter", "detector"]:
    var heading := UI.label("Emission order" if entry.kind == "emitter" else "Accepted particles")
    UI.heading(heading, 15)
    visual_form.add_child(heading)
    var particles := PARTICLE_PICKER.new()
    particles.sequence = entry.kind == "emitter"
    if particles.sequence:
      particles.load_text(", ".join(entry.particles))
    else:
      particles.load_text(entry.get("particle_expression", ""))
    visual_form.add_child(particles)
    visual_fields.particles = particles
  if entry.kind == "emitter":
    var rate := SpinBox.new()
    rate.min_value = 0.0
    rate.max_value = 1000.0
    rate.allow_greater = true
    rate.step = 0.0
    rate.value = float(entry.rate)
    _visual_row("Rate / step", rate)
    visual_fields.rate = rate
  var fixed_position := CheckBox.new()
  fixed_position.text = "Lock position"
  fixed_position.button_pressed = "p" in str(entry.fixed)
  visual_form.add_child(fixed_position)
  visual_fields.fixed_position = fixed_position
  if entry.kind in CATALOG.ROTATABLE_KINDS:
    var fixed_rotation := CheckBox.new()
    fixed_rotation.text = {"magnet": "Lock polarity", "filter": "Lock colour"}.get(entry.kind, "Lock rotation")
    fixed_rotation.button_pressed = CATALOG.rotation_lock_flag(entry.kind) in str(entry.fixed)
    visual_form.add_child(fixed_rotation)
    visual_fields.fixed_rotation = fixed_rotation
  for field in visual_fields.values():
    if field is OptionButton:
      field.item_selected.connect(func(_index: int) -> void: _apply_from_field.call_deferred(field))
    elif field is CheckBox:
      field.toggled.connect(func(_value: bool) -> void: _apply_from_field.call_deferred(field))
    elif field is SpinBox:
      field.value_changed.connect(func(_value: float) -> void: _apply_from_field.call_deferred(field))
    else:
      field.changed.connect(func() -> void: _apply_from_field.call_deferred(field))

func _apply_from_field(field: Control) -> void:
  if not is_instance_valid(field) or field not in visual_fields.values(): return
  if not edit_range:
    for axis in ["x", "y"]:
      if field != visual_fields[axis]: continue
      var original := selected_cell.x if axis == "x" else selected_cell.y
      var end: SpinBox = visual_fields[axis + "_end"]
      if end.value == original: end.set_value_no_signal(field.value)
  _apply_visual_properties()

func _option_row(key: String, title: String, values: Array, selected: String) -> void:
  var field := OptionButton.new()
  for value in values: field.add_item(value.capitalize())
  field.select(values.find(selected))
  _visual_row(title, field)
  visual_fields[key] = field

func _apply_visual_properties() -> void:
  if selected_block < 0: return
  var entry: Dictionary = blocks[selected_block].entries[0]
  var destination := Vector2i(int(visual_fields.x.value), int(visual_fields.y.value))
  var end := Vector2i(int(visual_fields.x_end.value), int(visual_fields.y_end.value))
  var parts: PackedStringArray = ["x=%d" % destination.x, "y=%d" % destination.y]
  if destination.x != end.x: parts[0] += "..%d" % end.x
  if destination.y != end.y: parts[1] += "..%d" % end.y
  var facing: String = visual_fields.facing.get_item_text(visual_fields.facing.selected) if visual_fields.has("facing") else "E"
  if visual_fields.has("facing"): parts.append(facing)
  if visual_fields.has("rotation") and visual_fields.rotation.get_selected_id() != 0:
    parts.append("rotation=%d" % visual_fields.rotation.get_selected_id())
  if visual_fields.has("colour"): parts.append("colour=" + CATALOG.FILTER_COLOURS[visual_fields.colour.selected])
  if visual_fields.has("open"): parts.append("open=" + str(visual_fields.open.button_pressed))
  if visual_fields.has("polarity"): parts.append("-" if visual_fields.polarity.selected == 1 else "+")
  if visual_fields.has("particles"):
    var expression: String = visual_fields.particles.source_text()
    if not expression.is_empty(): parts.append("[" + expression + "]")
  elif not entry.particles.is_empty():
    parts.append("[" + ", ".join(entry.particles) + "]")
  if visual_fields.has("rate"):
    parts.append("rate=%s/step" % String.num_scientific(visual_fields.rate.value))
  var fixed := str(entry.fixed).replace("p", "")
  if visual_fields.fixed_position.button_pressed: fixed += "p"
  if visual_fields.has("fixed_rotation"):
    var flag := CATALOG.rotation_lock_flag(entry.kind)
    fixed = fixed.replace(flag, "")
    if visual_fields.fixed_rotation.button_pressed: fixed += flag
  if not fixed.is_empty(): parts.append("fixed=" + fixed)
  for key in entry:
    if key not in ["kind", "x", "y", "facing", "fixed", "rate", "particles", "accepted", "polarity", "particle_expression", "colour", "travel", "track", "open", "rotation"]:
      parts.append("%s=%s" % [key, entry[key]])
  var replacement := "%s: {%s}" % [entry.kind, ", ".join(parts)]
  var keep_range := edit_range and destination != end
  if _replace_selected_cell(replacement):
    _select_at(destination, entry.kind, facing)
    if keep_range:
      edit_range = true
      _build_visual_form()

func _open_properties() -> void:
  if selected_block < 0: return
  var declaration: String = PARSER.mask_comments(blocks[selected_block].text).replace("\n", " ")
  if not edit_range: declaration = _single_declaration(declaration, selected_cell)
  declaration_error.text = ""
  _build_property_form(declaration)
  inspector_dialog.popup_centered_clamped(Vector2i(560, 340), 0.88)

func _clear_property_form() -> void:
  property_fields.clear()
  _clear_children(property_form)

func _clear_children(parent: Node) -> void:
  for child in parent.get_children():
    parent.remove_child(child)
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
  var regex := RegEx.new()
  regex.compile("\\[[^\\]]*\\]|[^,\\[\\]]+")
  for match_part in regex.search_all(body):
    var part := match_part.get_string().strip_edges()
    if part.is_empty(): continue
    var field: Control
    if part.begins_with("["):
      var particle_field := PARTICLE_PICKER.new()
      particle_field.sequence = blocks[selected_block].entries[0].kind != "detector"
      particle_field.load_text(part.substr(1, part.length() - 2))
      field = particle_field
    else:
      var text_field := LineEdit.new()
      text_field.text = part
      field = text_field
    property_form.add_child(field)
    property_fields.append(field)
    if field is LineEdit:
      field.text_submitted.connect(func(_value: String) -> void: _apply_advanced_field.call_deferred(field))
      field.focus_exited.connect(func() -> void: _apply_advanced_field.call_deferred(field))
    else:
      field.changed.connect(func() -> void: _apply_advanced_field.call_deferred(field))

func _apply_advanced_field(field: Control) -> void:
  if is_instance_valid(field) and field in property_fields:
    _apply_properties()

func _replace_block(index: int, replacement: String) -> bool:
  var block: Dictionary = blocks[index]
  var updated := source.text.left(block.start) + replacement + source.text.substr(block.end)
  var result := PARSER.parse(updated)
  if result.has("error"):
    var error := declaration_error if inspector_dialog.visible else property_error
    if is_instance_valid(error): error.text = result.error
    status.text = result.error
    return false
  if updated != source.text: _set_source(updated)
  return true

func _apply_properties() -> void:
  if selected_block < 0: return
  var parts := PackedStringArray()
  for field in property_fields:
    if field is LineEdit:
      parts.append(field.text.strip_edges())
    else:
      var value: String = field.source_text()
      if not value.is_empty(): parts.append("[" + value + "]")
  var declaration := property_prefix + " " + ", ".join(parts) + " " + property_suffix
  var left := declaration.find("{")
  var right := declaration.rfind("}")
  var kind: String = blocks[selected_block].entries[0].kind
  var keep_range := edit_range
  var result := PARSER.parse_building(kind, PARSER.mask_comments(declaration).substr(left + 1, right - left - 1), parsed.width, parsed.height, parsed.legacy_rates)
  if _replace_selected_cell(declaration):
    if not result.has("error"):
      var entry: Dictionary = result.entries[0]
      _select_at(Vector2i(entry.x, entry.y), kind, entry.facing)
      if keep_range:
        edit_range = true
        _build_visual_form()
    if selected_block >= 0:
      var updated: String = PARSER.mask_comments(blocks[selected_block].text).replace("\n", " ")
      _build_property_form(updated if edit_range else _single_declaration(updated, selected_cell))
    declaration_error.text = ""

func _delete_selected() -> void:
  if selected_block < 0: return
  _replace_selected_cell("")

# Goal panels express OR between alternatives and AND within each one.
func _add_goal_group(conditions: Dictionary = {}, targets: Dictionary = {}, source_index: int = -1) -> void:
  var group := PanelContainer.new()
  goal_rows.add_child(group)
  group.set_meta("source_index", source_index)
  var margin := UI.margin()
  group.add_child(margin)
  var column := VBoxContainer.new()
  margin.add_child(column)
  var header := HFlowContainer.new()
  column.add_child(header)
  var title := UI.label("Solution")
  UI.heading(title, 16)
  title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  header.add_child(title)
  var rows := VBoxContainer.new()
  column.add_child(rows)
  group.set_meta("rows", rows)
  UI.button(header, "+ Output", func() -> void: _add_goal_row(rows))
  UI.button(header, "+ Cost limit", func() -> void: _add_goal_row(rows, "cost", [INF, INF, INF]))
  UI.button(header, "Remove", func() -> void: group.queue_free()).tooltip_text = "Remove this solution"
  if conditions.is_empty():
    _add_goal_row(rows)
  else:
    for key in conditions:
      _add_goal_row(rows, targets.get(key, key), conditions[key])

func _add_goal_row(parent: VBoxContainer, target: String = "electron", values: Array = [1.0, 2.0, 3.0]) -> void:
  if parent.get_child_count() > 0: parent.add_child(HSeparator.new())
  var row := VBoxContainer.new()
  parent.add_child(row)
  var header := HBoxContainer.new()
  row.add_child(header)
  var type := OptionButton.new()
  type.add_item("Particle output")
  type.add_item("Build cost limit")
  type.select(1 if target == "cost" else 0)
  type.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  header.add_child(type)
  UI.button(header, "Remove condition", func() -> void:
    var previous := row.get_index() - 1
    var next := row.get_index() + 1
    if previous >= 0: parent.get_child(previous).queue_free()
    elif next < parent.get_child_count(): parent.get_child(next).queue_free()
    row.queue_free()
  )
  var expression := PARTICLE_PICKER.new()
  var bracketed := target.begins_with("[") and target.ends_with("]")
  if target != "cost":
    expression.load_text(target.substr(1, target.length() - 2) if bracketed else target)
  row.add_child(expression)
  var thresholds := HBoxContainer.new()
  row.add_child(thresholds)
  var fields: Array[LineEdit] = []
  for i in range(3):
    var tier := VBoxContainer.new()
    tier.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    thresholds.add_child(tier)
    var caption := UI.label("★".repeat(i + 1))
    caption.add_theme_color_override("font_color", UI.GOLD)
    tier.add_child(caption)
    var field := LineEdit.new()
    field.text = _threshold_text(values[i])
    tier.add_child(field)
    fields.append(field)
  var help := UI.label("")
  UI.muted(help)
  row.add_child(help)
  var show_type := func(index: int) -> void:
    expression.visible = index == 0
    help.text = "Minimum particles per step" if index == 0 else "Maximum cost per tier. Leave blank for no limit."
    for field in fields:
      field.placeholder_text = "per step" if index == 0 else "No limit"
  show_type.call(type.selected)
  type.item_selected.connect(show_type)
  row.set_meta("condition", {"type": type, "expression": expression, "bracketed": bracketed, "thresholds": fields})

func _threshold_text(value: float) -> String:
  return "inf" if is_inf(value) else String.num_scientific(value)

func _goal_declaration(clauses: PackedStringArray) -> String:
  return "goal: {" + "; ".join(clauses) + "};"

func _goal_clause(target: String, values: PackedStringArray) -> String:
  if target != "cost":
    for index in range(values.size()):
      if values[index].to_lower() != "inf": values[index] = values[index].trim_suffix("/step") + "/step"
  return target + ": " + ", ".join(values)

func _open_settings() -> void:
  if parsed.has("error") or parsed.is_empty(): return
  _clear_children(goal_rows)
  settings_error.text = ""
  title_input.text = str(parsed.get("title", ""))
  hint_input.text = str(parsed.get("hint", ""))
  rotation_input.select(rotation_input.get_item_index(parsed.rotation_steps))
  for i in range(parsed.goals.size()):
    _add_goal_group(parsed.goals[i], parsed.goal_targets[i], i)
  for kind in inventory_fields:
    inventory_fields[kind].value = int(parsed.inventory.get(kind, 0))
  settings_dialog.popup_centered_clamped(Vector2i(620, 660), 0.88)

func _apply_settings() -> void:
  var old_goals := {}
  var additional := PackedStringArray()
  var group_count := 0
  for group in goal_rows.get_children():
    if group.is_queued_for_deletion(): continue
    var clauses := PackedStringArray()
    for row in group.get_meta("rows").get_children():
      if row.is_queued_for_deletion() or not row.has_meta("condition"): continue
      var condition: Dictionary = row.get_meta("condition")
      var cost_goal: bool = condition.type.selected == 1
      var target := "cost"
      if not cost_goal:
        var expression: String = condition.expression.source_text()
        if expression.is_empty():
          settings_error.text = "Choose a particle for every output condition."
          return
        target = expression
        if condition.bracketed or not PARSER._valid_particle(expression):
          target = "[" + expression + "]"
      var values := PackedStringArray()
      for field in condition.thresholds:
        var value: String = field.text.strip_edges()
        if value.is_empty() and cost_goal: value = "inf"
        values.append(value)
      clauses.append(_goal_clause(target, values))
    if clauses.is_empty():
      settings_error.text = "Add a condition to each solution, or remove the empty solution."
      return
    var index: int = group.get_meta("source_index")
    if index >= 0:
      old_goals[index] = _goal_declaration(clauses)
    else:
      additional.append(_goal_declaration(clauses))
    group_count += 1
  if group_count == 0:
    settings_error.text = "Add at least one solution."
    return

  var inventory := {}
  var inventory_parts := PackedStringArray()
  for kind in inventory_fields:
    var count := int(inventory_fields[kind].value)
    if count == 0 and not parsed.inventory.has(kind): continue
    inventory[kind] = count
    inventory_parts.append("%s=%d" % [kind, count])
  if inventory != parsed.inventory and not inventory_parts.is_empty():
    additional.append("inventory: {" + ", ".join(inventory_parts) + "};")

  var masked: String = PARSER.mask_comments(source.text)
  var edits: Array[Dictionary] = []
  var original_goal := 0
  for item in PARSER.find_blocks(masked):
    var kind := item.get_string(1).to_lower()
    if kind == "inventory" and inventory != parsed.inventory:
      edits.append({"span": item, "text": ""})
    elif kind == "goal":
      var replacement: String = old_goals.get(original_goal, "")
      var original_clauses := PackedStringArray()
      for key in parsed.goals[original_goal]:
        var values := PackedStringArray()
        for value in parsed.goals[original_goal][key]: values.append(_threshold_text(value))
        original_clauses.append(_goal_clause(parsed.goal_targets[original_goal].get(key, key), values))
      if replacement != _goal_declaration(original_clauses):
        edits.append({"span": item, "text": replacement})
      original_goal += 1
  var prefix := ""
  var metadata: Array[RegExMatch] = PARSER.find_metadata(masked)
  var settings := {"title": title_input.text.strip_edges(), "hint": hint_input.text.strip_edges(),
    "rotation": str(rotation_input.get_selected_id())}
  for key in settings:
    var value: String = settings[key]
    var previous: String = str(parsed.rotation_steps) if key == "rotation" else parsed[key]
    if value == previous: continue
    if ";" in value or "#" in value:
      settings_error.text = "Titles and hints cannot contain a semicolon or #."
      return
    var matching: Array[RegExMatch] = []
    for item in metadata:
      if item.get_string(1).to_lower() == key: matching.append(item)
    var declaration := "%s: %s;" % [key, value] if not value.is_empty() else ""
    if matching.is_empty():
      prefix += declaration + "\n"
    elif value.is_empty():
      for item in matching: edits.append({"span": item, "text": ""})
    else:
      edits.append({"span": matching.back(), "text": declaration})

  var updated := source.text
  edits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.span.get_start() > b.span.get_start())
  for edit in edits:
    updated = updated.left(edit.span.get_start()) + edit.text + updated.substr(edit.span.get_end())
  if not additional.is_empty(): updated = updated.trim_suffix("\n") + "\n" + "\n".join(additional) + "\n"
  updated = prefix + updated
  var result: Dictionary = PARSER.parse(updated)
  if not result.has("error") and parsed.legacy_rates and not result.legacy_rates:
    var declarations := PARSER.find_blocks(PARSER.mask_comments(updated))
    declarations.reverse()
    for declaration in declarations:
      if declaration.get_string(1).to_lower() != "emitter": continue
      var emitter := PARSER.parse_building("emitter", declaration.get_string(2), result.width, result.height, true)
      var start := declaration.get_start()
      var stop := declaration.get_end()
      var authored := updated.substr(start, stop - start)
      updated = updated.left(start) + _explicit_emitter_rate(authored, emitter.entries[0].rate) + updated.substr(stop)
    result = PARSER.parse(updated)
  if result.has("error"):
    settings_error.text = str(result.error)
    return
  if updated != source.text: _set_source(updated)
  settings_dialog.hide()

func _explicit_emitter_rate(declaration: String, rate: float) -> String:
  var regex := RegEx.new()
  regex.compile("(?i)\\brate\\s*=\\s*[^,}\\s]+")
  var masked := PARSER.mask_comments(declaration)
  var found := regex.search(masked)
  var text := "rate=%s/step" % String.num_scientific(rate)
  if found != null:
    return declaration.left(found.get_start()) + text + declaration.substr(found.get_end())
  var end := masked.rfind("}")
  return declaration.left(end) + ", " + text + declaration.substr(end)

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
    var lock_rotation := CATALOG.rotation_lock_flag(entry.kind)
    if "p" not in flags or (entry.kind in CATALOG.ROTATABLE_KINDS and lock_rotation not in flags):
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
      _show_file_dialog(FileDialog.FILE_MODE_OPEN_FILE)
    "back": get_tree().change_scene_to_file("res://MainScene/level_select.tscn")
    "quit": get_tree().quit()

func _save() -> void:
  if path.is_empty() or _is_bundled_level(path): _save_as()
  else: _write_file(path)

func _save_as() -> void:
  if not _can_save(): return
  _show_file_dialog(FileDialog.FILE_MODE_SAVE_FILE)

func _show_file_dialog(mode: FileDialog.FileMode) -> void:
  if file_dialog.visible: return
  var directory := last_file_directory
  if directory.is_empty() or not DirAccess.dir_exists_absolute(directory):
    var error := Global.ensure_custom_levels()
    directory = ProjectSettings.globalize_path(Global.CUSTOM_LEVELS if error == OK else "user://")
  var saving := mode == FileDialog.FILE_MODE_SAVE_FILE
  file_dialog.file_mode = mode
  file_dialog.title = "Save Vertex level (.level)" if saving else "Open level"
  file_dialog.filters = PackedStringArray() if saving else PackedStringArray(["*.level ; Vertex levels"])
  file_dialog.current_dir = directory
  file_dialog.current_file = (path.get_file() if not path.is_empty() else "new-level.level") if saving else ""
  return_to_source = source_dialog.visible
  if return_to_source: source_dialog.hide()
  file_dialog.popup_centered_clamped(Vector2i(820, 560), 0.88)

func _restore_source_after_file_dialog() -> void:
  if not return_to_source: return
  return_to_source = false
  _open_source.call_deferred()

func _is_bundled_level(target: String) -> bool:
  return ProjectSettings.localize_path(target.simplify_path()).begins_with("res://Levels/")

func _file_selected(selected_path: String) -> void:
  _restore_source_after_file_dialog()
  if file_dialog.file_mode == FileDialog.FILE_MODE_SAVE_FILE:
    if not selected_path.to_lower().ends_with(".level"):
      selected_path += ".level"
      if FileAccess.file_exists(selected_path):
        status.text = "A file named %s already exists. Select it explicitly to replace it." % selected_path.get_file()
        return
    _write_file(selected_path)
  else:
    if not selected_path.to_lower().ends_with(".level"):
      status.text = "Choose a .level file."
      return
    var file := FileAccess.open(selected_path, FileAccess.READ)
    if file == null:
      status.text = "Could not open file: " + error_string(FileAccess.get_open_error())
      return
    path = selected_path
    if not _is_bundled_level(path): last_file_directory = path.get_base_dir()
    saved_text = file.get_as_text()
    _set_source(saved_text)

func _can_save() -> bool:
  var data: Dictionary = PARSER.parse(source.text)
  if data.has("error"):
    status.text = "Cannot save: " + str(data.error)
    return false
  return true

func _write_file(target: String) -> void:
  if not _can_save(): return
  if _is_bundled_level(target):
    status.text = "Built-in levels are read-only. Save a copy in another folder."
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
  last_file_directory = target.get_base_dir()
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
  game.running = false
  game.cancel_pending_steps()
  game.hide()
  game.get_node("SimulationControls").visible = false
  editor_panel.hide()
  editor_heading.hide()
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
  _reset_preview()
  editor_panel.show()
  editor_heading.show()
  inspector_panel.visible = selected_block >= 0
  palette.visible = selected_block < 0
  game._fit_camera()
