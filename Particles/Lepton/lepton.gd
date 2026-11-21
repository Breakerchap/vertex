extends Particle

func _ready() -> void:
  if flavour == Flavour.MUON:
    charge = -1
    size = 0.49
    textures = [preload("res://muon.png"), preload("res://anti_muon.png")]
  else:
    size = 0.2
    textures = [preload("res://neutrino.png")]
  super._ready()
