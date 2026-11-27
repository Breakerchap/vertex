# Particle emitter

Place an Emitter under a ParticleSimulation. The emitter's orientation rotates its local travel directions, which the simulation maps to the nearest of the eight compass headings. Particles spawn at the emitter's tile centre and can leave it. Incoming particles are absorbed.

Set `particleFlavour`, `isAnti` and `direction` in the inspector and call `spawnParticle()` for one particle. Alternatively, call `emit_particle(flavour, anti, direction, colour)` directly. The call returns the particle or null if the emitter has no simulation or the direction is zero.

To emit an ordered sequence, add ParticleEmission resources to the emitter's `sequence` array. Each resource specifies the flavour, antiparticle flag, direction and colour. Set `period` in grid ticks between particles (1 means every tick, 2 every other tick, 4 every four ticks). Fractional periods are supported, e.g. 0.5 emits twice per tick. Enable `start_on_ready` for automatic emission, or use `start_sequence()` or `play_sequence(entries)` to supply a sequence. With an empty sequence, automatic emission uses the inspector's single-particle settings. Call `start_emitting()` to start continuous emission manually and `stop_sequence()` to stop either mode. Emission pauses with the simulation.
