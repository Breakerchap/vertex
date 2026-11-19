extends "res://Particles/particle_simulation.gd"

const PARSER = preload("res://Levels/level_parser.gd")
const PARTICLES = preload("res://Particles/particle_catalog.gd")
const PARTICLE_PICKER = preload("res://MainScene/particle_picker.gd")
const UI = preload("res://MainScene/workspace_theme.gd")
const ENTRY = preload("res://Buildings/Emitter/particle_emission.gd")
const TILE = preload("res://tile.png")
const FORECAST = preload("res://MainScene/simulation_forecast.gd")
const PREVIEW = preload("res://Buildings/particle_preview.gd")
const OVERLAY = preload("res://MainScene/placement_overlay.gd")
const PALETTE = preload("res://MainScene/building_palette.gd")
const FILLED_STAR = preload("res://filled_star.png")
const EMPTY_STAR = preload("res://empty_star.png")
const CATALOG = preload("res://Buildings/building_catalog.gd")
const CELL: float = 102.4
const SCENES := CATALOG.SCENES
# Costs are shared by all levels, as described by the level format.
const COSTS := CATALOG.COSTS
const DIRECTIONS := ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
const WINDOW_SECONDS: float = 5.0
const OBSERVED_WINDOWS: int = 2
const FORECAST_WINDOWS: int = 3

signal editor_cell_clicked(cell: Vector2i, button: int)
signal editor_cell_dragged(from_cell: Vector2i, to_cell: Vector2i)
signal exit_playtest_requested
var drag_cell := Vector2i(-1, -1)
var drag_start := Vector2.ZERO

var editor_preview := false
var editor_playtest := false
var level_override: Dictionary = {}
var editor_brush := ""
var external_palette: PanelContainer
var diagnostic_overlay
var diagnostics_enabled := false
var undo_history: Array[Dictionary] = []
var redo_history: Array[Dictionary] = []
var restoring_history := false
var last_hud_update := 0.0
var editor_bottom_inset := 190.0
var editor_sidebar_width := 256.0
var hud_panel: PanelContainer
var level: Dictionary = {}
var buildings: Array[Node] = []
var inventory: Dictionary = {}
var selected_kind: String = ""
var selected_building: Node = null
var cost: int = 0
var simulating: bool = false
var total_counts: Dictionary = {}
var window_counts: Dictionary = {}
var windows: Array[Dictionary] = []
var window_time: float = 0.0
var elapsed: float = 0.0
var tracked_target := ""
var tracked_label := ""
var completed: bool = false
var config_dialog: AcceptDialog
var config_rate: SpinBox
var config_particles: Control
var config_heading: Label
var config_error: Label
var config_rate_row: HBoxContainer
var selection_label: Label
var status_label: Label
var measurement_label: Label
var diagnostic_legend: Label
var measurement_bar: ProgressBar
var rotate_button: Button
var rotate_left_button: Button
var configure_button: Button
var remove_button: Button
var next_level_button: Button
var restart_button: Button
var palette: PanelContainer
var star_icons: Array[TextureRect] = []
var results: AcceptDialog
var stop_button: Button

func _ready() -> void:
  running = false
  RenderingServer.set_default_clear_color(UI.BACKGROUND)
  $SimulationControls/Panel.theme = UI.theme()
  if editor_preview:
    particle_detected.connect(_on_particle_detected)
    simulation_stepped.connect(_on_simulation_stepped)
    var editor_overlay := Node2D.new()
    editor_overlay.set_script(OVERLAY)
    editor_overlay.z_index = 100
    add_child(editor_overlay)
    diagnostic_overlay = editor_overlay
    particle_event.connect(_on_particle_event)
    get_viewport().size_changed.connect(_fit_camera)
    return
  if Global.selected_level.is_empty() and level_override.is_empty():
    get_tree().call_deferred("change_scene_to_file", "res://MainScene/level_select.tscn")
    return
  level = level_override.duplicate(true) if not level_override.is_empty() else PARSER.parse(FileAccess.get_file_as_string(Global.selected_level))
  if level.has("error"):
    push_error("Cannot load level: " + str(level.error))
    get_tree().call_deferred("change_scene_to_file", "res://MainScene/level_select.tscn")
    return
  particle_detected.connect(_on_particle_detected)
  simulation_stepped.connect(_on_simulation_stepped)
  _create_hud()
  var overlay := Node2D.new()
  overlay.set_script(OVERLAY)
  overlay.z_index = 100
  add_child(overlay)
  diagnostic_overlay = overlay
  particle_event.connect(_on_particle_event)
  _load_initial_board()
  get_viewport().size_changed.connect(_fit_camera)
  _fit_camera()

