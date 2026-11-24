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
const MEDALS = preload("res://MainScene/medal_display.gd")
const STAR_MARKER = preload("res://filled_star.png")
const CATALOG = preload("res://Buildings/building_catalog.gd")
const BUILDING = preload("res://Buildings/building.gd")
const CELL := BUILDING.GRID_SIZE
const STAR_RADIUS := CELL * 0.16
const SIDEBAR_WIDTH := 288.0
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

var editor_preview := false
var editor_playtest := false
var level_override: Dictionary = {}
var external_palette: PanelContainer
var diagnostic_overlay
var undo_history: Array[Dictionary] = []
var redo_history: Array[Dictionary] = []
var last_hud_update := 0.0
var editor_bottom_inset := 190.0
var editor_sidebar_width := 256.0
var hud_panel: PanelContainer
var level_heading: VBoxContainer
var results_text: RichTextLabel
var results_medals: HBoxContainer
var results_button: Button
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
var earned_medals: Array[String] = []
var medal_icons := {}
var star_hits := {}
var star_labels: Array[Label] = []
var star_hits_changed := false
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
  for cell in level.stars:
    var at := _cell_position(cell)
    var tint := Color.WHITE if not star_hits.has(cell) else Color(1, 1, 1, 0.3)
    draw_texture_rect(STAR_MARKER, Rect2(at - Vector2.ONE * STAR_RADIUS, Vector2.ONE * STAR_RADIUS * 2.0), false, tint)

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
  var toolbar: Control = $SimulationControls/Panel
  var top_inset := toolbar.get_rect().end.y + 12.0 if editor_preview else level_heading.get_rect().end.y + 12.0
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
  rotate_left_button = UI.button(actions, "↶  Q", _rotate_selected.bind(-1))
  rotate_left_button.tooltip_text = "Rotate counterclockwise"
  rotate_button = UI.button(actions, "↷  E", _rotate_selected)
  rotate_button.tooltip_text = "Rotate clockwise"
  remove_button = UI.button(actions, "Remove  " + UI.delete_key_label(), _remove_selected)
  stop_button = $SimulationControls.enable_build(stop_to_build)
  restart_button = UI.button(actions, "Restart", restart_run)
  UI.button(actions, "Reset  X", reset_level)
  UI.button(actions, "Back to editor" if editor_playtest else "Levels", _return_to_select)
  results_button = UI.button(actions, "Level cleared", _show_results)
  results_button.theme_type_variation = "PrimaryButton"
  results_button.tooltip_text = "View results and continue to the next level"
  results_button.hide()
  results = AcceptDialog.new()
  UI.setup_dialog(results, layer, "Level complete")
  results.ok_button_text = "Back to build"
  results.confirmed.connect(stop_to_build)
  results.custom_action.connect(_result_action)
  results.add_button("Keep running", true, "continue")
  var next_level_button := results.add_button("Next level", true, "next")
  next_level_button.visible = not editor_playtest and not Global.next_level_path(Global.selected_level).is_empty()
  var summary := VBoxContainer.new()
  results.add_child(summary)
  results_medals = MEDALS.strip([], 38)
  summary.add_child(results_medals)
  results_text = RichTextLabel.new()
  results_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
  summary.add_child(results_text)

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
  _add_medals(rows)
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

func _add_medals(rows: VBoxContainer) -> void:
  var objective := UI.label("Detect any particle to clear the level.")
  objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
  rows.add_child(objective)
  _add_medal_heading(rows, "rate")
  _add_output_meter(rows, "any", "Total output", level.medals.rate, "rate")
  _add_medal_heading(rows, "cost")
  rows.add_child(UI.label("Build for under $%s" % str(level.medals.cost).trim_suffix(".0")))
  _add_medal_heading(rows, "star")
  for index in range(level.medals.star.size()):
    if index > 0: rows.add_child(UI.label("Or"))
    var rule: Dictionary = level.medals.star[index]
    for key in rule.rates:
      var target: String = rule.targets.get(key, key)
      var title := "Total output" if key == "any" else (PARTICLES.label(target) if PARTICLES.is_selector(target) else target)
      _add_output_meter(rows, key, title, rule.rates[key], "star")
    if rule.has("cost"):
      rows.add_child(UI.label("Build for under $%s" % str(rule.cost).trim_suffix(".0")))
    if not rule.no_buildings.is_empty():
      var names := PackedStringArray()
      for kind in rule.no_buildings: names.append(kind.capitalize())
      var omitted := UI.label("Use no %s" % ", ".join(names))
      omitted.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
      rows.add_child(omitted)
    if rule.hit_stars:
      var progress := UI.label("")
      rows.add_child(progress)
      star_labels.append(progress)
  var hint := str(level.get("hint", ""))
  if not hint.is_empty():
    var prompt := UI.label(hint)
    UI.muted(prompt)
    prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    rows.add_child(prompt)

