extends "res://Particles/particle_simulation.gd"

const PARSER = preload("res://Levels/level_parser.gd")
const PARTICLES = preload("res://Particles/particle_catalog.gd")
const UI = preload("res://MainScene/workspace_theme.gd")
const ENTRY = preload("res://Buildings/Emitter/particle_emission.gd")
const TILE = preload("res://tile.png")
const FORECAST = preload("res://MainScene/simulation_forecast.gd")
const PREVIEW = preload("res://Buildings/particle_preview.gd")
const OVERLAY = preload("res://MainScene/placement_overlay.gd")
const PALETTE = preload("res://MainScene/building_palette.gd")
const OUTPUT_METER = preload("res://MainScene/output_meter.gd")
const CATALOG = preload("res://Buildings/building_catalog.gd")
const CELL: float = 102.4
const SCENES := CATALOG.SCENES
# Costs are shared by all levels, as described by the level format.
const COSTS := CATALOG.COSTS
const DIRECTIONS := ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
const SIDEBAR_WIDTH := 288.0
const RECENT_SECONDS := 2.0
const SPEED_RAMP_START := 3.0
const SPEED_RAMP_END := 6.0
const WATCH_SECONDS := 7.0
const FORECAST_WINDOW_SECONDS := 10.0
const FORECAST_WINDOWS := 6

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
var undo_history: Array[Dictionary] = []
var redo_history: Array[Dictionary] = []
var restoring_history := false
var last_hud_update := 0.0
var editor_bottom_inset := 190.0
var editor_sidebar_width := 256.0
var hud_panel: PanelContainer
var sidebar: VBoxContainer
var level: Dictionary = {}
var buildings: Array[Node] = []
var inventory: Dictionary = {}
var selected_kind: String = ""
var selected_building: Node = null
var cost: int = 0
var simulating: bool = false
var total_counts: Dictionary = {}
var recent_counts: Dictionary = {}
var step_counts: Dictionary = {}
var recent_samples: Array[Dictionary] = []
var elapsed: float = 0.0
var automatic_speed := true
var next_forecast_at := WATCH_SECONDS
var forecast: FORECAST
var forecast_candidates: Array[Dictionary] = []
var forecast_counts: Dictionary = {}
var forecast_windows := 0
var completed: bool = false
var selection_label: Label
var output_rows: Array[Dictionary] = []
var rotate_button: Button
var rotate_left_button: Button
var remove_button: Button
var next_level_button: Button
var restart_button: Button
var palette: PanelContainer
var results: AcceptDialog
var stop_button: Button

func _ready() -> void:
  running = false
  RenderingServer.set_default_clear_color(UI.BACKGROUND)
  $SimulationControls/Panel.theme = UI.theme()
  if editor_preview:
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

func _exit_tree() -> void:
  _cancel_forecast()

func _draw() -> void:
  if level.is_empty() or level.has("error"):
    return
  for x in range(level.width):
    for y in range(level.height):
      draw_texture_rect(TILE, Rect2(Vector2(x, y) * CELL - Vector2.ONE * CELL * 0.5, Vector2.ONE * CELL), false)

func get_playback_speed() -> float:
  if editor_preview or not automatic_speed or not simulating:
    return super.get_playback_speed()
  return lerpf(1.0, 2.0, smoothstep(SPEED_RAMP_START, SPEED_RAMP_END, elapsed))

func set_playback_speed(speed: float) -> void:
  automatic_speed = false
  super.set_playback_speed(speed)