func _draw() -> void:
  if level.is_empty() or level.has("error"):
    return
  for x in range(level.width):
    for y in range(level.height):
      draw_texture_rect(TILE, Rect2(Vector2(x, y) * CELL - Vector2.ONE * CELL * 0.5, Vector2.ONE * CELL), false)

func _fit_camera() -> void:
  if level.is_empty():
    return
  var camera: Camera2D = $Camera2D
  camera.position = Vector2(level.width - 1, level.height - 1) * CELL * 0.5
  var view := get_viewport_rect().size
  var bottom_inset := editor_bottom_inset if editor_preview else hud_panel.size.y + 28.0
  var top_inset := 74.0 if editor_preview else 134.0
  var sidebar := editor_sidebar_width if editor_preview else 256.0
  var available := Vector2(maxf(100.0, view.x - sidebar - 36.0), maxf(100.0, view.y - top_inset - bottom_inset))
  var board := Vector2(level.width, level.height) * CELL
  var zoom_amount := minf(1.0, minf(available.x / board.x, available.y / board.y))
  camera.zoom = Vector2.ONE * zoom_amount
  camera.offset = Vector2(sidebar, bottom_inset - top_inset) * 0.5 / zoom_amount

func _create_hud() -> void:
  var layer := CanvasLayer.new()
  layer.layer = 2
  add_child(layer)
  var panel := PanelContainer.new()
  hud_panel = panel
  panel.theme = UI.theme()
  panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
  panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
  panel.offset_left = 16
  panel.offset_right = -272
  panel.offset_top = -191
  panel.offset_bottom = -16
  layer.add_child(panel)
  panel.resized.connect(_fit_camera)
  var margin := UI.margin(10)
  panel.add_child(margin)
  var column := VBoxContainer.new()
  column.add_theme_constant_override("separation", 4)
  margin.add_child(column)
  status_label = Label.new()
  UI.muted(status_label)
  column.add_child(status_label)
  _add_goal_table(column)
  measurement_label = Label.new()
  UI.muted(measurement_label)
  column.add_child(measurement_label)
  measurement_bar = ProgressBar.new()
  measurement_bar.custom_minimum_size.y = 8
  measurement_bar.max_value = WINDOW_SECONDS
  measurement_bar.show_percentage = false
  column.add_child(measurement_bar)
  palette = PALETTE.new()
  layer.add_child(palette)
  palette.kind_selected.connect(_select_inventory)
  palette.kind_dropped.connect(_drop_inventory)
  _add_level_heading(layer)
  var stars_panel := PanelContainer.new()
  stars_panel.theme = UI.theme()
  stars_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
  stars_panel.offset_left = -256
  stars_panel.offset_right = -16
  stars_panel.offset_top = 16
  stars_panel.offset_bottom = 88
  layer.add_child(stars_panel)
  var stars_column := VBoxContainer.new()
  stars_panel.add_child(stars_column)
  var stars_title := Label.new()
  stars_title.text = "Goal progress"
  UI.muted(stars_title)
  stars_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
  stars_column.add_child(stars_title)
  var stars_row := HBoxContainer.new()
  stars_row.alignment = BoxContainer.ALIGNMENT_CENTER
  stars_column.add_child(stars_row)
  for i in range(3):
    var icon := TextureRect.new()
    icon.custom_minimum_size = Vector2(34, 34)
    icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    icon.texture = EMPTY_STAR
    icon.tooltip_text = "%d-star tier" % [i + 1]
    stars_row.add_child(icon)
    star_icons.append(icon)
  selection_label = Label.new()
  UI.muted(selection_label)
  column.add_child(selection_label)
  var actions := HFlowContainer.new()
  column.add_child(actions)
  rotate_left_button = _button(actions, "↶  Q", _rotate_selected.bind(-1))
  rotate_left_button.tooltip_text = "Rotate counterclockwise"
  rotate_button = _button(actions, "↷  E", _rotate_selected)
  rotate_button.tooltip_text = "Rotate clockwise"
  configure_button = _button(actions, "Configure…", _open_config)
  remove_button = _button(actions, "Remove  Del", _remove_selected)
  stop_button = _button(actions, "Build  B", stop_to_build)
  restart_button = _button(actions, "Restart run", restart_run)
  _button(actions, "Reset  X", reset_level)
  _button(actions, "Back to editor" if editor_playtest else "Levels", _return_to_select)
  var diagnostics := CheckButton.new()
  diagnostics.text = "Interactions"
  diagnostics.tooltip_text = "Highlight reflections, detections, collisions and particles leaving the board"
  diagnostics.toggled.connect(func(enabled: bool) -> void:
    diagnostics_enabled = enabled
    if is_instance_valid(diagnostic_overlay): diagnostic_overlay.queue_redraw()
    _refresh_ui()
  )
  actions.add_child(diagnostics)
  diagnostic_legend = Label.new()
  diagnostic_legend.text = "Blue reflect  ·  Green detect  ·  Gold annihilate  ·  Red absorb/exit  ·  Purple field"
  diagnostic_legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
  UI.muted(diagnostic_legend, 12)
  diagnostic_legend.hide()
  column.add_child(diagnostic_legend)
  config_dialog = AcceptDialog.new()
  config_dialog.title = "Building settings"
  config_dialog.min_size = Vector2i(400, 160)
  config_dialog.theme = UI.theme()
  config_dialog.ok_button_text = "Cancel"
  layer.add_child(config_dialog)
  var config_column := VBoxContainer.new()
  config_dialog.add_child(config_column)
  config_heading = _config_label("")
  UI.heading(config_heading, 16)
  config_column.add_child(config_heading)
  config_rate_row = HBoxContainer.new()
  config_column.add_child(config_rate_row)
  config_rate_row.add_child(_config_label("Particles per second"))
  config_rate = SpinBox.new()
  config_rate.min_value = 0.0
  config_rate.max_value = 1000
  config_rate.allow_greater = true
  config_rate.step = 0.0
  config_rate_row.add_child(config_rate)
  config_error = _config_label("")
  config_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
  config_error.add_theme_color_override("font_color", UI.ERROR)
  config_column.add_child(config_error)
  _button(config_column, "Apply changes", _apply_config).theme_type_variation = "PrimaryButton"
  results = AcceptDialog.new()
  results.theme = UI.theme()
  results.title = "Level complete"
  results.ok_button_text = "Back to build"
  results.confirmed.connect(stop_to_build)
  results.canceled.connect(stop_to_build)
  results.custom_action.connect(_result_action)
  next_level_button = results.add_button("Next level", true, "next")
  next_level_button.visible = not editor_playtest and not Global.next_level_path(Global.selected_level).is_empty()
  layer.add_child(results)

