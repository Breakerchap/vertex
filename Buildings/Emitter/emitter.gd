@tool
class_name ParticleEmitter
extends "res://Buildings/solid_building.gd"

const EmissionEntry = preload("res://Buildings/Emitter/particle_emission.gd")

const ELECTRON_SCENE: PackedScene = preload("res://Particles/Electron/electron.tscn")
const PHOTON_SCENE: PackedScene = preload("res://Particles/Photon/photon.tscn")

@export_enum("0 degrees", "45 degrees", "90 degrees", "135 degrees", "180 degrees", "225 degrees", "270 degrees", "315 degrees") var orientation: int = 0:
  set(value):
    orientation = posmod(value, 8)
    rotation = orientation * PI / 4.0

@export var particleFlavour: Global.Flavour = Global.Flavour.ELECTRON
@export var isAnti: bool = false
@export var direction: Vector2 = Vector2.RIGHT
## Number of particles emitted per second.
@export_range(0.01, 1000.0, 0.01, "or_greater") var rate: float = 1.0
@export var sequence: Array[EmissionEntry] = []
@export var start_on_ready: bool = true

var _pending: Array[EmissionEntry] = []
var _time_until_next: float = 0.0
var _continuous: bool = false

func _ready() -> void:
  super._ready()
  if Engine.is_editor_hint():
    return
  add_to_group("particle_emitters")
  if start_on_ready:
    if sequence.is_empty():
      start_emitting()
    else:
      start_sequence()

## Emit one particle into the enclosing simulation, travelling in emitter-local coordinates.
func emit_particle(flavour: Global.Flavour, anti: bool, travel: Vector2) -> Particle:
  var simulation := _simulation()
  if simulation == null:
    push_warning("Emitter must be a child of a ParticleSimulation")
    return null
  var scene: PackedScene
  match flavour:
    Global.Flavour.ELECTRON: scene = ELECTRON_SCENE
    Global.Flavour.PHOTON: scene = PHOTON_SCENE
    _:
      push_warning("No particle scene exists for flavour %s" % flavour)
      return null
  if travel.is_zero_approx():
    push_warning("Cannot emit a particle with a zero direction")
    return null
  var particle := scene.instantiate() as Particle
  particle.isAnti = anti
  particle.direction = global_transform.basis_xform(travel).normalized()
  simulation.add_child(particle)
  var radius := particle.collision_radius * absf(particle.global_scale.x)
  particle.global_position = collision_shape.global_position + particle.direction * exit_distance(particle.direction, radius)
  return particle

## Emit one particle using the emitter's inspector settings.
func spawnParticle() -> Particle:
  return emit_particle(particleFlavour, isAnti, direction)

## Replace any pending sequence. The first entry is emitted on the next simulation step.
func start_sequence() -> void:
  play_sequence(sequence)

func play_sequence(entries: Array[EmissionEntry]) -> void:
  _continuous = false
  _pending = entries.duplicate()
  _time_until_next = 0.0

## Repeatedly emit using the single-particle inspector settings.
func start_emitting() -> void:
  _pending.clear()
  _continuous = true
  _time_until_next = 0.0

## Stop both continuous emission and any pending sequence.
func stop_sequence() -> void:
  _continuous = false
  _pending.clear()

## Called by ParticleSimulation; sequences pause when the simulation pauses.
func step_emission(delta: float) -> void:
  if not _continuous and _pending.is_empty():
    return
  if rate <= 0.0:
    push_warning("Emitter rate must be greater than zero")
    stop_sequence()
    return
  _time_until_next -= delta
  while (_continuous or not _pending.is_empty()) and _time_until_next <= 0.0:
    if _continuous:
      spawnParticle()
    else:
      var entry: EmissionEntry = _pending.pop_front()
      if entry != null:
        emit_particle(entry.flavour, entry.is_anti, entry.direction)
    _time_until_next += 1.0 / rate

func _simulation() -> ParticleSimulation:
  var node := get_parent()
  while node != null:
    if node is ParticleSimulation:
      return node as ParticleSimulation
    node = node.get_parent()
  return null
