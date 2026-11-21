@tool
class_name ParticleReflector
extends "res://Buildings/building.gd"

## The reflective strip is on the top of the unrotated sprite.
@export_enum("0 degrees", "45 degrees", "90 degrees", "135 degrees", "180 degrees", "225 degrees", "270 degrees", "315 degrees") var orientation: int = 0:
  set(value):
    orientation = posmod(value, 8)
    rotation = orientation * PI / 4.0

# The sprite is 256 pixels wide, drawn at 0.4 scale. The visible body is
# approximately 83 pixels high and centered with the Sprite2D offset.
const HALF_WIDTH: float = 51.2
const HALF_HEIGHT: float = 16.6
const EPSILON: float = 0.00001

func _ready() -> void:
  super._ready()
  if not Engine.is_editor_hint():
    add_to_group("particle_blockers")

## Sweep against the reflector body. Neutral particles reflect on every face.
func sweep_for(particle: Particle, from: Vector2, motion: Vector2) -> Dictionary:
  var neutral := particle.charge == 0
  var tangent := global_transform.x.normalized()
  var normal := Vector2(-tangent.y, tangent.x)
  var half_width := HALF_WIDTH * global_transform.x.length()
  var half_height := HALF_HEIGHT * global_transform.y.length()
  var radius := particle.world_collision_radius()
  var relative := from - global_position
  var start := Vector2(relative.dot(tangent), relative.dot(normal))
  var move := Vector2(motion.dot(tangent), motion.dot(normal))
  var best_t := INF
  var best_normal := Vector2.ZERO

  # Check the four straight faces expanded by the particle radius.
  if absf(move.y) > EPSILON:
    for side in [-1.0, 1.0]:
      # The reflective strip meets incoming beams on the tile's centre line.
      var face_y: float = 0.0 if neutral and side < 0.0 else side * (half_height + radius)
      var t: float = (face_y - start.y) / move.y
      var x: float = start.x + move.x * t
      var face_normal := Vector2(0.0, side)
      if t >= 0.0 and t <= 1.0 and t < best_t and absf(x) <= half_width and move.dot(face_normal) < -EPSILON:
        best_t = t
        best_normal = face_normal
  if absf(move.x) > EPSILON:
    for side in [-1.0, 1.0]:
      var t: float = (side * (half_width + radius) - start.x) / move.x
      var y: float = start.y + move.y * t
      var face_normal := Vector2(side, 0.0)
      if t >= 0.0 and t <= 1.0 and t < best_t and absf(y) <= half_height and move.dot(face_normal) < -EPSILON:
        best_t = t
        best_normal = face_normal

  # Round the expanded corners by the particle radius to avoid missed impacts.
  var a := move.length_squared()
  if radius > 0.0 and a > EPSILON * EPSILON:
    for sx in [-1.0, 1.0]:
      for sy in [-1.0, 1.0]:
        var corner := Vector2(sx * half_width, sy * half_height)
        var offset := start - corner
        var b := 2.0 * offset.dot(move)
        var c := offset.length_squared() - radius * radius
        var discriminant := b * b - 4.0 * a * c
        if discriminant < 0.0:
          continue
        var t := (-b - sqrt(discriminant)) / (2.0 * a)
        if t < 0.0 or t > 1.0 or t >= best_t:
          continue
        var hit_offset := offset + move * t
        var corner_normal := hit_offset.normalized()
        if hit_offset.x * sx >= 0.0 and hit_offset.y * sy >= 0.0 and move.dot(corner_normal) < -EPSILON:
          best_t = t
          best_normal = corner_normal

  # Handle particles spawned overlapping the body or already touching a face.
  var closest := Vector2(clampf(start.x, -half_width, half_width), clampf(start.y, -half_height, half_height))
  var offset := start - closest
  if offset.length_squared() <= radius * radius:
    var contact_normal := offset.normalized()
    if contact_normal.is_zero_approx():
      var distances := [half_height + start.y, half_height - start.y, half_width + start.x, half_width - start.x]
      var normals := [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
      var nearest := 0
      for i in range(1, distances.size()):
        if distances[i] < distances[nearest]:
          nearest = i
      contact_normal = normals[nearest]
    var approaching_center := neutral and contact_normal.is_equal_approx(Vector2.UP) and start.y <= 0.0 and move.y > EPSILON
    if move.dot(contact_normal) < -EPSILON and not approaching_center:
      best_t = 0.0
      best_normal = contact_normal

  if best_t == INF:
    return {}
  return {"fraction": best_t, "normal": (tangent * best_normal.x + normal * best_normal.y).normalized(), "reflective": neutral}