func _config_label(value: String) -> Label:
  var label := Label.new()
  label.text = value
  return label

func _add_level_heading(layer: CanvasLayer) -> void:
  var header := VBoxContainer.new()
  header.theme = UI.theme()
  header.set_anchors_preset(Control.PRESET_TOP_WIDE)
  header.offset_left = 16
  header.offset_right = -272
  header.offset_top = 72
  header.mouse_filter = Control.MOUSE_FILTER_IGNORE
  layer.add_child(header)
  var title := str(level.get("title", ""))
  if title.is_empty(): title = "Playtest" if editor_playtest else Global.selected_level.get_file().get_basename()
  var heading := _config_label(title)
  UI.heading(heading, 25)
  heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
  header.add_child(heading)
  var hint := str(level.get("hint", ""))
  if not hint.is_empty():
    var prompt := _config_label(hint)
    UI.muted(prompt)
    prompt.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    prompt.tooltip_text = hint
    prompt.mouse_filter = Control.MOUSE_FILTER_STOP
    header.add_child(prompt)

func _add_goal_table(column: VBoxContainer) -> void:
  var table_header := HBoxContainer.new()
  column.add_child(table_header)
  _add_goal_cells(table_header, "Goals", ["★", "★★", "★★★"], true)
  var scroll := ScrollContainer.new()
  scroll.custom_minimum_size.y = 54
  scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
  scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
  column.add_child(scroll)
  var rows := VBoxContainer.new()
  rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  scroll.add_child(rows)
  for index in range(level.goals.size()):
    if index > 0:
      var divider := _config_label("OR")
      UI.muted(divider, 11)
      rows.add_child(divider)
    for key in level.goals[index]:
      var targets: Array = level.get("goal_targets", [])
      var target: String = targets[index].get(key, key) if index < targets.size() else key
      var label := "Max build cost" if key == "cost" else PARTICLES.label(target) if PARTICLES.TYPES.has(target) else target
      if tracked_target.is_empty() and key != "cost":
        tracked_target = key
        tracked_label = label
      var thresholds: Array[String] = []
      for value in level.goals[index][key]:
        if is_inf(value): thresholds.append("∞")
        else: thresholds.append(("$" if key == "cost" else "") + _goal_value(value) + ("" if key == "cost" else "/s"))
      var row := HBoxContainer.new()
      rows.add_child(row)
      _add_goal_cells(row, label, thresholds)

