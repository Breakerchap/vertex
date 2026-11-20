extends Node2D

const PARTICLES = preload("res://Particles/particle_catalog.gd")
var particle_names: Array[String] = []
var emitter_preview: bool = false

func _process(_delta: float) -> void:
  # Counteract the parent rotation while keeping the preview attached to it.
  if not is_zero_approx(global_rotation):
    global_rotation = 0.0

func _draw() -> void:
  if particle_names.is_empty(): return
  var max_size := 65.0 if emitter_preview else 48.0
  var max_width := 96.0 if emitter_preview else 84.0
  var icon_size := minf(max_size, max_width / particle_names.size())
  var width := icon_size * particle_names.size()
  for i in range(particle_names.size()):
    var name := particle_names[i]
    var bounds := Rect2(-width * 0.5 + i * icon_size, -icon_size * 0.5, icon_size, icon_size)
    var texture := PARTICLES.texture_for(name)
    if Particle.texture_is_blank(texture):
      var tint: Color = Particle.COLOUR_TINTS.get(PARTICLES.TYPES[PARTICLES.emission_name(name)][2], Color("b9dbef"))
      draw_circle(bounds.get_center(), icon_size * 0.3, tint)
    else:
      draw_texture_rect(texture, bounds, false, Color(1, 1, 1, 0.7))

func show_particles(names: Array[String]) -> void:
  particle_names = names.duplicate()
  queue_redraw()
