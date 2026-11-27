extends SceneTree

const BUILDINGS = preload("res://Buildings/building_catalog.gd")
const PARTICLES = preload("res://Particles/particle_catalog.gd")
const FORECAST = preload("res://MainScene/simulation_forecast.gd")
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
  var field = BUILDINGS.SCENES.magnet.instantiate()
  field.polarity = polarity
  sim.add_child(field)
  var particle := PARTICLES.instantiate(Particle.Flavour.ELECTRON, anti)
  sim.add_child(particle)
  particle.global_position = Vector2(-102.4, 0)
  particle.direction = Vector2.RIGHT
  sim.step_simulation(1.0)
  _check(not particle.magnetic_exit.is_zero_approx(), "The particle should still be crossing the magnet.")
  sim.step_simulation(sqrt(0.5))
  _check(particle.direction.is_equal_approx(expected), "Incorrect magnetic turn.")
  _check(particle.motion_position().is_equal_approx(expected * SimulationGrid.CELL), "A magnet should exit on the original outbound grid line.")
  _check(not particle.is_queued_for_deletion(), "A magnetic field must let charged particles through.")
  sim.free()

func _perpendicular_entries(polarity: int) -> void:
  var sim := _simulation()
  var field = BUILDINGS.SCENES.magnet.instantiate()
  field.set_meta("kind", "magnet")
  field.polarity = polarity
  sim.add_child(field)
  var electron := PARTICLES.instantiate(Particle.Flavour.ELECTRON)
  electron.position = Vector2.LEFT * SimulationGrid.CELL
  sim.add_child(electron)
  var positron := PARTICLES.instantiate(Particle.Flavour.ELECTRON, true)
  positron.position = Vector2.DOWN * SimulationGrid.CELL
  positron.direction = Vector2.UP
  sim.add_child(positron)

  sim.step_simulation(0.65)
  var forecast := FORECAST.new(sim, [field])
  sim.step_simulation(1.35)
  forecast.shadow.step_simulation(1.35)
  if polarity > 0:
    _check(not electron.is_queued_for_deletion() and not positron.is_queued_for_deletion(), "Opposite corner paths should clear the particles' hitboxes.")
    _check(electron.direction == Vector2.UP and positron.direction == Vector2.RIGHT, "Both exits should keep their original directions.")
  else:
    _check(electron.is_queued_for_deletion() and positron.is_queued_for_deletion(), "Particles travelling along the same corner path should still collide.")
  var live := sim._particles()
  var predicted := forecast.shadow._particles()
  _check(live.size() == predicted.size(), "A forecast copied mid-turn should predict the same contacts.")
  for i in range(mini(live.size(), predicted.size())):
    _check(live[i].motion_position().is_equal_approx(predicted[i].motion_position()), "A forecast should resume the same magnetic path.")
  forecast.dispose()
  sim.free()

func _diagonal_entry() -> void:
  var sim := _simulation()
  sim.add_child(BUILDINGS.SCENES.magnet.instantiate())
  var electron := PARTICLES.instantiate(Particle.Flavour.ELECTRON)
  electron.position = -Vector2.ONE * SimulationGrid.CELL
  electron.direction = Vector2.ONE
  sim.add_child(electron)
  sim.step_simulation(1.0 + sqrt(2.0))
  _check(electron.direction == Vector2(1, -1), "A diagonal entry should preserve the magnet's 90-degree turn.")
  _check(electron.motion_position().is_equal_approx(Vector2(1, -1) * SimulationGrid.CELL), "A diagonal exit should reconnect to its grid line at normal speed.")
  sim.free()

func _absorption(anti: bool) -> void:
  var sim := _simulation()
  var electron := PARTICLES.instantiate(Particle.Flavour.ELECTRON, anti)
  sim.add_child(electron)
  electron.direction = Vector2.LEFT
  var photon := PARTICLES.instantiate(Particle.Flavour.PHOTON)
  sim.add_child(photon)
  photon.global_position = Vector2(-100, 0)
  photon.direction = Vector2.RIGHT
  sim.step_simulation(0.5)
  _check(photon.is_queued_for_deletion() and not electron.is_queued_for_deletion(), "A photon crossing an electron or positron should be absorbed alone.")
  sim.free()

func _run() -> void:
  _turn(true, 1, Vector2.DOWN)
  _turn(false, 1, Vector2.UP)
  _turn(true, -1, Vector2.UP)
  _turn(false, -1, Vector2.DOWN)
  _perpendicular_entries(1)
  _perpendicular_entries(-1)
  _diagonal_entry()
  _absorption(false)
  _absorption(true)
  var sim := _simulation()
  var field = BUILDINGS.SCENES.magnet.instantiate()
  sim.add_child(field)
  var photon := PARTICLES.instantiate(Particle.Flavour.PHOTON)
  sim.add_child(photon)
  photon.global_position = Vector2(-102.4, 0)
  photon.direction = Vector2.RIGHT
  sim.step_simulation(0.5)
  _check(photon.direction == Vector2.RIGHT and is_zero_approx(photon.global_position.y), "A neutral photon should pass straight through a magnetic field.")
  sim.free()
  var data: Dictionary = PARSER.parse("7 x 7; goal: {electron: 1/s, 2/s, 3/s}; magnetic_field: {x=3,y=2,polarity=negative,fixed=p}; inventory: {magnet=2};")
  _check(not data.has("error") and data.buildings[0].kind == "magnet" and data.buildings[0].polarity == "negative" and data.inventory.magnet == 2, "Magnetic field level syntax should parse.")
  var level: Dictionary = PARSER.parse(FileAccess.get_file_as_string("res://Tests/magnet_fixture.level"))
  _check(not level.has("error"), "Magnet Stuff should parse: " + str(level.get("error", "")))
  if not level.has("error"):
    _check(level.medals.star[0].periods.has("[electron,positron]"), "Legacy grouped goals should preserve their particle list in the Star medal.")
    _check(level.buildings[2].polarity == "-", "Bare minus should set negative polarity.")
  var negative: Dictionary = PARSER.parse("2 x 2; goal: {electron: 1, 2, 3}; magnet: {x=0,y=0,-};")
  _check(not negative.has("error") and negative.buildings[0].polarity == "-", "Bare minus should set negative polarity.")
  if failures == 0:
    print("Magnetic system checks passed")
  await process_frame
  quit(1 if failures else 0)
