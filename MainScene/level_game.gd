extends "res://Particles/particle_simulation.gd"

const PARSER = preload("res://Levels/level_parser.gd")
const UI = preload("res://MainScene/workspace_theme.gd")
const ENTRY = preload("res://Buildings/Emitter/particle_emission.gd")
const TILE = preload("res://tile.png")
const FORECAST = preload("res://MainScene/simulation_forecast.gd")
const PREVIEW = preload("res://Buildings/particle_preview.gd")
const OVERLAY = preload("res://MainScene/placement_overlay.gd")
const PALETTE = preload("res://MainScene/building_palette.gd")
const OUTPUT_METER = preload("res://MainScene/output_meter.gd")
const CATALOG = preload("res://Buildings/building_catalog.gd")
const BUILDING = preload("res://Buildings/building.gd")
const CELL := BUILDING.GRID_SIZE
const SIDEBAR_WIDTH := 288.0
const POINTER_SLOP := 8.0
const ZOOM_STEP := 1.2
const MIN_METER_STEPS := 8
const MAX_METER_STEPS := 2400
const METER_TARGET_COUNT := 8.0
const SPEED_RAMP_START := 12.0
const SPEED_RAMP_END := 24.0
const WATCH_STEPS := 28.0
const FORECAST_WINDOW_STEPS := 40.0
const FORECAST_WINDOWS := 6
const FORECAST_TARGET_COUNT := 2.0
const MAX_FORECAST_CHUNKS_PER_WINDOW := 30

signal editor_cell_clicked(cell: Vector2i, button: int, target: Node, facing: String)
signal editor_cell_dragged(from_cell: Vector2i, to_cell: Vector2i)
signal editor_area_selected(area: Rect2i)
signal exit_playtest_requested
var drag_cell := Vector2i(-1, -1)
var drag_start := Vector2.ZERO
var area_selection_enabled := false
var area_origin := Vector2i(-1, -1)
var camera_pan := Vector2.ZERO
var camera_scale := 1.0
var fitted_zoom := 1.0
var pan_button := MOUSE_BUTTON_NONE
var pan_start := Vector2.ZERO
var mouse_panning := false
var touches: Dictionary[int, Vector2] = {}
var touch_start := Vector2.ZERO
var touch_gesture := false
var board_uses_touch := false

var editor_preview := false
var editor_playtest := false
var level_override: Dictionary = {}
var external_palette: PanelContainer
var editor_tool_panel: Control
var diagnostic_overlay
var undo_history: Array[Dictionary] = []
var redo_history: Array[Dictionary] = []
var last_hud_update := 0.0
var editor_bottom_inset := 190.0
var editor_sidebar_width := 256.0
var hud_panel: PanelContainer
var level_heading: VBoxContainer
var game_sidebar: VBoxContainer
var goal_panel: PanelContainer
var goal_scroll: ScrollContainer
var goal_content: VBoxContainer
var sidebar_toggle: Button
var compact_layout := false
var sidebar_open := false
var results_text: RichTextLabel
var level: Dictionary = {}
var buildings: Array[Node] = []
var inventory: Dictionary = {}
var selected_kind: String = ""
var selected_building: Node = null
var cost: int = 0
var simulating: bool = false
var total_counts: Dictionary = {}
var output_samples: Array[Dictionary] = []
var sampled_counts: Dictionary = {}
var sampled_step := 0
var output_changed := false
var elapsed: float = 0.0
var automatic_speed := true
var next_forecast_at := WATCH_STEPS
var forecast: FORECAST
var forecast_candidates: Array[Dictionary] = []
var forecast_counts: Dictionary = {}
var forecast_chunks := 0
var forecast_best_stars := 0
var completed: bool = false
var selection_label: Label
var output_rows: Array[Dictionary] = []
var rotate_button: Button
var rotate_left_button: Button
var remove_button: Button
var restart_button: Button
var palette: PanelContainer
var results: AcceptDialog
var stop_button: Button

func _ready() -> void:
  running = false
  RenderingServer.set_default_clear_color(UI.BACKGROUND)
  $SimulationControls/Panel.theme = UI.theme()
  _add_camera_controls()
  if editor_preview:
    _add_diagnostic_overlay()
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
  _add_diagnostic_overlay()
  _load_initial_board()
  get_viewport().size_changed.connect(_fit_camera)
  _fit_camera()

func _add_diagnostic_overlay() -> void:
  var overlay := Node2D.new()
  overlay.set_script(OVERLAY)
  overlay.z_index = 100
  add_child(overlay)
  diagnostic_overlay = overlay
  particle_event.connect(_on_particle_event)

func _exit_tree() -> void:
  _cancel_forecast()

func _draw() -> void:
  if level.is_empty() or level.has("error"):
    return
  for x in range(level.width):
    for y in range(level.height):
      draw_texture_rect(TILE, Rect2(Vector2(x, y) * CELL - Vector2.ONE * CELL * 0.5, Vector2.ONE * CELL), false)
  for area in level.get("no_build_areas", []):
    var rect := _area_rect(area)
    draw_rect(rect, Color("e39662", 0.24))
    draw_rect(rect.grow(-1.0), Color("e39662", 0.85), false, 2.0)

func get_playback_speed() -> float:
  if editor_preview or not automatic_speed or not simulating:
    return super.get_playback_speed()
  return lerpf(1.0, 2.0, smoothstep(SPEED_RAMP_START, SPEED_RAMP_END, elapsed))

