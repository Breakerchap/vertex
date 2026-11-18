# Levels

The level selector reads every `.level` file in this directory. See the numbered `.level` files in this folder for examples of the format. Coordinates start at the bottom-left; ranges include both ends. Directions are `E`, `SE`, `S`, `SW`, `W`, `NW`, `N`, and `NE`. `fixed=p` locks position, `fixed=r` locks rotation, and `fixed=rp` locks both; magnets use `c` to lock polarity. Emitters repeat their particle lists at the specified rate. Detectors absorb particles and count only the listed types toward production goals.

Choose **Level editor** on the level select screen to create or open a level. Pick a building and click the grid to place it; choose **Select / move** to edit its properties or move it, and press **Delete** to remove it; right-click selects without deleting. The source panel edits goals, inventory and any advanced syntax directly. A range represents multiple cells, so change it in the source instead of moving or deleting one cell. Save defaults to the game's custom levels folder; those files appear in level select. Files saved elsewhere can be reopened with the editor.

The editor and parser use `Buildings/building_catalog.gd` for the available building scenes. Register new building kinds there when implementing them; the editor picks them up and exposes their declaration fields without a separate editor update. New game behavior still needs to be implemented in the game.

In build mode, select an inventory item and click a free cell or drag it into place. Select a building and click a free cell or drag it to move, press **R** to rotate, or press **Delete** to remove it. Right-click selects without deleting. Fixed buildings obey their level flags. Inventory placement costs are shared across levels: wall 5, mirror 10, detector 30, and emitter 40; removing an inventory building refunds its cost. Pre-placed buildings are free.

**Play/Pause** controls the simulation and **Step** pauses and advances 15 fixed simulation ticks smoothly, one per physics frame. **Space** toggles play, **.** advances 15 ticks, **B** stops and returns to build mode while keeping the layout, and **X** resets the level to its initial layout. The speed controls do not alter the step size.

A star tier requires every condition in any one goal to be met. Particle rates count particles accepted by detectors in each five-second window. After two consistent observed windows meet a goal, the game simulates three more windows on an isolated copy of the current state; every observed and predicted window must meet the goal. This is a forecast, not a proof of perpetual production. Results show total detections, the latest observed five-second rate, simulation time, cost, and stars.

During building, green outlines indicate movable buildings, gold indicates fixed-position buildings that can rotate, and red indicates fully fixed buildings. Emitter and detector icons show their configured particle types.


Magnetic fields: add `magnet: {x=3, y=2, polarity=positive, fixed=p};` (or `magnetic_field`) and use `inventory: {magnet=1};` for placeable fields. Polarity accepts `positive` or `negative`, or the shorthand `+` or `-`. Select a field and press **R** to flip it unless `fixed=c` is set; `r` locks rotation of other buildings and does not lock polarity. Fields cost 20. A centred charged beam turns smoothly by 90 degrees through the field: matching polarity turns clockwise, opposite polarity turns counterclockwise. Neutral particles pass through. Photon contact with an electron or positron absorbs the photon.

A grouped goal such as `goal: {[electron OR positron]: 1/s, 2/s, 3/s};` applies each threshold to the combined detected rate of the matching particle types. Goal expressions support `AND`, `OR`, parentheses and commas with the same meaning as detector expressions.

Detector lists support expressions such as `[electron OR positron]` and `[(up OR down) AND up_r]`. Each arriving particle is tested against the expression; `AND` takes precedence over `OR`, and parentheses change the grouping. A comma is equivalent to `OR`. Broad names such as `up` also match their colour-specific forms, such as `up_r`.

## Level presentation and progress

Optional `title: First Contact;` and `hint: A short, non-spoiler prompt;` statements provide level names and an explanation above the build HUD. Completion stars are saved to `user://level_progress.cfg`, keyed by level path; reaching a better tier upgrades the saved result. The next-level action follows the level selector's ordering.

A goal with two different particle outputs uses two semicolon-separated conditions in the **same** goal block, e.g. `goal: {electron: 1/s, 2/s, 3/s; photon: 1/s, 2/s, 3/s};`. A bracketed AND is for testing an individual particle's properties, not for requiring two simultaneous particle streams. Impossible bracket expressions and overlapping buildings are rejected when parsing.

## Editor and gameplay workflow

- **In-game:** Goals and their one/two/three-star thresholds stay visible below the board, along with a measurement-window progress bar. **Interactions** overlays brief colour-coded markers for reflections, annihilations, detector hits, magnetic entry, absorption and particles exiting the board. **Restart run** replays the current layout from a fresh simulation; **Back to build** retains it for changes. **Ctrl+Z / Ctrl+Y** undo and redo building changes. Right-click only selects; remove explicitly with Delete. Level completion offers the next level where available, and best stars are kept across launches.
- **Level editor:** Select an object for a persistent right-hand inspector. Direction, polarity, rate and lock changes update the source-backed board. **Ctrl+Z / Ctrl+Y** undo and redo source/visual changes; **Ctrl+S** saves, while **Ctrl+Shift+S** opens Save As. **Playtest** starts an isolated playable copy with the authored inventory and locks – use **Back to editor** to discard playtest changes. The editor keeps the last valid preview visible when the source has a syntax error, displaying the error until fixed.
- **Level settings:** Multiple conditions inside one *Solution* are ANDed; separate solutions are alternatives. Title and hint are optional. The status bar lists non-fatal design warnings (e.g. no detector or no player-adjustable mechanism); invalid syntax, mutually exclusive goal expressions and overlapping buildings prevent saving.
