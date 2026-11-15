extends Particle

func _ready() -> void:
  flavour = Flavour.ELECTRON
  size = 0.85
  speed = 400
  spin = 0.5
  charge = -1
  

  textures = [preload("res://Particles/Electron/electron.png"), preload("res://Particles/Electron/positron.png")]

  super._ready()