class_name ParticleSimulation
extends Node2D

signal particle_detected(particle_name: String)
signal simulation_stepped(steps: float)
signal particle_event(kind: String, at: Vector2)

const PARTICLES = preload("res://Particles/particle_catalog.gd")
const BOSON = preload("res://Particles/Boson/boson.gd")
const RAILS = preload("res://Buildings/GridDevices/rail_network.gd")
const EPSILON := 0.000001
const QUARK_COLOURS := [Particle.ColourCharge.RED, Particle.ColourCharge.GREEN, Particle.ColourCharge.BLUE]

@export var running := true
@export_range(0.25, 4.0, 0.25) var simulation_speed := 1.0

var _accumulated_time := 0.0
var _pending_ticks := 0
var _step_phase := 0.0
var _ticks_into_step := 0
var pause_requested := false
var level_bounds_enabled := false
var level_bounds: Rect2
var track_particle_paths := false

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
  var obstacles := _active_descendants("particle_blockers")
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
  var pulled_contacts := _advance_gluons(particles, time, obstacles, tiles)
  for particle in particles:
    for i in range(particle.separating_from.size() - 1, -1, -1):
      var partner := particle.separating_from[i]
      if not is_instance_valid(partner) or not _circles_overlap(particle, partner):
        particle.separating_from.remove_at(i)
  for particle in particles:
    if particle.flavour != Particle.Flavour.GLUON and not is_instance_valid(particle.trapped_by):
      paths[particle] = _advance_particle(particle, time, obstacles, tiles, terminal_hits)
  var rebounds := _resolve_particle_contacts(particles, paths, terminal_hits, pulled_contacts)
  if track_particle_paths:
    for particle in paths:
      _report_particle_path(particle, paths[particle], rebounds.get(particle, time))
  while true:
    var completed_pulls := _finish_motion(rebounds, terminal_hits, time, obstacles, tiles)
    if completed_pulls.is_empty(): break
    terminal_hits.clear()
    rebounds = _resolve_particle_contacts([], {}, terminal_hits, completed_pulls)
  for particle in particles:
    if particle.is_queued_for_deletion() or particle.flavour == Particle.Flavour.GLUON or is_instance_valid(particle.trapped_by): continue
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
          if particle.free_flight: particle.flight_cell = particle.global_position
          if particle.flavour == Particle.Flavour.GLUON:
            (particle as BOSON).record_path([], 0.0)
  simulation_stepped.emit(time / SimulationGrid.GRID_TICKS_PER_STEP)

func _advance_gluons(particles: Array[Particle], time: float, obstacles: Array[Node], tiles: Dictionary) -> Array[Dictionary]:
  var gluons: Array[BOSON] = []
  var pulls: Array[Dictionary] = []
  for particle in particles:
    if particle.flavour != Particle.Flavour.GLUON: continue
    var gluon := particle as BOSON
    gluon.prune_captives()
    var pull := _pull_captives(gluon, time)
    if not pull.is_empty(): pulls.append(pull)
    gluons.append(gluon)
    obstacles.append(gluon)
  if gluons.is_empty(): return pulls

  # Keep the previous trail geometry stable while sweeping all moving tips.
  var paths := {}
  var hits := {}
  for gluon in gluons:
    if gluon.caught.size() == 2: continue
    if gluon.edge_stopped or (is_instance_valid(gluon.blocked_by) and not gluon.blocked_by.is_queued_for_deletion()):
      var at := gluon.motion_position()
      paths[gluon] = [{"from": at, "to": at, "start": 0.0, "end": time}]
    else:
      gluon.blocked_by = null
      paths[gluon] = _advance_particle(gluon, time, obstacles, tiles, hits)

  var stopped := _block_gluon_tips(gluons, paths, hits)
  for gluon in gluons:
    if not paths.has(gluon): continue
    if track_particle_paths: _report_particle_path(gluon, paths[gluon], stopped.get(gluon, time))
    if hits.has(gluon):
      var hit: Dictionary = hits[gluon]
      if hit.has("edge"):
        _redirect_particle(gluon, hit.at, gluon.direction)
        gluon.edge_stopped = true
      elif hit.target is BOSON:
        _stop_gluon(gluon, hit.target, hit.at, gluon.direction)
      else:
        gluon.release_captives()
        _absorb_at_building(gluon, hit)
        continue
    gluon.record_path(paths[gluon], float(stopped.get(gluon, time)))
  return pulls

