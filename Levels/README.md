# Levels

The game opens on **Chapters**. Each folder directly inside `Levels/` with a `.chapter` file appears as a chapter and lists the `.level` files in that folder. Use `title: Electromagnetism` in `.chapter` to set its display name. Otherwise, the folder name appears.

Add `order: 1` on its own line in a `.chapter` or `.level` file to set its position. Lower numbers appear first. Entries without a number appear after them, alphabetically by display name. Entries with the same number also sort alphabetically.

**Custom levels** lists the files in the game's custom levels folder. Use **Custom levels folder** to open it in Finder or your desktop file manager. The editor uses your system's Open and Save dialogs where available. You can work on files elsewhere and save a copy in the custom levels folder to see it in the game. Bundled levels are read-only. Use **Save as…** to keep an edited copy.

Coordinates start at the bottom-left and ranges include both ends. Directions are `E`, `SE`, `S`, `SW`, `W`, `NW` and `N`. An optional `title` declaration sets the displayed name.

## Editor and playtest

- Pick a building and click the grid to place it. Right-click (secondary click on a trackpad) to select an existing building. Press **Delete** or **Backspace** to remove the selection. Inspector changes apply automatically to the selected tile unless **Edit all cells in range** is enabled.
- Select **Block area** and drag across the grid to mark a rectangle where players cannot place or move buildings. Use **Unblock area** to clear part or all of it. Click once for a single cell. Orange shading shows the restricted area in the editor and during play. Players cannot add an edge wall along the boundary from either side. You can still place starting buildings there in the editor, and particles travel through the area normally. The source form is `no_build: {x=2..5, y=1..3};`.
- Use **Cmd** on macOS and **Ctrl** on Windows and Linux. **Cmd/Ctrl+C** copies the selection. Hover over the destination and press **Cmd/Ctrl+V**, or click **Paste** and then choose a destination. With a range selected, the paste location is the first tile of the copied range.
- In **Level settings**, choose how players rotate. Eight directions use 45-degree turns and four directions use 90-degree turns. The source form is `rotation: 4;` or `rotation: 8;` on its own line. An emitter or reflector can override the level setting with its own rotation option. Its source form is `rotation=4` or `rotation=8` inside the building declaration. The direction picker can still author diagonal directions.
- `fixed=p` locks position, `fixed=r` locks rotation, and `fixed=rp` locks both. Magnets use `c` to lock polarity.
- **Cmd/Ctrl+Z** and **Cmd/Ctrl+Shift+Z** undo and redo changes. **Cmd/Ctrl+N** starts a new level, **Cmd/Ctrl+O** opens one, **Cmd/Ctrl+S** saves, and **Cmd/Ctrl+Shift+S** opens Save As. **Playtest** uses a separate copy of the board with the authored inventory and locks. The editor shows the last valid board if a source edit has an error.

**Space** plays or pauses, **.** advances one tick, **B** returns to build mode, and **X** resets the level. The Tick button advances one grid tick. A grid tick contains 15 internal simulation updates. Pausing still finishes the current four-tick simulation group. **Esc** clears the current selection and resets the level editor preview if it is running.

## Emitters, detectors and medals

Photons, neutrinos and antineutrinos travel 1.5 tiles per grid tick. Baryons start at half a tile per grid tick. Other particles start at one tile per grid tick. An elastic collision can redistribute speed between equal-mass particles with nonzero mass. The sprite and its hitbox move together during transit. Emitters repeat their particle list and emit electrons when the list is empty. Emitters use an emission period in grid ticks: `period=1` emits every tick, `period=2` every two ticks, `period=3` every three ticks, and `period=0.5` twice per tick. Positive decimals and fractions are supported. The default is `period=4`, or one particle every four ticks. Detector output and medal thresholds also use periods: the average number of grid ticks per detected particle, including gaps between bursts. A lower period means better throughput. For example, a threshold of `period=2` means one particle every two ticks on average or faster. The visual editor takes numbers in ticks per particle. In level source use `period=…` for each output requirement to avoid ambiguity with old rates. Quark colours use `_r`, `_g` or `_b` on `up` and `down`. Use `anti_neutrino` for an antineutrino.

Detectors absorb particles and count those that match their expression. For example, `[electron OR positron]` matches either type, while `[(up OR down) AND up_r]` matches a red up quark. `AND` binds more tightly than `OR`, and commas mean `OR`. Use a broad name such as `up` to match every colour of that quark.

By default, a level clears as soon as a detector accepts any particle. You can keep running to earn medals, and open the results or advance using **Level cleared**. Completion and each medal are saved independently across attempts.

Set all three medals in **Level settings**. Use **Place stars** to toggle a marker on any board cell. Example level source:

```text
throughput_medal: {period=2};
cost_medal: {30};
star_medal: {[electron OR positron]: period=4; cost: 20; no_buildings: reflector, magnet; hit_stars: true};
star: {x=2, y=3};
star: {x=5, y=3};
```

- The Throughput medal requires the average period between detected particles to be at or below the specified maximum. No sustained output never satisfies a positive target.
- The Cost medal requires a build cost at or below the amount. Buildings already on the board cost nothing.
- The Star medal supports total output (`any`), named particles or a detector-style particle expression, a build cost limit, excluded building types, and touching all placed stars during the run. Exclusions apply to every building on the board, including starting buildings. Conditions in one `star_medal` block are required together. Additional `star_medal` blocks offer alternative ways to earn the same medal.

In **Level settings**, choose how a level clears: any detector (the default), all selected detectors, or any selected detector. Select the detectors using their board coordinates. For Throughput and Star medals, add an output condition and choose either all detectors or a particular detector; choose total output or a particle expression. The editor automatically assigns persistent detector IDs when a condition references them. A detector's ID appears on the board. Move a detector without changing its ID; remove its objective references before deleting it.

