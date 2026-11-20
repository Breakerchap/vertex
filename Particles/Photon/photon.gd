extends Particle

const TEXTURE := preload("res://Particles/Photon/photon.png")

func _ready() -> void:
  flavour = Flavour.PHOTON
  colour = ColourCharge.NONE
  size = 0.55
  textures = [TEXTURE]
  super._ready()