func _pull_captives(gluon: BOSON, time: float) -> Dictionary:
  if not track_particle_paths or gluon.caught.size() != 2: return gluon.pull_pair(time)
  var starts: Array[Vector2] = []
  for particle in gluon.caught: starts.append(particle.global_position)
  var contact := gluon.pull_pair(time)
  for i in range(starts.size()):
    var particle := gluon.caught[i]
    var path: Array[Dictionary] = [{"from": starts[i], "to": particle.global_position, "start": 0.0, "end": time}]
    _report_particle_path(particle, path, time)
  return contact

func _report_particle_path(_particle: Particle, _path: Array[Dictionary], _until: float) -> void:
  pass

func _block_gluon_tips(gluons: Array[BOSON], paths: Dictionary, hits: Dictionary) -> Dictionary:
  var contacts: Array[Dictionary] = []
  for i in range(gluons.size()):
    var a := gluons[i]
    if not paths.has(a): continue
    for j in range(i + 1, gluons.size()):
      var b := gluons[j]
      if not paths.has(b): continue
      var contact := _first_contact(a, b, paths[a], paths[b])
      if not contact.is_empty():
        contact.a = a
        contact.b = b
        contacts.append(contact)
  contacts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.time < b.time)
  var stopped := {}
  for contact in contacts:
    var a: BOSON = contact.a
    var b: BOSON = contact.b
    if stopped.has(a) or stopped.has(b): continue
    _stop_gluon(a, b, contact.at_a, contact.velocity_a)
    _stop_gluon(b, a, contact.at_b, contact.velocity_b)
    stopped[a] = contact.time
    stopped[b] = contact.time
    hits.erase(a)
    hits.erase(b)
  return stopped

func _stop_gluon(gluon: BOSON, blocker: BOSON, at: Vector2, heading: Vector2) -> void:
  _redirect_particle(gluon, at, gluon.direction if heading.is_zero_approx() else heading)
  if not is_instance_valid(gluon.blocked_by): gluon.blocked_by = blocker

func _finish_motion(rebounds: Dictionary, terminal_hits: Dictionary, time: float, obstacles: Array[Node], tiles: Dictionary) -> Array[Dictionary]:
  for particle in rebounds:
    if particle.is_queued_for_deletion(): continue
    var from := float(rebounds[particle])
    var path := _advance_particle(particle, time - from, obstacles, tiles, terminal_hits)
    if track_particle_paths: _report_particle_path(particle, path, time - from)
    if terminal_hits.has(particle): terminal_hits[particle].time += from
  var completed_pulls: Array[Dictionary] = []
  var impacted := terminal_hits.keys()
  impacted.sort_custom(func(a: Particle, b: Particle) -> bool: return terminal_hits[a].time < terminal_hits[b].time)
  for particle in impacted:
    if not particle.is_queued_for_deletion():
      var contact := _settle_impact(particle, terminal_hits[particle], time, obstacles, tiles)
      if not contact.is_empty(): completed_pulls.append(contact)
  return completed_pulls

