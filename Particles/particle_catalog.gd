extends RefCounted

# Level names, their emitted particle, and the broader names they match.
# The parser and every particle dropdown read this same catalog.
const TYPES := {
  "electron": [Global.Flavour.ELECTRON, false, Particle.ColourCharge.NONE, ""],
  "positron": [Global.Flavour.ELECTRON, true, Particle.ColourCharge.NONE, ""],
  "photon": [Global.Flavour.PHOTON, false, Particle.ColourCharge.NONE, ""],
  "up": [Global.Flavour.UP, false, Particle.ColourCharge.NONE, ""],
  "up_r": [Global.Flavour.UP, false, Particle.ColourCharge.RED, "up"],
  "up_g": [Global.Flavour.UP, false, Particle.ColourCharge.GREEN, "up"],
  "up_b": [Global.Flavour.UP, false, Particle.ColourCharge.BLUE, "up"],
  "down": [Global.Flavour.DOWN, false, Particle.ColourCharge.NONE, ""],
  "down_r": [Global.Flavour.DOWN, false, Particle.ColourCharge.RED, "down"],
  "down_g": [Global.Flavour.DOWN, false, Particle.ColourCharge.GREEN, "down"],
  "down_b": [Global.Flavour.DOWN, false, Particle.ColourCharge.BLUE, "down"],
}

static func family(particle: String) -> String:
  return TYPES[particle][3] if TYPES.has(particle) else ""

static func label(particle: String) -> String:
  var base := family(particle)
  if base.is_empty(): return particle.capitalize()
  var colours := {Particle.ColourCharge.RED: "red", Particle.ColourCharge.GREEN: "green", Particle.ColourCharge.BLUE: "blue"}
  var colour: String = colours.get(TYPES[particle][2], particle.trim_prefix(base + "_"))
  return "%s (%s)" % [base.capitalize(), colour]

static func emission(particle: String) -> ParticleEmission:
  var type: Array = TYPES[particle]
  var entry := ParticleEmission.new()
  entry.flavour = type[0]
  entry.is_anti = type[1]
  entry.colour = type[2]
  return entry