func set_playback_speed(speed: float) -> void:
  automatic_speed = false
  super.set_playback_speed(speed)

func _fit_camera() -> void:
  if level.is_empty() or level.has("error"): return
  var available := _board_view()
  var board_size := Vector2(level.width, level.height) * CELL
  fitted_zoom = minf(1.0, minf(maxf(1.0, available.size.x - 36.0) / board_size.x,
    maxf(1.0, available.size.y - 24.0) / board_size.y))
  _update_board_camera(available)

func _board_view() -> Rect2:
  var view := get_viewport_rect().size
  var toolbar: Control = $SimulationControls/Panel
  var top_inset := toolbar.get_rect().end.y if editor_preview else level_heading.get_rect().end.y
  var bottom_inset := editor_bottom_inset if editor_preview else view.y - hud_panel.get_rect().position.y
  var right_inset := editor_sidebar_width if editor_preview else (0.0 if compact_layout else SIDEBAR_WIDTH + 16.0)
  return Rect2(0, top_inset, maxf(1.0, view.x - right_inset), maxf(1.0, view.y - top_inset - bottom_inset))

func _update_board_camera(available: Rect2) -> void:
  var camera: Camera2D = $Camera2D
  camera_scale = clampf(camera_scale, 0.5, 4.0 / fitted_zoom)
  var zoom_amount := fitted_zoom * camera_scale
  # Keep a strip of the board reachable at either end of a pan.
  var border := (available.size * 0.5 - Vector2(48, 48)).max(Vector2.ZERO)
  var pan_limit := Vector2(level.width, level.height) * CELL * 0.5 + border / zoom_amount
  camera_pan = camera_pan.clamp(-pan_limit, pan_limit)
  camera.position = Vector2(level.width - 1, level.height - 1) * CELL * 0.5 + camera_pan
  camera.zoom = Vector2.ONE * zoom_amount
  camera.offset = (get_viewport_rect().size * 0.5 - available.get_center()) / zoom_amount
  camera.force_update_scroll()

func fit_board() -> void:
  camera_pan = Vector2.ZERO
  camera_scale = 1.0
  _fit_camera()

func _zoom_board(factor: float, anchor: Vector2, destination: Vector2) -> void:
  var available := _board_view()
  var old_zoom := fitted_zoom * camera_scale
  camera_scale = clampf(camera_scale * factor, 0.5, 4.0 / fitted_zoom)
  var center := available.get_center()
  camera_pan += (anchor - center) / old_zoom - (destination - center) / (fitted_zoom * camera_scale)
  _update_board_camera(available)

func _pan_board(delta: Vector2) -> void:
  camera_pan -= delta / (fitted_zoom * camera_scale)
  _update_board_camera(_board_view())

func _zoom_from_button(factor: float) -> void:
  if level.is_empty(): return
  var center := _board_view().get_center()
  _zoom_board(factor, center, center)

func _add_camera_controls() -> void:
  var toolbar: PanelContainer = $SimulationControls/Panel
  var group := HBoxContainer.new()
  $SimulationControls/Panel/Margin/Controls.add_child(group)
  var zoom_out := UI.button(group, "−", _zoom_from_button.bind(1.0 / ZOOM_STEP))
  zoom_out.tooltip_text = "Zoom out"
  zoom_out.custom_minimum_size.x = 34
  var zoom_in := UI.button(group, "+", _zoom_from_button.bind(ZOOM_STEP))
  zoom_in.tooltip_text = "Zoom in"
  zoom_in.custom_minimum_size.x = 34
  var fit := UI.button(group, "Fit board", fit_board)
  fit.tooltip_text = "Fit the whole board. Pan with a middle or right drag, or drag with one finger. Zoom with the wheel or a pinch."
  var layout := func() -> void:
    toolbar.size.x = minf(590.0, get_viewport_rect().size.x - 32.0)
  get_viewport().size_changed.connect(layout)
  layout.call()

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
  sidebar_toggle = UI.button(actions, "Goals & inventory", _toggle_sidebar)
  sidebar_toggle.toggle_mode = true
  sidebar_toggle.hide()
  rotate_left_button = UI.button(actions, "↶  Q", _rotate_selected.bind(-1))
  rotate_left_button.tooltip_text = "Rotate counterclockwise"
  rotate_button = UI.button(actions, "↷  E", _rotate_selected)
  rotate_button.tooltip_text = "Rotate clockwise"
  remove_button = UI.button(actions, "Remove  " + UI.delete_key_label(), _remove_selected)
  stop_button = $SimulationControls.enable_build(stop_to_build)
  restart_button = UI.button(actions, "Restart", restart_run)
  UI.button(actions, "Reset  X", reset_level)
  UI.button(actions, "Back to editor" if editor_playtest else "Levels", _return_to_select)
  results = AcceptDialog.new()
  UI.setup_dialog(results, layer, "Level complete")
  results.about_to_popup.connect(cancel_board_gesture)
  results.ok_button_text = "Back to build"
  results.confirmed.connect(stop_to_build)
  results.canceled.connect(stop_to_build)
  results.custom_action.connect(_result_action)
  var next_level_button := results.add_button("Next level", true, "next")
  next_level_button.visible = not editor_playtest and not Global.next_level_path(Global.selected_level).is_empty()
  results_text = RichTextLabel.new()
  results.add_child(results_text)
  get_viewport().size_changed.connect(_layout_hud)
  panel.resized.connect(_layout_hud)
  _layout_hud()

