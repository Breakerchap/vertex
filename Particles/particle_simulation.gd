class_name ParticleSimulation
extends Node2D

signal particle_detected(particle_name: String)
signal simulation_stepped(steps: float)
signal particle_event(kind: String, at: Vector2)

const PARTICLES = preload("res://Particles/particle_catalog.gd")
const RAILS = preload("res://Buildings/GridDevices/rail_network.gd")
const EPSILON := 0.000001

@export var running := true
@export_range(0.25, 4.0, 0.25) var simulation_speed := 1.0

var _accumulated_time := 0.0
var _pending_ticks := 0
var _step_phase := 0.0
var _ticks_into_step := 0
var pause_requested := false
var level_bounds_enabled := false
var level_bounds: Rect2

func _physics_process(delta: float) -> void:
  var tick_duration := 1.0 / float(Engine.physics_ticks_per_second)
  if not running:
    if _pending_ticks > 0:
      _pending_ticks -= 1
      step_simulation(SimulationGrid.TICK)
    return
  _pending_ticks = 0
  _accumulated_time += delta * maxf(get_playback_speed(), 0.0)
  while running and _accumulated_time + EPSILON >= tick_duration:
    _accumulated_time = maxf(0.0, _accumulated_time - tick_duration)
    var amount := SimulationGrid.TICK
    if pause_requested and _ticks_into_step == SimulationGrid.GRID_TICKS_PER_STEP - 1:
      amount = minf(amount, 1.0 - _step_phase)
    step_simulation(amount)
    if pause_requested and _step_phase == 0.0 and _ticks_into_step == 0:
      running = false
      pause_requested = false
      _accumulated_time = 0.0

func get_playback_speed() -> float:
  return simulation_speed

func set_playback_speed(speed: float) -> void:
  simulation_speed = speed

func request_steps(count: int) -> void:
  running = false
  _accumulated_time = 0.0
  _pending_ticks += maxi(count, 0) * SimulationGrid.TICKS_PER_STEP

func cancel_pending_steps() -> void:
  _pending_ticks = 0
  pause_requested = false

func reset_step_clock() -> void:
  _step_phase = 0.0
  _ticks_into_step = 0
  _accumulated_time = 0.0

## Advance time in simulation steps, resolving contacts at least once per tick.
func step_simulation(steps: float = 1.0) -> void:
  assert(steps >= 0.0, "Simulation time cannot be negative")
  while steps > EPSILON:
    var time := minf(steps, minf(SimulationGrid.TICK, 1.0 - _step_phase))
    _simulate_tick(time)
    steps -= time

func _simulate_tick(time: float) -> void:
  var buildings := _active_descendants("grid_buildings")
  var obstacles := _active_descendants("particle_mirrors")
  obstacles.append_array(_active_descendants("particle_blockers"))
  var tiles := {}
  var rails: Array[Node] = []
  var riders: Array[Node] = []
  for building in buildings:
    match building.get_meta("grid_layer", "building"):
      "rail": rails.append(building)
      "edge_wall": pass
      _:
        riders.append(building)
        tiles[building.global_position] = building

  for emitter in _active_descendants("particle_emitters"):
    emitter.step_emission(time / SimulationGrid.GRID_TICKS_PER_STEP)
  var particles := _particles()
  var paths := {}
  var terminal_hits := {}
  for particle in particles:
    for i in range(particle.separating_from.size() - 1, -1, -1):
      var partner := particle.separating_from[i]
      if not is_instance_valid(partner) or not _circles_overlap(particle, partner):
        particle.separating_from.remove_at(i)
  for particle in particles:
    paths[particle] = _advance_particle(particle, time, obstacles, tiles, terminal_hits)
  _resolve_particle_contacts(particles, paths, terminal_hits)
  for particle in particles:
    if particle.is_queued_for_deletion(): continue
    if terminal_hits.has(particle):
      _absorb_at_building(particle, terminal_hits[particle])
      continue
    if level_bounds_enabled and not level_bounds.has_point(particle.motion_position()):
      particle_event.emit("exit", particle.motion_position())
      particle.queue_free()

  _step_phase += time
  if _step_phase >= 1.0 - EPSILON:
    _step_phase = 0.0
    _ticks_into_step = (_ticks_into_step + 1) % SimulationGrid.GRID_TICKS_PER_STEP
    if not rails.is_empty():
      RAILS.advance(rails, riders)
      for particle in particles:
        if is_instance_valid(particle.held_by) and not particle.is_queued_for_deletion():
          particle.global_position = particle.held_by.global_position
  simulation_stepped.emit(time / SimulationGrid.GRID_TICKS_PER_STEP)

