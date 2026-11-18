# Levels

The level selector reads every `.level` file in this directory. See `Example Level.level` for the format. Coordinates start at the bottom-left; ranges include both ends. Directions are `E`, `SE`, `S`, `SW`, `W`, `NW`, `N`, and `NE`. `fixed=p` locks position, `fixed=r` locks rotation, and `fixed=rp` locks both; magnets use `c` to lock polarity. Emitters repeat their particle lists at the specified rate. Detectors absorb particles and count only the listed types toward production goals.

In build mode, select an inventory item and click a free cell. Select a building and click a free cell to move it, press **R** to rotate, or right-click / press **Delete** to remove it. Fixed buildings obey their level flags. Inventory placement costs are shared across levels: wall 5, mirror 10, detector 30, and emitter 40; removing an inventory building refunds its cost. Pre-placed buildings are free.

**Play/Pause** controls the simulation and **Step** pauses and advances 15 fixed simulation ticks smoothly, one per physics frame. **Space** toggles play, **.** advances 15 ticks, **B** stops and returns to build mode while keeping the layout, and **X** resets the level to its initial layout. The speed controls do not alter the step size.

A star tier requires every condition in any one goal to be met. Particle rates count particles accepted by detectors in each five-second window. After two consistent observed windows meet a goal, the game simulates three more windows on an isolated copy of the current state; every observed and predicted window must meet the goal. This is a forecast, not a proof of perpetual production. Results show total detections, the latest observed five-second rate, simulation time, cost, and stars.

During building, green outlines indicate movable buildings, gold indicates fixed-position buildings that can rotate, and red indicates fully fixed buildings. Emitter and detector icons show their configured particle types.


Magnetic fields: add `magnet: {x=3, y=2, polarity=positive, fixed=p};` (or `magnetic_field`) and use `inventory: {magnet=1};` for placeable fields. Polarity accepts `positive` or `negative`, or the shorthand `+` or `-`. Select a field and press **R** to flip it unless `fixed=c` is set; `r` locks rotation of other buildings and does not lock polarity. Fields cost 20. A centred charged beam turns smoothly by 90 degrees through the field: matching polarity turns clockwise, opposite polarity turns counterclockwise. Neutral particles pass through. Photon contact with an electron or positron absorbs the photon.

A grouped goal such as `goal: {[electron OR positron]: 1/s, 2/s, 3/s};` applies each threshold to the combined detected rate of the matching particle types. Goal expressions support `AND`, `OR`, parentheses and commas with the same meaning as detector expressions.

Detector lists support expressions such as `[electron OR positron]` and `[(up OR down) AND up_r]`. Each arriving particle is tested against the expression; `AND` takes precedence over `OR`, and parentheses change the grouping. A comma is equivalent to `OR`. Broad names such as `up` also match their colour-specific forms, such as `up_r`.