For source editing, the equivalent is:

```text
detector: {x=8, y=8, [photon], id=a, fixed=p};
detector: {x=8, y=0, [photon], id=b, fixed=p};
clear: {a AND b};
throughput_medal: {photon@a: period=4; photon@b: period=4};
cost_medal: {30};
star_medal: {photon@a: period=2; photon@b: period=2};
```

Use `OR` instead of `AND` for alternative clear detectors. Clear requires one accepted particle at each required detector during the same run, not necessarily simultaneously. A scoped output condition such as `[electron OR positron]@a` measures only that detector. `any@a` counts everything accepted there. Unscoped output conditions still count across the board. All output conditions in a Throughput or Star set must be satisfied. IDs must be unique and may contain letters, digits and underscores, starting with a letter.

Deleting a detector in the editor removes its clear and medal conditions. If no named clear detectors remain, any detector can clear the level. A Throughput or Star medal that loses its last condition uses the corresponding new-level threshold.

Completing the clear objective starts a background simulation of the build. Output meters and throughput-based medals use the same forecast. It measures full cycles when the output repeats and averages a later window when the pattern is irregular. The display uses average ticks per detected particle, independent of playback speed. The output bar fills as the measured period approaches or improves on the maximum.

Existing `goal` blocks, `rate_medal` declarations, bare legacy rates, `/step`, historical `/s` and `rate=…/tick` declarations still load at their original cadence. Legacy per-step rates become periods using `period = 4 / rate`; per-tick rates become periods using `period = 1 / rate`. Custom levels in the game folder are migrated on launch, with a `.pre-throughput.bak` backup; earlier migration backups are preserved. Saved Rate medals count as Throughput medals. External levels are upgraded in the editor when opened and written in the new format on save. Invalid levels are left untouched. Legacy level goals supply default medal thresholds and are converted to medal declarations when you apply Level settings. Old hint declarations are ignored. Previous star totals carry forward as completion records.

## Gluons, Z bosons and W bosons

Use `gluon` and `z_boson` in emitter sequences. Gluons have mass zero and travel two tiles per tick. Glass slows them, the shiny side of reflectors bounces them, pushers shift them, and walls and filters absorb them. The trail follows the tip's route. Gluon tips pass through other gluon tips and trails.

An emitter waits for its previous gluon's trail to clear the emitter's front, then waits one firing interval before emitting another gluon.

The first particle to touch a trail stays in place. When a second touches it, the tip stops moving. Both particles align head-on along the nearest grid heading determined by the trail, then pull together at three tiles per tick. They interact on contact and the trail disappears. A trail stays active when its tip reaches the edge of the board. If a building absorbs the tip, the trail disappears and releases its captive.

Z bosons travel one tile per tick. They bounce off other particles, gluon trails, and most buildings, including detectors that reject them. A detector that accepts `z_boson` absorbs and counts it. The sides and back of a reflector also absorb Z bosons. They pass through an open gate.

W bosons use `w_plus` and `w_minus`. Both have a field three tiles across. W⁺ pulls nearby particles inward and W⁻ pushes them outward. The force fades toward the field's edge. W bosons pass through other particles and gluon trails. A neutrino is absorbed on contact and flips the W boson's sign. An antineutrino is absorbed and converts the W into a Z boson. The converted boson keeps its motion.

## Devices

| Declaration | Behavior |
| --- | --- |
| `gate: {x=2, y=1, open=false};` | Starts closed by default. Along its facing axis, a closed gate absorbs the hit and opens, and an open gate passes the hit and closes. Hits from other directions are blocked. |
| `glass: {x=2, y=1};` | Electrons, muons, neutrinos, their antiparticles, photons and gluons pause while passing through. Glass blocks all other particles. |
| `filter: {x=2, y=1, colour=blue};` | Passes photons and quarks of the chosen colour. Bounces rejected quarks and Z bosons. Absorbs other particles that hit it. Choose red, green or blue. |
| `edge_wall: {x=2, y=1, N};` | Blocks the chosen cardinal edge while leaving the cell free for a building. Click near an edge to place or select its wall. |
| `reflector: {x=2, y=1, N};` | The shiny front reflects uncharged particles at the tile centre line, preserving centred lanes. Charged hits and hits on the sides or back are absorbed. Neutrinos and antineutrinos pass through without interacting. Existing `mirror` declarations and inventory entries still load. |
| `holder: {x=2, y=1};` | Holds one particle at the cell centre, including neutrinos or antineutrinos. A particle interaction releases the holder’s contents or the reaction products. |
| `pusher: {x=2, y=1};` | The facing direction sets the first one-tile push. The next push goes in the opposite direction. A push into another pusher triggers it immediately. Each pusher fires at most once in that chain, and the particle keeps its speed and heading. |
| `magnet: {x=2, y=1, polarity=positive};` | Charged particles enter and exit through the edges along paths that turn them 90 degrees. A matching charge turns clockwise and an opposite charge turns counterclockwise. Neutral particles pass straight through. |
| `stray_particle: {x=2, y=1, E, [electron]};` | Starts the run with one particle travelling in the direction of its arrow. Rotate with **Q** or **E**, or tap it on a touchscreen. The rotation cycle includes `REST`, which gives it zero initial momentum. Choose the type in the editor. It defaults to an electron. |

Neutrinos and antineutrinos respond to Glass and Holders and pass freely through other buildings.

On Android, **Open** and **Save as…** let you choose the private game folder or device files. Choose **Device files…** to use the Android file picker for locations such as Downloads and Documents. Device files can be opened in the editor; save a copy in the private custom levels folder to see it on the level screen.
