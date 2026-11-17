extends "res://Particles/particle_simulation.gd"

const PARSER = preload("res://Levels/level_parser.gd")
const ENTRY = preload("res://Buildings/Emitter/particle_emission.gd")
const TILE = preload("res://tile.png")
const FORECAST = preload("res://MainScene/simulation_forecast.gd")
const PREVIEW = preload("res://Buildings/particle_preview.gd")
const OVERLAY = preload("res://MainScene/placement_overlay.gd")
const CELL: float = 102.4
const SCENES := {
  "emitter": preload("res://Buildings/Emitter/emitter.tscn"),
  "mirror": preload("res://Buildings/Mirror/mirror.tscn"),
  "wall": preload("res://Buildings/Wall/wall.tscn"),
  "detector": preload("res://Buildings/Detector/detector.tscn"),
  "magnet": preload("res://Buildings/MagneticField/magnetic_field.tscn"),
}
# Costs are shared by all levels, as described by the level format.
const COSTS := {"mirror": 10, "wall": 5, "emitter": 40, "detector": 30, "magnet": 20}
const DIRECTIONS := ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
const WINDOW_SECONDS: float = 5.0
const OBSERVED_WINDOWS: int = 2
const FORECAST_WINDOWS: int = 3

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
var completed: bool = false
var status_label: Label
var goals_label: Label
var inventory_box: HBoxContainer
var instructions: Label
var results: AcceptDialog
var stop_button: Button

func _ready() -> void:
  running = false
  if Global.selected_level.is_empty():
    get_tree().call_deferred("change_scene_to_file", "res://MainScene/level_select.tscn")
    return
  level = PARSER.parse(FileAccess.get_file_as_string(Global.selected_level))
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
  var available := Vector2(maxf(100.0, view.x - 40.0), maxf(100.0, view.y - 250.0))
  var board := Vector2(level.width, level.height) * CELL
  var zoom_amount := minf(1.0, minf(available.x / board.x, available.y / board.y))
  camera.zoom = Vector2.ONE * zoom_amount
  camera.offset = Vector2(0, 52.0 / zoom_amount)

func _create_hud() -> void:
  var layer := CanvasLayer.new()
  layer.layer = 2
  add_child(layer)
  var panel := PanelContainer.new()
  panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
  panel.offset_left = 16
  panel.offset_right = -16
  panel.offset_top = -174
  panel.offset_bottom = -16
  layer.add_child(panel)
  var margin := MarginContainer.new()
  for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
    margin.add_theme_constant_override(side, 8)
  panel.add_child(margin)
  var column := VBoxContainer.new()
  margin.add_child(column)
  status_label = Label.new()
  column.add_child(status_label)
  goals_label = Label.new()
  goals_label.add_theme_font_size_override("font_size", 12)
  goals_label.text = _goal_description()
  column.add_child(goals_label)
  inventory_box = HBoxContainer.new()
  inventory_box.add_theme_constant_override("separation", 6)
  column.add_child(inventory_box)
  var actions := HBoxContainer.new()
  actions.add_theme_constant_override("separation", 6)
  column.add_child(actions)
  _button(actions, "Rotate / polarity [R]", _rotate_selected)
  _button(actions, "Remove [Del]", _remove_selected)
  stop_button = _button(actions, "Back to build [B]", stop_to_build)
  _button(actions, "Reset level [X]", reset_level)
  _button(actions, "Level select", _return_to_select)
  instructions = Label.new()
  instructions.text = "Green: movable   |   Gold: rotate / polarity only   |   Red: fixed    •    Select a building to move/rotate; right-click to remove."
  instructions.add_theme_font_size_override("font_size", 12)
  column.add_child(instructions)
  results = AcceptDialog.new()
  results.title = "Level complete"
  results.ok_button_text = "Back to build"
  results.confirmed.connect(stop_to_build)
  results.canceled.connect(stop_to_build)
  layer.add_child(results)

