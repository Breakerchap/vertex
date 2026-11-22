# Levels

The level selector reads the `.level` files in this directory and the game's custom levels folder. Coordinates start at the bottom-left and ranges include both ends. Directions are `E`, `SE`, `S`, `SW`, `W`, `NW` and `N`. Optional `title` and `hint` declarations set the displayed name and objective hint.

## Editor and playtest

- Pick a building and click the grid to place it. Right-click to select an existing building. Press **Delete** to remove the selection. Inspector changes apply automatically to the selected tile unless **Edit all cells in range** is enabled.
- **Ctrl+C** copies the selection. Hover over the destination and press **Ctrl+V**, or click **Paste** and then choose a destination. With a range selected, the paste location is the first tile of the copied range.
- In **Level settings**, choose how players rotate. Eight directions use 45-degree turns and four directions use 90-degree turns. The source form is `rotation: 4;` or `rotation: 8;` on its own line. An emitter or reflector can override the level setting with its own rotation option. Its source form is `rotation=4` or `rotation=8` inside the building declaration. The direction picker can still author diagonal directions.
- `fixed=p` locks position, `fixed=r` locks rotation, and `fixed=rp` locks both. Magnets use `c` to lock polarity.
- **Ctrl+Z** and **Ctrl+Y** undo and redo changes. **Ctrl+S** saves and **Ctrl+Shift+S** opens Save As. **Playtest** uses a separate copy of the board with the authored inventory and locks. The editor shows the last valid board if a source edit has an error.

**Space** plays or pauses, **.** requests one step, **B** returns to build mode, and **X** resets the level. A grid tick contains 15 simulation ticks, and a step contains four grid ticks. The step button advances one grid tick. Pausing finishes the current step. **Esc** clears the current selection and resets the level editor preview if it is running.

## Emitters, detectors and goals

Photons, neutrinos and antineutrinos travel 1.5 tiles per grid tick. Baryons start at half a tile per grid tick. Other particles start at one tile per grid tick. An elastic collision can redistribute speed between equal-mass particles with nonzero mass. The sprite and its hitbox move together during transit. Emitters repeat their particle list and emit electrons when the list is empty. Rates use particles per step and accept decimals or fractions, as in `rate=0.5/step` and `rate=1/2`. Quark colours use `_r`, `_g` or `_b` on `up` and `down`. Use `anti_neutrino` for an antineutrino.

Detectors absorb particles and count those that match their expression. For example, `[electron OR positron]` matches either type, while `[(up OR down) AND up_r]` matches a red up quark. `AND` binds more tightly than `OR`, and commas mean `OR`. Use a broad name such as `up` to match every colour of that quark.

Each goal has three thresholds, one for each star. Conditions in one goal are required together, and separate goal blocks offer alternative solutions. For example, `goal: {[electron OR positron]: 0.25/step, 0.5/step, 0.75/step; cost: inf, 30, 20};` combines the counts of electrons and positrons and adds a cost limit for the higher tiers. Old `/s` values still load and are converted to per-step rates.

Output meters show rates over the most recent eight steps. From step 28 onward, the game can run an isolated 240-step forecast to check sustained output before awarding stars. Best results are kept across launches.

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

Neutrinos and antineutrinos respond to Glass and Holders and pass freely through other buildings.