func _add_medal_heading(rows: VBoxContainer, kind: String) -> void:
  var header := HBoxContainer.new()
  rows.add_child(header)
  var badge := MEDALS.icon(kind, 24, false)
  header.add_child(badge)
  medal_icons[kind] = badge
  var label := UI.label("%s medal" % kind.capitalize())
  UI.heading(label, 16)
  header.add_child(label)

func _add_output_meter(rows: VBoxContainer, key: String, title: String, target: float, medal: String) -> void:
  var caption := UI.label("%s ≥ %s/step" % [title, OUTPUT_METER.format_rate(target)])
  caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
  rows.add_child(caption)
  var row := HBoxContainer.new()
  rows.add_child(row)
  var label := UI.label("0/step")
  label.custom_minimum_size.x = 76
  label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
  label.mouse_filter = Control.MOUSE_FILTER_STOP
  row.add_child(label)
  var meter := OUTPUT_METER.new()
  meter.target = target
  meter.medal = medal
  meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  row.add_child(meter)
  var window := ceili(clampf(METER_TARGET_COUNT / target, MIN_METER_STEPS, MAX_METER_STEPS))
  output_rows.append({"key": key, "title": title, "meter": meter, "label": label, "window": window})

func _load_initial_board() -> void:
  running = false
  cancel_pending_steps()
  simulating = false
  completed = false
  _clear_particles()
  _clear_buildings()
  inventory = level.inventory.duplicate(true)
  track_particle_paths = not level.stars.is_empty()
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
  return _world_to_cell(get_canvas_transform().affine_inverse() * screen_position)

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
  if not area_selection_enabled or area_origin.x < 0 or not is_visible_in_tree(): return
  if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
    var area := _area_selection(screen_to_cell(event.position))
    area_origin = Vector2i(-1, -1)
    if not simulating: editor_area_selected.emit(area)
    get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
  if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
    area_origin = Vector2i(-1, -1)

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
  if simulating or not event is InputEventMouseButton:
    return
  if area_selection_enabled:
    if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
      var origin := screen_to_cell(event.position)
      if is_cell_on_board(origin): area_origin = origin
    return
  var cell := _mouse_cell()
  if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
    if drag_cell.x >= 0 and event.position.distance_to(drag_start) > 8.0:
      if editor_preview:
        editor_cell_dragged.emit(drag_cell, cell)
      else:
        if is_cell_on_board(cell): _move_selected_to(cell)
        else: _remove_selected()
    drag_cell = Vector2i(-1, -1)
    return
  if not event.pressed or not is_cell_on_board(cell):
    return
  var world := get_global_mouse_position()
  var target := _board_target(cell, world)
  var facing := _edge_facing(cell, world)
  if event.button_index == MOUSE_BUTTON_LEFT:
    drag_cell = Vector2i(-1, -1)
    if target != null:
      drag_cell = target.get_meta("cell")
      drag_start = event.position
  if editor_preview:
    editor_cell_clicked.emit(cell, event.button_index, target, facing)
  else:
    _click_cell(cell, event.button_index, target, facing)

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
  results_button.visible = completed
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
  var cell := screen_to_cell(screen_position)
  if not is_cell_on_board(cell): return
  var facing := _edge_facing(cell, get_canvas_transform().affine_inverse() * screen_position) if kind == "edge_wall" else CATALOG.default_facing(kind)
  if not _place_inventory_building(kind, cell, facing): return
  selected_building = _building_at(cell, kind, facing)
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
  if action == &"continue":
    results.hide()
    running = true
    return
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
  earned_medals.clear()
  star_hits.clear()
  star_hits_changed = false
  _refresh_medals()
  _refresh_star_labels()
  queue_redraw()
  if is_instance_valid(diagnostic_overlay): diagnostic_overlay.clear_events()

func _on_particle_detected(name: String) -> void:
  PARTICLES.record_detection(total_counts, name)
  output_changed = true

func _on_simulation_stepped(delta: float) -> void:
  if not simulating: return
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
  var first_detection := not completed and not total_counts.is_empty()
  if first_detection or star_hits_changed:
    star_hits_changed = false
    if first_detection or completed: _update_clear(first_detection)
  if not completed: return
  if forecast != null or elapsed + 0.000001 < next_forecast_at: return
  next_forecast_at = elapsed + 1.0
  if "rate" not in earned_medals:
    _add_forecast_candidate("rate", {"any": level.medals.rate})
  if "star" not in earned_medals:
    for rule in level.medals.star:
      if not rule.rates.is_empty() and _meets_build_conditions(rule):
        _add_forecast_candidate("star", rule.rates)
  if not forecast_candidates.is_empty():
    forecast = FORECAST.new(self, buildings, FORECAST_WINDOW_STEPS)

func _update_clear(first_detection: bool) -> void:
  completed = true
  var previous_count := earned_medals.size()
  if first_detection and cost < level.medals.cost: earned_medals.append("cost")
  if "star" not in earned_medals:
    for rule in level.medals.star:
      if rule.rates.is_empty() and _meets_build_conditions(rule):
        earned_medals.append("star")
        break
  if first_detection or previous_count != earned_medals.size(): _save_run_progress()

