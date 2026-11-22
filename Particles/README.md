# Particle scenes

Each particle type has a scene in `Particles/Types`. Open a scene in Godot and select its root node to edit its mass, speed (grid cells per tick), size, charge, flavour, colour, and antiparticle flag. The `Sprite2D` child holds its artwork. Size scales both the artwork and collision hitbox.

Emitters and reaction products instantiate these scenes through `particle_catalog.gd`, so changes to their defaults affect newly spawned particles. Speed is configured independently of mass. The family scenes and scripts provide shared behavior, including hadron constituents and gluon trails. Quark colours and supported antiquarks each have their own scene.
