extends Particle

func _ready() -> void:
  size = 0.75
  speed = 600
  direction = Vector2.RIGHT
  spin = 1.0
  charge = 0

  textures = [preload("res://Particles/Photon/photon.png")]

  super._ready()