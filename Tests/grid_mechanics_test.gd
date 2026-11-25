extends SceneTree

const CATALOG = preload("res://Buildings/building_catalog.gd")
const PARTICLES = preload("res://Particles/particle_catalog.gd")
const BOSON = preload("res://Particles/Boson/boson.gd")
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
  _check(_at(slow, Vector2.ONE.normalized() * 0.5) and _at(fast, Vector2(1.5, 3)) and _at(anti, Vector2(1, 5)), "Fractional, light and normal speed should use cells per tick.")
  sim.step_simulation(2.0 * sqrt(2.0) - 1.0)
  _check(_at(slow, Vector2.ONE), "A diagonal should reach the next tile centre after travelling its full length.")
  for name in PARTICLES.TYPES:
    var particle := _particle(name, Vector2(20, 20))
    var art_width := particle.sprite.texture.get_width() * particle.sprite.global_scale.x
    _check(is_equal_approx(particle.world_collision_radius() * 2.0, art_width), name + " collision diameter must match its sprite.")
    if particle.flavour == Particle.Flavour.NEUTRINO:
      _check(is_equal_approx(particle.scale.x, 0.16), name + " should be 60% larger.")
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

  for name in ["photon", "electron", "positron", "muon", "anti_muon", "neutrino", "anti_neutrino",
      "up_r", "down_b", "w_plus", "w_minus"]:
    _new_board()
    _device("glass", Vector2.ZERO)
    var particle := _particle(name, Vector2.LEFT)
    sim.step_simulation(2.0 / particle.speed)
    _check(not particle.is_queued_for_deletion() and _at(particle, Vector2.ZERO), name + " should pass the glass and wait at its centre.")
    sim.step_simulation(1.0 / particle.speed)
    _check(_at(particle, Vector2.RIGHT), name + " should carry on at full speed after passing glass.")
  _new_board()
  _device("glass", Vector2.ZERO)
  var proton := _particle("proton", Vector2.LEFT)
  sim.step_simulation()
  _check(proton.is_queued_for_deletion(), "Glass should still stop hadrons.")

  _new_board()
  _device("filter", Vector2.ZERO, {"filter_colour": 2})
  var good := _particle("down_b", Vector2.LEFT)
  var bad := _particle("up_g", Vector2.RIGHT, Vector2.LEFT)
  sim.step_simulation(2)
  _check(_at(good, Vector2.RIGHT) and bad.is_queued_for_deletion(), "Filters should allow only matching quark colours.")
  var blue := _particle("photon", Vector2.LEFT)
  sim.step_simulation()
  _check(_at(blue, Vector2.RIGHT * 0.5), "Uncoloured photons should pass through a filter.")

  _new_board()
  _device("edge_wall", Vector2.ZERO)
  var stopped := _particle("photon", Vector2.ZERO)
  var clear := _particle("photon", Vector2.LEFT, Vector2.LEFT)
  sim.step_simulation(0.5)
  _check(stopped.is_queued_for_deletion() and _at(clear, Vector2.LEFT * 1.75), "An inter-tile wall should block one edge and leave the cell usable.")

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

