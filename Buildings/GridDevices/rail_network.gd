extends RefCounted

const OFFSETS := [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]

## Follow each closed, orthogonally connected loop one cell per step.
static func advance(rails: Array[Node], buildings: Array[Node]) -> void:
  var tracks := {}
  for rail in rails:
    var cell := _cell(rail)
    if not tracks.has(rail.track):
      tracks[rail.track] = {}
    tracks[rail.track][cell] = rail
  var next_cells := {}
  for track in tracks.values():
    _map_track(track, next_cells)
  # Look up every destination before moving any riders.
  var moves := {}
  for building in buildings:
    var cell := _cell(building)
    if next_cells.has(cell):
      moves[building] = next_cells[cell]
  for building in moves:
    building.global_position = Vector2(moves[building]) * SimulationGrid.CELL

static func _map_track(track: Dictionary, next_cells: Dictionary) -> void:
  var visited := {}
  for initial in track:
    if visited.has(initial): continue
    var component: Array[Vector2i] = [initial]
    var top_left: Vector2i = initial
    visited[initial] = true
    var index := 0
    while index < component.size():
      var cell := component[index]
      index += 1
      if cell.y < top_left.y or (cell.y == top_left.y and cell.x < top_left.x):
        top_left = cell
      for offset in OFFSETS:
        var neighbour: Vector2i = cell + offset
        if track.has(neighbour) and not visited.has(neighbour):
          visited[neighbour] = true
          component.append(neighbour)
    if component.size() < 4 or not track.has(top_left + Vector2i.RIGHT):
      continue
    var loop := _outer_loop(track, top_left)
    if loop.size() != component.size(): continue
    var counterclockwise := loop.any(func(cell: Vector2i) -> bool: return track[cell].counterclockwise)
    var turn := -1 if counterclockwise else 1
    for i in range(loop.size()):
      next_cells[loop[i]] = loop[posmod(i + turn, loop.size())]

## Follow the exterior clockwise so short rectangles can contain adjacent rail
## cells across the loop, without treating those connections as extra turns.
static func _outer_loop(track: Dictionary, start: Vector2i) -> Array[Vector2i]:
  var loop: Array[Vector2i] = [start]
  var seen := {start: true}
  var cell := start + Vector2i.RIGHT
  var heading := 0
  while cell != start:
    if seen.has(cell): return []
    seen[cell] = true
    loop.append(cell)
    for turn in [-1, 0, 1, 2]:
      var next_heading := posmod(heading + turn, OFFSETS.size())
      var next_cell: Vector2i = cell + OFFSETS[next_heading]
      if track.has(next_cell):
        cell = next_cell
        heading = next_heading
        break
  return loop

static func _cell(building: Node2D) -> Vector2i:
  return Vector2i((building.global_position / SimulationGrid.CELL).round())
