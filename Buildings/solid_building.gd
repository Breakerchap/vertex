@tool
extends "res://Buildings/building.gd"

const COLLISION_EPSILON: float = 0.00001
@onready var collision_shape: CollisionShape2D = $Area2D/CollisionShape2D

func _ready() -> void:
  super._ready()
  if not Engine.is_editor_hint():
    add_to_group("particle_blockers")

## World-space distance from the building center to just outside its body.
func exit_distance(travel: Vector2, radius: float) -> float:
  var shape := collision_shape.shape as RectangleShape2D
  var basis := collision_shape.global_transform
  var axis_x := basis.x.normalized()
  var axis_y := basis.y.normalized()
  var half_size := shape.size * Vector2(basis.x.length(), basis.y.length()) * 0.5
  var direction := travel.normalized()
  var dx := absf(direction.dot(axis_x))
  var dy := absf(direction.dot(axis_y))
  var x_distance := (half_size.x + radius) / dx if dx > COLLISION_EPSILON else INF
  var y_distance := (half_size.y + radius) / dy if dy > COLLISION_EPSILON else INF
  return minf(x_distance, y_distance) + 0.01

## Returns the first swept-circle impact with this solid rectangle.
func sweep(from: Vector2, motion: Vector2, particle_radius: float) -> Dictionary:
  var shape := collision_shape.shape as RectangleShape2D
  if shape == null or collision_shape.disabled:
    return {}
  var basis := collision_shape.global_transform
  var axis_x := basis.x.normalized()
  var axis_y := basis.y.normalized()
  var half_size := shape.size * Vector2(basis.x.length(), basis.y.length()) * 0.5
  var relative := from - collision_shape.global_position
  var start := Vector2(relative.dot(axis_x), relative.dot(axis_y))
  var move := Vector2(motion.dot(axis_x), motion.dot(axis_y))
  var radius := maxf(0.0, particle_radius)
  var closest := Vector2(clampf(start.x, -half_size.x, half_size.x), clampf(start.y, -half_size.y, half_size.y))
  if start.distance_squared_to(closest) <= radius * radius:
    return {"fraction": 0.0, "reflective": false}

  var best := INF
  if absf(move.x) > COLLISION_EPSILON:
    for side in [-1.0, 1.0]:
      var t: float = (side * (half_size.x + radius) - start.x) / move.x
      if t >= 0.0 and t <= 1.0 and absf(start.y + move.y * t) <= half_size.y and move.x * side < 0.0:
        best = minf(best, t)
  if absf(move.y) > COLLISION_EPSILON:
    for side in [-1.0, 1.0]:
      var t: float = (side * (half_size.y + radius) - start.y) / move.y
      if t >= 0.0 and t <= 1.0 and absf(start.x + move.x * t) <= half_size.x and move.y * side < 0.0:
        best = minf(best, t)

  var a := move.length_squared()
  if radius > 0.0 and a > COLLISION_EPSILON * COLLISION_EPSILON:
    for sx in [-1.0, 1.0]:
      for sy in [-1.0, 1.0]:
        var offset := start - Vector2(sx * half_size.x, sy * half_size.y)
        var b := 2.0 * offset.dot(move)
        var c := offset.length_squared() - radius * radius
        var discriminant := b * b - 4.0 * a * c
        if discriminant < 0.0:
          continue
        var t := (-b - sqrt(discriminant)) / (2.0 * a)
        var hit_offset := offset + move * t
        if t >= 0.0 and t <= 1.0 and hit_offset.x * sx >= 0.0 and hit_offset.y * sy >= 0.0:
          best = minf(best, t)
  if best == INF:
    return {}
  return {"fraction": best, "reflective": false}
