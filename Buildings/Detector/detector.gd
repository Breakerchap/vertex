@tool
extends "res://Buildings/solid_building.gd"

@export var accepted: Array[String] = ["photon"]

func accepts(particle: Particle) -> bool:
  var name := particle.level_particle_name()
  return name in accepted or (particle.flavour == Particle.Flavour.UP and "up" in accepted) or (particle.flavour == Particle.Flavour.DOWN and "down" in accepted)