func _advance_particle(particle: Particle, time: float, obstacles: Array[Node], tiles: Dictionary, terminal_hits: Dictionary) -> Array[Dictionary]:
  var path: Array[Dictionary] = []
  particle.global_position = SimulationGrid.center(particle.global_position)
  var used := 0.0
  while time - used > EPSILON:
    var from := particle.motion_position()
    if particle.glass_wait > EPSILON:
      var wait := minf(time - used, particle.glass_wait)
      path.append({"from": from, "to": from, "start": used, "end": used + wait})
      particle.glass_wait -= wait
      used += wait
      continue
    var pace := particle.speed
    if is_instance_valid(particle.held_by):
      pace = 0.0
    if pace <= EPSILON or particle.direction.is_zero_approx():
      path.append({"from": from, "to": from, "start": used, "end": time})
      break

    var in_field := not particle.magnetic_exit.is_zero_approx()
    var destination := SimulationGrid.center(particle.global_position + particle.direction * SimulationGrid.CELL)
    var segment_end := 1.0
    if not in_field and particle.charge != 0 and particle.progress <= 0.5 + EPSILON:
      var field = tiles.get(destination)
      if field != null and field.is_in_group("magnetic_fields"):
        if particle.progress >= 0.5 - EPSILON:
          particle.global_position = destination
          particle.magnetic_exit = field.exit_heading(particle.direction, particle.charge)
          particle.progress = 0.0
          particle_event.emit("field", from)
          continue
        segment_end = 0.5

    var travel := particle.travel_vector()
    var progress_per_tick := pace * SimulationGrid.CELL / travel.length()
    var duration := minf(time - used, (segment_end - particle.progress) / progress_per_tick)
    var motion := travel * (progress_per_tick * duration)
    var hit := _building_impact(particle, from, motion, obstacles)
    if not hit.is_empty():
      var hit_time: float = duration * hit.fraction
      var point := from + motion * float(hit.fraction)
      path.append({"from": from, "to": point, "start": used, "end": used + hit_time})
      if not hit.reflective:
        terminal_hits[particle] = hit
        return path
      particle.global_position = SimulationGrid.center(point)
      particle.direction = particle.direction.bounce(hit.normal)
      particle.progress = 0.0
      particle.source_building = null
      particle.passed_gates.clear()
      used += hit_time
      continue

    path.append({"from": from, "to": from + motion, "start": used, "end": used + duration})
    used += duration
    particle.progress += progress_per_tick * duration
    if in_field and particle.progress >= 1.0 - EPSILON:
      particle.direction = particle.magnetic_exit
      particle.magnetic_exit = Vector2.ZERO
      # The exit is already half a tile along the outbound grid line.
      particle.progress = 0.5
      particle.source_building = null
      particle.passed_gates.clear()
    elif particle.progress >= 1.0 - EPSILON:
      particle.global_position = destination
      particle.progress = 0.0
      particle.source_building = null
      particle.passed_gates.clear()
      var terminal_hit := _enter_tile(particle, tiles, obstacles)
      if not terminal_hit.is_empty():
        terminal_hits[particle] = terminal_hit
        return path
  particle.update_motion_offset()
  return path

func _building_impact(particle: Particle, from: Vector2, motion: Vector2, obstacles: Array[Node], allow_reflection := true) -> Dictionary:
  while true:
    var hit := {}
    var target: Node
    for obstacle in obstacles:
      if obstacle == particle.source_building: continue
      var candidate: Dictionary
      if obstacle.has_method("sweep_for"):
        candidate = obstacle.sweep_for(particle, from, motion)
      elif particle.flavour == Particle.Flavour.PHOTON and obstacle.has_method("sweep_photon"):
        candidate = obstacle.sweep_photon(from, motion, particle.world_collision_radius())
      else:
        candidate = obstacle.sweep(from, motion, particle.world_collision_radius())
      if not candidate.is_empty() and (hit.is_empty() or candidate.fraction < hit.fraction):
        hit = candidate
        target = obstacle
    if hit.is_empty(): return {}
    var at := from + motion * float(hit.fraction)
    if target.get_meta("device", "") == "gate":
      if target.hit_gate(particle, from, motion): continue
    if allow_reflection and particle.flavour == Particle.Flavour.PHOTON and hit.reflective:
      particle_event.emit("reflection", at)
      return hit
    hit.reflective = false
    hit.at = at
    hit.target = target
    return hit
  return {}

