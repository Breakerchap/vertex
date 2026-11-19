extends RefCounted

# Level names, their emitted particle, and the broader names they match.
# The parser and every particle dropdown read this same catalog.
const TYPES := {
  "electron": [Particle.Flavour.ELECTRON, false, Particle.ColourCharge.NONE, ""],
  "positron": [Particle.Flavour.ELECTRON, true, Particle.ColourCharge.NONE, ""],
  "photon": [Particle.Flavour.PHOTON, false, Particle.ColourCharge.NONE, ""],
  "up": [Particle.Flavour.UP, false, Particle.ColourCharge.NONE, ""],
  "up_r": [Particle.Flavour.UP, false, Particle.ColourCharge.RED, "up"],
  "up_g": [Particle.Flavour.UP, false, Particle.ColourCharge.GREEN, "up"],
  "up_b": [Particle.Flavour.UP, false, Particle.ColourCharge.BLUE, "up"],
  "down": [Particle.Flavour.DOWN, false, Particle.ColourCharge.NONE, ""],
  "down_r": [Particle.Flavour.DOWN, false, Particle.ColourCharge.RED, "down"],
  "down_g": [Particle.Flavour.DOWN, false, Particle.ColourCharge.GREEN, "down"],
  "down_b": [Particle.Flavour.DOWN, false, Particle.ColourCharge.BLUE, "down"],
}

static func family(particle: String) -> String:
  return TYPES[particle][3] if TYPES.has(particle) else ""

static func detection_keys(particle: String) -> Array[String]:
  var base := family(particle)
  return [particle] if base.is_empty() else [particle, base]

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
