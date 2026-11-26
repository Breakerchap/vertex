extends Particle

const Z_TEXTURE = preload("res://Z_boson.png")
const TIP = preload("res://gluon_tip.png")
const MIDDLE = preload("res://gluon_middle.png")
const LINE = preload("res://gluon_line.png")
const PULL_SPEED := 3.0
const LINE_HALF_WIDTH := 0.18
const EPSILON := 0.00001

var trail_points := PackedVector2Array()
var edge_stopped := false
var caught: Array[Particle] = []

func _ready() -> void:
  if flavour == Flavour.GLUON:
    z_index = 2
  super._ready()
  if flavour == Flavour.GLUON:
    trail_points.append(motion_position())
    sprite.rotation = direction.angle() + PI * 0.5

func prune_captives() -> void:
  for i in range(caught.size() - 1, -1, -1):
    if not is_instance_valid(caught[i]) or caught[i].is_queued_for_deletion():
      caught.remove_at(i)
  sprite.visible = caught.size() < 2

func release_captives() -> void:
  for particle in caught:
    if is_instance_valid(particle): particle.trapped_by = null
  caught.clear()

func record_path(path: Array[Dictionary]) -> void:
  for leg in path:
    _record_point(leg.from)
    _record_point(leg.to)
  _record_point(motion_position())
  sprite.rotation = direction.angle() + PI * 0.5
  queue_redraw()

func _record_point(point: Vector2) -> void:
  var count := trail_points.size()
  var last := trail_points[count - 1]
  if last.distance_squared_to(point) <= EPSILON: return
  if count > 1:
    var prior := (last - trail_points[count - 2]).normalized()
    var next := (point - last).normalized()
    if prior.dot(next) > 0.99999:
      trail_points[count - 1] = point
      return
  trail_points.append(point)

func trap(particle: Particle) -> void:
  caught.append(particle)
  particle.trapped_by = self
  sprite.visible = caught.size() < 2
  queue_redraw()

## Close the gap between the hitboxes. Both particles travel at the same pull speed.
func pull_pair(time: float) -> Dictionary:
  if caught.size() != 2: return {}
  var a := caught[0]
  var b := caught[1]
  var delta := b.global_position - a.global_position
  var axis := direction if delta.is_zero_approx() else delta.normalized()
  var gap := maxf(0.0, delta.length() - a.world_collision_radius() - b.world_collision_radius())
  var contact_time := gap / (2.0 * PULL_SPEED * SimulationGrid.CELL)
  var travel := axis * (PULL_SPEED * SimulationGrid.CELL * minf(time, contact_time))
  _move_captive(a, a.global_position + travel, axis)
  _move_captive(b, b.global_position - travel, -axis)
  if contact_time > time: return {}
  return {"a": a, "b": b, "gluon": self, "time": contact_time,
    "at_a": a.global_position, "at_b": b.global_position, "at": (a.global_position + b.global_position) * 0.5,
    "velocity_a": axis * PULL_SPEED, "velocity_b": -axis * PULL_SPEED}

func _move_captive(particle: Particle, at: Vector2, heading: Vector2) -> void:
  particle.free_flight = true
  particle.flight_cell = SimulationGrid.center(at)
  particle.direction = heading
  particle.global_position = at
  particle.update_motion_offset()

func sweep_trail(particle: Particle, from: Vector2, motion: Vector2) -> Dictionary:
  if particle.flavour == Flavour.GLUON: return {}
  var reflect := particle.flavour == Flavour.Z_BOSON
  if caught.size() == 2 and not reflect: return {}
  return _sweep_trail(from, motion, particle.world_collision_radius(), reflect)

func trail_overlaps(at: Vector2, radius: float) -> bool:
  if caught.size() == 2: prune_captives()
  if caught.size() != 2 and trail_points[0].distance_squared_to(at) <= radius * radius:
    return true
  return not _sweep_trail(at, Vector2.ZERO, radius, false).is_empty()