func _advance_particle(particle: Particle, time: float, obstacles: Array[Node], tiles: Dictionary, terminal_hits: Dictionary) -> Array[Dictionary]:
  var path: Array[Dictionary] = []
  if not particle.free_flight:
    particle.global_position = SimulationGrid.center(particle.global_position)
  var used := 0.0
  while time - used > EPSILON:
    var from := particle.motion_position()
    var held := is_instance_valid(particle.held_by)
    if held or particle.glass_wait > EPSILON or particle.speed <= EPSILON or particle.direction.is_zero_approx():
      var trap := _world_impact(particle, from, Vector2.ZERO, obstacles)
      if not trap.is_empty():
        trap.time = used
        terminal_hits[particle] = trap
        path.append({"from": from, "to": from, "start": used, "end": used})
        return path
    if particle.glass_wait > EPSILON:
      var wait := minf(time - used, particle.glass_wait)
      path.append({"from": from, "to": from, "start": used, "end": used + wait})
      particle.glass_wait -= wait
      used += wait
      continue
    var pace := 0.0 if held else particle.speed
    if pace <= EPSILON or particle.direction.is_zero_approx():
      path.append({"from": from, "to": from, "start": used, "end": time})
      break

    var in_field := not particle.magnetic_exit.is_zero_approx()
    var destination := SimulationGrid.center(particle.global_position + particle.direction * SimulationGrid.CELL)
    var segment_end := 1.0
    if not particle.free_flight and not in_field and particle.charge != 0 and particle.progress <= 0.5 + EPSILON:
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
    var flight_edges := Vector2.INF
    var flight_boundary := INF
    if particle.free_flight:
      flight_edges = _flight_edges(particle, particle.direction * (pace * SimulationGrid.CELL))
      flight_boundary = minf(flight_edges.x, flight_edges.y)
      duration = minf(time - used, flight_boundary)
    var motion := travel * (progress_per_tick * duration)
    var hit := _world_impact(particle, from, motion, obstacles)
    if not hit.is_empty():
      var hit_time: float = duration * hit.fraction
      var point := from + motion * float(hit.fraction)
      path.append({"from": from, "to": point, "start": used, "end": used + hit_time})
      if not hit.reflective:
        hit.time = used + hit_time
        terminal_hits[particle] = hit
        return path
      _reflect_particle(particle, point, hit, particle.direction)
      used += hit_time
      continue

    path.append({"from": from, "to": from + motion, "start": used, "end": used + duration})
    used += duration
    if particle.free_flight:
      particle.global_position = from + motion
      if duration >= flight_boundary:
        var crossed := Vector2(float(duration >= flight_edges.x), float(duration >= flight_edges.y))
        particle.flight_cell = SimulationGrid.center(particle.flight_cell + crossed * particle.direction.sign() * SimulationGrid.CELL)
        particle.source_building = null
        # Leaving a cell can happen while an off-grid particle still overlaps its gate.
        for i in range(particle.passed_gates.size() - 1, -1, -1):
          var gate := particle.passed_gates[i] as Node2D
          if not is_instance_valid(gate) or particle.global_position.distance_to(gate.global_position) > SimulationGrid.CELL + particle.world_collision_radius():
            particle.passed_gates.remove_at(i)
        var terminal_hit := _enter_tile(particle, tiles, obstacles, path, used)
        if not terminal_hit.is_empty():
          terminal_hit.time = used
          terminal_hits[particle] = terminal_hit
          return path
      continue
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
      var terminal_hit := _enter_tile(particle, tiles, obstacles, path, used)
      if not terminal_hit.is_empty():
        terminal_hit.time = used
        terminal_hits[particle] = terminal_hit
        return path
  particle.update_motion_offset()
  return path

func _flight_edges(particle: Particle, velocity: Vector2) -> Vector2:
  var edge := particle.flight_cell + velocity.sign() * (SimulationGrid.CELL * 0.5)
  var distance := edge - particle.global_position
  var across_x := INF if absf(velocity.x) <= EPSILON else maxf(0.0, distance.x / velocity.x)
  var across_y := INF if absf(velocity.y) <= EPSILON else maxf(0.0, distance.y / velocity.y)
  return Vector2(across_x, across_y)

func _is_grid_heading(travel: Vector2) -> bool:
  return travel.normalized().is_equal_approx(SimulationGrid.heading(travel).normalized())

