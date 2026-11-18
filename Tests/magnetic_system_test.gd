extends SceneTree

const FIELD = preload("res://Buildings/MagneticField/magnetic_field.tscn")
const ELECTRON = preload("res://Particles/Electron/electron.tscn")
const PHOTON = preload("res://Particles/Photon/photon.tscn")
const PARSER = preload("res://Levels/level_parser.gd")
var failures: int = 0

func _initialize() -> void:
  call_deferred("_run")

func _check(condition: bool, message: String) -> void:
  if not condition:
    failures += 1
    push_error(message)

func _simulation() -> ParticleSimulation:
  var sim := ParticleSimulation.new()
  sim.running = false
  root.add_child(sim)
  return sim

func _turn(anti: bool, polarity: int, expected: Vector2) -> void:
  var sim := _simulation()
  var field = FIELD.instantiate()
  field.polarity = polarity
  sim.add_child(field)
  var particle := ELECTRON.instantiate() as Particle
  particle.isAnti = anti
  sim.add_child(particle)
  particle.global_position = Vector2(-102.4, 0)
  particle.direction = Vector2.RIGHT
  var curved := false
  for tick in range(40):
    sim.step_simulation(1.0 / 60.0)
    if absf(particle.direction.x) > 0.05 and absf(particle.direction.y) > 0.05:
      curved = true
  _check(curved, "Magnetic turns should include intermediate directions.")
  _check(particle.direction.is_equal_approx(expected), "Incorrect magnetic turn.")
  _check(absf(particle.global_position.x) < 0.02, "Centred beams should stay on the grid after turning.")
  _check(not particle.is_queued_for_deletion() and particle.magnetic_field == null, "A field should apply one complete turn.")
  sim.free()

func _absorption(anti: bool) -> void:
  var sim := _simulation()
  var electron := ELECTRON.instantiate() as Particle
  electron.isAnti = anti
  sim.add_child(electron)
  electron.direction = Vector2.LEFT
  var photon := PHOTON.instantiate() as Particle
  sim.add_child(photon)
  photon.global_position = Vector2(-100, 0)
  photon.direction = Vector2.RIGHT
  sim.step_simulation(0.2)
  _check(photon.is_queued_for_deletion() and not electron.is_queued_for_deletion(), "A photon crossing an electron or positron should be absorbed alone.")
  sim.free()

func _run() -> void:
  _turn(true, 1, Vector2.DOWN)
  _turn(false, 1, Vector2.UP)
  _turn(true, -1, Vector2.UP)
  _turn(false, -1, Vector2.DOWN)
  _absorption(false)
  _absorption(true)
  var sim := _simulation()
  var field = FIELD.instantiate()
  sim.add_child(field)
  var photon := PHOTON.instantiate() as Particle
  sim.add_child(photon)
  photon.global_position = Vector2(-102.4, 0)
  photon.direction = Vector2.RIGHT
  sim.step_simulation(0.5)
  _check(photon.direction == Vector2.RIGHT and is_zero_approx(photon.global_position.y), "A neutral photon should pass straight through a magnetic field.")
  sim.free()
  var data: Dictionary = PARSER.parse("7 x 7; goal: {electron: 1/s, 2/s, 3/s}; magnetic_field: {x=3,y=2,polarity=negative,fixed=p}; inventory: {magnet=2};")
  _check(not data.has("error") and data.buildings[0].kind == "magnet" and data.buildings[0].polarity == "negative" and data.inventory.magnet == 2, "Magnetic field level syntax should parse.")
  var level: Dictionary = PARSER.parse(FileAccess.get_file_as_string("res://Levels/Magnet Stuff.level"))
  _check(not level.has("error"), "Magnet Stuff should parse: " + str(level.get("error", "")))
  if not level.has("error"):
    _check(level.goals[0].has("[electron,positron]"), "Grouped goals should preserve their particle list.")
    _check(level.buildings[2].polarity == "-", "Bare minus should set negative polarity.")
  var negative: Dictionary = PARSER.parse("2 x 2; goal: {electron: 1, 2, 3}; magnet: {x=0,y=0,-};")
  _check(not negative.has("error") and negative.buildings[0].polarity == "-", "Bare minus should set negative polarity.")
  if failures == 0:
    print("Magnetic system checks passed")
  quit(1 if failures else 0)