func _goal_description() -> String:
  var alternatives: PackedStringArray = []
  for goal in level.goals:
    var requirements: PackedStringArray = []
    for key in goal:
      var values: Array = goal[key]
      var suffix := "" if key == "cost" else "/s"
      requirements.append("%s: %s / %s / %s%s" % [str(key).capitalize(), str(values[0]), str(values[1]), str(values[2]), suffix])
    alternatives.append("; ".join(requirements))
  return "Goals (1 / 2 / 3 stars): " + "  OR  ".join(alternatives)
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
  building.set_meta("cell", cell)
  building.set_meta("kind", entry.kind)
  building.set_meta("fixed_position", "p" in str(entry.get("fixed", "")))
  building.set_meta("fixed_rotation", "r" in str(entry.get("fixed", "")))
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
      var item = ENTRY.new()
      if name == "photon": item.flavour = Global.Flavour.PHOTON
      elif name == "electron" or name == "positron":
        item.flavour = Global.Flavour.ELECTRON
        item.is_anti = name == "positron"
      elif name.begins_with("up"): item.flavour = Global.Flavour.UP
      elif name.begins_with("down"): item.flavour = Global.Flavour.DOWN
      if name.ends_with("_r"): item.colour = Particle.ColourCharge.RED
      elif name.ends_with("_g"): item.colour = Particle.ColourCharge.GREEN
      elif name.ends_with("_b"): item.colour = Particle.ColourCharge.BLUE
      sequence.append(item)
    building.sequence = sequence
  if entry.kind == "detector":
    var accepted: Array[String] = []
    accepted.assign(entry.get("particles", ["photon"]))
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
  if event is InputEventKey and event.pressed and not event.echo:
    match event.keycode:
      KEY_B: stop_to_build()
      KEY_X: reset_level()
      KEY_SPACE: $SimulationControls._toggle_running()
      KEY_PERIOD: $SimulationControls._step_once()
      KEY_R: _rotate_selected()
      KEY_DELETE, KEY_BACKSPACE: _remove_selected()
      KEY_ESCAPE:
        selected_building = null
        selected_kind = ""
        _refresh_ui()
        queue_redraw()
    return
  if simulating or not event is InputEventMouseButton or not event.pressed:
    return
  var cell := _mouse_cell()
  if cell.x < 0 or cell.y < 0 or cell.x >= level.width or cell.y >= level.height:
    return
  _click_cell(cell, event.button_index)

func _click_cell(cell: Vector2i, button_index: int) -> void:
  if simulating or cell.x < 0 or cell.y < 0 or cell.x >= level.width or cell.y >= level.height:
    return
  var target := _building_at(cell)
  if button_index == MOUSE_BUTTON_RIGHT:
    selected_building = target
    _remove_selected()
  elif button_index == MOUSE_BUTTON_LEFT:
    if target != null:
      selected_building = target
      selected_kind = ""
    elif not selected_kind.is_empty() and int(inventory.get(selected_kind, 0)) > 0:
      var entry := {"kind": selected_kind, "x": cell.x, "y": cell.y}
      _place_building(entry, true)
      inventory[selected_kind] -= 1
      cost += COSTS[selected_kind]
    elif is_instance_valid(selected_building) and not selected_building.get_meta("fixed_position"):
      selected_building.position = _cell_position(cell)
      selected_building.set_meta("cell", cell)
    _refresh_ui()
    queue_redraw()

func _rotate_selected() -> void:
  if simulating or not is_instance_valid(selected_building) or selected_building.get_meta("fixed_rotation"):
    return
  if selected_building.get_meta("kind") == "magnet":
    selected_building.polarity *= -1
    queue_redraw()
  elif selected_building.get_meta("kind") in ["emitter", "mirror"]:
    selected_building.orientation = (selected_building.orientation + 1) % 8
    queue_redraw()