func _world_impact(particle: Particle, from: Vector2, motion: Vector2, obstacles: Array[Node]) -> Dictionary:
  var hits_buildings := particle.flavour != Particle.Flavour.NEUTRINO and not motion.is_zero_approx()
  var z_boson := particle.flavour == Particle.Flavour.Z_BOSON
  var gluon := particle.flavour == Particle.Flavour.GLUON
  var edge := _gluon_edge_impact(from, motion) if gluon else {}
  while true:
    var hit := {}
    var target: Node
    for obstacle in obstacles:
      if obstacle == particle or obstacle == particle.source_building or obstacle.is_queued_for_deletion(): continue
      var candidate: Dictionary
      if obstacle is BOSON:
        if gluon and motion.is_zero_approx(): continue
        candidate = obstacle.sweep_trail(particle, from, motion)
      elif not hits_buildings:
        continue
      elif obstacle.has_method("sweep_for"):
        candidate = obstacle.sweep_for(particle, from, motion)
      else:
        candidate = obstacle.sweep(from, motion, particle.world_collision_radius())
      if not candidate.is_empty() and z_boson and motion.dot(candidate.normal) >= 0.0:
        continue
      if not candidate.is_empty() and (hit.is_empty() or candidate.fraction < hit.fraction):
        hit = candidate
        target = obstacle
    if hit.is_empty() or (not edge.is_empty() and edge.fraction < hit.fraction): return edge
    var at := from + motion * float(hit.fraction)
    if target.get_meta("device", "") == "gate":
      if target.hit_gate(particle, from, motion): continue
    hit.target = target
    hit.at = at
    hit.reflective = hit.reflective or z_boson
    if hit.reflective:
      particle_event.emit("reflection", at)
    return hit
  return {}

func _gluon_edge_impact(from: Vector2, motion: Vector2) -> Dictionary:
  if not level_bounds_enabled or motion.is_zero_approx() or level_bounds.has_point(from + motion):
    return {}
  var edge := level_bounds.grow(-0.001)
  var corner := Vector2(edge.end.x if motion.x > 0.0 else edge.position.x,
    edge.end.y if motion.y > 0.0 else edge.position.y)
  var distance := corner - from
  var x := INF if is_zero_approx(motion.x) else distance.x / motion.x
  var y := INF if is_zero_approx(motion.y) else distance.y / motion.y
  var fraction := clampf(minf(x, y), 0.0, 1.0)
  return {"fraction": fraction, "at": from + motion * fraction, "edge": true, "reflective": false}

func _settle_impact(particle: Particle, hit: Dictionary, time: float, obstacles: Array[Node], tiles: Dictionary) -> Dictionary:
  var elapsed := 0.0
  while not hit.is_empty():
    if not hit.target is BOSON:
      _absorb_at_building(particle, hit)
      return {}
    var gluon := hit.target as BOSON
    elapsed += float(hit.time)
    if not gluon.is_queued_for_deletion() and gluon.caught.size() < 2:
      _redirect_particle(particle, hit.at, particle.direction)
      _release_holder(gluon)
      gluon.trap(particle)
      var contact := _pull_captives(gluon, maxf(0.0, time - elapsed))
      if not contact.is_empty(): contact.time += elapsed
      return contact
    if not particle.motion_position().is_equal_approx(hit.at):
      _redirect_particle(particle, hit.at, particle.direction)
    var next_hit := {}
    var path := _advance_particle(particle, time - elapsed, obstacles, tiles, next_hit)
    if track_particle_paths: _report_particle_path(particle, path, time - elapsed)
    hit = next_hit.get(particle, {})
  return {}

func _reflect_particle(particle: Particle, at: Vector2, hit: Dictionary, incoming: Vector2) -> void:
  _redirect_particle(particle, at, incoming.bounce(hit.normal))
  particle.source_building = hit.target
  particle.passed_gates.clear()

func _absorb_at_building(particle: Particle, hit: Dictionary) -> void:
  if hit.target.has_method("accepts") and hit.target.accepts(particle):
    particle_event.emit("detection", hit.at)
    particle_detected.emit(particle.level_particle_name())
  else:
    particle_event.emit("absorption", hit.at)
  particle.queue_free()

