class_name ParticleSimulation
extends Node2D

const PHOTON_SCENE: PackedScene = preload("res://Particles/Photon/photon.tscn")

## Advances every particle and resolves collisions once per explicit call.
func step_simulation(delta: float) -> void:
  assert(delta >= 0.0, "Simulation delta cannot be negative")
  var particles := _particles()
  for particle in particles:
    particle.advance(delta)

  var consumed: Dictionary = {}
  for i in range(particles.size()):
    var a: Particle = particles[i]
    if not is_instance_valid(a) or consumed.has(a):
      continue
    for j in range(i + 1, particles.size()):
      var b: Particle = particles[j]
      if not is_instance_valid(b) or consumed.has(b):
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