func _remove_selected() -> void:
  if simulating or not is_instance_valid(selected_building) or selected_building.get_meta("fixed_position"):
    return
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
  var title := Global.selected_level.get_file().trim_suffix(".level")
  var mode := "SIMULATING" if simulating else "BUILD"
  var tracked := "photon"
  for goal in level.goals:
    for key in goal:
      if key != "cost":
        tracked = key
        break
    if tracked != "photon" or goal.has("photon"):
      break
  var recent_rate := float(windows.back().get(tracked, 0)) / WINDOW_SECONDS if not windows.is_empty() else 0.0
  status_label.text = "%s   |   %s   |   Cost: %d   |   %s: %d   |   Last 5s: %.2f / s" % [title, mode, cost, tracked.capitalize(), int(total_counts.get(tracked, 0)), recent_rate]
  stop_button.disabled = not simulating
  for child in inventory_box.get_children():
    inventory_box.remove_child(child)
    child.queue_free()
  for kind in inventory:
    var button := _button(inventory_box, "%s  %d  ($%d)%s" % [str(kind).capitalize(), inventory[kind], COSTS[kind], "  ✓" if selected_kind == kind else ""], _select_inventory.bind(kind))
    button.disabled = simulating or int(inventory[kind]) <= 0

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

func reset_level() -> void:
  results.hide()
  _load_initial_board()

func _return_to_select() -> void:
  get_tree().change_scene_to_file("res://MainScene/level_select.tscn")

func _clear_particles() -> void:
  for particle in _particles():
    remove_child(particle)
    particle.queue_free()

func _clear_stats() -> void:
  total_counts.clear()
  window_counts.clear()
  windows.clear()
  window_time = 0.0
  elapsed = 0.0

func _on_particle_detected(name: String) -> void:
  for key in [name, name.split("_")[0]] if "_" in name else [name]:
    total_counts[key] = int(total_counts.get(key, 0)) + 1
    window_counts[key] = int(window_counts.get(key, 0)) + 1

func _on_simulation_stepped(delta: float) -> void:
  if not simulating or completed: return
  elapsed += delta
  window_time += delta
  if window_time + 0.000001 < WINDOW_SECONDS: return
  windows.append(window_counts.duplicate())
  window_counts.clear()
  window_time -= WINDOW_SECONDS
  if windows.size() > OBSERVED_WINDOWS: windows.pop_front()
  _refresh_ui()
  if windows.size() < OBSERVED_WINDOWS or _stable_stars(windows) == 0: return
  # Check additional windows on an isolated copy: the live board, emitter
  # timers, particles and statistics are not advanced by this prediction.
  var samples: Array[Dictionary] = windows.duplicate(true)
  samples.append_array(FORECAST.predict(self, buildings, WINDOW_SECONDS, FORECAST_WINDOWS))
  var stars := _stable_stars(samples)
  if stars > 0:
    completed = true
    running = false
    cancel_pending_steps()
    var stats := ""
    var latest: Dictionary = windows.back()
    for kind in total_counts:
      stats += "\n%s: %d total, %.2f / s in the last 5s" % [str(kind).capitalize(), int(total_counts[kind]), float(latest.get(kind, 0)) / WINDOW_SECONDS]
    if stats.is_empty(): stats = "\nNo particles detected"
    results.dialog_text = "%d / 3 stars\n\nSimulation time: %.1f s\nBuild cost: %d\nDetected:%s\n\nTwo observed and three simulated-ahead five-second windows met the goal. Future production is an estimate." % [stars, elapsed, cost, stats]
    results.popup_centered()

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
          var rate := float(counts.get(key, 0)) / WINDOW_SECONDS
          low = minf(low, rate)
          high = maxf(high, rate)
        # Every five-second window must meet the goal. Small fluctuations are
        # allowed because whole-particle counts can straddle window boundaries.
        if low + 0.0001 < threshold or high - low > maxf(0.4, high * 0.2):
          satisfied = false
      if satisfied: best = maxi(best, star)
  return best