func _absorb_at_building(particle: Particle, hit: Dictionary) -> void:
  if hit.target.has_method("accepts") and hit.target.accepts(particle):
    particle_event.emit("detection", hit.at)
    particle_detected.emit(particle.level_particle_name())
  else:
    particle_event.emit("absorption", hit.at)
  particle.queue_free()

func _enter_tile(particle: Particle, tiles: Dictionary, obstacles: Array[Node], pushed := false) -> Dictionary:
  var tile = tiles.get(particle.global_position)
  if tile == null: return {}
  if tile.is_in_group("magnetic_fields") and particle.charge != 0:
    particle.direction = tile.exit_heading(particle.direction, particle.charge)
    particle_event.emit("field", particle.global_position)
  match tile.get_meta("device", ""):
    "glass":
      if particle.is_small() and particle.speed > EPSILON:
        particle.glass_wait = 1.0 / particle.speed
    "holder":
      if not is_instance_valid(tile.held_particle) or tile.held_particle.is_queued_for_deletion():
        tile.held_particle = particle
        particle.held_by = tile
    "pusher":
      if pushed: return {}
      var shift: Vector2 = tile.next_push()
      var hit := _building_impact(particle, particle.global_position, shift, obstacles, false)
      if not hit.is_empty(): return hit
      particle.global_position = SimulationGrid.center(particle.global_position + shift)
      return _enter_tile(particle, tiles, obstacles, true)
  return {}

func _resolve_particle_contacts(particles: Array[Particle], paths: Dictionary, terminal_hits: Dictionary) -> void:
  var contacts: Array[Dictionary] = []
  for i in range(particles.size()):
    var a := particles[i]
    if a.is_queued_for_deletion(): continue
    for j in range(i + 1, particles.size()):
      var b := particles[j]
      if b in a.separating_from: continue
      if a.flavour == Particle.Flavour.ELECTRON and b.flavour == Particle.Flavour.ELECTRON and a.isAnti == b.isAnti:
        continue
      var contact := _first_contact(a, b, paths[a], paths[b])
      if not contact.is_empty():
        contact.a = a
        contact.b = b
        contacts.append(contact)
  contacts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.time < b.time)
  var redirected := {}
  for contact in contacts:
    var a: Particle = contact.a
    var b: Particle = contact.b
    if a.is_queued_for_deletion() or b.is_queued_for_deletion() or redirected.has(a) or redirected.has(b):
      continue
    if a.flavour == b.flavour and a.isAnti != b.isAnti:
      _annihilate(a, b, contact.at, contact.velocity_a - contact.velocity_b)
      continue
    var photon := a if a.flavour == Particle.Flavour.PHOTON else b
    var other := b if photon == a else a
    if photon.flavour == Particle.Flavour.PHOTON and other.is_pion():
      var incoming: Vector2 = contact.velocity_a if photon == a else contact.velocity_b
      _split_pion(other, photon, contact.at, incoming)
      continue
    if _can_bind(a, b):
      var participants: Array[Particle] = [a, b]
      var momentum: Vector2 = a.mass * contact.velocity_a + b.mass * contact.velocity_b
      if a.is_quark() and b.is_quark():
        for c in particles:
          if c == a or c == b or c.is_queued_for_deletion() or redirected.has(c): continue
          if not c.is_quark() or not _can_bind(a, c) or not _can_bind(b, c): continue
          var leg := _touching_leg(c, paths[c], a, paths[a], b, paths[b], contact.time)
          if not leg.is_empty():
            participants.append(c)
            momentum += c.mass * _leg_velocity(leg)
            break
      _bind_quarks(participants, contact.at, momentum)
      continue
    if a.mass == b.mass:
      _bounce(a, b, contact)
      redirected[a] = true
      redirected[b] = true
      terminal_hits.erase(a)
      terminal_hits.erase(b)
      continue

    var lighter := a if a.mass < b.mass else b
    var heavier := b if lighter == a else a
    if is_instance_valid(heavier.held_by):
      var velocity: Vector2 = contact.velocity_a if lighter == a else contact.velocity_b
      _redirect_particle(heavier, heavier.global_position, velocity * lighter.mass / heavier.mass)
      redirected[heavier] = true
      terminal_hits.erase(heavier)
    _release_holder(lighter)
    lighter.queue_free()
    particle_event.emit("absorption", contact.at)