func _layout_hud() -> void:
  var view := get_viewport_rect().size
  var compact := UI.compact_board(view)
  if compact_layout != compact:
    compact_layout = compact
    sidebar_open = false
  var right := -16.0 if compact else -SIDEBAR_WIDTH - 32.0
  hud_panel.offset_right = right
  level_heading.offset_right = right
  sidebar_toggle.visible = compact
  sidebar_toggle.set_pressed_no_signal(sidebar_open)
  game_sidebar.visible = not compact or sidebar_open
  _layout_sidebar()
  _fit_camera()

func _toggle_sidebar() -> void:
  sidebar_open = not sidebar_open
  _layout_hud()

func _add_level_heading(layer: CanvasLayer) -> void:
  var header := VBoxContainer.new()
  level_heading = header
  header.theme = UI.theme()
  header.set_anchors_preset(Control.PRESET_TOP_WIDE)
  header.offset_left = 16
  header.offset_right = -SIDEBAR_WIDTH - 32.0
  header.offset_top = 72
  header.mouse_filter = Control.MOUSE_FILTER_IGNORE
  layer.add_child(header)
  var title := str(level.get("title", ""))
  if title.is_empty(): title = "Playtest" if editor_playtest else Global.selected_level.get_file().get_basename()
  var heading := UI.label(title)
  UI.heading(heading, 25)
  heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
  header.add_child(heading)
  var toolbar: Control = $SimulationControls/Panel
  var fit := func() -> void:
    header.offset_top = toolbar.get_rect().end.y + 8.0
    _fit_camera()
  toolbar.resized.connect(fit)
  header.resized.connect(_fit_camera)
  fit.call()

func _add_sidebar(layer: CanvasLayer) -> void:
  var sidebar := VBoxContainer.new()
  game_sidebar = sidebar
  sidebar.name = "Sidebar"
  sidebar.theme = UI.theme()
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
  goal_panel = panel
  goal_scroll = scroll
  goal_content = rows
  rows.minimum_size_changed.connect(_layout_sidebar)
  $SimulationControls/Panel.resized.connect(_layout_sidebar)

func _layout_sidebar() -> void:
  var view := get_viewport_rect().size
  var toolbar_end: Vector2 = $SimulationControls/Panel.get_rect().end
  var top := 16.0 if toolbar_end.x + 8.0 <= view.x - SIDEBAR_WIDTH - 16.0 else toolbar_end.y + 8.0
  var bottom := view.y - 16.0
  if compact_layout:
    bottom = hud_panel.get_rect().position.y - 8.0
    top = maxf(toolbar_end.y + 8.0, bottom - minf(360.0, view.y * 0.5))
  var available := bottom - top
  var frame_height := goal_panel.get_combined_minimum_size().y - goal_scroll.get_combined_minimum_size().y
  goal_scroll.custom_minimum_size.y = minf(goal_content.get_combined_minimum_size().y, maxf(44.0, available * 0.46 - frame_height))
  palette.height_limit = available - frame_height - goal_scroll.custom_minimum_size.y - game_sidebar.get_theme_constant("separation")
  game_sidebar.offset_left = 16.0 if compact_layout else view.x - SIDEBAR_WIDTH - 16.0
  game_sidebar.offset_right = view.x - 16.0
  game_sidebar.offset_top = top
  game_sidebar.offset_bottom = bottom

func _add_goals(rows: VBoxContainer) -> void:
  var targets: Array = level.get("goal_targets", [])
  for index in range(level.goals.size()):
    if index > 0:
      var divider := UI.label("OR")
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
      var title: String = "Cost" if key == "cost" else (PARTICLES.label(target) if PARTICLES.is_selector(target) else target)
      var thresholds: Array[String] = []
      for value in goal[key]:
        var amount := str(value).trim_suffix(".0")
        thresholds.append("∞" if is_inf(value) else amount + ("" if key == "cost" else "/step"))
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
        var name_label := UI.label(title)
        UI.muted(name_label, 12)
        name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
        details.add_child(name_label)
      var rate_label := UI.label("")
      rate_label.add_theme_color_override("font_color", UI.ACCENT)
      rate_label.mouse_filter = Control.MOUSE_FILTER_STOP
      details.add_child(rate_label)
      var meter := OUTPUT_METER.new()
      meter.set_thresholds(goal[key])
      meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
      row.add_child(meter)
      output_rows.append({"key": key, "title": title, "meter": meter, "label": rate_label, "window": _meter_window(goal[key])})
  var hint := str(level.get("hint", ""))
  if not hint.is_empty():
    var prompt := UI.label(hint)
    UI.muted(prompt)
    prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    rows.add_child(prompt)

func _add_goal_cells(table: GridContainer, title: String, values: Array, heading := false) -> void:
  var label := UI.label(title)
  label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
  label.tooltip_text = title
  label.mouse_filter = Control.MOUSE_FILTER_STOP
  if heading: UI.heading(label, 15)
  table.add_child(label)
  for value in values:
    var cell := UI.label(value)
    cell.custom_minimum_size.x = 43
    cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    cell.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    cell.tooltip_text = value
    cell.mouse_filter = Control.MOUSE_FILTER_STOP
    if heading: cell.add_theme_color_override("font_color", UI.GOLD)
    table.add_child(cell)