func _add_goal_cells(row: HBoxContainer, target: String, values: Array, heading: bool = false) -> void:
  var name_label := _config_label(target)
  name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
  name_label.tooltip_text = target
  name_label.mouse_filter = Control.MOUSE_FILTER_STOP
  if heading: UI.heading(name_label, 16)
  row.add_child(name_label)
  for value in values:
    var threshold := _config_label(value)
    threshold.custom_minimum_size.x = 68
    threshold.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    threshold.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    threshold.tooltip_text = value
    threshold.mouse_filter = Control.MOUSE_FILTER_STOP
    if heading: threshold.add_theme_color_override("font_color", UI.GOLD)
    row.add_child(threshold)

func _open_config() -> void:
  if simulating or not is_instance_valid(selected_building): return
  var kind: String = selected_building.get_meta("kind")
  if kind not in ["emitter", "detector"]: return
  var entry: Dictionary = selected_building.get_meta("entry")
  if is_instance_valid(config_particles):
    config_particles.get_parent().remove_child(config_particles)
    config_particles.queue_free()
  config_particles = PARTICLE_PICKER.new()
  config_particles.sequence = kind == "emitter"
  var default_particles := ["electron"] if config_particles.sequence else ["photon"]
  var authored: String = entry.get("particle_expression", ", ".join(entry.get("particles", default_particles)))
  config_particles.load_text(authored)
  config_heading.get_parent().add_child(config_particles)
  config_heading.get_parent().move_child(config_particles, 1)
  config_heading.text = "Emission order" if kind == "emitter" else "Accepted particles"
  config_error.text = ""
  config_dialog.title = "%s settings" % kind.capitalize()
  config_rate_row.visible = kind == "emitter"
  if kind == "emitter": config_rate.value = selected_building.rate
  config_dialog.popup_centered()

func _apply_config() -> void:
  if not is_instance_valid(selected_building): return
  var kind: String = selected_building.get_meta("kind")
  var cell: Vector2i = selected_building.get_meta("cell")
  var entry: Dictionary = selected_building.get_meta("entry").duplicate(true)
  var from_inventory: bool = selected_building.get_meta("from_inventory")
  var expression: String = config_particles.source_text()
  if kind == "emitter":
    if config_rate.value <= 0.0:
      config_error.text = "Emission rate must be greater than zero."
      return
    var sequence: Array[String] = []
    for name in expression.split(",", false):
      sequence.append(name.strip_edges())
    entry.particles = sequence
    entry.rate = config_rate.value
    entry.facing = DIRECTIONS[selected_building.orientation]
  else:
    var parsed_expression := {"particles": [], "accepted": []} if expression.is_empty() else PARSER.particle_expression(expression)
    if parsed_expression.has("error"):
      config_error.text = parsed_expression.error
      return
    entry.particle_expression = expression
    entry.particles = parsed_expression.particles
    entry.accepted = parsed_expression.accepted
  entry.x = cell.x
  entry.y = cell.y
  _record_undo()
  var old := selected_building
  buildings.erase(old)
  remove_child(old)
  old.queue_free()
  _place_building(entry, from_inventory)
  selected_building = buildings.back()
  config_dialog.hide()
  _refresh_ui()

func _button(parent: Node, title: String, action: Callable) -> Button:
  var button := Button.new()
  button.text = title
  button.pressed.connect(action)
  parent.add_child(button)
  return button

func _load_initial_board() -> void:
  running = false
  cancel_pending_steps()
  simulating = false
  completed = false
  _clear_particles()
  for building in buildings:
    if is_instance_valid(building):
      remove_child(building)
      building.queue_free()
  buildings.clear()
  inventory = level.inventory.duplicate(true)
  cost = 0
  undo_history.clear()
  redo_history.clear()
  selected_building = null
  selected_kind = ""
  for entry in level.buildings:
    _place_building(entry, false)
  level_bounds_enabled = true
  level_bounds = Rect2(-CELL * 0.5, -CELL * 0.5, level.width * CELL, level.height * CELL)
  _clear_stats()
  _refresh_ui()
  queue_redraw()

