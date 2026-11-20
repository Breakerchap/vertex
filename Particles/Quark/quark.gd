extends Particle

const SPRITES := {
  Flavour.UP: {
    ColourCharge.RED: preload("res://Particles/Quark/up_r.png"),
    ColourCharge.GREEN: preload("res://Particles/Quark/up_g.png"),
    ColourCharge.BLUE: preload("res://Particles/Quark/up_b.png"),
  },
  Flavour.DOWN: {
    ColourCharge.RED: preload("res://Particles/Quark/down_r.png"),
    ColourCharge.GREEN: preload("res://Particles/Quark/down_g.png"),
    ColourCharge.BLUE: preload("res://Particles/Quark/down_b.png"),
  },
}

func _ready() -> void:
  var variants: Dictionary = SPRITES[flavour]
  if colour == ColourCharge.NONE:
    colour = ColourCharge.RED
  textures = [variants.get(colour, variants[ColourCharge.RED])]
  size = 0.85
  charge = 1 if flavour == Flavour.UP else -1
  super._ready()