func _load_initial_board() -> void:
  running = false
  cancel_pending_steps()
  simulating = false
  completed = false
  _clear_particles()
  _clear_buildings()
  inventory = level.inventory.duplicate(true)
  inventory.erase("rail")
  cost = 0
  undo_history.clear()
  redo_history.clear()
  selected_building = null
  selected_kind = ""
  area_origin = Vector2i(-1, -1)
  for entry in level.buildings:
    _place_building(entry, false)
  level_bounds_enabled = true
  level_bounds = Rect2(-CELL * 0.5, -CELL * 0.5, level.width * CELL, level.height * CELL)
  _clear_stats()
  _refresh_ui()
  queue_redraw()

func _clear_buildings() -> void:
  for building in buildings:
    if is_instance_valid(building):
      remove_child(building)
      building.queue_free()
  buildings.clear()

func _place_building(entry: Dictionary, from_inventory: bool) -> void:
  if not CATALOG.SCENES.has(entry.kind): return
  var scene: PackedScene = CATALOG.SCENES[entry.kind]
  var building := scene.instantiate()
  var cell := Vector2i(int(entry.x), int(entry.y))
  building.position = _cell_position(cell)
  building.set_meta("entry", entry.duplicate(true))
  building.set_meta("cell", cell)
  building.set_meta("kind", entry.kind)
  var fixed := str(entry.get("fixed", ""))
  building.set_meta("fixed_position", "p" in fixed)
  building.set_meta("fixed_rotation", CATALOG.rotation_lock_flag(entry.kind) in fixed)
  building.set_meta("from_inventory", from_inventory)
  if entry.kind in CATALOG.FACING_KINDS or entry.kind == "edge_wall":
    var direction := CATALOG.DIRECTIONS.find(entry.get("facing", CATALOG.default_facing(entry.kind)))
    building.orientation = (direction + 2) % 8 if entry.kind in ["reflector", "pusher"] else direction
  if entry.kind == "magnet":
    building.polarity = -1 if str(entry.get("polarity", "positive")) in CATALOG.NEGATIVE_POLARITIES else 1
  match entry.kind:
    "gate": building.starts_open = entry.get("open", "false") == "true"
    "filter": building.filter_colour = CATALOG.FILTER_COLOURS.find(entry.get("colour", "red"))
  if entry.kind != "edge_wall": building.z_index = 1
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
    names.assign(entry.get("particles", ["photon"] if entry.kind == "detector" else []))
    preview.show_particles(names)
  buildings.append(building)

func _cell_position(cell: Vector2i) -> Vector2:
  return Vector2(cell.x, level.height - 1 - cell.y) * CELL

func _mouse_cell() -> Vector2i:
  return _world_to_cell(get_global_mouse_position())

func screen_to_cell(screen_position: Vector2) -> Vector2i:
  return _world_to_cell(_screen_to_world(screen_position))

func _screen_to_world(screen_position: Vector2) -> Vector2:
  return get_canvas_transform().affine_inverse() * screen_position

func is_board_pointer(screen_position: Vector2) -> bool:
  if level.is_empty() or not _board_view().has_point(screen_position): return false
  var controls: Control = editor_tool_panel if editor_preview else game_sidebar
  return not is_instance_valid(controls) or not controls.is_visible_in_tree() or not controls.get_global_rect().has_point(screen_position)

func _world_to_cell(world_position: Vector2) -> Vector2i:
  var point := world_position / CELL
  return Vector2i(roundi(point.x), int(level.get("height", 0)) - 1 - roundi(point.y))

func is_cell_on_board(cell: Vector2i) -> bool:
  return cell.x >= 0 and cell.y >= 0 and cell.x < level.get("width", 0) and cell.y < level.get("height", 0)

func _area_rect(area: Rect2i) -> Rect2:
  var top_left := _cell_position(Vector2i(area.position.x, area.end.y - 1)) - Vector2.ONE * CELL * 0.5
  return Rect2(top_left, Vector2(area.size) * CELL)

func _area_selection(cell: Vector2i) -> Rect2i:
  if area_origin.x < 0: return Rect2i()
  var last := cell.clamp(Vector2i.ZERO, Vector2i(level.width - 1, level.height - 1))
  var first := area_origin.min(last)
  return Rect2i(first, area_origin.max(last) - first + Vector2i.ONE)

func _is_build_blocked(cell: Vector2i) -> bool:
  for area in level.get("no_build_areas", []):
    if area.has_point(cell): return true
  return false

func _edge_neighbor(cell: Vector2i, facing: String) -> Vector2i:
  var offset: Vector2 = SimulationGrid.VECTORS[CATALOG.DIRECTIONS.find(facing)]
  return cell + Vector2i(offset.x, -offset.y)

func _can_place_building(cell: Vector2i, kind: String, facing: String) -> bool:
  if not is_cell_on_board(cell): return false
  if not editor_preview:
    if _is_build_blocked(cell): return false
    # An edge can be placed from either adjoining cell.
    if kind == "edge_wall" and _is_build_blocked(_edge_neighbor(cell, facing)): return false
  return _building_at(cell, kind, facing) == null

func _building_at(cell: Vector2i, kind := "", facing := "E") -> Node:
  var key := CATALOG.occupancy_key(kind, cell, facing)
  for building in buildings:
    if not is_instance_valid(building): continue
    if _building_key(building, building.get_meta("cell")) == key:
      return building
  return null

