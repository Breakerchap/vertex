extends Particle

func _ready() -> void:
  size = 0.85
  speed = 400
  spin = 0.5
  charge = 1 if flavour == Flavour.UP else -1
  textures = [preload("res://Particles/Electron/electron.png")]
  super._ready()
  match colour:
    ColourCharge.RED: sprite.modulate = Color(1.0, 0.35, 0.35)
    ColourCharge.GREEN: sprite.modulate = Color(0.35, 1.0, 0.45)
    ColourCharge.BLUE: sprite.modulate = Color(0.4, 0.55, 1.0)
