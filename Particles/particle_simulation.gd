class_name ParticleSimulation
extends Node2D

const PHOTON_SCENE: PackedScene = preload("res://Particles/Photon/photon.tscn")

@export var running: bool = true
@export_range(0.25, 4.0, 0.25) var simulation_speed: float = 1.0

var _accumulated_time: float = 0.0

func _physics_process(delta: float) -> void:
  if not running:
    return
  var step_duration := 1.0 / float(Engine.physics_ticks_per_second)
  _accumulated_time += delta * maxf(simulation_speed, 0.0)
  while _accumulated_time + 0.0000001 >= step_duration:
    _accumulated_time = maxf(0.0, _accumulated_time - step_duration)
    step_simulation(step_duration)

## Pause and advance one fixed physics tick, independent of the speed setting.
func step_once() -> void:
  running = false
  _accumulated_time = 0.0
  step_simulation(1.0 / float(Engine.physics_ticks_per_second))

## Advances every particle and resolves collisions once per explicit call.
func step_simulation(delta: float) -> void:
  assert(delta >= 0.0, "Simulation delta cannot be negative")
  for emitter in get_tree().get_nodes_in_group("particle_emitters"):
    if is_ancestor_of(emitter) and not emitter.is_queued_for_deletion():
      emitter.step_emission(delta)
  var particles := _particles()
  var mirrors := _mirrors()
  for particle in particles:
    _advance_particle(particle, delta, mirrors)

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
      if a.global_position.distance_squared_to(b.global_position) > pow(radius_a + radius_b, 2):
        continue
      if a.flavour == b.flavour and a.isAnti != b.isAnti:
        _annihilate(a, b)
        consumed[a] = true
        consumed[b] = true
        break

## Sweep against mirror surfaces so fast particles cannot pass through between steps.
func _advance_particle(particle: Particle, delta: float, mirrors: Array[Node]) -> void:
  var remaining := delta
  # Bound work for a particle trapped between surfaces in a single step.
  for _bounce in range(8):
    if remaining <= 0.0:
      return
    var motion := particle.direction.normalized() * particle.speed * remaining
    if motion.is_zero_approx():
      return
    var hit: Dictionary = {}
    for mirror in mirrors:
      var candidate: Dictionary = mirror.sweep(particle.global_position, motion, particle.collision_radius * absf(particle.global_scale.x))
      if not candidate.is_empty() and (hit.is_empty() or candidate.fraction < hit.fraction):
        hit = candidate
    if hit.is_empty():
      particle.global_position += motion
      return
    particle.global_position += motion * float(hit.fraction)
    if particle.flavour != Particle.Flavour.PHOTON or not hit.reflective:
      particle.queue_free()
      return
    var normal: Vector2 = hit.normal
    particle.direction = particle.direction.bounce(normal).normalized()
    particle.global_position += normal * 0.001
    remaining *= 1.0 - float(hit.fraction)

func _mirrors() -> Array[Node]:
  var result: Array[Node] = []
  for mirror in get_tree().get_nodes_in_group("particle_mirrors"):
    if is_ancestor_of(mirror) and not mirror.is_queued_for_deletion():
      result.append(mirror)
  return result
func _particles() -> Array[Particle]:
  var result: Array[Particle] = []
  for child in get_children():
    if child is Particle and not child.is_queued_for_deletion():
      result.append(child)
  return result

func _annihilate(a: Particle, b: Particle) -> void:
  var position_mid := (a.global_position + b.global_position) * 0.5
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