func _building_key(building: Node, cell: Vector2i) -> Vector3i:
  var kind: String = building.get_meta("kind")
  var facing := str(CATALOG.DIRECTIONS[building.orientation]) if kind == "edge_wall" else "E"
  return CATALOG.occupancy_key(kind, cell, facing)

func _edge_facing(cell: Vector2i, world: Vector2) -> String:
  var offset := to_local(world) - _cell_position(cell)
  if absf(offset.x) >= absf(offset.y):
    return "E" if offset.x >= 0.0 else "W"
  return "S" if offset.y >= 0.0 else "N"

func _board_target(cell: Vector2i, world: Vector2) -> Node:
  var offset := (to_local(world) - _cell_position(cell)).abs()
  if maxf(offset.x, offset.y) >= CELL * 0.34:
    var edge := _building_at(cell, "edge_wall", _edge_facing(cell, world))
    if edge != null: return edge
  return _building_at(cell)

func _input(event: InputEvent) -> void:
  if not is_visible_in_tree(): return
  if event is InputEventScreenDrag and touches.has(event.index):
    _drag_touch(event)
  elif event is InputEventScreenTouch and not event.pressed and touches.has(event.index):
    _release_touch(event)
  elif event is InputEventMouse and event.device != InputEvent.DEVICE_ID_EMULATION:
    if event is InputEventMouseMotion:
      board_uses_touch = false
      if pan_button == MOUSE_BUTTON_NONE: return
      var delta: Vector2 = event.relative
      if not mouse_panning:
        delta = event.position - pan_start
        if delta.length() <= POINTER_SLOP: return
        mouse_panning = true
      _pan_board(delta)
    elif event is InputEventMouseButton and not event.pressed:
      if pan_button != MOUSE_BUTTON_NONE and event.button_index == pan_button:
        var clicked := not mouse_panning and pan_button == MOUSE_BUTTON_RIGHT
        pan_button = MOUSE_BUTTON_NONE
        mouse_panning = false
        if clicked and is_board_pointer(event.position):
          _press_board(event.position, MOUSE_BUTTON_RIGHT)
      elif event.button_index == MOUSE_BUTTON_LEFT and area_origin.x >= 0 and touches.is_empty():
        _finish_area_selection(event.position)
      elif event.button_index == MOUSE_BUTTON_LEFT and drag_cell.x >= 0:
        var from := drag_cell
        drag_cell = Vector2i(-1, -1)
        if not simulating and not area_selection_enabled and is_board_pointer(event.position) and event.position.distance_to(drag_start) > POINTER_SLOP:
          var cell := screen_to_cell(event.position)
          if editor_preview: editor_cell_dragged.emit(from, cell)
          elif is_cell_on_board(cell): _move_selected_to(cell)
          else: _remove_selected()
      else: return
    else: return
  else: return
  get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
  if what == NOTIFICATION_APPLICATION_FOCUS_OUT or (what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree()):
    cancel_board_gesture()

func cancel_board_gesture() -> void:
  area_origin = Vector2i(-1, -1)
  drag_cell = Vector2i(-1, -1)
  pan_button = MOUSE_BUTTON_NONE
  mouse_panning = false
  touches.clear()

func _unhandled_input(event: InputEvent) -> void:
  if not is_visible_in_tree(): return
  if event is InputEventKey:
    if event.pressed and not event.echo: _handle_game_shortcut(event)
  else:
    _handle_board_input(event)

func _handle_game_shortcut(event: InputEventKey) -> void:
  if not editor_preview and UI.is_primary_shortcut(event):
    if event.keycode == KEY_Z:
      if event.shift_pressed: redo_build()
      else: undo_build()
    elif event.keycode == KEY_Y and not event.shift_pressed: redo_build()
    else: return
  elif event.get_modifiers_mask() != 0: return
  elif event.keycode == KEY_SPACE: $SimulationControls._toggle_running()
  elif event.keycode == KEY_PERIOD: $SimulationControls._step_once()
  elif event.keycode == KEY_HOME: fit_board()
  elif not editor_preview:
    match event.keycode:
      KEY_B: stop_to_build()
      KEY_X: reset_level()
      KEY_Q: _rotate_selected(-1)
      KEY_E, KEY_R: _rotate_selected(1)
      KEY_DELETE, KEY_BACKSPACE: _remove_selected()
      KEY_ESCAPE:
        if simulating:
          stop_to_build()
        else:
          selected_building = null
          selected_kind = ""
          _refresh_ui()
          queue_redraw()
      _: return
  else: return
  get_viewport().set_input_as_handled()

func _handle_board_input(event: InputEvent) -> void:
  if event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION and event.pressed and is_board_pointer(event.position):
    board_uses_touch = false
    if pan_button != MOUSE_BUTTON_NONE or not touches.is_empty(): return
    match event.button_index:
      MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
        var direction := 1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
        _zoom_board(pow(ZOOM_STEP, direction * (event.factor if event.factor > 0.0 else 1.0)), event.position, event.position)
      MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT:
        pan_button = event.button_index
        pan_start = event.position
        drag_cell = Vector2i(-1, -1)
        area_origin = Vector2i(-1, -1)
      MOUSE_BUTTON_LEFT:
        if area_selection_enabled and not simulating:
          _start_area_selection(event.position)
        else:
          _press_board(event.position, MOUSE_BUTTON_LEFT, true)
      _: return
  elif event is InputEventScreenTouch and event.pressed and is_board_pointer(event.position):
    if pan_button != MOUSE_BUTTON_NONE: return
    board_uses_touch = true
    if touches.is_empty():
      touch_start = event.position
      touch_gesture = false
      if area_selection_enabled and not simulating: _start_area_selection(event.position)
    else:
      area_origin = Vector2i(-1, -1)
      touch_gesture = true
    touches[event.index] = event.position
  elif event is InputEventMagnifyGesture and touches.is_empty() and is_board_pointer(event.position):
    if event.factor <= 0.0: return
    _zoom_board(event.factor, event.position, event.position)
  else: return
  get_viewport().set_input_as_handled()

