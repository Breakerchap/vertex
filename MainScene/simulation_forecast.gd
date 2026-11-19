extends RefCounted

const PARTICLES = preload("res://Particles/particle_catalog.gd")
const FRAME_BUDGET_USEC := 3000

var shadow: ParticleSimulation
var counts: Dictionary = {}
var steps_per_window: int
var steps_remaining := 0
var delta: float

## Copy the board and in-flight state so the prediction never advances the live run.
func _init(source: ParticleSimulation, buildings: Array[Node], seconds: float) -> void:
  steps_per_window = roundi(seconds * Engine.physics_ticks_per_second)
  delta = 1.0 / float(Engine.physics_ticks_per_second)
  shadow = ParticleSimulation.new()
  shadow.running = false
  shadow.level_bounds_enabled = source.level_bounds_enabled
  shadow.level_bounds = source.level_bounds
  shadow.hide()
  source.get_tree().root.add_child(shadow)
  shadow.set_physics_process(false)
  var field_copies := {}
  for original in buildings:
    var copy = original.duplicate()
    if original.get_meta("kind") == "emitter":
      copy.start_on_ready = false
    shadow.add_child(copy)
    copy.global_position = original.global_position
    if original.get_meta("kind") == "magnet":
      field_copies[original] = copy
    if original.get_meta("kind") == "emitter":
      copy._continuous = original._continuous
      copy._pending = original._pending.duplicate()
      copy._sequence_template = original._sequence_template.duplicate()
      copy._time_until_next = original._time_until_next
  for original in source._particles():
    var copy := original.duplicate() as Particle
    # _ready() applies the particle's size again when the copy enters the tree.
    copy.scale = original.scale / original.size if original.size != 0.0 else original.scale
    copy.flavour = original.flavour
    copy.colour = original.colour
    copy.isAnti = original.isAnti
    copy.direction = original.direction
    shadow.add_child(copy)
    copy.global_position = original.global_position
    copy.speed = original.speed
    copy.collision_radius = original.collision_radius
    copy.magnetic_field = field_copies.get(original.magnetic_field)
    copy.magnetic_last_field = field_copies.get(original.magnetic_last_field)
    copy.magnetic_remaining = original.magnetic_remaining
    copy.magnetic_turn_sign = original.magnetic_turn_sign
  shadow.particle_detected.connect(_on_detected)

func _on_detected(particle_name: String) -> void:
  var family := PARTICLES.family(particle_name)
  for key in [particle_name, family] if not family.is_empty() else [particle_name]:
    counts[key] = int(counts.get(key, 0)) + 1

## Advance one measurement window over as many rendered frames as needed.
func advance() -> bool:
  if steps_remaining == 0:
    counts.clear()
    steps_remaining = steps_per_window
  var deadline := Time.get_ticks_usec() + FRAME_BUDGET_USEC
  while steps_remaining > 0:
    shadow.step_simulation(delta)
    for child in shadow.get_children():
      if child is Particle and child.is_queued_for_deletion():
        child.free()
    steps_remaining -= 1
    if Time.get_ticks_usec() >= deadline: break
  return steps_remaining == 0

func dispose() -> void:
  shadow.queue_free()
  shadow = null