func _enter_tile(particle: Particle, tiles: Dictionary, obstacles: Array[Node], path: Array[Dictionary], time: float, pushed := false) -> Dictionary:
  var at := particle.flight_cell if particle.free_flight else particle.global_position
  var tile = tiles.get(at)
  if tile == null: return {}
  var device: String = tile.get_meta("device", "")
  if particle.flavour == Particle.Flavour.NEUTRINO and device not in ["glass", "holder"]: return {}
  if tile.is_in_group("magnetic_fields") and particle.charge != 0:
    particle.direction = tile.exit_heading(particle.direction, particle.charge, particle.free_flight)
    particle_event.emit("field", particle.global_position)
  match device:
    "glass":
      if particle.passes_glass() and particle.speed > EPSILON:
        particle.glass_wait = 1.0 / particle.speed
    "holder":
      if not is_instance_valid(tile.held_particle) or tile.held_particle.is_queued_for_deletion():
        tile.held_particle = particle
        particle.held_by = tile
        particle.global_position = tile.global_position
    "pusher":
      if pushed: return {}
      var shift: Vector2 = tile.next_push()
      var hit := _world_impact(particle, particle.global_position, shift, obstacles)
      if track_particle_paths:
        var from := particle.global_position
        path.back()["push"] = {"from": from, "to": hit.get("at", from + shift), "start": time, "end": time}
      if not hit.is_empty():
        if not hit.reflective: return hit
        _reflect_particle(particle, hit.at, hit, shift)
        return {}
      particle.global_position += shift
      if particle.free_flight:
        particle.flight_cell = SimulationGrid.center(particle.flight_cell + shift)
      return _enter_tile(particle, tiles, obstacles, path, time, true)
  return {}

func _resolve_particle_contacts(particles: Array[Particle], paths: Dictionary, terminal_hits: Dictionary,
    contacts: Array[Dictionary]) -> Dictionary:
  for i in range(particles.size()):
    var a := particles[i]
    if not paths.has(a): continue
    for j in range(i + 1, particles.size()):
      var b := particles[j]
      if not paths.has(b) or b in a.separating_from or _passes_through(a, b): continue
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
    var pulled := contact.has("gluon")
    if pulled:
      contact.gluon.release_captives()
      contact.gluon.queue_free()
      redirected[a] = contact.time
      redirected[b] = contact.time
      particle_event.emit("annihilation", contact.at)
      if _passes_through(a, b): continue
    if a.flavour == Particle.Flavour.Z_BOSON or b.flavour == Particle.Flavour.Z_BOSON:
      _bounce(a, b, contact, pulled)
      redirected[a] = contact.time
      redirected[b] = contact.time
      terminal_hits.erase(a)
      terminal_hits.erase(b)
      continue
    if _neutrino_reaction(a, b, contact, redirected, terminal_hits) or _muon_reaction(a, b, contact):
      if a.is_queued_for_deletion(): redirected[a] = contact.time
      if b.is_queued_for_deletion(): redirected[b] = contact.time
      continue
    if a.flavour == Particle.Flavour.ELECTRON and b.flavour == Particle.Flavour.ELECTRON:
      _perpendicular_reaction(a, b, contact, Particle.Flavour.PHOTON)
      redirected[a] = contact.time
      redirected[b] = contact.time
      continue
    var photon := a if a.flavour == Particle.Flavour.PHOTON else b
    var other := b if photon == a else a
    if photon.flavour == Particle.Flavour.PHOTON and other.is_pion():
      var incoming: Vector2 = contact.velocity_a if photon == a else contact.velocity_b
      _split_pion(other, photon, contact.at, incoming)
      redirected[a] = contact.time
      redirected[b] = contact.time
      continue
    if _can_bind(a, b):
      var participants: Array[Particle] = [a, b]
      var momentum: Vector2 = a.mass * contact.velocity_a + b.mass * contact.velocity_b
      if not pulled and a.is_quark() and b.is_quark():
        for c in particles:
          if c == a or c == b or not paths.has(c) or c.is_queued_for_deletion() or redirected.has(c): continue
          if not c.is_quark() or not _can_bind(a, c) or not _can_bind(b, c): continue
          var leg := _touching_leg(c, paths[c], a, paths[a], b, paths[b], contact.time)
          if not leg.is_empty():
            participants.append(c)
            momentum += c.mass * _leg_velocity(leg)
            break
      _bind_quarks(participants, contact.at, momentum)
      for participant in participants: redirected[participant] = contact.time
      continue
    if a.mass == b.mass:
      _bounce(a, b, contact, pulled)
      redirected[a] = contact.time
      redirected[b] = contact.time
      terminal_hits.erase(a)
      terminal_hits.erase(b)
      continue

    var lighter := a if a.mass < b.mass else b
    var heavier := b if lighter == a else a
    _release_holder(heavier)
    _release_holder(lighter)
    lighter.queue_free()
    redirected[lighter] = contact.time
    particle_event.emit("absorption", contact.at)
  return redirected

