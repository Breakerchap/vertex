extends SceneTree

const CATALOG = preload("res://Buildings/building_catalog.gd")
const PARTICLES = preload("res://Particles/particle_catalog.gd")
const FORECAST = preload("res://MainScene/simulation_forecast.gd")
const RAIL = preload("res://Buildings/GridDevices/rail.tscn")
const CELL := SimulationGrid.CELL
var failures := 0
var sim: ParticleSimulation

func _initialize() -> void:
  _run.call_deferred()

func _check(condition: bool, message: String) -> void:
  if not condition:
    failures += 1
    push_error(message)

func _new_board() -> void:
  if is_instance_valid(sim): sim.free()
  sim = ParticleSimulation.new()
  sim.running = false
  root.add_child(sim)

func _device(kind: String, cell: Vector2, properties := {}) -> Node2D:
  var scene: PackedScene = RAIL if kind == "rail" else CATALOG.SCENES[kind]
  var device := scene.instantiate() as Node2D
  device.position = cell * CELL
  device.set_meta("kind", kind)
  for property in properties: device.set(property, properties[property])
  sim.add_child(device)
  return device

func _particle(name: String, cell: Vector2, direction := Vector2.RIGHT, pace := -1.0) -> Particle:
  var type: Array = PARTICLES.TYPES[name]
  var result := PARTICLES.instantiate(type[0], type[1], type[2])
  result.position = cell * CELL
  result.direction = direction
  if pace >= 0.0: result.speed = pace
  sim.add_child(result)
  return result

func _at(particle: Particle, cell: Vector2) -> bool:
  return particle.motion_position().is_equal_approx(cell * CELL)

func _movement_and_hitboxes() -> void:
  _new_board()
  var slow := _particle("electron", Vector2.ZERO, Vector2(1, 0.9), 0.5)
  var fast := _particle("photon", Vector2(0, 3))
  var anti := _particle("positron", Vector2(0, 5))
  sim.step_simulation()
  _check(slow.direction == Vector2.ONE and slow.global_position == Vector2.ZERO, "The logical position should stay on a tile centre in transit.")
  _check(_at(slow, Vector2.ONE.normalized() * 0.5) and _at(fast, Vector2(2, 3)) and _at(anti, Vector2(1, 5)), "Fractional, light and normal speed should use cells per step.")
  sim.step_simulation(2.0 * sqrt(2.0) - 1.0)
  _check(_at(slow, Vector2.ONE), "A diagonal should reach the next tile centre after travelling its full length.")
  for name in PARTICLES.TYPES:
    var particle := _particle(name, Vector2(20, 20))
    var art_width := particle.sprite.texture.get_width() * particle.sprite.global_scale.x
    _check(is_equal_approx(particle.world_collision_radius() * 2.0, art_width), name + " collision diameter must match its sprite.")
    particle.queue_free()

