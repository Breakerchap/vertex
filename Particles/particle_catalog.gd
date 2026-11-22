extends RefCounted

const SCENES := {
  "electron": preload("res://Particles/Types/electron.tscn"),
  "positron": preload("res://Particles/Types/positron.tscn"),
  "muon": preload("res://Particles/Types/muon.tscn"),
  "anti_muon": preload("res://Particles/Types/anti_muon.tscn"),
  "neutrino": preload("res://Particles/Types/neutrino.tscn"),
  "anti_neutrino": preload("res://Particles/Types/anti_neutrino.tscn"),
  "photon": preload("res://Particles/Types/photon.tscn"),
  "gluon": preload("res://Particles/Types/gluon.tscn"),
  "z_boson": preload("res://Particles/Types/z_boson.tscn"),
  "up_r": preload("res://Particles/Types/up_r.tscn"),
  "up_g": preload("res://Particles/Types/up_g.tscn"),
  "up_b": preload("res://Particles/Types/up_b.tscn"),
  "down_r": preload("res://Particles/Types/down_r.tscn"),
  "down_g": preload("res://Particles/Types/down_g.tscn"),
  "down_b": preload("res://Particles/Types/down_b.tscn"),
  "pion_plus": preload("res://Particles/Types/pion_plus.tscn"),
  "pion_minus": preload("res://Particles/Types/pion_minus.tscn"),
  "pion_zero": preload("res://Particles/Types/pion_zero.tscn"),
  "proton": preload("res://Particles/Types/proton.tscn"),
  "neutron": preload("res://Particles/Types/neutron.tscn"),
  "delta_minus": preload("res://Particles/Types/delta_minus.tscn"),
  "delta_plus": preload("res://Particles/Types/delta_plus.tscn"),
}
const ANTI_QUARK_SCENES := {
  "up_r": preload("res://Particles/Types/anti_up_r.tscn"),
  "up_g": preload("res://Particles/Types/anti_up_g.tscn"),
  "up_b": preload("res://Particles/Types/anti_up_b.tscn"),
  "down_r": preload("res://Particles/Types/anti_down_r.tscn"),
  "down_g": preload("res://Particles/Types/anti_down_g.tscn"),
  "down_b": preload("res://Particles/Types/anti_down_b.tscn"),
}

const TYPES := {
  "electron": [Particle.Flavour.ELECTRON, false, Particle.ColourCharge.NONE, ""],
  "positron": [Particle.Flavour.ELECTRON, true, Particle.ColourCharge.NONE, ""],
  "muon": [Particle.Flavour.MUON, false, Particle.ColourCharge.NONE, ""],
  "anti_muon": [Particle.Flavour.MUON, true, Particle.ColourCharge.NONE, ""],
  "neutrino": [Particle.Flavour.NEUTRINO, false, Particle.ColourCharge.NONE, ""],
  "anti_neutrino": [Particle.Flavour.NEUTRINO, true, Particle.ColourCharge.NONE, ""],
  "photon": [Particle.Flavour.PHOTON, false, Particle.ColourCharge.NONE, ""],
  "gluon": [Particle.Flavour.GLUON, false, Particle.ColourCharge.NONE, ""],
  "z_boson": [Particle.Flavour.Z_BOSON, false, Particle.ColourCharge.NONE, ""],
  "up_r": [Particle.Flavour.UP, false, Particle.ColourCharge.RED, "up"],
  "up_g": [Particle.Flavour.UP, false, Particle.ColourCharge.GREEN, "up"],
  "up_b": [Particle.Flavour.UP, false, Particle.ColourCharge.BLUE, "up"],
  "down_r": [Particle.Flavour.DOWN, false, Particle.ColourCharge.RED, "down"],
  "down_g": [Particle.Flavour.DOWN, false, Particle.ColourCharge.GREEN, "down"],
  "down_b": [Particle.Flavour.DOWN, false, Particle.ColourCharge.BLUE, "down"],
  "pion_plus": [Particle.Flavour.PION_PLUS, false, Particle.ColourCharge.NONE, ""],
  "pion_minus": [Particle.Flavour.PION_MINUS, false, Particle.ColourCharge.NONE, ""],
  "pion_zero": [Particle.Flavour.PION_ZERO, false, Particle.ColourCharge.NONE, ""],
  "proton": [Particle.Flavour.PROTON, false, Particle.ColourCharge.NONE, ""],
  "neutron": [Particle.Flavour.NEUTRON, false, Particle.ColourCharge.NONE, ""],
  "delta_minus": [Particle.Flavour.DELTA_MINUS, false, Particle.ColourCharge.NONE, ""],
  "delta_plus": [Particle.Flavour.DELTA_PLUS, false, Particle.ColourCharge.NONE, ""],
}