func _start_area_selection(at: Vector2) -> void:
  var origin := screen_to_cell(at)
  if is_cell_on_board(origin): area_origin = origin

func _finish_area_selection(at: Vector2) -> void:
  var area := _area_selection(screen_to_cell(at))
  area_origin = Vector2i(-1, -1)
  if area_selection_enabled and not simulating: editor_area_selected.emit(area)

func area_pointer_cell() -> Vector2i:
  return _mouse_cell() if touches.is_empty() else screen_to_cell(touches.values()[0])

func _drag_touch(event: InputEventScreenDrag) -> void:
  var previous: Vector2 = touches[event.index]
  if touches.size() >= 2:
    var indices := touches.keys()
    if event.index == indices[0] or event.index == indices[1]:
      var other: Vector2 = touches[indices[1] if event.index == indices[0] else indices[0]]
      var factor := maxf(1.0, event.position.distance_to(other)) / maxf(1.0, previous.distance_to(other))
      _zoom_board(factor, (previous + other) * 0.5, (event.position + other) * 0.5)
  elif area_origin.x < 0:
    if touch_gesture:
      _pan_board(event.position - previous)
    elif event.position.distance_to(touch_start) > POINTER_SLOP:
      touch_gesture = true
      _pan_board(event.position - touch_start)
  touches[event.index] = event.position

func _release_touch(event: InputEventScreenTouch) -> void:
  touches.erase(event.index)
  if not touches.is_empty(): return
  if event.canceled:
    area_origin = Vector2i(-1, -1)
  elif not touch_gesture:
    if area_origin.x >= 0:
      _finish_area_selection(event.position)
    elif not area_selection_enabled and event.position.distance_to(touch_start) <= POINTER_SLOP and is_board_pointer(event.position):
      _press_board(event.position, MOUSE_BUTTON_LEFT)

func _press_board(at: Vector2, button: int, allow_drag := false) -> void:
  if simulating or area_selection_enabled: return
  var world := _screen_to_world(at)
  var cell := _world_to_cell(world)
  if not is_cell_on_board(cell): return
  var target := _board_target(cell, world)
  var facing := _edge_facing(cell, world)
  if allow_drag:
    drag_cell = target.get_meta("cell") if target != null else Vector2i(-1, -1)
    drag_start = at
  if editor_preview:
    editor_cell_clicked.emit(cell, button, target, facing)
  else:
    _click_cell(cell, button, target, facing)

func _move_selected_to(cell: Vector2i) -> void:
  if not is_instance_valid(selected_building) or selected_building.get_meta("fixed_position"): return
  if selected_building.get_meta("cell") == cell: return
  var kind: String = selected_building.get_meta("kind")
  var facing: String = CATALOG.DIRECTIONS[selected_building.orientation] if kind == "edge_wall" else "E"
  if not _can_place_building(cell, kind, facing): return
  _record_undo()
  selected_building.position = _cell_position(cell)
  selected_building.set_meta("cell", cell)
  _refresh_ui()
  queue_redraw()

func _click_cell(cell: Vector2i, button_index: int, target: Node = null, facing := "E") -> void:
  if simulating or not is_cell_on_board(cell): return
  if target == null: target = _building_at(cell)
  if button_index == MOUSE_BUTTON_RIGHT:
    selected_building = target
    selected_kind = ""
  elif button_index == MOUSE_BUTTON_LEFT:
    var placement_facing := facing if selected_kind == "edge_wall" else CATALOG.default_facing(selected_kind)
    if not selected_kind.is_empty() and _place_inventory_building(selected_kind, cell, placement_facing):
      if inventory[selected_kind] == 0: selected_kind = ""
    elif target != null:
      selected_building = target
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
  var kind: String = selected_building.get_meta("kind")
  if kind not in CATALOG.ROTATABLE_KINDS: return
  if kind == "edge_wall":
    var orientation := CATALOG.next_orientation(selected_building.orientation, turn, 4)
    var cell: Vector2i = selected_building.get_meta("cell")
    var facing: String = CATALOG.DIRECTIONS[orientation]
    if not editor_preview and _is_build_blocked(_edge_neighbor(cell, facing)): return
    var occupied := _building_at(cell, kind, facing)
    if occupied != null and occupied != selected_building: return
  _record_undo()
  match kind:
    "magnet": selected_building.polarity *= -1
    "filter": selected_building.filter_colour = posmod(selected_building.filter_colour + turn, CATALOG.FILTER_COLOURS.size())
    _:
      var entry: Dictionary = selected_building.get_meta("entry")
      var steps := 4 if kind == "edge_wall" else int(entry.get("rotation", level.get("rotation_steps", 8)))
      selected_building.orientation = CATALOG.next_orientation(selected_building.orientation, turn, steps)
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
    cost -= CATALOG.COSTS[kind]
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
  if compact_layout and not kind.is_empty() and sidebar_open: _toggle_sidebar()
  _refresh_ui()
  queue_redraw()