func _meets_build_conditions(rule: Dictionary) -> bool:
  if cost >= rule.get("cost", INF): return false
  if rule.hit_stars and (level.stars.is_empty() or star_hits.size() < level.stars.size()): return false
  if not rule.no_buildings.is_empty():
    for building in buildings:
      if building.get_meta("kind") in rule.no_buildings: return false
  return true

func _add_forecast_candidate(medal: String, rates: Dictionary) -> void:
  var window_chunks := 1
  for key in rates:
    if _goal_count(total_counts, key) == 0: return
    var chunks_needed := FORECAST_TARGET_COUNT / (float(rates[key]) * FORECAST_WINDOW_STEPS)
    window_chunks = maxi(window_chunks, ceili(minf(chunks_needed, MAX_FORECAST_CHUNKS_PER_WINDOW)))
  forecast_candidates.append({"medal": medal, "rates": rates, "window_chunks": window_chunks, "previous_counts": {}})

func _process(_delta: float) -> void:
  if forecast == null or not forecast.advance(): return
  for key in forecast.counts:
    forecast_counts[key] = int(forecast_counts.get(key, 0)) + int(forecast.counts[key])
  forecast_chunks += 1
  var previous_count := earned_medals.size()
  for i in range(forecast_candidates.size() - 1, -1, -1):
    var candidate := forecast_candidates[i]
    if candidate.medal in earned_medals:
      forecast_candidates.remove_at(i)
      continue
    var chunks: int = candidate.window_chunks
    if forecast_chunks % chunks != 0: continue
    var window_steps := FORECAST_WINDOW_STEPS * chunks
    if not _meets_output(candidate.rates, forecast_counts, window_steps, candidate.previous_counts):
      forecast_candidates.remove_at(i)
    elif forecast_chunks == chunks * FORECAST_WINDOWS:
      if _meets_output(candidate.rates, forecast_counts, window_steps * FORECAST_WINDOWS):
        earned_medals.append(candidate.medal)
      forecast_candidates.remove_at(i)
    else:
      candidate.previous_counts = forecast_counts.duplicate()
  if previous_count != earned_medals.size(): _save_run_progress()
  if forecast_candidates.is_empty():
    _cancel_forecast()
    next_forecast_at = elapsed + 8.0

func _cancel_forecast() -> void:
  if forecast != null:
    forecast.dispose()
  forecast = null
  forecast_candidates.clear()
  forecast_counts.clear()
  forecast_chunks = 0

func _save_run_progress() -> void:
  if not editor_playtest: Global.record_level_progress(Global.selected_level, earned_medals)
  results_button.show()
  _refresh_medals()
  if results.visible: _update_results()

func _refresh_medals() -> void:
  for kind in medal_icons:
    MEDALS.set_earned(medal_icons[kind], kind, kind in earned_medals)

func _refresh_star_labels() -> void:
  for label in star_labels:
    label.text = "Hit every star (%d/%d)" % [star_hits.size(), level.stars.size()]

func _show_results() -> void:
  running = false
  cancel_pending_steps()
  _update_results()
  results_text.scroll_to_line(0)
  var height := clampi(190 + total_counts.size() * 25, 235, 520)
  results.popup_centered_clamped(Vector2i(480, height), 0.88)

func _update_results() -> void:
  var index := 0
  for kind in MEDALS.ICONS:
    MEDALS.set_earned(results_medals.get_child(index), kind, kind in earned_medals)
    index += 1
  var stats := ""
  for kind in total_counts:
    if kind == "any" or kind in PARTICLES.QUARK_FAMILIES: continue
    var run_rate := float(total_counts[kind]) / elapsed if elapsed > 0.0 else 0.0
    stats += "\n%s · %d detected · %s/step average" % [PARTICLES.label(kind), int(total_counts[kind]), OUTPUT_METER.format_rate(run_rate)]
  results_text.text = "%d of 3 medals earned\nBuild cost $%d\n%s" % [earned_medals.size(), cost, stats]

func _report_particle_path(particle: Particle, path: Array[Dictionary], until: float) -> void:
  if star_hits.size() == level.stars.size(): return
  var radius := STAR_RADIUS + particle.world_collision_radius()
  for leg in path:
    if leg.start > until: break
    _check_star_segment(to_local(leg.from), to_local(_position_on_leg(leg, until)), radius)
    if leg.has("push") and leg.end <= until:
      _check_star_segment(to_local(leg.push.from), to_local(leg.push.to), radius)

func _check_star_segment(from: Vector2, to: Vector2, radius: float) -> void:
  var previous := star_hits.size()
  for cell in level.stars:
    if star_hits.has(cell): continue
    var at := _cell_position(cell)
    var nearest := Geometry2D.get_closest_point_to_segment(at, from, to) if from != to else from
    if at.distance_squared_to(nearest) <= radius * radius: star_hits[cell] = true
  if previous != star_hits.size():
    star_hits_changed = true
    _refresh_star_labels()
    queue_redraw()

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

func _meets_output(rates: Dictionary, counts: Dictionary, steps: float, previous_counts := {}) -> bool:
  for key in rates:
    var threshold: float = rates[key]
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