func _place_building(entry: Dictionary, from_inventory: bool) -> void:
  var scene: PackedScene = SCENES[entry.kind]
  var building := scene.instantiate()
  var cell := Vector2i(int(entry.x), int(entry.y))
  building.position = _cell_position(cell)
  building.set_meta("entry", entry.duplicate(true))
  building.set_meta("cell", cell)
  building.set_meta("kind", entry.kind)
  building.set_meta("fixed_position", "p" in str(entry.get("fixed", "")))
  var fixed_flag := "c" if entry.kind == "magnet" else "r"
  building.set_meta("fixed_rotation", fixed_flag in str(entry.get("fixed", "")))
  building.set_meta("from_inventory", from_inventory)
  if entry.kind in ["mirror", "emitter"]:
    var direction := DIRECTIONS.find(entry.get("facing", "E"))
    building.orientation = (direction + 2) % 8 if entry.kind == "mirror" else direction
  if entry.kind == "magnet":
    building.polarity = -1 if str(entry.get("polarity", "positive")) in ["negative", "-", "-1", "n"] else 1
  if entry.kind == "emitter":
    building.start_on_ready = false
    building.rate = float(entry.get("rate", 1.0))
    building.repeat_sequence = true
    var sequence: Array[ENTRY] = []
    for name in entry.get("particles", []):
      sequence.append(PARTICLES.emission(name))
    building.sequence = sequence
  if entry.kind == "detector":
    var accepted: Array[String] = []
    accepted.assign(entry.get("accepted", entry.get("particles", ["photon"])))
    building.accepted = accepted
  add_child(building)
  if entry.kind in ["emitter", "detector"]:
    var preview = Node2D.new()
    preview.set_script(PREVIEW)
    preview.z_index = 2
    preview.emitter_preview = entry.kind == "emitter"
    building.add_child(preview)
    var names: Array[String] = []
    names.assign(entry.get("particles", ["photon"] if entry.kind == "detector" else ["electron"]))
    if names.is_empty() and entry.kind == "emitter": names.append("electron")
    preview.show_particles(names)
  buildings.append(building)

func _cell_position(cell: Vector2i) -> Vector2:
  return Vector2(cell.x, level.height - 1 - cell.y) * CELL

func _mouse_cell() -> Vector2i:
  var point := get_global_mouse_position() / CELL
  return Vector2i(roundi(point.x), level.height - 1 - roundi(point.y))

func _building_at(cell: Vector2i) -> Node:
  for building in buildings:
    if is_instance_valid(building) and building.get_meta("cell") == cell:
      return building
  return null

func _unhandled_input(event: InputEvent) -> void:
  if not is_visible_in_tree(): return
  if editor_preview:
    if event is InputEventKey and event.pressed and not event.echo:
      if event.keycode == KEY_SPACE: $SimulationControls._toggle_running()
      elif event.keycode == KEY_PERIOD: $SimulationControls._step_once()
      return
    if not simulating and event is InputEventMouseButton:
      var cell := _mouse_cell()
      if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
        if drag_cell.x >= 0 and event.position.distance_to(drag_start) > 8.0:
          editor_cell_dragged.emit(drag_cell, cell)
        drag_cell = Vector2i(-1, -1)
      elif event.pressed and cell.x >= 0 and cell.y >= 0 and cell.x < level.get("width", 0) and cell.y < level.get("height", 0):
        if event.button_index == MOUSE_BUTTON_LEFT: drag_cell = Vector2i(-1, -1)
        if event.button_index == MOUSE_BUTTON_LEFT and _building_at(cell) != null:
          drag_cell = cell
          drag_start = event.position
        editor_cell_clicked.emit(cell, event.button_index)
    return
  if event is InputEventKey and event.pressed and not event.echo:
    if event.ctrl_pressed and event.keycode == KEY_Z:
      if event.shift_pressed: redo_build()
      else: undo_build()
      return
    if event.ctrl_pressed and event.keycode == KEY_Y:
      redo_build()
      return
    match event.keycode:
      KEY_B: stop_to_build()
      KEY_X: reset_level()
      KEY_SPACE: $SimulationControls._toggle_running()
      KEY_PERIOD: $SimulationControls._step_once()
      KEY_Q: _rotate_selected(-1)
      KEY_E, KEY_R: _rotate_selected(1)
      KEY_DELETE, KEY_BACKSPACE: _remove_selected()
      KEY_ESCAPE:
        selected_building = null
        selected_kind = ""
        _refresh_ui()
        queue_redraw()
    return
  if simulating or not event is InputEventMouseButton: return
  var cell := _mouse_cell()
  if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
    if drag_cell.x >= 0 and event.position.distance_to(drag_start) > 8.0:
      _move_selected_to(cell)
    drag_cell = Vector2i(-1, -1)
    return
  if not event.pressed or cell.x < 0 or cell.y < 0 or cell.x >= level.width or cell.y >= level.height: return
  if event.button_index == MOUSE_BUTTON_LEFT: drag_cell = Vector2i(-1, -1)
  if event.button_index == MOUSE_BUTTON_LEFT and _building_at(cell) != null:
    drag_cell = cell
    drag_start = event.position
  _click_cell(cell, event.button_index)