func _refresh_ui() -> void:
  if not is_instance_valid(palette): return
  _refresh_output()
  var has_selection := is_instance_valid(selected_building)
  var kind: String = selected_building.get_meta("kind") if has_selection else ""
  var action := {"magnet": "Flip polarity", "filter": "Change colour"}.get(kind, "") as String
  var can_rotate: bool = has_selection and kind in CATALOG.ROTATABLE_KINDS and not selected_building.get_meta("fixed_rotation")
  rotate_left_button.visible = action.is_empty() or kind == "filter"
  rotate_left_button.disabled = simulating or not can_rotate
  rotate_button.text = action + "  E" if not action.is_empty() else "↷  E"
  rotate_button.tooltip_text = action if not action.is_empty() else "Rotate clockwise"
  rotate_button.disabled = simulating or not can_rotate
  remove_button.disabled = simulating or not has_selection or selected_building.get_meta("fixed_position")
  selection_label.visible = has_selection
  if has_selection:
    var cell: Vector2i = selected_building.get_meta("cell")
    selection_label.text = "%s (%d, %d)" % [kind.capitalize(), cell.x, cell.y]
    if kind == "magnet":
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
    var measured_steps := mini(sampled_step, row.window)
    var rate := _recent_rate(row.key, measured_steps)
    row.label.text = "%s/step" % OUTPUT_METER.format_rate(rate)
    row.label.tooltip_text = row.title
    if measured_steps > 0 and measured_steps < row.window:
      row.label.tooltip_text += " · measuring (%d of %d steps)" % [measured_steps, row.window]
    elif measured_steps > 0:
      row.label.tooltip_text += " · last %d steps" % measured_steps
    row.meter.set_rate(rate, simulating and measured_steps > 0, measured_steps)

func _meter_window(thresholds: Array) -> int:
  var slowest := INF
  for threshold in thresholds:
    if threshold > 0.0: slowest = minf(slowest, threshold)
  return ceili(clampf(METER_TARGET_COUNT / slowest, MIN_METER_STEPS, MAX_METER_STEPS))

func _sample_at_or_before(step: int) -> int:
  var lower := 0
  var upper := output_samples.size()
  while lower < upper:
    var middle := (lower + upper) >> 1
    if output_samples[middle].step <= step: lower = middle + 1
    else: upper = middle
  return lower - 1

func _recent_rate(key: String, measured_steps: int) -> float:
  if measured_steps <= 0: return 0.0
  var previous := _sample_at_or_before(sampled_step - measured_steps)
  var old_count := _goal_count(output_samples[previous].counts, key) if previous >= 0 else 0
  return float(_goal_count(sampled_counts, key) - old_count) / measured_steps

func _drop_inventory(kind: String, screen_position: Vector2) -> void:
  if not is_board_pointer(screen_position): return
  var cell := screen_to_cell(screen_position)
  if not is_cell_on_board(cell): return
  var facing := _edge_facing(cell, _screen_to_world(screen_position)) if kind == "edge_wall" else CATALOG.default_facing(kind)
  if not _place_inventory_building(kind, cell, facing): return
  selected_building = _building_at(cell, kind, facing)
  if compact_layout and sidebar_open: _toggle_sidebar()
  _refresh_ui()
  queue_redraw()

func _place_inventory_building(kind: String, cell: Vector2i, facing := "") -> bool:
  if facing.is_empty(): facing = CATALOG.default_facing(kind)
  if simulating or int(inventory.get(kind, 0)) <= 0 or not _can_place_building(cell, kind, facing): return false
  _record_undo()
  _place_building({"kind": kind, "x": cell.x, "y": cell.y, "facing": facing}, true)
  inventory[kind] -= 1
  cost += CATALOG.COSTS[kind]
  return true

func begin_run() -> void:
  if simulating: return
  simulating = true
  completed = false
  selected_building = null
  selected_kind = ""
  _clear_particles()
  _clear_stats()
  reset_step_clock()
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
  reset_step_clock()
  for building in buildings:
    building.position = _cell_position(building.get_meta("cell"))
    if building.get_meta("kind") == "emitter": building.stop_sequence()
    if building.has_method("reset_device"): building.reset_device()
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
  next_forecast_at = WATCH_STEPS
  last_hud_update = 0.0
  total_counts.clear()
  output_samples.clear()
  sampled_counts = {}
  sampled_step = 0
  output_changed = false
  elapsed = 0.0
  if is_instance_valid(diagnostic_overlay): diagnostic_overlay.clear_events()

func _on_particle_detected(name: String) -> void:
  for key in PARTICLES.detection_keys(name):
    total_counts[key] = int(total_counts.get(key, 0)) + 1
  output_changed = true