func _passes_through(a: Particle, b: Particle) -> bool:
  if a.is_quark() and b.is_quark(): return a.colour == b.colour
  if a.flavour == Particle.Flavour.PHOTON:
    return b.flavour in [Particle.Flavour.PHOTON, Particle.Flavour.NEUTRINO]
  if b.flavour == Particle.Flavour.PHOTON:
    return a.flavour == Particle.Flavour.NEUTRINO
  return a.flavour == Particle.Flavour.ELECTRON and b.flavour == Particle.Flavour.ELECTRON and a.isAnti == b.isAnti

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
  var cell := SimulationGrid.center(at)
  particle.free_flight = not at.is_equal_approx(cell) or not _is_grid_heading(velocity)
  particle.global_position = at if particle.free_flight else cell
  if particle.free_flight: particle.flight_cell = cell
  particle.direction = velocity
  particle.progress = 0.0
  particle.magnetic_exit = Vector2.ZERO
  particle.glass_wait = 0.0
  particle.update_motion_offset()

func _keep_separating(a: Particle, b: Particle) -> void:
  a.separating_from.append(b)
  b.separating_from.append(a)

func _bounce(a: Particle, b: Particle, contact: Dictionary, pulled := false) -> void:
  var velocity_a: Vector2 = contact.velocity_a
  var velocity_b: Vector2 = contact.velocity_b
  var relative := velocity_a - velocity_b
  var separation: Vector2 = contact.at_a - contact.at_b
  var normal := (relative if separation.is_zero_approx() else separation).normalized()
  var z_bounce := a.flavour == Particle.Flavour.Z_BOSON or b.flavour == Particle.Flavour.Z_BOSON
  if z_bounce:
    # Z collisions deflect both particles without changing their travel speeds.
    velocity_a = velocity_a.bounce(normal)
    velocity_b = velocity_b.bounce(normal)
  else:
    var exchange := relative.dot(normal) * normal
    velocity_a -= exchange
    velocity_b += exchange
  if a.mass == 0.0 or z_bounce:
    if velocity_a.is_zero_approx(): velocity_a = normal
  elif not pulled:
    a.speed = velocity_a.length()
  if b.mass == 0.0 or z_bounce:
    if velocity_b.is_zero_approx(): velocity_b = -normal
  elif not pulled:
    b.speed = velocity_b.length()
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
  result.position = to_local(SimulationGrid.center(at))
  add_child(result)
  particle_event.emit("fusion", result.global_position)

func _split_pion(pion: Particle, photon: Particle, at: Vector2, incoming: Vector2) -> void:
  at = _reaction_site(pion, photon, at)
  _consume(pion)
  _consume(photon)
  var axis := (photon.direction if incoming.is_zero_approx() else incoming).orthogonal()
  var quarks: Array[Particle] = []
  for constituent in pion.constituents:
    quarks.append(_spawn_product(constituent.x, false, at, axis, constituent.y))
    axis = -axis
  _keep_separating(quarks[0], quarks[1])
  particle_event.emit("fusion", at)

