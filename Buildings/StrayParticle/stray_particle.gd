extends Node2D

const PARTICLES = preload("res://Particles/particle_catalog.gd")
const AT_REST := "REST"
const ARROW_COLOUR := Color("263d56")

@export var particle_name := "electron"
@export var facing := "E":
  set(value):
    facing = value
    queue_redraw()

func _ready() -> void:
  var names: Array[String] = [particle_name]
  $ParticlePreview.show_particles(names)

func _draw() -> void:
  if facing == AT_REST: return
  var direction := _launch_direction().normalized()
  var side := direction.orthogonal()
  var tip := direction * 45.0
  var base := tip - direction * 10.0
  draw_line(direction * 25.0, base, ARROW_COLOUR, 4.0, true)
  draw_colored_polygon(PackedVector2Array([tip, base + side * 6.0, base - side * 6.0]), ARROW_COLOUR)

func spawn_in(simulation: ParticleSimulation) -> void:
  var emission := PARTICLES.emission(particle_name)
  var particle := PARTICLES.instantiate(emission.flavour, emission.is_anti, emission.colour)
  particle.position = simulation.to_local(global_position)
  particle.direction = _launch_direction()
  if facing == AT_REST: particle.speed = 0.0
  simulation.add_child(particle)
  hide()

func _launch_direction() -> Vector2:
  if facing == AT_REST: return Vector2.ZERO
  return SimulationGrid.VECTORS[SimulationGrid.DIRECTIONS.find(facing)]