func _move_selected_to(cell: Vector2i) -> void:
  if not is_instance_valid(selected_building) or selected_building.get_meta("fixed_position"): return
  if cell.x < 0 or cell.y < 0 or cell.x >= level.width or cell.y >= level.height or _building_at(cell) != null: return
  _record_undo()
  selected_building.position = _cell_position(cell)
  selected_building.set_meta("cell", cell)
  _refresh_ui()
  queue_redraw()

func _click_cell(cell: Vector2i, button_index: int) -> void:
  if simulating or cell.x < 0 or cell.y < 0 or cell.x >= level.width or cell.y >= level.height:
    return
  var target := _building_at(cell)
  if button_index == MOUSE_BUTTON_RIGHT:
    selected_building = target
    selected_kind = ""
  elif button_index == MOUSE_BUTTON_LEFT:
    if target != null:
      selected_building = target
      selected_kind = ""
    elif not selected_kind.is_empty() and int(inventory.get(selected_kind, 0)) > 0:
      var entry := {"kind": selected_kind, "x": cell.x, "y": cell.y}
      _record_undo()
      _place_building(entry, true)
      inventory[selected_kind] -= 1
      cost += COSTS[selected_kind]
      if inventory[selected_kind] == 0:
        selected_kind = ""
    elif is_instance_valid(selected_building):
      if not selected_building.get_meta("fixed_position"):
        _move_selected_to(cell)
      else:
        selected_building = null
    else:
      selected_building = null
    _refresh_ui()
    queue_redraw()

func _rotate_selected(turn: int = 1) -> void:
  if simulating or not is_instance_valid(selected_building) or selected_building.get_meta("fixed_rotation"):
    return
  if selected_building.get_meta("kind") not in ["magnet", "emitter", "mirror"]: return
  _record_undo()
  if selected_building.get_meta("kind") == "magnet":
    selected_building.polarity *= -1
  elif selected_building.get_meta("kind") in ["emitter", "mirror"]:
    selected_building.orientation = posmod(selected_building.orientation + turn, DIRECTIONS.size())
  _refresh_ui()
  queue_redraw()

func _remove_selected() -> void:
  if simulating or not is_instance_valid(selected_building) or selected_building.get_meta("fixed_position"):
    return
  _record_undo()
  var building := selected_building
  if building.get_meta("from_inventory"):
    var kind: String = building.get_meta("kind")
    inventory[kind] = int(inventory.get(kind, 0)) + 1
    cost -= COSTS[kind]
  buildings.erase(building)
  remove_child(building)
  building.queue_free()
  selected_building = null
  _refresh_ui()
  queue_redraw()

func _select_inventory(kind: String) -> void:
  if simulating: return
  selected_building = null
  selected_kind = kind
  _refresh_ui()
  queue_redraw()

func _refresh_ui() -> void:
  if not is_instance_valid(status_label): return
  var mode := "Build"
  if simulating: mode = "Complete" if completed else "Simulation"
  status_label.text = "%s  •  Build cost $%d" % [mode, cost]
  if simulating:
    measurement_label.text = "Measuring stable output  •  Window %d/%d  •  %.1f / %.0f s" % [mini(windows.size() + 1, OBSERVED_WINDOWS), OBSERVED_WINDOWS, window_time, WINDOW_SECONDS]
    if not windows.is_empty() and not tracked_target.is_empty():
      var recent_rate := float(_goal_count(windows.back(), tracked_target)) / WINDOW_SECONDS
      status_label.text += "  •  Last window  %.2f/s" % recent_rate
      status_label.tooltip_text = tracked_label
    else:
      status_label.tooltip_text = ""
  else:
    measurement_label.text = "Press Play or Space to measure output." if not tracked_target.is_empty() else "Press Play or Space to check the cost limit."
    status_label.tooltip_text = ""
  status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
  measurement_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
  measurement_bar.value = window_time if simulating else 0.0
  diagnostic_legend.visible = diagnostics_enabled
  var has_selection := is_instance_valid(selected_building)
  var kind: String = selected_building.get_meta("kind") if has_selection else ""
  var magnet := kind == "magnet"
  var can_rotate: bool = has_selection and kind in ["emitter", "mirror", "magnet"] and not selected_building.get_meta("fixed_rotation")
  rotate_left_button.visible = not magnet
  rotate_left_button.disabled = simulating or not can_rotate
  rotate_button.text = "Flip polarity  Q / E" if magnet else "↷  E"
  rotate_button.tooltip_text = "Flip between positive and negative" if magnet else "Rotate clockwise"
  rotate_button.disabled = simulating or not can_rotate
  remove_button.disabled = simulating or not has_selection or selected_building.get_meta("fixed_position")
  configure_button.disabled = simulating or kind not in ["emitter", "detector"]
  if has_selection:
    var cell: Vector2i = selected_building.get_meta("cell")
    var move_hint := "Position locked" if selected_building.get_meta("fixed_position") else "Drag or click an empty tile to move"
    if magnet:
      move_hint = ("Positive" if selected_building.polarity > 0 else "Negative") + " polarity  •  " + move_hint
    selection_label.text = "%s (%d, %d)  •  %s" % [kind.capitalize(), cell.x, cell.y, move_hint]
  elif not selected_kind.is_empty():
    selection_label.text = "Click an empty tile to place a %s." % selected_kind
  else:
    selection_label.text = "Select a building on the board or choose one from inventory."
  selection_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
  stop_button.disabled = not simulating
  restart_button.disabled = not simulating
  palette.counts = inventory
  palette.selected = selected_kind
  palette.locked = simulating
  palette.refresh()
  var earned := _stable_stars(windows) if simulating and not windows.is_empty() else 0
  for i in range(star_icons.size()):
    star_icons[i].texture = FILLED_STAR if i < earned else EMPTY_STAR