func _fit_camera() -> void:
  if level.is_empty():
    return
  var camera: Camera2D = $Camera2D
  camera.position = Vector2(level.width - 1, level.height - 1) * CELL * 0.5
  var view := get_viewport_rect().size
  var bottom_inset := editor_bottom_inset if editor_preview else hud_panel.size.y + 28.0
  var top_inset := 74.0 if editor_preview else 115.0
  var right_inset := editor_sidebar_width if editor_preview else SIDEBAR_WIDTH + 16.0
  var available := Vector2(maxf(100.0, view.x - right_inset - 36.0), maxf(100.0, view.y - top_inset - bottom_inset))
  var board := Vector2(level.width, level.height) * CELL
  var zoom_amount := minf(1.0, minf(available.x / board.x, available.y / board.y))
  camera.zoom = Vector2.ONE * zoom_amount
  camera.offset = Vector2(right_inset, bottom_inset - top_inset) * 0.5 / zoom_amount

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
  panel.offset_right = -SIDEBAR_WIDTH - 32.0
  panel.offset_top = -16
  panel.offset_bottom = -16
  layer.add_child(panel)
  panel.resized.connect(_fit_camera)
  var margin := UI.margin(10)
  panel.add_child(margin)
  var column := VBoxContainer.new()
  column.add_theme_constant_override("separation", 4)
  margin.add_child(column)
  _add_sidebar(layer)
  _add_level_heading(layer)
  selection_label = Label.new()
  UI.muted(selection_label)
  column.add_child(selection_label)
  var actions := HFlowContainer.new()
  column.add_child(actions)
  rotate_left_button = _button(actions, "↶  Q", _rotate_selected.bind(-1))
  rotate_left_button.tooltip_text = "Rotate counterclockwise"
  rotate_button = _button(actions, "↷  E", _rotate_selected)
  rotate_button.tooltip_text = "Rotate clockwise"
  remove_button = _button(actions, "Remove  Del", _remove_selected)
  stop_button = $SimulationControls.enable_build(stop_to_build)
  restart_button = _button(actions, "Restart", restart_run)
  _button(actions, "Reset  X", reset_level)
  _button(actions, "Back to editor" if editor_playtest else "Levels", _return_to_select)
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

func _label(value: String) -> Label:
  var label := Label.new()
  label.text = value
  return label

func _add_level_heading(layer: CanvasLayer) -> void:
  var header := VBoxContainer.new()
  header.theme = UI.theme()
  header.set_anchors_preset(Control.PRESET_TOP_WIDE)
  header.offset_left = 16
  header.offset_right = -SIDEBAR_WIDTH - 32.0
  header.offset_top = 72
  header.mouse_filter = Control.MOUSE_FILTER_IGNORE
  layer.add_child(header)
  var title := str(level.get("title", ""))
  if title.is_empty(): title = "Playtest" if editor_playtest else Global.selected_level.get_file().get_basename()
  var heading := _label(title)
  UI.heading(heading, 25)
  heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
  header.add_child(heading)

func _add_sidebar(layer: CanvasLayer) -> void:
  sidebar = VBoxContainer.new()
  sidebar.name = "Sidebar"
  sidebar.theme = UI.theme()
  sidebar.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
  sidebar.offset_left = -SIDEBAR_WIDTH - 16.0
  sidebar.offset_right = -16
  sidebar.offset_top = 16
  sidebar.offset_bottom = -16
  sidebar.mouse_filter = Control.MOUSE_FILTER_IGNORE
  layer.add_child(sidebar)
  var panel := PanelContainer.new()
  panel.name = "GoalPanel"
  sidebar.add_child(panel)
  var margin := UI.margin()
  panel.add_child(margin)
  var scroll := ScrollContainer.new()
  scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
  margin.add_child(scroll)
  var rows := VBoxContainer.new()
  rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  scroll.add_child(rows)
  _add_goals(rows)
  palette = PALETTE.new()
  sidebar.add_child(palette)
  palette.kind_selected.connect(_select_inventory)
  palette.kind_dropped.connect(_drop_inventory)
  var toolbar: PanelContainer = $SimulationControls/Panel
  var fit := func() -> void:
    var view := get_viewport_rect().size
    var toolbar_end := toolbar.get_rect().end
    sidebar.offset_top = 16.0 if toolbar_end.x + 8.0 <= view.x - SIDEBAR_WIDTH - 16.0 else toolbar_end.y + 8.0
    var available := view.y - sidebar.offset_top - 16.0
    var frame_height := panel.get_combined_minimum_size().y - scroll.get_combined_minimum_size().y
    scroll.custom_minimum_size.y = minf(rows.get_combined_minimum_size().y, maxf(44.0, available * 0.46 - frame_height))
    palette.height_limit = available - frame_height - scroll.custom_minimum_size.y - sidebar.get_theme_constant("separation")
  rows.minimum_size_changed.connect(fit)
  get_viewport().size_changed.connect(fit)
  toolbar.resized.connect(fit)
  fit.call()

