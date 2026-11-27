extends RefCounted

const PARTICLES = preload("res://Particles/particle_catalog.gd")
const BOSON = preload("res://Particles/Boson/boson.gd")
const FRAME_BUDGET_USEC := 3000
const TICKS_PER_SIMULATION_STEP := SimulationGrid.TICKS_PER_STEP * SimulationGrid.GRID_TICKS_PER_STEP
const CHECK_INTERVAL := 8 * TICKS_PER_SIMULATION_STEP
const MIN_FORECAST_TICKS := 96 * TICKS_PER_SIMULATION_STEP
const MAX_FORECAST_TICKS := 7200 * TICKS_PER_SIMULATION_STEP
const MAX_CYCLE_EVENTS := 128
const CYCLE_REPEATS := 3

var shadow: ParticleSimulation
var measured_counts: Dictionary = {}
var measured_grid_ticks := 0.0
var emitters: Array[ParticleEmitter] = []
var has_rails := false
var emission_periods: Array[float] = []
var event_ticks := PackedInt64Array()
var event_counts: Array[Dictionary] = []
var counts: Dictionary = {}
var midpoint_counts: Dictionary = {}
var elapsed_ticks := 0
var forecast_ticks := MIN_FORECAST_TICKS

## Copy the board and in-flight state so the prediction never advances the live run.
func _init(source: ParticleSimulation, buildings: Array[Node]) -> void:
  shadow = ParticleSimulation.new()
  shadow.running = false
  shadow.level_bounds_enabled = source.level_bounds_enabled
  shadow.level_bounds = source.level_bounds
  shadow._step_phase = source._step_phase
  shadow._ticks_into_step = source._ticks_into_step
  shadow.hide()
  source.get_tree().root.add_child(shadow)
  shadow.set_physics_process(false)
  var building_copies := {}
  for original in buildings:
    var copy = original.duplicate()
    var kind: String = original.get_meta("kind")
    if kind == "emitter":
      copy.start_on_ready = false
    shadow.add_child(copy)
    copy.global_position = original.global_position
    building_copies[original] = copy
    match kind:
      "emitter":
        emitters.append(copy)
        copy._continuous = original._continuous
        copy._pending = original._pending.duplicate()
        copy._sequence_template = original._sequence_template.duplicate()
        copy._time_until_next = original._time_until_next
        copy._gluon_cooldown = original._gluon_cooldown
        if copy._continuous or (copy.repeat_sequence and not copy._pending.is_empty()):
          var entries: int = 1 if copy._continuous else copy._sequence_template.size()
          var period: float = entries * SimulationGrid.TICKS_PER_STEP * copy.period
          emission_periods.append(period)
          forecast_ticks = ceili(clampf(period * 4.0, forecast_ticks, MAX_FORECAST_TICKS))
        elif not copy._pending.is_empty():
          forecast_ticks = ceili(clampf(copy._pending.size() * SimulationGrid.TICKS_PER_STEP * copy.period * 2.0,
            forecast_ticks, MAX_FORECAST_TICKS))
      "gate": copy.gate_open = original.gate_open
      "pusher": copy.push_up = original.push_up
      "rail": has_rails = true
  var particle_copies := {}
  for original in source._particles():
    var copy := PARTICLES.instantiate(original.flavour, original.isAnti, original.colour)
    copy.free_flight = original.free_flight
    copy.direction = original.direction
    copy.speed = original.speed
    copy.mass = original.mass
    copy.size = original.size
    copy.charge = original.charge
    copy.position = shadow.to_local(original.global_position)
    copy.progress = original.progress
    copy.magnetic_exit = original.magnetic_exit
    copy.glass_wait = original.glass_wait
    copy.constituents = original.constituents.duplicate()
    copy.source_building = building_copies.get(original.source_building)
    copy.emission_source = building_copies.get(original.emission_source)
    copy.held_by = building_copies.get(original.held_by)
    if is_instance_valid(copy.held_by):
      copy.held_by.set("held_particle", copy)
    for gate in original.passed_gates:
      if building_copies.has(gate):
        copy.passed_gates.append(building_copies[gate])
    shadow.add_child(copy)
    copy.flight_cell = original.flight_cell
    particle_copies[original] = copy
  for original in building_copies:
    if original is ParticleEmitter and is_instance_valid(original.last_gluon):
      building_copies[original].last_gluon = particle_copies.get(original.last_gluon)
  for original in particle_copies:
    if original.flavour == Particle.Flavour.GLUON:
      var gluon := original as BOSON
      var trail := particle_copies[original] as BOSON
      trail.trail_points = gluon.trail_points.duplicate()
      trail.tip_stopped = gluon.tip_stopped
      for captive in gluon.caught:
        if particle_copies.has(captive): trail.trap(particle_copies[captive])
      trail.pull_axis = gluon.pull_axis
    for partner in original.separating_from:
      if particle_copies.has(partner):
        particle_copies[original].separating_from.append(particle_copies[partner])
  shadow.particle_detected.connect(_on_detected)