func _neutrino_reaction(a: Particle, b: Particle, contact: Dictionary, redirected: Dictionary, terminal_hits: Dictionary) -> bool:
  var neutrino := a if a.flavour == Particle.Flavour.NEUTRINO else b
  if neutrino.flavour != Particle.Flavour.NEUTRINO: return false
  var other := b if neutrino == a else a
  if other.flavour == Particle.Flavour.NEUTRINO:
    if a.isAnti and b.isAnti: return false
    var product := Particle.Flavour.PHOTON if a.isAnti != b.isAnti else Particle.Flavour.NEUTRINO
    _perpendicular_reaction(a, b, contact, product, product == Particle.Flavour.NEUTRINO)
    return true

  var incoming: Vector2 = contact.velocity_a if neutrino == a else contact.velocity_b
  var outgoing: Vector2 = contact.velocity_b if neutrino == a else contact.velocity_a
  if other.is_pion() and (not neutrino.isAnti or other.flavour == Particle.Flavour.PION_ZERO):
    var normal: Vector2 = contact.at_a - contact.at_b if neutrino == a else contact.at_b - contact.at_a
    if normal.is_zero_approx(): normal = outgoing - incoming
    normal = normal.normalized()
    var rebound := incoming - 2.0 * (incoming - outgoing).dot(normal) * normal
    var at: Vector2 = contact.at_a if neutrino == a else contact.at_b
    _redirect_particle(neutrino, at, normal if rebound.is_zero_approx() else rebound)
    _release_holder(other)
    _keep_separating(neutrino, other)
    redirected[neutrino] = contact.time
    terminal_hits.erase(neutrino)
    particle_event.emit("reflection", contact.at)
    return true

  var flavour := other.flavour
  var anti := other.isAnti
  var colour := other.colour
  var constituents: Array[Vector2i] = []
  var extra_lepton := false
  if neutrino.isAnti:
    match flavour:
      Particle.Flavour.ELECTRON: flavour = Particle.Flavour.MUON
      Particle.Flavour.MUON: flavour = Particle.Flavour.ELECTRON
      Particle.Flavour.UP, Particle.Flavour.DOWN:
        colour = QUARK_COLOURS[(QUARK_COLOURS.find(colour) + 1) % QUARK_COLOURS.size()]
      Particle.Flavour.PION_PLUS, Particle.Flavour.PION_MINUS:
        var was_positive := flavour == Particle.Flavour.PION_PLUS
        flavour = Particle.Flavour.PION_MINUS if was_positive else Particle.Flavour.PION_PLUS
        var quark_flavour := Particle.Flavour.DOWN if was_positive else Particle.Flavour.UP
        for original in other.constituents:
          constituents.append(Vector2i(quark_flavour, original.y))
      _: return false
  else:
    match flavour:
      Particle.Flavour.ELECTRON, Particle.Flavour.MUON: anti = not anti
      Particle.Flavour.UP: flavour = Particle.Flavour.DOWN
      Particle.Flavour.DOWN: flavour = Particle.Flavour.UP
      Particle.Flavour.PROTON: flavour = Particle.Flavour.NEUTRON
      Particle.Flavour.NEUTRON: flavour = Particle.Flavour.PROTON
      Particle.Flavour.DELTA_PLUS, Particle.Flavour.DELTA_MINUS:
        flavour = Particle.Flavour.PROTON if other.flavour == Particle.Flavour.DELTA_PLUS else Particle.Flavour.NEUTRON
        extra_lepton = true
      _: return false

  var origin := _reaction_site(neutrino, other, contact.at)
  _consume(neutrino)
  _consume(other)
  if incoming.is_zero_approx(): incoming = neutrino.direction
  if outgoing.is_zero_approx(): outgoing = incoming
  var result := _spawn_product(flavour, anti, origin, outgoing, colour, constituents)
  if extra_lepton:
    var lepton := _spawn_product(Particle.Flavour.ELECTRON, other.flavour == Particle.Flavour.DELTA_PLUS, origin, incoming.orthogonal())
    _keep_separating(result, lepton)
  particle_event.emit("fusion", origin)
  return true