func _on_simulation_stepped(delta: float) -> void:
  if not simulating or completed: return
  elapsed += delta
  var whole_step := floori(elapsed + 0.000001)
  if whole_step > sampled_step:
    sampled_step = whole_step
    if output_changed:
      sampled_counts = total_counts.duplicate()
      output_samples.append({"step": sampled_step, "counts": sampled_counts})
      output_changed = false
      var cutoff := _sample_at_or_before(sampled_step - MAX_METER_STEPS)
      if cutoff >= 64: output_samples = output_samples.slice(cutoff)
  if elapsed - last_hud_update >= 0.6:
    last_hud_update = elapsed
    _refresh_output()
  if forecast != null or elapsed + 0.000001 < next_forecast_at: return
  next_forecast_at = elapsed + 1.0
  for goal in level.goals:
    for tier in range(3):
      var eligible := true
      var window_chunks := 1
      for key in goal:
        var threshold: float = goal[key][tier]
        if key == "cost":
          if cost > threshold: eligible = false
        elif is_inf(threshold) or (threshold > 0.0 and _goal_count(total_counts, key) == 0):
          eligible = false
        elif threshold > 0.0:
          var chunks_needed := FORECAST_TARGET_COUNT / (threshold * FORECAST_WINDOW_STEPS)
          window_chunks = maxi(window_chunks, ceili(minf(chunks_needed, MAX_FORECAST_CHUNKS_PER_WINDOW)))
      if eligible:
        forecast_candidates.append({"goal": goal, "tier": tier, "window_chunks": window_chunks, "previous_counts": {}})
  if not forecast_candidates.is_empty():
    forecast = FORECAST.new(self, buildings, FORECAST_WINDOW_STEPS)

func _process(_delta: float) -> void:
  if forecast == null or not forecast.advance(): return
  for key in forecast.counts:
    forecast_counts[key] = int(forecast_counts.get(key, 0)) + int(forecast.counts[key])
  forecast_chunks += 1
  for i in range(forecast_candidates.size() - 1, -1, -1):
    var candidate := forecast_candidates[i]
    var stars: int = candidate.tier + 1
    if stars <= forecast_best_stars:
      forecast_candidates.remove_at(i)
      continue
    var chunks: int = candidate.window_chunks
    if forecast_chunks % chunks != 0: continue
    var window_steps := FORECAST_WINDOW_STEPS * chunks
    if not _meets_output(candidate, forecast_counts, window_steps, candidate.previous_counts):
      forecast_candidates.remove_at(i)
    elif forecast_chunks == chunks * FORECAST_WINDOWS:
      if _meets_output(candidate, forecast_counts, window_steps * FORECAST_WINDOWS):
        forecast_best_stars = stars
      forecast_candidates.remove_at(i)
    else:
      candidate.previous_counts = forecast_counts.duplicate()
  if forecast_candidates.is_empty() or forecast_best_stars == 3:
    var stars := forecast_best_stars
    _cancel_forecast()
    next_forecast_at = elapsed + 8.0
    if stars > 0: _finish_run(stars)

func _cancel_forecast() -> void:
  if forecast != null:
    forecast.dispose()
    forecast = null
  forecast_candidates.clear()
  forecast_counts.clear()
  forecast_chunks = 0
  forecast_best_stars = 0

func _finish_run(stars: int) -> void:
  completed = true
  running = false
  cancel_pending_steps()
  if not editor_playtest: Global.record_best_stars(Global.selected_level, stars)
  _refresh_ui()
  var stats := ""
  for kind in total_counts:
    var run_rate := float(total_counts[kind]) / elapsed if elapsed > 0.0 else 0.0
    stats += "\n%s: %d total · %s/step live avg" % [PARTICLES.label(kind), int(total_counts[kind]), OUTPUT_METER.format_rate(run_rate)]
  if stats.is_empty(): stats = "\nNo particles detected"
  results_text.text = "%d star(s) earned\nBuild cost: $%d\n\nDetected%s" % [stars, cost, stats]
  results_text.scroll_to_line(0)
  var height := clampi(132 + stats.count("\n") * 25, 210, 520)
  results.popup_centered_clamped(Vector2i(480, height), 0.88)

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

func _meets_output(candidate: Dictionary, counts: Dictionary, steps: float, previous_counts := {}) -> bool:
  for key in candidate.goal:
    if key == "cost": continue
    var threshold: float = candidate.goal[key][candidate.tier]
    if is_inf(threshold): return false
    if threshold <= 0.0: continue
    var required := maxf(1.0, floorf(threshold * steps + 0.000001))
    if _goal_count(counts, key) - _goal_count(previous_counts, key) < required: return false
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
    match kind:
      "emitter":
        entry.facing = CATALOG.DIRECTIONS[building.orientation]
        entry.rate = building.rate
      "reflector", "pusher":
        entry.facing = CATALOG.DIRECTIONS[posmod(building.orientation - 2, CATALOG.DIRECTIONS.size())]
      "magnet":
        entry.polarity = "+" if building.polarity > 0 else "-"
      "edge_wall", "gate": entry.facing = CATALOG.DIRECTIONS[building.orientation]
      "filter": entry.colour = CATALOG.FILTER_COLOURS[building.filter_colour]
    entries.append({"entry": entry, "inventory_piece": building.get_meta("from_inventory")})
  return {"entries": entries, "inventory": inventory.duplicate(true), "cost": cost}

func _record_undo() -> void:
  if simulating: return
  undo_history.append(_snapshot_build())
  if undo_history.size() > 100: undo_history.pop_front()
  redo_history.clear()

func _restore_build(snapshot: Dictionary) -> void:
  _clear_buildings()
  inventory = snapshot.inventory.duplicate(true)
  cost = snapshot.cost
  selected_kind = ""
  selected_building = null
  for item in snapshot.entries:
    _place_building(item.entry, item.inventory_piece)
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
