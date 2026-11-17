extends Node2D

const PHOTON = preload("res://Particles/Photon/photon.png")
const ELECTRON = preload("res://Particles/Electron/electron.png")
const POSITRON = preload("res://Particles/Electron/positron.png")
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
    var texture: Texture2D = ELECTRON
    if name == "photon": texture = PHOTON
    elif name == "positron": texture = POSITRON
    var tint := Color(1, 1, 1, 0.7)
    if name.ends_with("_r"): tint = Color(1, 0.35, 0.35, 1.0)
    elif name.ends_with("_g"): tint = Color(0.35, 1, 0.45, 1.0)
    elif name.ends_with("_b"): tint = Color(0.4, 0.55, 1, 1.0)
    draw_texture_rect(texture, Rect2(-width * 0.5 + i * icon_size, -icon_size * 0.5, icon_size, icon_size), false, tint)

func show_particles(names: Array[String]) -> void:
  particle_names = names.duplicate()
  queue_redraw()
