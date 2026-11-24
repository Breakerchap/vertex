extends SceneTree

const PARTICLES = preload("res://Particles/particle_catalog.gd")
const FORECAST = preload("res://MainScene/simulation_forecast.gd")
const EMITTER = preload("res://Buildings/Emitter/emitter.tscn")
var failures := 0

func _initialize() -> void:
  _run.call_deferred()

func _check(condition: bool, message: String) -> void:
  if not condition:
    failures += 1
    push_error(message)

func _run() -> void:
  var paths := {}
  for name in PARTICLES.TYPES:
    var type: Array = PARTICLES.TYPES[name]
    var particle := PARTICLES.instantiate(type[0], type[1], type[2])
    _check(not paths.has(particle.scene_file_path), name + " should have its own scene.")
    paths[particle.scene_file_path] = true
    root.add_child(particle)
    _check(particle.level_particle_name() == name, name + " should retain its identity after initialization.")
    _check(particle.sprite.texture == PARTICLES.texture_for(name), name + " preview should use its scene's artwork.")
    particle.free()

  for name in PARTICLES.ANTI_QUARK_SCENES:
    var type: Array = PARTICLES.TYPES[name]
    var anti := PARTICLES.instantiate(type[0], true, type[2])
    _check(anti.scene_file_path == PARTICLES.ANTI_QUARK_SCENES[name].resource_path, "Antiquarks should use their own scene.")
    root.add_child(anti)
    _check(anti.charge == (-1 if type[0] == Particle.Flavour.UP else 1), "Antiquark charge should come from its scene.")
    anti.free()

  # Substitute a scene with custom values to exercise both emitters and reactions.
  var original: PackedScene = PARTICLES.SCENES.electron
  var configured := original.instantiate() as Particle
  configured.mass = 7.0
  configured.speed = 2.25
  configured.size = 0.42
  configured.charge = -3
  _check(original.pack(configured) == OK, "Could not pack custom particle scene.")
  configured.free()
  var sim := ParticleSimulation.new()
  sim.running = false
  root.add_child(sim)
  var emitter := EMITTER.instantiate() as ParticleEmitter
  emitter.start_on_ready = false
  sim.add_child(emitter)
  var emitted := emitter.emit_particle(Particle.Flavour.ELECTRON, false, Vector2.RIGHT)
  var product := sim._spawn_product(Particle.Flavour.ELECTRON, false, Vector2(1000, 0), Vector2.RIGHT)
  for particle in [emitted, product]:
    _check(particle.mass == 7.0 and particle.speed == 2.25 and particle.size == 0.42 and particle.charge == -3, "Spawned particles should retain all scene settings.")
  emitted.mass = 8.0
  emitted.speed = 3.0
  emitted.size = 0.6
  emitted.charge = -4
  var forecast := FORECAST.new(sim, [])
  var copy := forecast.shadow._particles()[0]
  _check(copy.mass == emitted.mass and copy.speed == emitted.speed and copy.size == emitted.size and copy.charge == emitted.charge, "Forecasts should preserve instance properties.")
  forecast.dispose()
  sim.free()
  if failures == 0:
    print("Particle scene checks passed")
  quit(1 if failures else 0)

