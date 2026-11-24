extends Particle

const FIELD_RADIUS := 1.5 * SimulationGrid.CELL
const ATTRACTION_COLOUR := Color("54b9e9")
const REPULSION_COLOUR := Color("df767b")

func update_motion_offset() -> void:
  super.update_motion_offset()
  queue_redraw()

func _draw() -> void:
  var tint := ATTRACTION_COLOUR if flavour == Flavour.W_PLUS else REPULSION_COLOUR
  var inverse_scale := 1.0 / absf(global_scale.x)
  var radius := FIELD_RADIUS * inverse_scale
  draw_circle(sprite.position, radius, Color(tint, 0.08), true, -1.0, true)
  draw_arc(sprite.position, radius, 0.0, TAU, 64, Color(tint, 0.3), 1.5 * inverse_scale, true)
