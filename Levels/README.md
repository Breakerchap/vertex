# Levels

The level selector reads the `.level` files in this directory and the game's custom levels folder. Coordinates start at the bottom-left and ranges include both ends. Directions are `E`, `SE`, `S`, `SW`, `W`, `NW` and `N`. Optional `title` and `hint` declarations set the displayed name and objective hint.

## Editor and playtest

- Pick a building and click the grid to place it. Right-click to select an existing building. Press **Delete** to remove the selection. Inspector changes apply automatically to the selected tile unless **Edit all cells in range** is enabled.
- **Ctrl+C** copies the selection. Hover over the destination and press **Ctrl+V**, or click **Paste** and then choose a destination. With a range selected, the paste location is the first tile of the copied range.
- In **Level settings**, choose how players rotate. Eight directions use 45-degree turns and four directions use 90-degree turns. The source form is `rotation: 4;` or `rotation: 8;` on its own line. An emitter or mirror can override the level setting with its own rotation option. Its source form is `rotation=4` or `rotation=8` inside the building declaration. The direction picker can still author diagonal directions.
- `fixed=p` locks position, `fixed=r` locks rotation, and `fixed=rp` locks both. Magnets use `c` to lock polarity.
- **Ctrl+Z** and **Ctrl+Y** undo and redo changes. **Ctrl+S** saves and **Ctrl+Shift+S** opens Save As. **Playtest** uses a separate copy of the board with the authored inventory and locks. The editor shows the last valid board if a source edit has an error.

**Space** plays or pauses, **.** requests one step, **B** returns to build mode, and **X** resets the level. A grid tick contains 15 simulation ticks, and a step contains four grid ticks. The step button advances one grid tick. Pausing finishes the current step. **Esc** clears the current selection and resets the level editor preview if it is running.

## Emitters, detectors and goals

A normal particle travels one grid tile per tick and light travels two. Diagonal and straight routes cover the same distance per tick. The sprite and its hitbox move together during transit. Emitters repeat their particle list. Rates use particles per step and accept decimals or fractions, as in `rate=0.5/step` and `rate=1/2`. Quark colours use `_r`, `_g` or `_b` on `up` and `down`. Photons have no colour. Reaction products are `pion_plus`, `pion_minus`, `pion_zero`, `proton`, `neutron`, `delta_minus` and `delta_plus`.

Detectors absorb particles and count those that match their expression. For example, `[electron OR positron]` matches either type, while `[(up OR down) AND up_r]` matches a red up quark. `AND` binds more tightly than `OR`, and commas mean `OR`. Use a broad name such as `up` to match every colour of that quark.

Each goal has three thresholds, one for each star. Conditions in one goal are required together, and separate goal blocks offer alternative solutions. For example, `goal: {[electron OR positron]: 0.25/step, 0.5/step, 0.75/step; cost: inf, 30, 20};` combines the counts of electrons and positrons and adds a cost limit for the higher tiers. Old `/s` values still load and are converted to per-step rates.

Output meters show rates over the most recent eight steps. From step 28 onward, the game can run an isolated 240-step forecast to check sustained output before awarding stars. Best results are kept across launches.

## Devices

| Declaration | Behavior |
| --- | --- |
| `gate: {x=2, y=1, open=false};` | Starts closed by default. Along its facing axis, a closed gate absorbs the hit and opens, and an open gate passes the hit and closes. Hits from other directions are blocked. |
| `glass: {x=2, y=1};` | Electrons, positrons and photons wait at the centre before continuing. Quarks and their reaction products are blocked. |
| `filter: {x=2, y=1, colour=blue};` | Passes photons and quarks of one matching colour. Choose red, green or blue. |
| `edge_wall: {x=2, y=1, N};` | Blocks the chosen cardinal edge while leaving the cell free for a building. Click near an edge to place or select its wall. |
| `holder: {x=2, y=1};` | Holds one particle at the cell centre. A particle interaction releases the holder’s contents or the reaction products. |
| `pusher: {x=2, y=1};` | The facing direction sets the first one-tile push. The next push goes in the opposite direction. Each keeps its speed and heading. |
| `magnet: {x=2, y=1, polarity=positive};` | Charged particles enter and exit through the edges along paths that turn them 90 degrees. A matching charge turns clockwise and an opposite charge turns counterclockwise. Neutral particles pass straight through. |
