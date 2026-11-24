# Levels

The level selector reads the bundled `.level` files and files in the game's custom levels folder. Use **Custom levels folder** on the level screen to open it in Finder or your desktop file manager. The editor uses your system's Open and Save dialogs where available. You can work on files elsewhere, but save a copy in the custom levels folder to see it on the level screen. Bundled levels are read-only; use **Save as…** to keep an edited copy.

Coordinates start at the bottom-left and ranges include both ends. Directions are `E`, `SE`, `S`, `SW`, `W`, `NW` and `N`. An optional `title` declaration sets the displayed name.

## Editor and playtest

- Pick a building and click the grid to place it. Right-click (secondary click on a trackpad) to select an existing building. Press **Delete** or **Backspace** to remove the selection. Inspector changes apply automatically to the selected tile unless **Edit all cells in range** is enabled.
- Select **Block area** and drag across the grid to mark a rectangle where players cannot place or move buildings. Use **Unblock area** to clear part or all of it. Click once for a single cell. Orange shading shows the restricted area in the editor and during play. Players cannot add an edge wall along the boundary from either side. You can still place starting buildings there in the editor, and particles travel through the area normally. The source form is `no_build: {x=2..5, y=1..3};`.
- Use **Cmd** on macOS and **Ctrl** on Windows and Linux. **Cmd/Ctrl+C** copies the selection. Hover over the destination and press **Cmd/Ctrl+V**, or click **Paste** and then choose a destination. With a range selected, the paste location is the first tile of the copied range.
- In **Level settings**, choose how players rotate. Eight directions use 45-degree turns and four directions use 90-degree turns. The source form is `rotation: 4;` or `rotation: 8;` on its own line. An emitter or reflector can override the level setting with its own rotation option. Its source form is `rotation=4` or `rotation=8` inside the building declaration. The direction picker can still author diagonal directions.
- `fixed=p` locks position, `fixed=r` locks rotation, and `fixed=rp` locks both. Magnets use `c` to lock polarity.
- **Cmd/Ctrl+Z** and **Cmd/Ctrl+Shift+Z** undo and redo changes. **Cmd/Ctrl+N** starts a new level, **Cmd/Ctrl+O** opens one, **Cmd/Ctrl+S** saves, and **Cmd/Ctrl+Shift+S** opens Save As. **Playtest** uses a separate copy of the board with the authored inventory and locks. The editor shows the last valid board if a source edit has an error.

**Space** plays or pauses, **.** requests one step, **B** returns to build mode, and **X** resets the level. A grid tick contains 15 simulation ticks, and a step contains four grid ticks. The step button advances one grid tick. Pausing finishes the current step. **Esc** clears the current selection and resets the level editor preview if it is running.

## Emitters, detectors and medals

Photons, neutrinos and antineutrinos travel 1.5 tiles per grid tick. Baryons start at half a tile per grid tick. Other particles start at one tile per grid tick. An elastic collision can redistribute speed between equal-mass particles with nonzero mass. The sprite and its hitbox move together during transit. Emitters repeat their particle list and emit electrons when the list is empty. Rates use particles per step and accept decimals or fractions, as in `rate=0.5/step` and `rate=1/2`. Quark colours use `_r`, `_g` or `_b` on `up` and `down`. Use `anti_neutrino` for an antineutrino.

Detectors absorb particles and count those that match their expression. For example, `[electron OR positron]` matches either type, while `[(up OR down) AND up_r]` matches a red up quark. `AND` binds more tightly than `OR`, and commas mean `OR`. Use a broad name such as `up` to match every colour of that quark.

A level clears as soon as a detector accepts any particle. You can keep running to earn medals, and open the results or advance using **Level cleared**. Completion and each medal are saved independently across attempts.

Set all three medals in **Level settings**. Use **Place stars** to toggle a marker on any board cell. Example level source:

```text
rate_medal: {2/step};
cost_medal: {30};
star_medal: {[electron OR positron]: 1/step; cost: 20; no_buildings: reflector, magnet; hit_stars: true};
star: {x=2, y=3};
star: {x=5, y=3};
```

- The Rate medal counts total detected particles per step.
- The Cost medal requires a build cost at or below the amount. Buildings already on the board cost nothing.
- The Star medal supports total output (`any`), named particles or a detector-style particle expression, a build cost limit, excluded building types, and touching all placed stars during the run. Exclusions apply to every building on the board, including starting buildings. Conditions in one `star_medal` block are required together. Additional `star_medal` blocks offer alternative ways to earn the same medal.

The first detection clears the level and starts a background simulation of the build. Output meters and rate-based medals use the same forecast. It measures full cycles when the output repeats and averages a later window when the pattern is irregular. The display uses particles per second at normal playback speed.

Existing `goal` blocks and `/s` rates still load. Legacy level goals supply default medal thresholds and are converted to medal declarations when you apply Level settings. Old hint declarations are ignored. Previous star totals carry forward as completion records.

## Gluons and Z bosons

Use `gluon` and `z_boson` in emitter sequences. Gluons have mass zero and travel two tiles per tick. Glass slows them, reflectors bounce them, pushers shift them, and walls and filters block them. The trail follows the tip's route. Two gluon tips stop when they meet, and a tip also stops if it hits another gluon's trail.

The first particle to touch a trail stays in place. When a second touches it, the tip stops moving and both particles are pulled together at three tiles per tick. They interact on contact and the trail disappears. A trail stays active when its tip reaches the edge of the board. If a building absorbs the tip, the trail disappears and releases its captive.

Z bosons travel one tile per tick. They bounce off other particles, gluon trails, and buildings that would otherwise absorb them. They still pass through an open gate.

## Devices

| Declaration | Behavior |
| --- | --- |
| `gate: {x=2, y=1, open=false};` | Starts closed by default. Along its facing axis, a closed gate absorbs the hit and opens, and an open gate passes the hit and closes. Hits from other directions are blocked. |
| `glass: {x=2, y=1};` | Electrons, muons, neutrinos, their antiparticles, photons and gluons pause while passing through. Glass blocks all other particles. |
| `filter: {x=2, y=1, colour=blue};` | Passes photons and quarks of one matching colour. Choose red, green or blue. |
| `edge_wall: {x=2, y=1, N};` | Blocks the chosen cardinal edge while leaving the cell free for a building. Click near an edge to place or select its wall. |
| `reflector: {x=2, y=1, N};` | Reflects uncharged particles and absorbs charged ones. Existing `mirror` declarations and inventory entries still load. |
| `holder: {x=2, y=1};` | Holds one particle at the cell centre, including neutrinos or antineutrinos. A particle interaction releases the holder’s contents or the reaction products. |
| `pusher: {x=2, y=1};` | The facing direction sets the first one-tile push. The next push goes in the opposite direction. Each keeps its speed and heading. |
| `magnet: {x=2, y=1, polarity=positive};` | Charged particles enter and exit through the edges along paths that turn them 90 degrees. A matching charge turns clockwise and an opposite charge turns counterclockwise. Neutral particles pass straight through. |
| `stray_particle: {x=2, y=1, E, [electron]};` | Starts the run with one particle travelling in the direction of its arrow. Rotate with **Q** or **E**, or tap it on a touchscreen. The rotation cycle includes `REST`, which gives it zero initial momentum. Choose the type in the editor. It defaults to an electron. |

Neutrinos and antineutrinos respond to Glass and Holders and pass freely through other buildings.
