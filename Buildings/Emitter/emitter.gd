@tool
class_name ParticleEmitter
extends "res://Buildings/solid_building.gd"

const EmissionEntry = preload("res://Buildings/Emitter/particle_emission.gd")

const PARTICLES = preload("res://Particles/particle_catalog.gd")
const BOSON = preload("res://Particles/Boson/boson.gd")

@export_enum("0 degrees", "45 degrees", "90 degrees", "135 degrees", "180 degrees", "225 degrees", "270 degrees", "315 degrees") var orientation: int = 0:
  set(value):
    orientation = posmod(value, 8)
    rotation = orientation * PI / 4.0

@export var particleFlavour: Particle.Flavour = Particle.Flavour.ELECTRON
@export var isAnti: bool = false
@export var direction: Vector2 = Vector2.RIGHT
## Number of particles emitted per grid tick.
@export_range(0.0025, 250.0, 0.0025, "or_greater") var rate: float = 0.25
@export var sequence: Array[EmissionEntry] = []
@export var repeat_sequence: bool = false
@export var start_on_ready: bool = true

var _pending: Array[EmissionEntry] = []
var _time_until_next: float = 0.0
var _continuous: bool = false
var _sequence_template: Array[EmissionEntry] = []
var last_gluon: BOSON
# An obstructing trail keeps the cooldown at infinity until it clears.
var _gluon_cooldown := 0.0

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
func emit_particle(flavour: Particle.Flavour, anti: bool, travel: Vector2, colour: Particle.ColourCharge = Particle.ColourCharge.NONE) -> Particle:
  if _gluon_emission_blocked(flavour): return null
  var simulation := _simulation()
  if simulation == null:
    push_warning("Emitter must be a child of a ParticleSimulation")
    return null
  if travel.is_zero_approx():
    push_warning("Cannot emit a particle with a zero direction")
    return null
  var particle := PARTICLES.instantiate(flavour, anti, colour)
  particle.direction = global_transform.basis_xform(travel)
  particle.position = simulation.to_local(global_position)
  particle.emission_source = self
  simulation.add_child(particle)
  if flavour == Particle.Flavour.GLUON:
    last_gluon = particle as BOSON
    _gluon_cooldown = INF
  return particle

## Emit one particle using the emitter's inspector settings.
func spawnParticle() -> Particle:
  return emit_particle(particleFlavour, isAnti, direction)

## Replace any pending sequence. The first entry is emitted on the next simulation update.
func start_sequence() -> void:
  play_sequence(sequence)

func play_sequence(entries: Array[EmissionEntry]) -> void:
  _continuous = false
  _sequence_template = entries.duplicate()
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

func reset_device() -> void:
  last_gluon = null
  _gluon_cooldown = 0.0

## Called by ParticleSimulation; sequences pause when the simulation pauses.
func step_emission(ticks: float) -> void:
  if _last_gluon_covers_front():
    _gluon_cooldown = INF
  elif is_inf(_gluon_cooldown) and rate > 0.0:
    _gluon_cooldown = 1.0 / rate
  _step_scheduled_emission(ticks)
  _gluon_cooldown = maxf(0.0, _gluon_cooldown - ticks)

func _step_scheduled_emission(ticks: float) -> void:
  if not _continuous and _pending.is_empty():
    return
  if rate <= 0.0:
    push_warning("Emitter rate must be greater than zero")
    stop_sequence()
    return
  while (_continuous or not _pending.is_empty()) and _time_until_next <= 0.000001:
    var entry: EmissionEntry = null if _continuous else _pending[0]
    var flavour := entry.flavour if entry != null else particleFlavour
    if (_continuous or entry != null) and _gluon_emission_blocked(flavour):
      _time_until_next = 0.0 if is_inf(_gluon_cooldown) else maxf(0.0, _gluon_cooldown - ticks)
      return
    if _continuous:
      spawnParticle()
    else:
      _pending.pop_front()
      if entry != null:
        emit_particle(entry.flavour, entry.is_anti, entry.direction, entry.colour)
      if _pending.is_empty() and repeat_sequence and not _sequence_template.is_empty():
        _pending = _sequence_template.duplicate()
    _time_until_next += 1.0 / rate
  _time_until_next -= ticks

func _gluon_emission_blocked(flavour: Particle.Flavour) -> bool:
  return flavour == Particle.Flavour.GLUON and (_gluon_cooldown > 0.000001 or _last_gluon_covers_front())

func _last_gluon_covers_front() -> bool:
  if not is_instance_valid(last_gluon) or last_gluon.is_queued_for_deletion():
    return false
  var body := collision_shape.shape as RectangleShape2D
  var mouth := collision_shape.to_global(Vector2(body.size.x * 0.5, 0.0))
  return last_gluon.trail_overlaps(mouth, mouth.distance_to(global_position))

func _simulation() -> ParticleSimulation:
  var node := get_parent()
  while node != null:
    if node is ParticleSimulation:
      return node as ParticleSimulation
    node = node.get_parent()
  return null