func _add_goals(rows: VBoxContainer) -> void:
  var targets: Array = level.get("goal_targets", [])
  for index in range(level.goals.size()):
    if index > 0:
      var divider := _label("OR")
      UI.muted(divider, 11)
      rows.add_child(divider)
    var goal: Dictionary = level.goals[index]
    var table := GridContainer.new()
    table.columns = 4
    table.add_theme_constant_override("h_separation", 5)
    table.add_theme_constant_override("v_separation", 3)
    rows.add_child(table)
    _add_goal_cells(table, "Stars", ["★", "★★", "★★★"], true)
    var output_count := goal.size() - int(goal.has("cost"))
    for key in goal:
      var target: String = targets[index].get(key, key) if index < targets.size() else key
      var title: String = "Cost" if key == "cost" else (PARTICLES.label(target) if PARTICLES.TYPES.has(target) else target)
      var thresholds: Array[String] = []
      for value in goal[key]:
        var amount := str(value).trim_suffix(".0")
        thresholds.append("∞" if is_inf(value) else amount + ("" if key == "cost" else "/s"))
      _add_goal_cells(table, title, thresholds)
      if key == "cost": continue
      var row := HBoxContainer.new()
      rows.add_child(row)
      var details := VBoxContainer.new()
      details.custom_minimum_size.x = 85 if output_count > 1 else 59
      details.size_flags_vertical = Control.SIZE_SHRINK_CENTER
      details.add_theme_constant_override("separation", 0)
      row.add_child(details)
      if output_count > 1:
        var name_label := _label(title)
        UI.muted(name_label, 12)
        name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
        details.add_child(name_label)
      var rate_label := _label("")
      rate_label.add_theme_color_override("font_color", UI.ACCENT)
      rate_label.tooltip_text = "Recent output · " + title
      rate_label.mouse_filter = Control.MOUSE_FILTER_STOP
      details.add_child(rate_label)
      var meter := OUTPUT_METER.new()
      meter.set_thresholds(goal[key])
      meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
      row.add_child(meter)
      output_rows.append({"key": key, "meter": meter, "label": rate_label})
  var hint := str(level.get("hint", ""))
  if not hint.is_empty():
    var prompt := _label(hint)
    UI.muted(prompt)
    prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    rows.add_child(prompt)

func _add_goal_cells(table: GridContainer, title: String, values: Array, heading := false) -> void:
  var label := _label(title)
  label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
  label.tooltip_text = title
  label.mouse_filter = Control.MOUSE_FILTER_STOP
  if heading: UI.heading(label, 15)
  table.add_child(label)
  for value in values:
    var cell := _label(value)
    cell.custom_minimum_size.x = 43
    cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    cell.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    cell.tooltip_text = value
    cell.mouse_filter = Control.MOUSE_FILTER_STOP
    if heading: cell.add_theme_color_override("font_color", UI.GOLD)
    table.add_child(cell)

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
  if not is_instance_valid(palette): return
  _refresh_output()
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
  selection_label.visible = has_selection
  if has_selection:
    var cell: Vector2i = selected_building.get_meta("cell")
    selection_label.text = "%s (%d, %d)" % [kind.capitalize(), cell.x, cell.y]
    if magnet:
      selection_label.text += "  %s" % ("+" if selected_building.polarity > 0 else "−")
  stop_button.disabled = not simulating
  restart_button.disabled = not simulating
  palette.counts = inventory
  palette.build_cost = cost
  palette.selected = selected_kind
  palette.locked = simulating
  palette.refresh()

func _refresh_output() -> void:
  for row in output_rows:
    var rate := float(_goal_count(recent_counts, row.key)) / RECENT_SECONDS
    row.label.text = "%s/s" % String.num(rate, 2)
    row.meter.set_rate(rate, simulating)

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

func _clear_particles() -> void:
  for particle in _particles():
    remove_child(particle)
    particle.queue_free()

func _clear_stats() -> void:
  _cancel_forecast()
  next_forecast_at = WATCH_SECONDS
  last_hud_update = 0.0
  total_counts.clear()
  recent_counts.clear()
  step_counts.clear()
  recent_samples.clear()
  elapsed = 0.0
  if is_instance_valid(diagnostic_overlay): diagnostic_overlay.clear_events()

