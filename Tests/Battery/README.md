# Vertex battery benchmark

This opt-in scene runs the same seven photon streams on the normal level-game
scene at a fixed 1× speed. It does not change production gameplay or saves.
Clear “Run particle simulation” to benchmark the same board without motion.
Keep your hands off the board during a run.

| Variant | Render cap | After the first forecast |
| --- | --- | --- |
| baseline | device default (60 FPS in headless test) | repeat after 16 simulation steps |
| fps30 | 30 FPS | repeat after 16 steps |
| forecast64 | device default (60 FPS in headless test) | repeat after 64 steps |
| combined | 30 FPS | repeat after 64 steps |

The forecast variant still makes the first prediction as soon as the first
particle is detected. It can take longer to correct later estimates, so check
changing output patterns before adopting it. A 30 FPS cap can also make movement
less smooth and gives the forecast fewer opportunities to run per second.
Neither change is on by default in the normal game.

## Android battery measurement

Install the separately signed arm64 benchmark APK. It uses another app ID and
does not overwrite Vertex. Unplug after installing. Fix brightness and display
refresh rate, disable adaptive brightness, and keep background conditions and
signal consistent (airplane mode is useful). Let the phone cool between rounds.
Run baseline, fps30, forecast64, then combined. Repeat in reverse order. Each
run takes 3 minutes and 15 seconds (15 seconds warm-up plus 3 minutes measured).
The menu shows recent results; a screenshot is enough to share the readings.
For detailed data after reconnecting: `adb logcat -d -s godot | findstr VERTEX_BENCH_END`
on Windows Command Prompt.

The displayed average mA is **whole-phone** discharge derived from Android's
charge counter, not current attributable to Vertex alone. The app also displays
average mW when Android exposes a usable energy counter. If the charge reading
doesn't move or isn't supported, it reports no result rather than zero drain.
Discard interrupted or charging runs. Compare repeated runs of the same scenario;
don't turn a short or noisy result into a battery-life claim.

To rebuild, configure the Android SDK, Java, Godot 4.7.2 export templates and a
debug signing key, then run `bash Tests/Battery/export_android.sh /path/to/output.apk`.
See the script header for the three signing environment variables.

## Linux CPU check

Run `godot --headless --import`, then `python3 Tests/Battery/compare_cpu.py`.
The script records Godot process CPU milliseconds per wall-clock second, excluding
startup and warm-up. Headless runs do not exercise the renderer or GPU. They
are a CPU proxy, not a direct battery measurement. A CPU result per variant is
only comparable if game steps and detections remain similar.