func _sweep_trail(from: Vector2, motion: Vector2, radius: float, reflect: bool) -> Dictionary:
  var diameter := world_collision_radius() * 2.0
  var sweep_bounds := Rect2(from, Vector2.ZERO).expand(from + motion).grow(radius + diameter * 0.5)
  if caught.size() == 2:
    return _sweep_capsule(from, motion, caught[0].global_position, caught[1].global_position, radius + diameter * LINE_HALF_WIDTH, reflect)
  var tip := trail_points[trail_points.size() - 1]
  var best := _sweep_capsule(from, motion, tip, tip, radius + diameter * 0.5, reflect)
  var travelled := 0.0
  for i in range(trail_points.size() - 1, 0, -1):
    var end := trail_points[i]
    var start := trail_points[i - 1]
    var delta := start - end
    var length := delta.length()
    if sweep_bounds.intersects(Rect2(start, Vector2.ZERO).expand(end), true):
      var middle_start := clampf(diameter * 0.5 - travelled, 0.0, length)
      var middle_end := clampf(diameter * 1.5 - travelled, 0.0, length)
      var axis := delta / length
      if middle_end > middle_start:
        var middle := _sweep_capsule(from, motion, end + axis * middle_start, end + axis * middle_end, radius + diameter * 0.29, reflect)
        if not middle.is_empty() and (best.is_empty() or middle.fraction < best.fraction): best = middle
      if length > middle_end:
        var line := _sweep_capsule(from, motion, end + axis * middle_end, start, radius + diameter * LINE_HALF_WIDTH, reflect)
        if not line.is_empty() and (best.is_empty() or line.fraction < best.fraction): best = line
    travelled += length
  return best

## Sweep a particle centre against the trail expanded by its radius.
func _sweep_capsule(from: Vector2, motion: Vector2, start: Vector2, end: Vector2, radius: float, reflect: bool) -> Dictionary:
  var segment := end - start
  var tangent := segment.normalized()
  var side := tangent.orthogonal()
  var nearest := Geometry2D.get_closest_point_to_segment(from, start, end) if start != end else start
  var offset := from - nearest
  if offset.length_squared() <= radius * radius:
    var normal := offset.normalized()
    if normal.is_zero_approx(): normal = -motion.normalized()
    if not reflect or motion.dot(normal) < -EPSILON:
      return {"fraction": 0.0, "normal": normal, "reflective": reflect}
    return {}
  if motion.length_squared() <= EPSILON: return {}
  var best := INF
  var best_normal := Vector2.ZERO
  if start != end:
    for normal in [side, -side]:
      var approach: float = motion.dot(normal)
      if approach >= -EPSILON: continue
      var fraction: float = (radius - (from - start).dot(normal)) / approach
      var along := (from + motion * fraction - start).dot(tangent)
      if fraction >= 0.0 and fraction <= 1.0 and along >= 0.0 and along <= segment.length():
        best = fraction
        best_normal = normal
  var squared := motion.length_squared()
  var caps := [start] if start == end else [start, end]
  for cap in caps:
    var relative: Vector2 = from - cap
    var projection := relative.dot(motion)
    var discriminant := projection * projection - squared * (relative.length_squared() - radius * radius)
    if discriminant < 0.0: continue
    var fraction := (-projection - sqrt(discriminant)) / squared
    if fraction < 0.0 or fraction > 1.0 or fraction >= best: continue
    best = fraction
    best_normal = (relative + motion * fraction).normalized()
  if best == INF: return {}
  return {"fraction": best, "normal": best_normal, "reflective": reflect}

func _draw() -> void:
  if flavour != Flavour.GLUON: return
  var art := TIP.get_size()
  if caught.size() == 2 and is_instance_valid(caught[0]) and is_instance_valid(caught[1]):
    var start := to_local(caught[0].global_position)
    var delta := to_local(caught[1].global_position) - start
    draw_set_transform(start, delta.angle() - PI * 0.5)
    draw_texture_rect(LINE, Rect2(-art.x * 0.5, 0.0, art.x, delta.length()), false)
    return
  var travelled := 0.0
  for i in range(trail_points.size() - 1, 0, -1):
    var end := to_local(trail_points[i])
    var delta := to_local(trail_points[i - 1]) - end
    var length := delta.length()
    var middle_start := clampf(art.y * 0.5 - travelled, 0.0, length)
    var middle_end := clampf(art.y * 1.5 - travelled, 0.0, length)
    draw_set_transform(end, delta.angle() - PI * 0.5)
    if middle_end > middle_start:
      draw_texture_rect_region(MIDDLE, Rect2(-art.x * 0.5, middle_start, art.x, middle_end - middle_start),
        Rect2(0.0, travelled + middle_start - art.y * 0.5, art.x, middle_end - middle_start))
    if length > middle_end:
      draw_texture_rect(LINE, Rect2(-art.x * 0.5, middle_end, art.x, length - middle_end), false)
    travelled += length