func _pusher_contacts() -> void:
  for pushed_first in [false, true]:
    _new_board()
    _device("pusher", Vector2.ZERO)
    if pushed_first: _particle("up_r", Vector2.LEFT)
    _particle("down_b", Vector2.UP, Vector2.ZERO)
    if not pushed_first: _particle("up_r", Vector2.LEFT)
    sim.step_simulation()
    var particles := sim._particles()
    _check(particles.size() == 1 and particles[0].flavour == Particle.Flavour.PION_ZERO
      and particles[0].direction == Vector2.RIGHT,
      "A push at the end of a tick should react with the resting quark while retaining the incoming momentum.")

  _new_board()
  var pusher := _device("pusher", Vector2.ZERO)
  _particle("photon", Vector2.LEFT)
  _particle("electron", Vector2(0, -2), Vector2.DOWN, 1.5)
  var forecast := FORECAST.new(sim, [pusher])
  sim.step_simulation(0.67)
  forecast.shadow.step_simulation(0.67)
  for simulation in [sim, forecast.shadow]:
    var particles: Array[Particle] = simulation._particles()
    _check(particles.size() == 1 and particles[0].flavour == Particle.Flavour.ELECTRON,
      "The pushed photon should collide with a moving electron in both the live simulation and forecast.")
  forecast.dispose()

  _new_board()
  _device("pusher", Vector2.ZERO)
  _device("pusher", Vector2.UP)
  var up := _particle("up_r", Vector2.LEFT)
  var down := _particle("down_b", Vector2(-1, -1))
  sim.step_simulation()
  _check(sim._particles().size() == 2 and _at(up, Vector2.UP) and _at(down, Vector2.UP * 2.0),
    "Particles pushed in parallel should stay separated.")

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
  var forecast := FORECAST.new(sim, buildings)
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
  var b := _particle("down_r", Vector2.RIGHT, Vector2.LEFT)
  sim.step_simulation(2.0)
  _check(sim._particles().size() == 2 and _at(a, Vector2.RIGHT) and _at(b, Vector2.LEFT), "Same-colour quarks should pass through one another.")

  _new_board()
  a = _particle("photon", Vector2.LEFT)
  b = _particle("photon", Vector2.RIGHT, Vector2.LEFT)
  sim.step_simulation()
  _check(sim._particles().size() == 2 and _at(a, Vector2.RIGHT * 0.5) and _at(b, Vector2.LEFT * 0.5), "Photons should pass through one another.")
  _new_board()
  a = _particle("muon", Vector2.LEFT)
  b = _particle("muon", Vector2.RIGHT, Vector2.LEFT)
  sim.step_simulation(2.0)
  _check(sim._particles().size() == 2 and a.direction == Vector2.LEFT and b.direction == Vector2.RIGHT, "Equal masses with no written interaction should bounce.")
  _new_board()
  a = _particle("anti_neutrino", Vector2.LEFT)
  b = _particle("anti_neutrino", Vector2.RIGHT, Vector2.LEFT)
  sim.step_simulation()
  _check(sim._particles().size() == 2 and a.direction == Vector2.LEFT and b.direction == Vector2.RIGHT, "Two antineutrinos should use the equal-mass fallback.")
  _new_board()
  a = _particle("proton", Vector2.RIGHT, Vector2.LEFT)
  b = _particle("electron", Vector2.LEFT)
  sim.step_simulation(2.0)
  _check(b.is_queued_for_deletion() and _at(a, Vector2.ZERO) and a.direction == Vector2.LEFT, "The lighter particle should be absorbed while the heavier particle continues on course.")
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

func _elastic_bounce() -> void:
  _new_board()
  var a := _particle("muon", Vector2.LEFT)
  var b := _particle("muon", Vector2.ZERO, Vector2.ZERO, 0.0)
  var radius := (a.world_collision_radius() + b.world_collision_radius()) / CELL
  var offset := radius * 0.5
  a.free_flight = true
  a.flight_cell = a.global_position
  a.global_position.y = offset * CELL
  var impact := Vector2(-sqrt(radius * radius - offset * offset), offset)
  var normal := impact.normalized()
  var velocity_b := normal * Vector2.RIGHT.dot(normal)
  var velocity_a := Vector2.RIGHT - velocity_b
  var remaining := -impact.x
  sim.step_simulation()
  _check((a.direction * a.speed - velocity_a).length() < 0.001 and (b.direction * b.speed - velocity_b).length() < 0.001, "A glancing bounce should exchange the normal velocities while retaining the tangential velocities.")
  _check(a.motion_position().distance_to((impact + velocity_a * remaining) * CELL) < 0.01 and b.motion_position().distance_to(velocity_b * remaining * CELL) < 0.01, "Bouncing particles should continue from their contact positions during the rest of the tick.")

