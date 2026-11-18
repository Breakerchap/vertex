class_name ParticleSimulation
extends Node2D

signal particle_detected(particle_name: String)
signal simulation_stepped(delta: float)
signal particle_event(kind: String, at: Vector2)

const PHOTON_SCENE: PackedScene = preload("res://Particles/Photon/photon.tscn")

@export var running: bool = true
@export_range(0.25, 4.0, 0.25) var simulation_speed: float = 1.0

var _accumulated_time: float = 0.0
var _pending_steps: int = 0
var level_bounds_enabled: bool = false
var level_bounds: Rect2

func _physics_process(delta: float) -> void:
  if not running:
    if _pending_steps > 0:
      _pending_steps -= 1
      step_simulation(1.0 / float(Engine.physics_ticks_per_second))
    return
  _pending_steps = 0
  var step_duration := 1.0 / float(Engine.physics_ticks_per_second)
  _accumulated_time += delta * maxf(simulation_speed, 0.0)
  while running and _accumulated_time + 0.0000001 >= step_duration:
    _accumulated_time = maxf(0.0, _accumulated_time - step_duration)
    step_simulation(step_duration)

## Queue fixed-size steps, advancing one per physics frame while paused.
func request_steps(count: int) -> void:
  running = false
  _accumulated_time = 0.0
  _pending_steps += maxi(count, 0)

func cancel_pending_steps() -> void:
  _pending_steps = 0

## Pause and advance one fixed physics tick, independent of the speed setting.
func step_once() -> void:
  running = false
  cancel_pending_steps()
  _accumulated_time = 0.0
  step_simulation(1.0 / float(Engine.physics_ticks_per_second))

## Advances every particle and resolves collisions once per explicit call.
func step_simulation(delta: float) -> void:
  assert(delta >= 0.0, "Simulation delta cannot be negative")
  for emitter in get_tree().get_nodes_in_group("particle_emitters"):
    if is_ancestor_of(emitter) and not emitter.is_queued_for_deletion():
      emitter.step_emission(delta)
  var particles := _particles()
  var obstacles := _obstacles()
  var fields := _fields()
  var previous_positions := {}
  for particle in particles:
    previous_positions[particle] = particle.global_position
    _advance_particle(particle, delta, obstacles, fields)
    if level_bounds_enabled and not particle.is_queued_for_deletion() and not level_bounds.has_point(particle.global_position):
      particle_event.emit("exit", particle.global_position)
      particle.queue_free()

  var consumed: Dictionary = {}
  for i in range(particles.size()):
    var a: Particle = particles[i]
    if not is_instance_valid(a) or a.is_queued_for_deletion() or consumed.has(a):
      continue
    for j in range(i + 1, particles.size()):
      var b: Particle = particles[j]
      if not is_instance_valid(b) or b.is_queued_for_deletion() or consumed.has(b):
        continue
      var radius_a : float = a.collision_radius * absf(a.global_scale.x)
      var radius_b : float = b.collision_radius * absf(b.global_scale.x)
      var contact_radius := radius_a + radius_b
      var photon_electron := (a.flavour == Particle.Flavour.PHOTON and b.flavour == Particle.Flavour.ELECTRON) or (b.flavour == Particle.Flavour.PHOTON and a.flavour == Particle.Flavour.ELECTRON)
      if photon_electron:
        # Relative swept movement catches particles that cross between ticks.
        var relative_start: Vector2 = previous_positions[a] - previous_positions[b]
        var relative_motion: Vector2 = (a.global_position - previous_positions[a]) - (b.global_position - previous_positions[b])
        var t := 0.0
        if relative_motion.length_squared() > 0.000001:
          t = clampf(-relative_start.dot(relative_motion) / relative_motion.length_squared(), 0.0, 1.0)
        if (relative_start + relative_motion * t).length_squared() <= contact_radius * contact_radius:
          var photon := a if a.flavour == Particle.Flavour.PHOTON else b
          particle_event.emit("absorption", photon.global_position)
          photon.queue_free()
          consumed[photon] = true
          if photon == a:
            break
          continue
      if a.global_position.distance_squared_to(b.global_position) > contact_radius * contact_radius:
        continue
      if a.flavour == b.flavour and a.isAnti != b.isAnti:
        _annihilate(a, b)
        consumed[a] = true
        consumed[b] = true
        break
  simulation_stepped.emit(delta)