func _devices() -> void:
  _new_board()
  var gate = _device("gate", Vector2.ZERO)
  var blocked := _particle("electron", Vector2.LEFT)
  sim.step_simulation()
  _check(gate.gate_open and blocked.is_queued_for_deletion(), "A closed gate should stop the hit and open.")
  var passed := _particle("electron", Vector2.LEFT)
  sim.step_simulation(2)
  _check(not gate.gate_open and _at(passed, Vector2.RIGHT), "An open gate closes while passing the hit exactly once.")
  _new_board()
  var rotated_gate = _device("gate", Vector2.ZERO, {"orientation": 2, "starts_open": true})
  var side_hit := _particle("electron", Vector2.LEFT)
  sim.step_simulation()
  _check(side_hit.is_queued_for_deletion() and rotated_gate.gate_open, "Side hits should be blocked without toggling a gate.")
  var through := _particle("electron", Vector2.UP, Vector2.DOWN)
  sim.step_simulation(2)
  _check(_at(through, Vector2.DOWN) and not rotated_gate.gate_open, "The gate should toggle only along its rotated axis.")

  _new_board()
  _device("glass", Vector2.ZERO)
  var electron := _particle("positron", Vector2.LEFT)
  var quark := _particle("up_r", Vector2.RIGHT, Vector2.LEFT)
  sim.step_simulation(2)
  _check(quark.is_queued_for_deletion() and _at(electron, Vector2.ZERO), "Glass should block quarks and delay small particles at its centre.")
  sim.step_simulation(2)
  _check(_at(electron, Vector2(2, 0)), "Particles should regain speed after leaving glass.")
  _new_board()
  _device("glass", Vector2.ZERO)
  var light := _particle("photon", Vector2.LEFT)
  sim.step_simulation(1.5)
  _check(_at(light, Vector2.RIGHT), "Glass should halve light speed too.")

  _new_board()
  _device("filter", Vector2.ZERO, {"filter_colour": 2})
  var good := _particle("down_b", Vector2.LEFT)
  var bad := _particle("up_g", Vector2.RIGHT, Vector2.LEFT)
  sim.step_simulation(2)
  _check(_at(good, Vector2.RIGHT) and bad.is_queued_for_deletion(), "Filters should allow only matching quark colours.")
  var blue := _particle("photon", Vector2.LEFT)
  sim.step_simulation()
  _check(_at(blue, Vector2.RIGHT), "Uncoloured photons should pass through a filter.")

  _new_board()
  _device("edge_wall", Vector2.ZERO)
  var stopped := _particle("photon", Vector2.ZERO)
  var clear := _particle("photon", Vector2.LEFT, Vector2.LEFT)
  sim.step_simulation(0.5)
  _check(stopped.is_queued_for_deletion() and _at(clear, Vector2.LEFT * 2), "An inter-tile wall should block one edge and leave the cell usable.")

  _new_board()
  var holder = _device("holder", Vector2.ZERO)
  var held := _particle("up_r", Vector2.LEFT)
  sim.step_simulation(2)
  _check(held.held_by == holder and _at(held, Vector2.ZERO), "The holder should retain its particle.")
  _particle("down_b", Vector2.RIGHT, Vector2.LEFT)
  sim.step_simulation()
  var product := sim._particles()[0]
  _check(product.flavour == Particle.Flavour.PION_ZERO and product.held_by == null and holder.held_particle == null and product.direction == Vector2.LEFT, "The holder should release the product along the incoming quark’s heading.")

  _new_board()
  var pusher = _device("pusher", Vector2.ZERO)
  var first := _particle("electron", Vector2.LEFT)
  sim.step_simulation(2)
  _check(_at(first, Vector2(1, -1)) and first.direction == Vector2.RIGHT and not pusher.push_up, "The first push should go up without changing momentum.")
  var second := _particle("electron", Vector2.LEFT)
  sim.step_simulation(2)
  _check(_at(second, Vector2(1, 1)) and second.direction == Vector2.RIGHT and pusher.push_up, "The second push should go down without changing momentum.")
  _new_board()
  _device("pusher", Vector2.ZERO, {"orientation": 2})
  var shifted := _particle("electron", Vector2.DOWN, Vector2.UP)
  sim.step_simulation(2)
  _check(_at(shifted, Vector2(1, -1)) and shifted.direction == Vector2.UP, "Turning a pusher should rotate the offset without turning the particle.")

func _rails_and_forecast() -> void:
  _new_board()
  var loop := [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN]
  var rails: Array[Node] = []
  for cell in loop: rails.append(_device("rail", cell))
  var rider := _device("holder", Vector2.ZERO)
  var second := _device("gate", Vector2.RIGHT, {"starts_open": true})
  var held := _particle("electron", Vector2.LEFT)
  sim.step_simulation(0.5)
  var buildings := rails.duplicate()
  buildings.append_array([rider, second])
  var forecast := FORECAST.new(sim, buildings, 1.0)
  forecast.shadow.step_simulation(0.5)
  var shadow_particle: Particle = forecast.shadow._particles()[0]
  sim.step_simulation(0.5)
  _check(held.held_by == rider and _at(held, Vector2.RIGHT) and _at(shadow_particle, Vector2.RIGHT), "Held particles and forecast copies should ride with their holder.")
  _check(second.position.is_equal_approx(Vector2.ONE * CELL), "Rail riders should advance simultaneously clockwise.")
  rails[0].counterclockwise = true
  sim.step_simulation()
  _check(rider.position == Vector2.ZERO and second.position.is_equal_approx(Vector2.RIGHT * CELL), "One reversed rail should reverse the loop.")
  forecast.dispose()
  _new_board()
  for x in range(2):
    for y in range(3):
      _device("rail", Vector2(x, y))
  rider = _device("pusher", Vector2(1, 1))
  sim.step_simulation()
  _check(rider.position.is_equal_approx(Vector2(1, 2) * CELL), "A narrow rectangular loop should follow its perimeter.")