func _muons_and_mass_speeds() -> void:
  var expected := {"photon": [0.0, 1.5], "neutrino": [0.0, 1.5], "anti_neutrino": [0.0, 1.5], "electron": [1.0, 1.0],
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
      var defaults := PARTICLES.instantiate(particle.flavour, particle.isAnti, particle.colour)
      _check(particle.speed == defaults.speed, "Reaction products should use their scene speed.")
      defaults.free()
    names.sort()
    _check(names == reaction[2], "Incorrect products for %s + %s: %s" % [reaction[0], reaction[1], names])
    sim.step_simulation(0.1)
    _check(sim._particles().size() == reaction[2].size(), "Reaction products should separate without immediately colliding.")

func _neutrino_reactions() -> void:
  var conversions := {
    "neutrino": {"electron": ["positron"], "positron": ["electron"], "up_g": ["down_g"], "down_b": ["up_b"],
      "muon": ["anti_muon"], "anti_muon": ["muon"], "proton": ["neutron"], "neutron": ["proton"],
      "delta_plus": ["positron", "proton"], "delta_minus": ["electron", "neutron"]},
    "anti_neutrino": {"electron": ["muon"], "positron": ["anti_muon"], "muon": ["electron"], "anti_muon": ["positron"],
      "up_r": ["up_g"], "up_g": ["up_b"], "down_b": ["down_r"], "pion_plus": ["pion_minus"], "pion_minus": ["pion_plus"]},
  }
  for name in conversions:
    for target in conversions[name]:
      _new_board()
      var other := _particle(target, Vector2.RIGHT, Vector2.LEFT)
      _particle(name, Vector2.LEFT)
      if other.is_pion():
        other.constituents = [Vector2i(other.constituents[0].x, Particle.ColourCharge.GREEN), Vector2i(other.constituents[1].x, Particle.ColourCharge.BLUE)]
      sim.step_simulation()
      var names: Array[String] = []
      for result in sim._particles():
        names.append(result.level_particle_name())
        if result.is_pion():
          var flipped := Particle.Flavour.DOWN if target == "pion_plus" else Particle.Flavour.UP
          _check(result.constituents == [Vector2i(flipped, Particle.ColourCharge.GREEN), Vector2i(flipped, Particle.ColourCharge.BLUE)], "Pion flips should preserve both original colours.")
      names.sort()
      _check(names == conversions[name][target], "Incorrect products for %s + %s: %s" % [name, target, names])
    _new_board()
    var neutrino := _particle(name, Vector2.LEFT)
    var photon := _particle("photon", Vector2.RIGHT, Vector2.LEFT)
    sim.step_simulation()
    _check(sim._particles().size() == 2 and _at(neutrino, Vector2.RIGHT * 0.5) and _at(photon, Vector2.LEFT * 0.5), "%s and photons should pass through one another." % name)
    var bounce_targets := ["pion_plus", "pion_minus", "pion_zero"] if name == "neutrino" else ["pion_zero"]
    for target in bounce_targets:
      _new_board()
      neutrino = _particle(name, Vector2.LEFT)
      var pion := _particle(target, Vector2.RIGHT, Vector2.LEFT)
      sim.step_simulation()
      _check(sim._particles().size() == 2 and neutrino.direction == Vector2.LEFT and _at(pion, Vector2.ZERO) and pion.direction == Vector2.LEFT, "%s should bounce without redirecting %s." % [name, target])

func _perpendicular_products() -> void:
  for reaction in [["electron", "positron", "photon"], ["neutrino", "neutrino", "anti_neutrino"], ["neutrino", "anti_neutrino", "photon"]]:
    _new_board()
    _particle(reaction[0], Vector2.LEFT)
    _particle(reaction[1], Vector2.UP, Vector2.DOWN)
    sim.step_simulation()
    var products := sim._particles()
    _check(products.size() == 2 and products.all(func(p: Particle) -> bool: return p.level_particle_name() == reaction[2]), "The perpendicular reaction should make two %s particles." % reaction[2])
    if products.size() == 2:
      _check(products[0].direction == -products[1].direction and is_zero_approx(products[0].direction.dot(Vector2.ONE)), "Products should travel perpendicular to the combined momentum.")

  _new_board()
  var a := _particle("neutrino", Vector2.ZERO)
  var b := _particle("neutrino", Vector2.ZERO, Vector2.ONE)
  var diagonal := Vector2.ONE.normalized()
  var contact := {"at": Vector2.ZERO, "velocity_a": Vector2.RIGHT * 1.5, "velocity_b": diagonal * 1.5}
  sim._perpendicular_reaction(a, b, contact, Particle.Flavour.NEUTRINO, true)
  var products := sim._particles()
  var heading := (Vector2.RIGHT + diagonal).orthogonal().normalized()
  var holder_cell := Vector2(0.0, signf(heading.y))
  var holder = _device("holder", holder_cell)
  var forecast := FORECAST.new(sim, [holder])
  sim.step_simulation(0.2)
  forecast.shadow.step_simulation(0.2)
  _check(_at(products[0], heading * 0.3) and _at(products[1], -heading * 0.3), "Perpendicular trajectories between grid headings should retain their angle and speed.")
  _check(_at(forecast.shadow._particles()[0], heading * 0.3), "Forecasts should preserve off-grid trajectories.")
  sim.step_simulation(0.3)
  _check(products[0].held_by == holder and _at(products[0], holder_cell), "Holders should catch a particle crossing on an off-grid trajectory.")
  forecast.dispose()

func _reflectors_and_neutrino_holders() -> void:
  for name in ["neutrino", "anti_neutrino"]:
    _new_board()
    var particle := _particle(name, Vector2.LEFT * 2.0)
    var gate = _device("gate", Vector2.LEFT)
    _device("reflector", Vector2.ZERO)
    var pusher = _device("pusher", Vector2.RIGHT)
    var holder = _device("holder", Vector2.RIGHT * 2.0)
    sim.step_simulation(3.0)
    _check(particle.held_by == holder and _at(particle, Vector2.RIGHT * 2.0) and not gate.gate_open and pusher.push_up, "%s should bypass other buildings and stop in the holder." % name)
    _particle("photon", Vector2.RIGHT * 3.0, Vector2.LEFT)
    sim.step_simulation(0.6)
    _check(holder.held_particle == particle, "Passing photons should leave the holder occupied.")
    _particle("electron", Vector2.RIGHT * 3.0, Vector2.LEFT)
    sim.step_simulation()
    var products := sim._particles().filter(func(p: Particle) -> bool: return p.flavour != Particle.Flavour.PHOTON)
    var result := "muon" if name == "anti_neutrino" else "positron"
    _check(holder.held_particle == null and products.size() == 1 and products[0].level_particle_name() == result and products[0].direction == Vector2.LEFT, "A reaction should release the holder and its product.")
  for name in ["photon", "pion_zero", "neutron", "electron", "pion_plus", "proton"]:
    for side in [Vector2.UP, Vector2.DOWN, Vector2.RIGHT]:
      _new_board()
      _device("reflector", Vector2.ZERO)
      var particle := _particle(name, side * 2.0, -side)
      sim.step_simulation(4.5)
      if particle.charge == 0:
        _check(not particle.is_queued_for_deletion() and particle.direction == side, "Reflectors should bounce neutral %s from %s." % [name, side])
      else:
        _check(particle.is_queued_for_deletion(), "Reflectors should destroy charged %s from %s." % [name, side])
  _new_board()
  _device("pusher", Vector2.ZERO)
  _device("reflector", Vector2.UP)
  var photon := _particle("photon", Vector2.LEFT)
  sim.step_simulation()
  _check(sim._particles().size() == 1 and photon.direction == Vector2.DOWN, "A photon pushed into a reflector should reflect on impact.")

func _muon_reaction_directions() -> void:
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

func _z_boson_bounces() -> void:
  for kind in ["wall", "edge_wall", "gate", "glass", "filter", "detector", "emitter", "reflector"]:
    _new_board()
    var device := _device(kind, Vector2.ZERO)
    if kind == "emitter": device.stop_sequence()
    if kind == "detector": device.accepted.assign(["z_boson"])
    var z := _particle("z_boson", Vector2.LEFT * 2.0)
    sim.step_simulation(4.5)
    _check(sim._particles() == [z] and z.direction == Vector2.LEFT, "A Z boson should bounce off a blocking " + kind + ".")
  _new_board()
  var gate := _device("gate", Vector2.ZERO, {"starts_open": true})
  var z := _particle("z_boson", Vector2.LEFT * 2.0)
  sim.step_simulation(3.0)
  _check(_at(z, Vector2.RIGHT) and not gate.gate_open, "A Z boson should pass through an open gate.")

  for name in ["proton", "photon", "neutrino", "z_boson"]:
    _new_board()
    z = _particle("z_boson", Vector2.RIGHT, Vector2.LEFT)
    var incoming := _particle(name, Vector2.LEFT)
    sim.step_simulation(2.0)
    _check(sim._particles().size() == 2 and z.direction == Vector2.RIGHT and incoming.direction == Vector2.LEFT and z.speed == 1.0, "A Z boson and %s should bounce off each other while the Z boson keeps its speed." % name)

func _w_boson_fields() -> void:
  for name in ["w_plus", "w_minus"]:
    var sign := -1.0 if name == "w_plus" else 1.0
    _new_board()
    var boson := _particle(name, Vector2.ZERO, Vector2.ZERO, 0.0)
    var photon := _particle("photon", Vector2(-1, 1))
    var outside := _particle("proton", Vector2(0, 2))
    var idle := _particle("electron", Vector2.UP, Vector2.ZERO, 0.0)
    var forecast := FORECAST.new(sim, [])
    sim.step_simulation(0.5)
    forecast.shadow.step_simulation(0.5)
    _check(sign * (photon.motion_position().y - CELL) > 0.0, name + " should bend a neutral particle's path.")
    _check(is_equal_approx(outside.motion_position().y, 2.0 * CELL), name + " should have no effect beyond 1.5 tiles.")
    _check(sign * (idle.motion_position().y + CELL) < 0.0, name + " should also move a particle that started at rest.")
    _check(_at(boson, Vector2.ZERO), name + " should never accelerate itself.")
    _check(forecast.shadow._particles()[1].motion_position().is_equal_approx(photon.motion_position()),
      "The forecast should apply the same W fields as the live board.")
    forecast.dispose()

    for other_name in ["electron", "z_boson", "w_plus"]:
      _new_board()
      boson = _particle(name, Vector2.ZERO, Vector2.ZERO, 0.0)
      var incoming := _particle(other_name, Vector2.LEFT, Vector2.RIGHT, 4.0)
      sim.step_simulation(0.5)
      _check(sim._particles().size() == 2 and incoming.motion_position().x > 0.0,
        "%s and %s should pass through each other." % [name, other_name])
    _new_board()
    _particle("gluon", Vector2.ZERO, Vector2.ZERO, 0.0)
    boson = _particle(name, Vector2.LEFT, Vector2.RIGHT, 4.0)
    sim.step_simulation(0.5)
    _check(sim._particles().size() == 2 and boson.motion_position().x > 0.0 and not is_instance_valid(boson.trapped_by),
      name + " should pass through a gluon tip without getting caught.")

    for neutrino_name in ["neutrino", "anti_neutrino"]:
      _new_board()
      _particle(name, Vector2.ZERO)
      _particle(neutrino_name, Vector2.RIGHT, Vector2.LEFT)
      sim.step_simulation()
      var products := sim._particles()
      var flipped := "w_minus" if name == "w_plus" else "w_plus"
      var expected := flipped if neutrino_name == "neutrino" else "z_boson"
      _check(products.size() == 1 and products[0].level_particle_name() == expected,
        "%s should convert %s to %s." % [neutrino_name, name, expected])
      if products.size() == 1:
        _check(products[0].direction == Vector2.RIGHT and is_equal_approx(products[0].speed, 1.0) and _at(products[0], Vector2.RIGHT),
          "A converted W should keep its direction and speed and continue through the tick.")

func _gluon_buildings() -> void:
  for kind in ["wall", "edge_wall", "filter", "gate", "detector", "emitter"]:
    _new_board()
    var device := _device(kind, Vector2.ZERO)
    if kind == "emitter": device.stop_sequence()
    var gluon := _particle("gluon", Vector2.LEFT * 2.0) as BOSON
    sim.step_simulation(2.0)
    _check(gluon.is_queued_for_deletion(), "A gluon should be blocked by a " + kind + ".")

  _new_board()
  _device("glass", Vector2.ZERO)
  var gluon := _particle("gluon", Vector2.LEFT) as BOSON
  sim.step_simulation()
  _check(gluon.mass == 0.0 and gluon.speed == 2.0 and _at(gluon, Vector2.ZERO), "A mass-zero gluon should travel at two tiles per tick and pause in glass.")
  sim.step_simulation(0.5)
  _check(_at(gluon, Vector2.RIGHT), "A gluon should resume speed after glass.")

  _new_board()
  _device("pusher", Vector2.ZERO)
  gluon = _particle("gluon", Vector2.LEFT) as BOSON
  sim.step_simulation()
  _check(_at(gluon, Vector2(1, -1)) and gluon.trail_points.size() == 4, "A pusher should shift the tip and leave both bends in the trail.")
  var probe := _particle("neutrino", Vector2(10, 10))
  _check(not gluon.sweep_trail(probe, Vector2(0.0, -0.5) * CELL, Vector2.ZERO).is_empty()
    and gluon.sweep_trail(probe, Vector2(-0.55, -0.7) * CELL, Vector2.ZERO).is_empty(), "Only the actual bent gluon trail should trap particles.")

  _new_board()
  _device("reflector", Vector2.ZERO)
  gluon = _particle("gluon", Vector2.UP * 2.0, Vector2.DOWN) as BOSON
  sim.step_simulation(1.5)
  _check(_at(gluon, Vector2.UP) and gluon.direction == Vector2.UP and gluon.trail_points.size() == 3, "A reflector should bounce the neutral tip and retain its path up to the reflection.")

  _new_board()
  var holder := _device("holder", Vector2.ZERO)
  gluon = _particle("gluon", Vector2.LEFT) as BOSON
  sim.step_simulation(2.0)
  _check(holder.held_particle == gluon and _at(gluon, Vector2.ZERO), "A Holder should stop a gluon tip.")

  _new_board()
  _device("wall", Vector2.RIGHT * 5.0)
  gluon = _particle("gluon", Vector2.ZERO) as BOSON
  sim.step_simulation()
  var captive := _particle("electron", Vector2(1, -1), Vector2.DOWN)
  sim.step_simulation(0.8)
  _check(captive.trapped_by == gluon, "The trail should catch a particle before it hits a wall.")
  sim.step_simulation(0.8)
  _check(gluon.is_queued_for_deletion() and captive.trapped_by == null and not captive.is_queued_for_deletion(), "A destroyed gluon should release its trapped particle.")

func _gluon_blocks() -> void:
  _new_board()
  var a := _particle("gluon", Vector2.LEFT * 2.0) as BOSON
  var b := _particle("gluon", Vector2.RIGHT * 2.0, Vector2.LEFT) as BOSON
  sim.step_simulation(2.0)
  _check(a.blocked_by == b and b.blocked_by == a and a.caught.is_empty() and b.caught.is_empty(), "Head-on gluon tips should block each other without trapping each other.")
  _check(is_equal_approx(a.motion_position().distance_to(b.motion_position()), a.world_collision_radius() + b.world_collision_radius()), "A gluon tip should stop where its hitbox meets the other tip.")
  var forecast := FORECAST.new(sim, [])
  forecast.shadow.step_simulation()
  var shadow_a := forecast.shadow._particles()[0] as BOSON
  _check(shadow_a.blocked_by == forecast.shadow._particles()[1] and shadow_a.motion_position().is_equal_approx(a.motion_position()), "Forecasts should preserve blocked tips.")
  forecast.dispose()

  _new_board()
  a = _particle("gluon", Vector2.ZERO) as BOSON
  sim.step_simulation(2.0)
  b = _particle("gluon", Vector2(2, -2), Vector2.DOWN) as BOSON
  sim.step_simulation(2.0)
  _check(b.blocked_by == a and a.blocked_by == null and b.motion_position().y < 0.0 and _at(a, Vector2.RIGHT * 8.0), "A gluon should stop at another gluon's laid trail while the leading tip continues.")

func _gluon_trap() -> void:
  _new_board()
  sim.level_bounds_enabled = true
  sim.level_bounds = Rect2(-Vector2.ONE * CELL * 2.0, Vector2(10.0, 4.0) * CELL)
  var gluon := _particle("gluon", Vector2.ZERO) as BOSON
  sim.step_simulation(3.0)
  _check(_at(gluon, Vector2.RIGHT * 6.0) and gluon.caught.is_empty(), "A gluon should leave its trail at two tiles per tick.")
  var electron := _particle("electron", Vector2(2, -1), Vector2.DOWN)
  sim.step_simulation(2.0)
  _check(gluon.caught == [electron] and electron.trapped_by == gluon and gluon.edge_stopped, "The old trail should catch a particle and persist at the board edge.")
  var held_position := electron.motion_position()
  sim.step_simulation(0.2)
  _check(electron.motion_position() == held_position, "One captive should stay where it touched the trail.")
  var positron := _particle("positron", Vector2(5, 1), Vector2.UP)
  sim.step_simulation(0.67)
  _check(gluon.caught == [electron, positron], "The second particle should join the trap.")
  var tip_position := gluon.motion_position()
  var prior_electron := electron.motion_position()
  var prior_positron := positron.motion_position()
  var forecast := FORECAST.new(sim, [])
  sim.step_simulation(0.2)
  forecast.shadow.step_simulation(0.2)
  var shadow_trail := forecast.shadow._particles()[0] as BOSON
  _check(is_equal_approx(electron.motion_position().distance_to(prior_electron), 0.6 * CELL)
    and is_equal_approx(positron.motion_position().distance_to(prior_positron), 0.6 * CELL)
    and gluon.motion_position() == tip_position, "The gluon should stop and pull both particles at three tiles per tick.")
  _check(shadow_trail.caught.size() == 2 and shadow_trail.caught[0].motion_position().is_equal_approx(electron.motion_position()), "The forecast should copy a contracting gluon trail.")
  sim.step_simulation(0.6)
  forecast.shadow.step_simulation(0.6)
  for simulation in [sim, forecast.shadow]:
    var products: Array[Particle] = simulation._particles()
    _check(products.size() == 2 and products.all(func(p: Particle) -> bool: return p.flavour == Particle.Flavour.PHOTON), "A captured electron and positron should react normally and annihilate the gluon.")
  forecast.dispose()

func _gluon_trail_bounces_and_releases() -> void:
  _new_board()
  var gluon := _particle("gluon", Vector2.ZERO) as BOSON
  sim.step_simulation(3.0)
  var z := _particle("z_boson", Vector2(2, -1), Vector2.DOWN)
  sim.step_simulation(2.0)
  _check(z.direction == Vector2.UP and gluon.caught.is_empty(), "A Z boson should reflect from the gluon trail.")
  var first := _particle("photon", Vector2(1, -1), Vector2.DOWN)
  var second := _particle("photon", Vector2(4, 1), Vector2.UP)
  sim.step_simulation(1.2)
  _check(gluon.is_queued_for_deletion() and first.trapped_by == null and second.trapped_by == null and sim._particles().size() == 3,
    "The gluon should release both particles after contact even when their normal interaction is pass-through.")

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
  _pusher_contacts()
  _rails_and_forecast()
  _reactions()
  _mass_and_split()
  _elastic_bounce()
  _muons_and_mass_speeds()
  _neutrino_reactions()
  _perpendicular_products()
  _reflectors_and_neutrino_holders()
  _muon_reaction_directions()
  _z_boson_bounces()
  _w_boson_fields()
  _gluon_buildings()
  _gluon_blocks()
  _gluon_trap()
  _gluon_trail_bounces_and_releases()
  if is_instance_valid(sim): sim.free()
  if failures == 0: print("Grid mechanics checks passed")
  quit(int(failures > 0))