## Sweep against buildings and follow smooth magnetic arcs in fixed-size segments.
func _advance_particle(particle: Particle, delta: float, obstacles: Array[Node], fields: Array[Node]) -> void:
  var remaining := delta
  for _segment in range(64):
    if remaining <= 0.0000001 or particle.speed <= 0 or particle.direction.is_zero_approx():
      return
    if is_instance_valid(particle.magnetic_last_field) and not particle.magnetic_last_field.contains_point(particle.global_position):
      particle.magnetic_last_field = null
    if not is_instance_valid(particle.magnetic_field):
      particle.magnetic_field = null
      particle.magnetic_remaining = 0.0
    var field = particle.magnetic_field
    var segment_time := remaining
    var turn := 0.0
    var motion := particle.direction.normalized() * particle.speed * segment_time
    if field != null:
      var radius: float = field.turn_radius()
      var angular_speed := particle.speed / radius
      var angle := minf(minf(remaining * angular_speed, particle.magnetic_remaining), PI / 36.0)
      segment_time = angle / angular_speed
      turn = angle * particle.magnetic_turn_sign
      motion = particle.direction.normalized().rotated(turn * 0.5) * (2.0 * radius * sin(angle * 0.5))
    var hit: Dictionary = {}
    for obstacle in obstacles:
      var radius := particle.collision_radius * absf(particle.global_scale.x)
      var candidate: Dictionary
      if particle.flavour == Particle.Flavour.PHOTON and obstacle.has_method("sweep_photon"):
        candidate = obstacle.sweep_photon(particle.global_position, motion, radius)
      else:
        candidate = obstacle.sweep(particle.global_position, motion, radius)
      if not candidate.is_empty() and (hit.is_empty() or candidate.fraction < hit.fraction):
        hit = candidate
        hit["obstacle"] = obstacle
    if particle.charge != 0 and field == null:
      for candidate_field in fields:
        if candidate_field == particle.magnetic_last_field:
          continue
        var fraction: float = candidate_field.entry_fraction(particle.global_position, motion)
        if fraction <= 1.0 and (hit.is_empty() or fraction < hit.fraction):
          hit = {"fraction": fraction, "field": candidate_field}
    var fraction: float = float(hit.fraction) if not hit.is_empty() else 1.0
    particle.global_position += motion * fraction
    if field != null:
      particle.direction = particle.direction.rotated(turn * fraction).normalized()
      particle.magnetic_remaining = maxf(0.0, particle.magnetic_remaining - absf(turn) * fraction)
      if particle.magnetic_remaining <= 0.000001:
        particle.magnetic_last_field = field
        particle.magnetic_field = null
    remaining -= segment_time * fraction
    if hit.is_empty():
      continue
    if hit.has("field"):
      particle.magnetic_field = hit.field
      particle_event.emit("field", particle.global_position)
      particle.magnetic_remaining = PI * 0.5
      particle.magnetic_turn_sign = 1.0 if particle.charge * hit.field.polarity > 0 else -1.0
      continue
    if hit.obstacle.has_method("accepts") and hit.obstacle.accepts(particle):
      particle_event.emit("detection", particle.global_position)
      particle_detected.emit(particle.level_particle_name())
    if particle.flavour != Particle.Flavour.PHOTON or not hit.reflective:
      particle_event.emit("absorption", particle.global_position)
      particle.queue_free()
      return
    var normal: Vector2 = hit.normal
    particle_event.emit("reflection", particle.global_position)
    particle.direction = particle.direction.bounce(normal).normalized()
    particle.global_position += particle.direction * 0.001

func _fields() -> Array[Node]:
  var result: Array[Node] = []
  for field in get_tree().get_nodes_in_group("magnetic_fields"):
    if is_ancestor_of(field) and not field.is_queued_for_deletion():
      result.append(field)
  return result

func _obstacles() -> Array[Node]:
  var result: Array[Node] = []
  for mirror in get_tree().get_nodes_in_group("particle_mirrors"):
    if is_ancestor_of(mirror) and not mirror.is_queued_for_deletion():
      result.append(mirror)
  for blocker in get_tree().get_nodes_in_group("particle_blockers"):
    if is_ancestor_of(blocker) and not blocker.is_queued_for_deletion():
      result.append(blocker)
  return result

func _particles() -> Array[Particle]:
  var result: Array[Particle] = []
  for child in get_children():
    if child is Particle and not child.is_queued_for_deletion():
      result.append(child)
  return result

func _annihilate(a: Particle, b: Particle) -> void:
  var position_mid := (a.global_position + b.global_position) * 0.5
  particle_event.emit("annihilation", position_mid)
  var relative := a.direction.normalized() - b.direction.normalized()
  if relative.is_zero_approx():
    relative = a.direction.normalized()
  if relative.is_zero_approx():
    relative = Vector2.RIGHT
  var photon_direction := relative.orthogonal().normalized()
  _spawn_photon(position_mid, photon_direction)
  _spawn_photon(position_mid, -photon_direction)
  a.queue_free()
  b.queue_free()

func _spawn_photon(at: Vector2, travel: Vector2) -> void:
  var photon := PHOTON_SCENE.instantiate() as Particle
  photon.direction = travel
  add_child(photon)
  photon.global_position = at
