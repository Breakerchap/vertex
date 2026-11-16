# Particle emitter

Place an Emitter under a ParticleSimulation. Its direction values are world-space vectors. Set `particleFlavour`, `isAnti`, and `direction` in the inspector and call `spawnParticle()` to emit one particle, or call `emit_particle(flavour, anti, direction)` to supply those values directly. The call returns the particle, or null if it cannot be emitted.

To emit an ordered sequence, add ParticleEmission resources to the emitter's `sequence` array. Each entry supplies a flavour, antiparticle flag, and direction. Set `rate` to the number of entries per second, then call `start_sequence()` or enable `start_on_ready`. When `start_on_ready` is enabled with an empty sequence, the emitter continuously emits particles using its single-particle settings at the configured rate. Call `start_emitting()` to start continuous emission manually. `play_sequence(entries)` starts a supplied array instead; `stop_sequence()` cancels pending entries or stops continuous emission. Starting another sequence replaces the pending one. The first entry is emitted on the next simulation step, and emission pauses with the simulation.

Electron and photon scenes are currently available. Up and down flavours do not yet have scenes and cannot be emitted. A zero direction is also rejected.