func _can_bind(a: Particle, b: Particle) -> bool:
  if b.is_quark() and a.is_pion(): return _can_bind(b, a)
  if not a.is_quark() or a.isAnti: return false
  if b.is_pion():
    return not b.constituents.any(func(quark: Vector2i) -> bool: return quark.y == a.colour)
  return b.is_quark() and not b.isAnti and a.colour != b.colour

func _circles_overlap(a: Particle, b: Particle) -> bool:
  var radius := a.world_collision_radius() + b.world_collision_radius()
  return a.motion_position().distance_squared_to(b.motion_position()) <= radius * radius

func _leg_velocity(leg: Dictionary) -> Vector2:
  var duration: float = leg.end - leg.start
  if duration <= EPSILON: return Vector2.ZERO
  var travel: Vector2 = leg.to - leg.from
  return travel / (SimulationGrid.CELL * duration)

func _first_contact(a: Particle, b: Particle, a_path: Array, b_path: Array) -> Dictionary:
  var radius := a.world_collision_radius() + b.world_collision_radius()
  for leg_a in a_path:
    for leg_b in b_path:
      var start := maxf(leg_a.start, leg_b.start)
      var end := minf(leg_a.end, leg_b.end)
      if end < start: continue
      var a_start := _position_on_leg(leg_a, start)
      var b_start := _position_on_leg(leg_b, start)
      var relative := a_start - b_start
      var motion := _position_on_leg(leg_a, end) - _position_on_leg(leg_b, end) - relative
      if motion.length_squared() <= EPSILON or relative.dot(motion) > EPSILON: continue
      var c := relative.length_squared() - radius * radius
      var fraction := 0.0
      if c > EPSILON:
        var squared := motion.length_squared()
        var projection := relative.dot(motion)
        var discriminant := projection * projection - squared * c
        if squared <= EPSILON or discriminant < 0.0: continue
        fraction = (-projection - sqrt(discriminant)) / squared
        if fraction < 0.0 or fraction > 1.0: continue
      var time := lerpf(start, end, fraction)
      var at_a := _position_on_leg(leg_a, time)
      var at_b := _position_on_leg(leg_b, time)
      return {"time": time, "at": (at_a + at_b) * 0.5, "at_a": at_a, "at_b": at_b,
        "velocity_a": _leg_velocity(leg_a), "velocity_b": _leg_velocity(leg_b)}
  return {}

func _position_on_leg(leg: Dictionary, time: float) -> Vector2:
  if leg.end <= leg.start: return leg.to
  return leg.from.lerp(leg.to, clampf(inverse_lerp(leg.start, leg.end, time), 0.0, 1.0))

func _touching_leg(c: Particle, c_path: Array, a: Particle, a_path: Array, b: Particle, b_path: Array, time: float) -> Dictionary:
  for leg in c_path:
    if time < leg.start - EPSILON or time > leg.end + EPSILON: continue
    var at := _position_on_leg(leg, time)
    if _overlaps_at(at, c.world_collision_radius(), a, a_path, time) or _overlaps_at(at, c.world_collision_radius(), b, b_path, time):
      return leg
  return {}

func _overlaps_at(at: Vector2, radius: float, particle: Particle, path: Array, time: float) -> bool:
  for leg in path:
    if time < leg.start - EPSILON or time > leg.end + EPSILON: continue
    if at.distance_to(_position_on_leg(leg, time)) <= radius + particle.world_collision_radius() + EPSILON:
      return true
  return false

func _release_holder(particle: Particle) -> void:
  if is_instance_valid(particle.held_by):
    if particle.held_by.get("held_particle") == particle:
      particle.held_by.set("held_particle", null)
    particle.held_by = null

func _redirect_particle(particle: Particle, at: Vector2, velocity: Vector2) -> void:
  _release_holder(particle)
  particle.global_position = SimulationGrid.center(at)
  particle.direction = velocity
  particle.speed = velocity.length()
  particle.progress = 0.0
  particle.magnetic_exit = Vector2.ZERO
  particle.glass_wait = 0.0
  particle.update_motion_offset()

