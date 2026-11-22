extends RefCounted

const PARTICLES = preload("res://Particles/particle_catalog.gd")
const BOSON = preload("res://Particles/Boson/boson.gd")
const FRAME_BUDGET_USEC := 3000

var shadow: ParticleSimulation
var counts: Dictionary = {}
var ticks_per_window: int
var ticks_remaining := 0

## Copy the board and in-flight state so the prediction never advances the live run.
func _init(source: ParticleSimulation, buildings: Array[Node], steps: float) -> void:
  ticks_per_window = roundi(steps * SimulationGrid.GRID_TICKS_PER_STEP * SimulationGrid.TICKS_PER_STEP)
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
        copy._continuous = original._continuous
        copy._pending = original._pending.duplicate()
        copy._sequence_template = original._sequence_template.duplicate()
        copy._time_until_next = original._time_until_next
      "gate": copy.gate_open = original.gate_open
      "pusher": copy.push_up = original.push_up
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
    copy.held_by = building_copies.get(original.held_by)
    if is_instance_valid(copy.held_by):
      copy.held_by.set("held_particle", copy)
    for gate in original.passed_gates:
      if building_copies.has(gate):
        copy.passed_gates.append(building_copies[gate])
    shadow.add_child(copy)
    copy.flight_cell = original.flight_cell
    particle_copies[original] = copy
  for original in particle_copies:
    if original.flavour == Particle.Flavour.GLUON:
      var gluon := original as BOSON
      var trail := particle_copies[original] as BOSON
      trail.trail_points = gluon.trail_points.duplicate()
      trail.edge_stopped = gluon.edge_stopped
      trail.blocked_by = particle_copies.get(gluon.blocked_by)
      for captive in gluon.caught:
        if particle_copies.has(captive): trail.trap(particle_copies[captive])
    for partner in original.separating_from:
      if particle_copies.has(partner):
        particle_copies[original].separating_from.append(particle_copies[partner])
  shadow.particle_detected.connect(_on_detected)

func _on_detected(particle_name: String) -> void:
  for key in PARTICLES.detection_keys(particle_name):
    counts[key] = int(counts.get(key, 0)) + 1

## Advance one measurement window over as many rendered frames as needed.
func advance() -> bool:
  if ticks_remaining == 0:
    counts.clear()
    ticks_remaining = ticks_per_window
  var deadline := Time.get_ticks_usec() + FRAME_BUDGET_USEC
  while ticks_remaining > 0:
    shadow.step_simulation(SimulationGrid.TICK)
    for child in shadow.get_children():
      if child is Particle and child.is_queued_for_deletion():
        child.free()
    ticks_remaining -= 1
    if Time.get_ticks_usec() >= deadline: break
  return ticks_remaining == 0

func dispose() -> void:
  shadow.queue_free()
  shadow = null
