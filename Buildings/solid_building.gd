@tool
extends "res://Buildings/building.gd"

const COLLISION_EPSILON: float = 0.00001
@onready var collision_shape: CollisionShape2D = $Area2D/CollisionShape2D

func _ready() -> void:
  super._ready()
  if not Engine.is_editor_hint():
    add_to_group("particle_blockers")

## Returns the first swept-circle impact with this solid rectangle.
func sweep(from: Vector2, motion: Vector2, particle_radius: float) -> Dictionary:
  var shape := collision_shape.shape as RectangleShape2D
  if shape == null or collision_shape.disabled:
    return {}
  var basis := collision_shape.global_transform
  var axis_x := basis.x.normalized()
  var axis_y := basis.y.normalized()
  var half_size := shape.size * Vector2(basis.x.length(), basis.y.length()) * 0.5
  var relative := from - basis.origin
  var start := Vector2(relative.dot(axis_x), relative.dot(axis_y))
  var move := Vector2(motion.dot(axis_x), motion.dot(axis_y))
  var radius := maxf(0.0, particle_radius)
  var extent := half_size + Vector2.ONE * radius
  var sweep_min := start.min(start + move)
  var sweep_max := start.max(start + move)
  if (sweep_min.x > extent.x or sweep_max.x < -extent.x
      or sweep_min.y > extent.y or sweep_max.y < -extent.y):
    return {}
  var closest := Vector2(clampf(start.x, -half_size.x, half_size.x), clampf(start.y, -half_size.y, half_size.y))
  var offset := start - closest
  if offset.length_squared() <= radius * radius:
    var normal := offset.normalized()
    if normal.is_zero_approx():
      var gap := half_size - start.abs()
      if gap.x < gap.y:
        normal = Vector2(signf(start.x) if start.x != 0.0 else -signf(move.x), 0.0)
      else:
        normal = Vector2(0.0, signf(start.y) if start.y != 0.0 else -signf(move.y))
      if normal.is_zero_approx(): normal = -move.normalized()
    return {"fraction": 0.0, "normal": axis_x * normal.x + axis_y * normal.y, "reflective": false}

  var best := INF
  var best_normal := Vector2.ZERO
  if absf(move.x) > COLLISION_EPSILON:
    for side in [-1.0, 1.0]:
      var t: float = (side * (half_size.x + radius) - start.x) / move.x
      if t >= 0.0 and t <= 1.0 and t < best and absf(start.y + move.y * t) <= half_size.y and move.x * side < 0.0:
        best = t
        best_normal = Vector2(side, 0.0)
  if absf(move.y) > COLLISION_EPSILON:
    for side in [-1.0, 1.0]:
      var t: float = (side * (half_size.y + radius) - start.y) / move.y
      if t >= 0.0 and t <= 1.0 and t < best and absf(start.x + move.x * t) <= half_size.x and move.y * side < 0.0:
        best = t
        best_normal = Vector2(0.0, side)

  var a := move.length_squared()
  if radius > 0.0 and a > COLLISION_EPSILON * COLLISION_EPSILON:
    for sx in [-1.0, 1.0]:
      for sy in [-1.0, 1.0]:
        var relative_corner := start - Vector2(sx * half_size.x, sy * half_size.y)
        var b := 2.0 * relative_corner.dot(move)
        var c := relative_corner.length_squared() - radius * radius
        var discriminant := b * b - 4.0 * a * c
        if discriminant < 0.0:
          continue
        var t := (-b - sqrt(discriminant)) / (2.0 * a)
        var hit_offset := relative_corner + move * t
        if t >= 0.0 and t <= 1.0 and t < best and hit_offset.x * sx >= 0.0 and hit_offset.y * sy >= 0.0:
          best = t
          best_normal = hit_offset.normalized()
  if best == INF:
    return {}
  return {"fraction": best, "normal": axis_x * best_normal.x + axis_y * best_normal.y, "reflective": false}
