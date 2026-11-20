extends Particle

const SPRITES := {
  Flavour.PION_PLUS: preload("res://Particles/Hadron/pion_plus.png"),
  Flavour.PION_MINUS: preload("res://Particles/Hadron/pion_minus.png"),
  Flavour.PION_ZERO: preload("res://Particles/Hadron/pion_zero.png"),
  Flavour.PROTON: preload("res://Particles/Hadron/proton.png"),
  Flavour.NEUTRON: preload("res://Particles/Hadron/neutron.png"),
  Flavour.DELTA_MINUS: preload("res://Particles/Hadron/delta_minus.png"),
  Flavour.DELTA_PLUS: preload("res://Particles/Hadron/delta_plus.png"),
}

func _ready() -> void:
  if is_pion() and constituents.is_empty():
    var first := Flavour.DOWN if flavour == Flavour.PION_MINUS else Flavour.UP
    var second := Flavour.UP if flavour == Flavour.PION_PLUS else Flavour.DOWN
    constituents = [Vector2i(first, ColourCharge.RED), Vector2i(second, ColourCharge.GREEN)]
  charge = 0
  if flavour in [Flavour.PION_PLUS, Flavour.PROTON, Flavour.DELTA_PLUS]:
    charge = 1
  elif flavour in [Flavour.PION_MINUS, Flavour.DELTA_MINUS]:
    charge = -1
  textures = [SPRITES[flavour]]
  super._ready()
