extends Particle

func _ready() -> void:
  flavour = Flavour.ELECTRON
  size = 0.7
  charge = -1
  textures = [preload("res://Particles/Electron/electron.png"), preload("res://Particles/Electron/positron.png")]
  super._ready()
