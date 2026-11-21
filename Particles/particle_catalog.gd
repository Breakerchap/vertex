extends RefCounted

const ELECTRON = preload("res://Particles/Electron/electron.tscn")
const QUARK = preload("res://Particles/Quark/quark.tscn")
const PHOTON = preload("res://Particles/Photon/photon.tscn")
const LEPTON = preload("res://Particles/Lepton/lepton.tscn")
const HADRON = preload("res://Particles/Hadron/hadron.tscn")
const PHOTON_ART = preload("res://Particles/Photon/photon.gd")
const QUARK_ART = preload("res://Particles/Quark/quark.gd")
const HADRON_ART = preload("res://Particles/Hadron/hadron.gd")

const TYPES := {
  "electron": [Particle.Flavour.ELECTRON, false, Particle.ColourCharge.NONE, ""],
  "positron": [Particle.Flavour.ELECTRON, true, Particle.ColourCharge.NONE, ""],
  "muon": [Particle.Flavour.MUON, false, Particle.ColourCharge.NONE, ""],
  "anti_muon": [Particle.Flavour.MUON, true, Particle.ColourCharge.NONE, ""],
  "neutrino": [Particle.Flavour.NEUTRINO, false, Particle.ColourCharge.NONE, ""],
  "anti_neutrino": [Particle.Flavour.NEUTRINO, true, Particle.ColourCharge.NONE, ""],
  "photon": [Particle.Flavour.PHOTON, false, Particle.ColourCharge.NONE, ""],
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
  "nucleus": [Particle.Flavour.NUCLEUS, false, Particle.ColourCharge.NONE, ""],
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
  var scene: PackedScene
  match flavour:
    Particle.Flavour.UP, Particle.Flavour.DOWN: scene = QUARK
    Particle.Flavour.ELECTRON: scene = ELECTRON
    Particle.Flavour.PHOTON: scene = PHOTON
    Particle.Flavour.MUON, Particle.Flavour.NEUTRINO: scene = LEPTON
    _: scene = HADRON
  var particle := scene.instantiate() as Particle
  particle.flavour = flavour
  if particle.is_quark():
    particle.colour = colour if colour != Particle.ColourCharge.NONE else Particle.ColourCharge.RED
  particle.isAnti = anti
  particle.speed = particle.mass_speed()
  return particle

static func texture_for(particle: String) -> Texture2D:
  var type: Array = TYPES[emission_name(particle)]
  match type[0]:
    Particle.Flavour.ELECTRON:
      return preload("res://Particles/Electron/positron.png") if type[1] else preload("res://Particles/Electron/electron.png")
    Particle.Flavour.PHOTON: return PHOTON_ART.TEXTURE
    Particle.Flavour.NEUTRINO: return preload("res://anti_neutrino.png") if type[1] else preload("res://neutrino.png")
    Particle.Flavour.MUON: return preload("res://anti_muon.png") if type[1] else preload("res://muon.png")
    Particle.Flavour.UP, Particle.Flavour.DOWN: return QUARK_ART.SPRITES[type[0]][type[2]]
    _: return HADRON_ART.SPRITES[type[0]]
