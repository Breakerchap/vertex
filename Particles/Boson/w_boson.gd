extends Particle

const FIELD_RADIUS := 1.5 * SimulationGrid.CELL
const ATTRACTION_COLOUR := Color("54b9e9")
const REPULSION_COLOUR := Color("df767b")

# Cache the field mesh on a child and translate it with the sprite. Rebuilding
# an antialiased circle at every physics substep is especially costly on mobile.
class FieldVisual extends Node2D:
  var radius := 0.0
  var tint := Color.WHITE
  var line_width := 1.0

  func _draw() -> void:
    draw_circle(Vector2.ZERO, radius, Color(tint, 0.08), true, -1.0, true)
    draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, Color(tint, 0.3), line_width, true)

var field_visual: FieldVisual

func update_motion_offset() -> void:
  super.update_motion_offset()
  # The forecast's shadow board is invisible and needs no field graphics.
  if not is_visible_in_tree(): return
  if not is_instance_valid(field_visual):
    field_visual = FieldVisual.new()
    add_child(field_visual)
  var tint := ATTRACTION_COLOUR if flavour == Flavour.W_PLUS else REPULSION_COLOUR
  var inverse_scale := 1.0 / absf(global_scale.x)
  var radius := FIELD_RADIUS * inverse_scale
  if field_visual.radius != radius or field_visual.tint != tint:
    field_visual.radius = radius
    field_visual.tint = tint
    field_visual.line_width = 1.5 * inverse_scale
    field_visual.queue_redraw()
  field_visual.position = sprite.position