func _drop_inventory(kind: String, screen_position: Vector2) -> void:
  if simulating or int(inventory.get(kind, 0)) <= 0: return
  var point: Vector2 = get_canvas_transform().affine_inverse() * screen_position / CELL
  var cell := Vector2i(roundi(point.x), level.height - 1 - roundi(point.y))
  if cell.x < 0 or cell.y < 0 or cell.x >= level.width or cell.y >= level.height: return
  if _building_at(cell) != null: return
  _record_undo()
  _place_building({"kind": kind, "x": cell.x, "y": cell.y}, true)
  inventory[kind] -= 1
  cost += COSTS[kind]
  selected_building = _building_at(cell)
  _refresh_ui()
  queue_redraw()

func begin_run() -> void:
  if simulating: return
  simulating = true
  completed = false
  selected_building = null
  selected_kind = ""
  _clear_particles()
  _clear_stats()
  if is_instance_valid(diagnostic_overlay): diagnostic_overlay.clear_events()
  _accumulated_time = 0.0
  for building in buildings:
    if building.get_meta("kind") == "emitter":
      if building.sequence.is_empty(): building.start_emitting()
      else: building.start_sequence()
  _refresh_ui()
  queue_redraw()

func stop_to_build() -> void:
  running = false
  cancel_pending_steps()
  simulating = false
  _accumulated_time = 0.0
  for building in buildings:
    if building.get_meta("kind") == "emitter": building.stop_sequence()
  _clear_particles()
  _clear_stats()
  completed = false
  _refresh_ui()

func restart_run() -> void:
  if not simulating: return
  stop_to_build()
  begin_run()
  running = true

func reset_level() -> void:
  results.hide()
  _load_initial_board()

func _return_to_select() -> void:
  if editor_playtest:
    exit_playtest_requested.emit()
  else:
    get_tree().change_scene_to_file("res://MainScene/level_select.tscn")

func _result_action(action: StringName) -> void:
  if action != &"next" or editor_playtest: return
  var path := Global.next_level_path(Global.selected_level)
  if path.is_empty(): return
  Global.selected_level = path
  get_tree().change_scene_to_file("res://MainScene/level_game.tscn")

func _goal_value(value: float) -> String:
  return "∞" if is_inf(value) else str(value)

func _clear_particles() -> void:
  for particle in _particles():
    remove_child(particle)
    particle.queue_free()

func _clear_stats() -> void:
  last_hud_update = 0.0
  total_counts.clear()
  window_counts.clear()
  windows.clear()
  window_time = 0.0
  elapsed = 0.0

func _on_particle_detected(name: String) -> void:
  var family := PARTICLES.family(name)
  for key in [name, family] if not family.is_empty() else [name]:
    total_counts[key] = int(total_counts.get(key, 0)) + 1
    window_counts[key] = int(window_counts.get(key, 0)) + 1