const SYMBOLS := {"pion_plus": "π⁺", "pion_minus": "π⁻", "pion_zero": "π⁰", "delta_minus": "Δ⁻", "delta_plus": "Δ⁺"}

const QUARK_FAMILIES := ["up", "down"]

static func current_name(particle: String) -> String:
  return "photon" if particle in ["photon_r", "photon_g", "photon_b"] else particle

static func current_expression(expression: String) -> String:
  var retired_colour := RegEx.new()
  retired_colour.compile("(?i)\\bphoton_[rgb]\\b")
  return retired_colour.sub(expression, "photon", true)

static func emission_name(particle: String) -> String:
  return particle + "_r" if particle in QUARK_FAMILIES else current_name(particle)

static func is_selector(particle: String) -> bool:
  return particle in QUARK_FAMILIES or TYPES.has(current_name(particle))

static func family(particle: String) -> String:
  return TYPES[particle][3] if TYPES.has(particle) else ""

static func detection_keys(particle: String) -> Array[String]:
  var base := family(particle)
  return [particle] if base.is_empty() else [particle, base]

static func label(particle: String) -> String:
  if particle in QUARK_FAMILIES: return "%s (any colour)" % particle.capitalize()
  var base := family(particle)
  if base.is_empty(): return SYMBOLS.get(particle, particle.capitalize())
  var colours := {Particle.ColourCharge.RED: "red", Particle.ColourCharge.GREEN: "green", Particle.ColourCharge.BLUE: "blue"}
  var colour: String = colours.get(TYPES[particle][2], particle.trim_prefix(base + "_"))
  return "%s (%s)" % [base.capitalize(), colour]

static func emission(particle: String) -> ParticleEmission:
  var type: Array = TYPES[emission_name(particle)]
  var entry := ParticleEmission.new()
  entry.flavour = type[0]
  entry.is_anti = type[1]
  entry.colour = type[2]
  return entry

static func instantiate(flavour: Particle.Flavour, anti := false, colour := Particle.ColourCharge.NONE) -> Particle:
  # Anticolours can be passed when copying an already initialized quark.
  var base_colour: Particle.ColourCharge = colour
  if colour >= Particle.ColourCharge.ANTIRED:
    base_colour = colour - 3
  if flavour in [Particle.Flavour.UP, Particle.Flavour.DOWN]:
    if base_colour == Particle.ColourCharge.NONE: base_colour = Particle.ColourCharge.RED
  else:
    base_colour = Particle.ColourCharge.NONE
  for name in TYPES:
    var type: Array = TYPES[name]
    if type[0] == flavour and type[1] == anti and type[2] == base_colour:
      return SCENES[name].instantiate() as Particle
  if anti:
    for name in TYPES:
      var type: Array = TYPES[name]
      if type[0] == flavour and not type[1] and type[2] == base_colour:
        if ANTI_QUARK_SCENES.has(name):
          return ANTI_QUARK_SCENES[name].instantiate() as Particle
        # Preserve the emitter's optional antiparticle setting for other flavours.
        var particle := SCENES[name].instantiate() as Particle
        particle.isAnti = true
        particle.charge = -particle.charge
        return particle
  push_error("No particle scene for flavour %s, anti %s, colour %s" % [flavour, anti, colour])
  return null

static func texture_for(particle: String) -> Texture2D:
  var scene: PackedScene = SCENES[emission_name(particle)]
  var instance := scene.instantiate() as Particle
  var texture: Texture2D = instance.get_node("Sprite2D").texture
  if not instance.textures.is_empty():
    texture = instance.textures[1] if instance.isAnti and instance.textures.size() > 1 else instance.textures[0]
  instance.free()
  return texture
