extends Particle

func _ready() -> void:
  flavour = Flavour.PHOTON
  size = 0.75
  speed = 750
  charge = 0

  textures = [preload("res://Particles/Photon/photon.png")]

  super._ready()