func _reactions() -> void:
  var pion_names := ["pion_minus", "pion_zero", "pion_plus"]
  var baryon_names := ["delta_minus", "neutron", "proton", "delta_plus"]
  for ups in range(3):
    _new_board()
    _particle(("up" if ups >= 1 else "down") + "_r", Vector2.LEFT)
    _particle(("up" if ups >= 2 else "down") + "_g", Vector2.RIGHT, Vector2.LEFT)
    sim.step_simulation()
    var products := sim._particles()
    _check(products.size() == 1 and products[0].level_particle_name() == pion_names[ups] and products[0].charge == ups - 1, "Two colours should form the requested pion with the requested charge.")
    var same_colour := _particle("up_r", Vector2.UP, Vector2.DOWN)
    sim.step_simulation()
    _check(same_colour.is_queued_for_deletion() and not products[0].is_queued_for_deletion(), "A pion should destroy a lighter quark of an already-used colour.")
    _particle("down_b", Vector2.UP, Vector2.DOWN)
    sim.step_simulation()
    products = sim._particles()
    _check(products.size() == 1 and products[0].level_particle_name() == baryon_names[ups], "A third colour should complete the baryon.")
  for ups in range(4):
    _new_board()
    _particle(("up" if ups >= 1 else "down") + "_r", Vector2.LEFT)
    _particle(("up" if ups >= 2 else "down") + "_g", Vector2.RIGHT, Vector2.LEFT)
    _particle(("up" if ups >= 3 else "down") + "_b", Vector2.UP, Vector2.DOWN)
    sim.step_simulation()
    var products := sim._particles()
    _check(products.size() == 1 and products[0].level_particle_name() == baryon_names[ups], "Simultaneous three-colour collisions should directly form " + baryon_names[ups])

func _mass_and_split() -> void:
  _new_board()
  var a := _particle("up_r", Vector2.LEFT)
  var b := _particle("down_r", Vector2.UP, Vector2.DOWN)
  sim.step_simulation()
  _check(not a.is_queued_for_deletion() and not b.is_queued_for_deletion() and a.direction == -b.direction and a.direction.dot(Vector2.ONE) == 0.0, "Same-colour quarks should leave perpendicular to their combined momentum.")

  _new_board()
  a = _particle("photon", Vector2.LEFT)
  b = _particle("photon", Vector2.RIGHT, Vector2.LEFT)
  sim.step_simulation()
  _check(a.direction == Vector2.LEFT and b.direction == Vector2.RIGHT, "Equal-mass particles should bounce.")
  for name in ["electron", "positron"]:
    _new_board()
    a = _particle(name, Vector2.LEFT)
    b = _particle(name, Vector2.RIGHT, Vector2.LEFT)
    sim.step_simulation(2.0)
    _check(_at(a, Vector2.RIGHT) and _at(b, Vector2.LEFT), "Like leptons should pass straight through each other.")

  _new_board()
  _particle("down_g", Vector2.LEFT)
  _particle("up_b", Vector2.RIGHT, Vector2.LEFT)
  sim.step_simulation()
  var photon := _particle("photon", Vector2.UP, Vector2.DOWN)
  sim.step_simulation(2)
  var names: Array[String] = []
  for particle in sim._particles(): names.append(particle.level_particle_name())
  names.sort()
  _check(photon.is_queued_for_deletion() and names == ["down_g", "up_b"], "A photon should be consumed while restoring the original quark flavours and colours.")

  _new_board()
  var holder = _device("holder", Vector2.ZERO)
  var pion := _particle("pion_zero", Vector2.LEFT)
  sim.step_simulation()
  _check(pion.held_by == holder, "The holder should catch a pion.")
  _particle("up_b", Vector2.RIGHT, Vector2.LEFT)
  sim.step_simulation()
  var proton := sim._particles()[0]
  _check(proton.level_particle_name() == "proton" and proton.held_by == null and proton.direction == Vector2.LEFT and is_equal_approx(proton.speed, 0.5), "A proton made in a holder should leave in the incoming direction at its mass-based speed.")