func _on_particle_detected(name: String) -> void:
  var family := PARTICLES.family(name)
  for key in [name, family] if not family.is_empty() else [name]:
    total_counts[key] = int(total_counts.get(key, 0)) + 1
    recent_counts[key] = int(recent_counts.get(key, 0)) + 1
    step_counts[key] = int(step_counts.get(key, 0)) + 1

func _on_simulation_stepped(delta: float) -> void:
  if not simulating or completed: return
  elapsed += delta
  if not step_counts.is_empty():
    recent_samples.append({"time": elapsed, "counts": step_counts})
    step_counts = {}
  while not recent_samples.is_empty() and recent_samples.front().time <= elapsed - RECENT_SECONDS + 0.000001:
    var expired: Dictionary = recent_samples.pop_front().counts
    for key in expired:
      recent_counts[key] -= expired[key]
  if elapsed - last_hud_update >= 0.15:
    last_hud_update = elapsed
    _refresh_output()
  if forecast != null or elapsed + 0.000001 < next_forecast_at: return
  next_forecast_at = elapsed + 0.25
  for goal in level.goals:
    for tier in range(3):
      var eligible := true
      for key in goal:
        var threshold: float = goal[key][tier]
        if key == "cost":
          if cost > threshold: eligible = false
        elif is_inf(threshold) or (threshold > 0.0 and _goal_count(total_counts, key) == 0):
          eligible = false
      if eligible:
        forecast_candidates.append({"goal": goal, "tier": tier})
  if not forecast_candidates.is_empty():
    forecast = FORECAST.new(self, buildings, FORECAST_WINDOW_SECONDS)

func _process(_delta: float) -> void:
  if forecast == null or not forecast.advance(): return
  for key in forecast.counts:
    forecast_counts[key] = int(forecast_counts.get(key, 0)) + int(forecast.counts[key])
  forecast_windows += 1
  var finished := forecast_windows == FORECAST_WINDOWS
  var stars := 0
  for i in range(forecast_candidates.size() - 1, -1, -1):
    var candidate := forecast_candidates[i]
    if not _meets_output(candidate, forecast.counts, FORECAST_WINDOW_SECONDS, true):
      forecast_candidates.remove_at(i)
    elif finished and _meets_output(candidate, forecast_counts, FORECAST_WINDOWS * FORECAST_WINDOW_SECONDS, false):
      stars = maxi(stars, candidate.tier + 1)
  if finished or forecast_candidates.is_empty():
    _cancel_forecast()
    next_forecast_at = elapsed + 2.0
    if stars > 0: _finish_run(stars)

func _cancel_forecast() -> void:
  if forecast != null:
    forecast.dispose()
    forecast = null
  forecast_candidates.clear()
  forecast_counts.clear()
  forecast_windows = 0

func _finish_run(stars: int) -> void:
  completed = true
  running = false
  cancel_pending_steps()
  if not editor_playtest: Global.record_best_stars(Global.selected_level, stars)
  _refresh_ui()
  var stats := ""
  for kind in total_counts:
    stats += "\n%s: %d total · %.2f/s recent" % [PARTICLES.label(kind), int(total_counts[kind]), float(recent_counts.get(kind, 0)) / RECENT_SECONDS]
  if stats.is_empty(): stats = "\nNo particles detected"
  results.dialog_text = "%d star(s) earned\nBuild cost: $%d\n\nDetected%s" % [stars, cost, stats]
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

func _meets_output(candidate: Dictionary, counts: Dictionary, seconds: float, allow_fraction: bool) -> bool:
  for key in candidate.goal:
    if key == "cost": continue
    var required: float = candidate.goal[key][candidate.tier] * seconds
    # A whole-particle count can round down in one window. The full forecast
    # still has to meet the authored average.
    if allow_fraction: required = floorf(required + 0.000001)
    if _goal_count(counts, key) + 0.000001 < required: return false
  return true

func _on_particle_event(kind: String, at: Vector2) -> void:
  if is_instance_valid(diagnostic_overlay):
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