func _on_simulation_stepped(delta: float) -> void:
  if not simulating or completed: return
  elapsed += delta
  window_time += delta
  if elapsed - last_hud_update >= 0.4:
    last_hud_update = elapsed
    _refresh_ui()
  if window_time + 0.000001 < WINDOW_SECONDS: return
  windows.append(window_counts.duplicate())
  window_counts.clear()
  window_time -= WINDOW_SECONDS
  if windows.size() > OBSERVED_WINDOWS: windows.pop_front()
  _refresh_ui()
  if editor_preview: return
  if windows.size() < OBSERVED_WINDOWS or _stable_stars(windows) == 0: return
  # Check additional windows on an isolated copy: the live board, emitter
  # timers, particles and statistics are not advanced by this prediction.
  var samples: Array[Dictionary] = windows.duplicate(true)
  samples.append_array(FORECAST.predict(self, buildings, WINDOW_SECONDS, FORECAST_WINDOWS))
  var stars := _stable_stars(samples)
  if stars > 0:
    completed = true
    if not editor_playtest: Global.record_best_stars(Global.selected_level, stars)
    running = false
    cancel_pending_steps()
    var stats := ""
    var latest: Dictionary = windows.back()
    for kind in total_counts:
      stats += "\n%s: %d total, %.2f / s in the last 5s" % [str(kind).capitalize(), int(total_counts[kind]), float(latest.get(kind, 0)) / WINDOW_SECONDS]
    if stats.is_empty(): stats = "\nNo particles detected"
    for i in range(star_icons.size()):
      star_icons[i].texture = FILLED_STAR if i < stars else EMPTY_STAR
    results.dialog_text = "%d star(s) earned\nSimulation time: %.1f s\nBuild cost: %d\nDetected:%s" % [stars, elapsed, cost, stats]
    results.popup_centered()

func _goal_count(counts: Dictionary, key: String) -> int:
  if not (key.begins_with("[") and key.ends_with("]")):
    return int(counts.get(key, 0))
  var names := key.substr(1, key.length() - 2).split(",", false)
  var total := 0
  for name in names:
    # Colour-specific counts are also included in their broad flavour count.
    if PARTICLES.family(name) in names: continue
    total += int(counts.get(name, 0))
  return total

func _stable_stars(samples: Array[Dictionary]) -> int:
  if samples.is_empty(): return 0
  var best := 0
  for goal in level.goals:
    for star in range(1, 4):
      var satisfied := true
      for key in goal:
        var threshold: float = goal[key][star - 1]
        if key == "cost":
          if cost > threshold: satisfied = false
          continue
        var low := INF
        var high := 0.0
        for counts in samples:
          var rate := float(_goal_count(counts, key)) / WINDOW_SECONDS
          low = minf(low, rate)
          high = maxf(high, rate)
        # Every five-second window must meet the goal. Small fluctuations are
        # allowed because whole-particle counts can straddle window boundaries.
        if low + 0.0001 < threshold or high - low > maxf(0.4, high * 0.2):
          satisfied = false
      if satisfied: best = maxi(best, star)
  return best

func _on_particle_event(kind: String, at: Vector2) -> void:
  if diagnostics_enabled and is_instance_valid(diagnostic_overlay):
    diagnostic_overlay.add_event(kind, at)

# Store the actual configured state rather than the original level declaration.
func _snapshot_build() -> Dictionary:
  var entries: Array[Dictionary] = []
  for building in buildings:
    if not is_instance_valid(building): continue
    var entry: Dictionary = building.get_meta("entry").duplicate(true)
    var cell: Vector2i = building.get_meta("cell")
    entry.x = cell.x
    entry.y = cell.y
    var kind: String = building.get_meta("kind")
    if kind == "emitter": entry.facing = DIRECTIONS[building.orientation]
    elif kind == "mirror": entry.facing = DIRECTIONS[posmod(building.orientation - 2, 8)]
    elif kind == "magnet": entry.polarity = "+" if building.polarity > 0 else "-"
    if kind == "emitter": entry.rate = building.rate
    entries.append({"entry": entry, "inventory_piece": building.get_meta("from_inventory")})
  return {"entries": entries, "inventory": inventory.duplicate(true), "cost": cost}

func _record_undo() -> void:
  if simulating or restoring_history: return
  undo_history.append(_snapshot_build())
  if undo_history.size() > 100: undo_history.pop_front()
  redo_history.clear()

func _restore_build(snapshot: Dictionary) -> void:
  restoring_history = true
  for building in buildings:
    if is_instance_valid(building):
      remove_child(building)
      building.queue_free()
  buildings.clear()
  inventory = snapshot.inventory.duplicate(true)
  cost = snapshot.cost
  selected_kind = ""
  selected_building = null
  for item in snapshot.entries:
    _place_building(item.entry, item.inventory_piece)
  restoring_history = false
  _refresh_ui()
  queue_redraw()

func undo_build() -> void:
  if simulating or undo_history.is_empty(): return
  redo_history.append(_snapshot_build())
  _restore_build(undo_history.pop_back())

func redo_build() -> void:
  if simulating or redo_history.is_empty(): return
  undo_history.append(_snapshot_build())
  _restore_build(redo_history.pop_back())