func _keep_separating(a: Particle, b: Particle) -> void:
  a.separating_from.append(b)
  b.separating_from.append(a)

func _bounce(a: Particle, b: Particle, contact: Dictionary) -> void:
  var velocity_a: Vector2 = contact.velocity_a
  var velocity_b: Vector2 = contact.velocity_b
  var relative := velocity_a - velocity_b
  var separation: Vector2 = contact.at_a - contact.at_b
  if a.is_quark() and b.is_quark() and a.colour == b.colour:
    var combined := velocity_a + velocity_b
    var perpendicular := (relative if combined.is_zero_approx() else combined).orthogonal().normalized()
    if perpendicular.dot(separation) < 0.0: perpendicular = -perpendicular
    var rebound_speed := (velocity_a.length() + velocity_b.length()) * 0.5
    velocity_a = perpendicular * rebound_speed
    velocity_b = -velocity_a
  else:
    var normal := (relative if separation.is_zero_approx() else separation).normalized()
    var exchange := relative.dot(normal) * normal
    velocity_a -= exchange
    velocity_b += exchange
  _redirect_particle(a, contact.at_a, velocity_a)
  _redirect_particle(b, contact.at_b, velocity_b)
  _keep_separating(a, b)
  particle_event.emit("reflection", contact.at)

func _bind_quarks(participants: Array[Particle], at: Vector2, momentum: Vector2) -> void:
  var constituents: Array[Vector2i] = []
  for particle in participants:
    if particle.is_pion():
      constituents.append_array(particle.constituents)
    else:
      constituents.append(Vector2i(particle.flavour, particle.colour))
    if is_instance_valid(particle.held_by): at = particle.global_position
    _release_holder(particle)
    particle.queue_free()
  var ups := 0
  for quark in constituents:
    if quark.x == Particle.Flavour.UP: ups += 1
  var pions := [Particle.Flavour.PION_MINUS, Particle.Flavour.PION_ZERO, Particle.Flavour.PION_PLUS]
  var baryons := [Particle.Flavour.DELTA_MINUS, Particle.Flavour.NEUTRON, Particle.Flavour.PROTON, Particle.Flavour.DELTA_PLUS]
  var result := PARTICLES.instantiate(pions[ups] if constituents.size() == 2 else baryons[ups])
  result.constituents = constituents
  result.direction = momentum
  result.speed = momentum.length() / result.mass
  result.position = to_local(SimulationGrid.center(at))
  add_child(result)
  particle_event.emit("fusion", result.global_position)

func _split_pion(pion: Particle, photon: Particle, at: Vector2, incoming: Vector2) -> void:
  if is_instance_valid(pion.held_by): at = pion.global_position
  _release_holder(pion)
  _release_holder(photon)
  var axis := (photon.direction if incoming.is_zero_approx() else incoming).orthogonal()
  var quarks: Array[Particle] = []
  for constituent in pion.constituents:
    var quark := PARTICLES.instantiate(constituent.x, false, constituent.y)
    quark.direction = axis
    axis = -axis
    quark.position = to_local(SimulationGrid.center(at))
    add_child(quark)
    quarks.append(quark)
  _keep_separating(quarks[0], quarks[1])
  particle_event.emit("fusion", at)
  pion.queue_free()
  photon.queue_free()

func _annihilate(a: Particle, b: Particle, at: Vector2, relative: Vector2) -> void:
  _release_holder(a)
  _release_holder(b)
  particle_event.emit("annihilation", at)
  if relative.is_zero_approx(): relative = a.direction
  if relative.is_zero_approx(): relative = Vector2.RIGHT
  var photons: Array[Particle] = []
  for travel in [relative.orthogonal(), -relative.orthogonal()]:
    var photon := PARTICLES.instantiate(Particle.Flavour.PHOTON)
    photon.direction = travel
    photon.position = to_local(SimulationGrid.center(at))
    add_child(photon)
    photons.append(photon)
  _keep_separating(photons[0], photons[1])
  a.queue_free()
  b.queue_free()

func _active_descendants(group: StringName) -> Array[Node]:
  var result: Array[Node] = []
  for node in get_tree().get_nodes_in_group(group):
    if is_ancestor_of(node) and not node.is_queued_for_deletion():
      result.append(node)
  return result

func _particles() -> Array[Particle]:
  var result: Array[Particle] = []
  for child in get_children():
    if child is Particle and not child.is_queued_for_deletion():
      result.append(child)
  return result
