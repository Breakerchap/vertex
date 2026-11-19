@tool
extends "res://Buildings/solid_building.gd"

const PARTICLES = preload("res://Particles/particle_catalog.gd")

@export var accepted: Array[String] = ["photon"]

func accepts(particle: Particle) -> bool:
  var name := particle.level_particle_name()
  return name in accepted or PARTICLES.family(name) in accepted