func _muons_and_mass_speeds() -> void:
  var expected := {"photon": [0.0, 2.0], "neutrino": [0.0, 2.0], "electron": [1.0, 1.0],
    "positron": [1.0, 1.0], "muon": [2.0, 1.0], "anti_muon": [2.0, 1.0],
    "up_r": [2.0, 1.0], "pion_zero": [3.0, 1.0], "proton": [4.0, 0.5]}
  _new_board()
  for name in expected:
    var particle := _particle(name, Vector2(20, 20))
    _check(particle.mass == expected[name][0] and particle.speed == expected[name][1], name + " should use its mass-based speed.")
    particle.queue_free()
  var reactions := [
    ["muon", "anti_muon", ["photon", "photon", "photon", "photon"]],
    ["muon", "positron", ["electron", "photon", "photon"]],
    ["anti_muon", "electron", ["photon", "photon", "positron"]],
    ["muon", "electron", ["electron", "electron", "neutrino", "neutrino"]],
    ["anti_muon", "positron", ["neutrino", "neutrino", "positron", "positron"]],
  ]
  for reaction in reactions:
    _new_board()
    _particle(reaction[0], Vector2.LEFT)
    _particle(reaction[1], Vector2.RIGHT, Vector2.LEFT)
    sim.step_simulation()
    var names: Array[String] = []
    for particle in sim._particles():
      names.append(particle.level_particle_name())
      _check(particle.speed == particle.mass_speed(), "Reaction products should use their mass-based speed.")
    names.sort()
    _check(names == reaction[2], "Incorrect products for %s + %s: %s" % [reaction[0], reaction[1], names])
    sim.step_simulation(0.1)
    _check(sim._particles().size() == reaction[2].size(), "Reaction products should separate without immediately colliding.")

func _neutrinos_and_reaction_directions() -> void:
  _new_board()
  var neutrino := _particle("neutrino", Vector2.LEFT * 2.0)
  var other := _particle("electron", Vector2.LEFT, Vector2.LEFT)
  _device("gate", Vector2.ZERO)
  var holder = _device("holder", Vector2.RIGHT)
  sim.step_simulation(2.0)
  _check(_at(neutrino, Vector2.RIGHT * 2.0) and not neutrino.is_queued_for_deletion(), "Neutrinos should pass through particles, gates, and holders at full speed.")
  _check(not other.is_queued_for_deletion() and holder.held_particle == null, "Neutrinos should not affect particles or devices.")
  _new_board()
  _device("pusher", Vector2.ZERO)
  neutrino = _particle("neutrino", Vector2.LEFT)
  sim.step_simulation()
  _check(_at(neutrino, Vector2.RIGHT), "Neutrinos should not be pushed by devices.")
  _new_board()
  var a := _particle("muon", Vector2.LEFT)
  var b := _particle("positron", Vector2.RIGHT, Vector2.LEFT)
  var contact := {"at": Vector2.ZERO, "at_a": Vector2.LEFT, "at_b": Vector2.RIGHT,
    "velocity_a": Vector2.RIGHT, "velocity_b": Vector2.LEFT}
  sim._muon_reaction(a, b, contact)
  var first: Array[Vector2] = []
  for product in sim._particles(): first.append(product.direction)
  _new_board()
  a = _particle("muon", Vector2.LEFT)
  b = _particle("positron", Vector2.RIGHT, Vector2.LEFT)
  contact.velocity_a = Vector2.RIGHT + Vector2.DOWN
  contact.velocity_b = Vector2.LEFT + Vector2.DOWN
  sim._muon_reaction(a, b, contact)
  var second: Array[Vector2] = []
  for product in sim._particles(): second.append(product.direction)
  _check(first != second, "Product headings should change when incoming momentum changes even with the same relative velocity.")

func _run() -> void:
  _new_board()
  sim.running = true
  sim.step_simulation(1.5)
  sim.pause_requested = true
  for frame in range(37):
    sim._physics_process(1.0 / 60.0)
  _check(sim.running, "A pause should wait until the end of the four-tick step.")
  sim._physics_process(1.0 / 60.0)
  sim._physics_process(1.0 / 60.0)
  _check(not sim.running and sim._ticks_into_step == 0 and sim._step_phase == 0.0, "Pausing should stop on the next step boundary.")
  sim.request_steps(1)
  for frame in range(SimulationGrid.TICKS_PER_STEP):
    sim._physics_process(1.0 / 60.0)
  _check(sim._ticks_into_step == 1 and not sim.running, "The step control should advance one grid tick.")
  _movement_and_hitboxes()
  _devices()
  _rails_and_forecast()
  _reactions()
  _mass_and_split()
  _muons_and_mass_speeds()
  _neutrinos_and_reaction_directions()
  if is_instance_valid(sim): sim.free()
  if failures == 0: print("Grid mechanics checks passed")
  quit(int(failures > 0))