func _muon_reaction(a: Particle, b: Particle, contact: Dictionary) -> bool:
  var muon := a if a.flavour == Particle.Flavour.MUON else b
  var other := b if muon == a else a
  if muon.flavour != Particle.Flavour.MUON: return false
  var products: Array[Array] = []
  if other.flavour == Particle.Flavour.MUON and muon.isAnti != other.isAnti:
    products = [[Particle.Flavour.PHOTON, false], [Particle.Flavour.PHOTON, false],
      [Particle.Flavour.PHOTON, false], [Particle.Flavour.PHOTON, false]]
  elif other.flavour == Particle.Flavour.ELECTRON:
    if muon.isAnti != other.isAnti:
      products = [[Particle.Flavour.ELECTRON, muon.isAnti], [Particle.Flavour.PHOTON, false], [Particle.Flavour.PHOTON, false]]
    else:
      products = [[Particle.Flavour.ELECTRON, muon.isAnti], [Particle.Flavour.ELECTRON, muon.isAnti],
        [Particle.Flavour.NEUTRINO, false], [Particle.Flavour.NEUTRINO, false]]
  else:
    return false
  var at := _reaction_site(a, b, contact.at)
  var velocity_a: Vector2 = contact.velocity_a
  var velocity_b: Vector2 = contact.velocity_b
  var momentum := (a.mass * velocity_a + b.mass * velocity_b) / (a.mass + b.mass)
  var relative := (velocity_a - velocity_b) * 0.5
  if relative.is_zero_approx(): relative = (contact.at_a - contact.at_b).normalized()
  if relative.is_zero_approx(): relative = a.direction.normalized()
  if relative.is_zero_approx(): relative = Vector2.RIGHT
  var sideways := relative.orthogonal()
  if sideways.dot(contact.at_a - contact.at_b) < 0.0: sideways = -sideways
  var directions := [momentum + relative, momentum - relative, momentum + sideways, momentum - sideways]
  var spawned: Array[Particle] = []
  for i in range(products.size()):
    var heading: Vector2 = directions[i] if not directions[i].is_zero_approx() else relative
    var product := _spawn_product(products[i][0], products[i][1], at, heading)
    for previous in spawned: _keep_separating(product, previous)
    spawned.append(product)
  particle_event.emit("annihilation", at)
  _consume(a)
  _consume(b)
  return true

func _perpendicular_reaction(a: Particle, b: Particle, contact: Dictionary, flavour: Particle.Flavour, anti := false) -> void:
  var at := _reaction_site(a, b, contact.at)
  var axis: Vector2 = contact.velocity_a + contact.velocity_b
  if axis.is_zero_approx(): axis = contact.velocity_a - contact.velocity_b
  if axis.is_zero_approx(): axis = a.direction
  if axis.is_zero_approx(): axis = Vector2.RIGHT
  var sideways := axis.orthogonal()
  _consume(a)
  _consume(b)
  var first := _spawn_product(flavour, anti, at, sideways, Particle.ColourCharge.NONE, [], true)
  var second := _spawn_product(flavour, anti, at, -sideways, Particle.ColourCharge.NONE, [], true)
  _keep_separating(first, second)
  particle_event.emit("annihilation", at)

func _reaction_site(a: Particle, b: Particle, at: Vector2) -> Vector2:
  if is_instance_valid(a.held_by): return a.global_position
  if is_instance_valid(b.held_by): return b.global_position
  return at

func _consume(particle: Particle) -> void:
  _release_holder(particle)
  particle.queue_free()

func _spawn_product(flavour: Particle.Flavour, anti: bool, at: Vector2, heading: Vector2,
    colour := Particle.ColourCharge.NONE, constituents: Array[Vector2i] = [], exact_heading := false) -> Particle:
  var product := PARTICLES.instantiate(flavour, anti, colour)
  product.free_flight = exact_heading and not _is_grid_heading(heading)
  product.direction = heading
  product.constituents = constituents
  product.position = to_local(SimulationGrid.center(at))
  add_child(product)
  return product

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