func _on_detected(particle_name: String, detector_id := "") -> void:
  PARTICLES.record_detection(counts, particle_name, detector_id)
  if event_ticks.is_empty() or event_ticks[-1] != elapsed_ticks:
    event_ticks.append(elapsed_ticks)
    event_counts.append({})
  PARTICLES.record_detection(event_counts[-1], particle_name, detector_id)

## Measure a repeating output cycle or fall back to a time average.
func advance() -> bool:
  if emission_periods.is_empty(): return true
  var deadline := Time.get_ticks_usec() + FRAME_BUDGET_USEC
  var midpoint := forecast_ticks >> 1
  while elapsed_ticks < forecast_ticks:
    var boundary := mini(forecast_ticks, elapsed_ticks - elapsed_ticks % CHECK_INTERVAL + CHECK_INTERVAL)
    if elapsed_ticks < midpoint: boundary = mini(boundary, midpoint)
    var skipped := _skip_idle_steps(boundary - elapsed_ticks)
    elapsed_ticks += skipped
    if skipped == 0:
      elapsed_ticks += 1
      shadow.step_simulation(SimulationGrid.TICK)
      for child in shadow.get_children():
        if child is Particle and child.is_queued_for_deletion(): child.free()
    if elapsed_ticks == midpoint: midpoint_counts = counts.duplicate()
    if elapsed_ticks % CHECK_INTERVAL == 0:
      if _measure_cycle(): return true
      var keep := MAX_CYCLE_EVENTS * CYCLE_REPEATS + 1
      if event_ticks.size() > keep:
        event_ticks = event_ticks.slice(-keep)
        event_counts = event_counts.slice(-keep)
    if Time.get_ticks_usec() >= deadline and elapsed_ticks < forecast_ticks: return false
  measured_grid_ticks = float(forecast_ticks - midpoint) / SimulationGrid.TICKS_PER_STEP
  for key in counts:
    measured_counts[key] = counts[key] - midpoint_counts.get(key, 0)
  return true

func _measure_cycle() -> bool:
  var last := event_ticks.size() - 1
  @warning_ignore("integer_division")
  var max_events := mini(MAX_CYCLE_EVENTS, last / CYCLE_REPEATS)
  for events_per_cycle in range(1, max_events + 1):
    var previous := last - events_per_cycle
    var period := event_ticks[last] - event_ticks[previous]
    # A burst can look periodic until its first pause. Require the same emission
    # phases and make sure the next expected detection is not already overdue.
    if elapsed_ticks >= event_ticks[previous + 1] + period or not _emission_phases_repeat(period): continue
    var matches := true
    for index in range(last, last - (CYCLE_REPEATS - 1) * events_per_cycle - 1, -1):
      var earlier := index - events_per_cycle
      if event_ticks[index] - event_ticks[earlier] != period or event_counts[index] != event_counts[earlier]:
        matches = false
        break
    if not matches: continue
    measured_grid_ticks = float(period) / SimulationGrid.TICKS_PER_STEP
    for index in range(previous + 1, last + 1):
      for key in event_counts[index]:
        measured_counts[key] = measured_counts.get(key, 0) + event_counts[index][key]
    return true
  return false

func _emission_phases_repeat(period: int) -> bool:
  for emission_period in emission_periods:
    var repeats := roundf(period / emission_period)
    if repeats < 1.0 or absf(period - repeats * emission_period) > 0.0001: return false
  for emitter in emitters:
    if not emitter._continuous and not emitter.repeat_sequence and not emitter._pending.is_empty(): return false
  return true

func _skip_idle_steps(remaining_ticks: int) -> int:
  if has_rails or remaining_ticks < TICKS_PER_SIMULATION_STEP: return 0
  var idle_steps := float(remaining_ticks) / TICKS_PER_SIMULATION_STEP
  for emitter in emitters:
    if is_inf(emitter._gluon_cooldown): return 0
    if emitter._continuous or not emitter._pending.is_empty():
      idle_steps = minf(idle_steps, (emitter._time_until_next - ParticleSimulation.EPSILON) / SimulationGrid.GRID_TICKS_PER_STEP)
      if idle_steps < 1.0: return 0
  var whole_steps := floori(idle_steps)
  if not shadow._particles().is_empty(): return 0
  var grid_ticks := whole_steps * SimulationGrid.GRID_TICKS_PER_STEP
  for emitter in emitters:
    if emitter._continuous or not emitter._pending.is_empty(): emitter._time_until_next -= grid_ticks
    emitter._gluon_cooldown = maxf(0.0, emitter._gluon_cooldown - grid_ticks)
  return whole_steps * TICKS_PER_SIMULATION_STEP

func dispose() -> void:
  shadow.queue_free()
  shadow = null
