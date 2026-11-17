extends RefCounted

## Runs independent fixed-step copies of the current board and particle state.
static func predict(source: ParticleSimulation, buildings: Array[Node], seconds: float, count: int) -> Array[Dictionary]:
  var shadow := ParticleSimulation.new()
  shadow.running = false
  shadow.level_bounds_enabled = source.level_bounds_enabled
  shadow.level_bounds = source.level_bounds
  source.get_tree().root.add_child(shadow)
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
  var tally := {"counts": {}}
  shadow.particle_detected.connect(func(name: String) -> void:
    var keys := [name, name.split("_")[0]] if "_" in name else [name]
    for key in keys:
      tally.counts[key] = int(tally.counts.get(key, 0)) + 1
  )
  var windows: Array[Dictionary] = []
  var steps := roundi(seconds * Engine.physics_ticks_per_second)
  var delta := 1.0 / float(Engine.physics_ticks_per_second)
  for _window in range(count):
    tally.counts = {}
    for _step in range(steps):
      shadow.step_simulation(delta)
      # The forecast runs without rendering frames, so process its deferred
      # particle deletions explicitly to keep long forecasts bounded.
      for child in shadow.get_children():
        if child is Particle and child.is_queued_for_deletion():
          child.free()
    windows.append(tally.counts.duplicate())
  source.get_tree().root.remove_child(shadow)
  shadow.queue_free()
  return windows
