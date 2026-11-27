class_name LevelParser
extends RefCounted

const CATALOG = preload("res://Buildings/building_catalog.gd")
const PARTICLES = preload("res://Particles/particle_catalog.gd")
const PARTICLE_TOKEN := "[a-zA-Z_][a-zA-Z_0-9]*|[(),]"
const MEDAL_BLOCKS := ["throughput_medal", "cost_medal", "star_medal"]
# Historical levels used four grid ticks per step (one second at 60 Hz).
# Keep this conversion fixed even if simulation timing changes later.
const LEGACY_RATE_DIVISOR := 4.0
const DEFAULT_PERIOD := 4.0

static func mask_comments(source: String) -> String:
  var lines := PackedStringArray()
  for line in source.split("\n"):
    var comment := line.find("#")
    lines.append(line if comment < 0 else line.left(comment) + " ".repeat(line.length() - comment))
  return "\n".join(lines)

static func find_metadata(text: String, chapter := false) -> Array[RegExMatch]:
  var metadata := RegEx.new()
  metadata.compile("(?im)^\\h*(title|hint|rotation|order)\\h*:\\h*([^;\\r\\n]+)(;|\\r?$)")
  var matches := metadata.search_all(text)
  if chapter: return matches
  return matches.filter(func(item: RegExMatch) -> bool:
    return item.get_string(1).to_lower() == "order" or item.get_string(3) == ";"
  )

static func _without_metadata(text: String) -> String:
  for item in find_metadata(text):
    text = text.left(item.get_start()) + " ".repeat(item.get_end() - item.get_start()) + text.substr(item.get_end())
  return text

static func find_dimensions(text: String) -> RegExMatch:
  var dimensions := RegEx.new()
  dimensions.compile("(?i)(\\d+)\\s*x\\s*(\\d+)")
  return dimensions.search(_without_metadata(text))

static func find_blocks(text: String) -> Array[RegExMatch]:
  var blocks := RegEx.new()
  var names: Array = CATALOG.SCENES.keys()
  names.append_array(MEDAL_BLOCKS + ["rate_medal", "clear", "star", "goal", "inventory", "no_build", "magnetic_field", "mirror"])
  blocks.compile("(?is)\\b(" + "|".join(names) + ")\\s*:\\s*\\{([^}]*)\\}[ \\t]*;?")
  return blocks.search_all(_without_metadata(text))

static func parse(source: String) -> Dictionary:
  var text := mask_comments(source)
  var size_match := find_dimensions(text)
  if size_match == null:
    return {"error": "Missing grid size (for example 15 x 7)."}
  var data := {"width": int(size_match.get_string(1)), "height": int(size_match.get_string(2)), "medals": {}, "stars": [], "buildings": [], "inventory": {}, "no_build_areas": [], "title": "", "rotation_steps": 8, "legacy_rates": false}
  if data.width <= 0 or data.height <= 0:
    return {"error": "Grid dimensions must be positive."}
  for item in find_metadata(text):
    var key := item.get_string(1).to_lower()
    var value := item.get_string(2).strip_edges().trim_prefix('"').trim_suffix('"')
    if key == "rotation":
      if value not in ["4", "8"]: return {"error": "Rotation must be 4 or 8 directions."}
      data.rotation_steps = int(value)
    elif key == "title":
      data.title = value
  var blocks := find_blocks(text)
  var legacy_suffix := RegEx.new()
  legacy_suffix.compile("(?i)/s\\b")
  for block in blocks:
    if block.get_string(1).to_lower() in ["goal", "rate_medal", "throughput_medal", "star_medal"] and legacy_suffix.search(block.get_string(2)) != null:
      data.legacy_rates = true
  var old_goals: Array[Dictionary] = []
  for block in blocks:
    var kind := building_kind(block.get_string(1))
    var body := block.get_string(2)
    match kind:
      "goal":
        var result := _parse_goal(body)
        if result.has("error"):
          return result
        old_goals.append(result)
      "clear":
        if data.has("clear_ids"): return {"error": "Duplicate clear declaration."}
        var clear_rule := _parse_clear(body)
        if clear_rule.has("error"): return clear_rule
        data.merge(clear_rule)
      "rate_medal", "throughput_medal", "cost_medal":
        var medal := "cost" if kind == "cost_medal" else "throughput"
        if data.medals.has(medal): return {"error": "Duplicate " + medal + " medal declaration."}
        if medal == "throughput" and ":" in body:
          var rule := _parse_star_medal(body, kind == "throughput_medal")
          if rule.has("error"): return rule
          if rule.periods.is_empty() or rule.has("cost") or rule.hit_stars or not rule.no_buildings.is_empty():
            return {"error": "The Throughput medal accepts only output conditions."}
          data.throughput_rule = rule
          data.medals.throughput = float(rule.periods.get("any", DEFAULT_PERIOD))
          continue
        var amount := _parse_output_period(body, kind == "throughput_medal") if medal == "throughput" else _parse_cost_limit(body)
        if medal == "throughput" and amount <= 0.0: return {"error": "The Throughput medal needs a positive period in ticks."}
        if medal == "cost" and amount < 0.0: return {"error": "The Cost medal needs a nonnegative cost limit."}
        data.medals[medal] = amount
      "star_medal":
        var result := _parse_star_medal(body)
        if result.has("error"): return result
        if not data.medals.has("star"): data.medals.star = []
        data.medals.star.append(result)
      "star":
        var result := _parse_no_build(body, data.width, data.height)
        if result.has("error") or result.area.size != Vector2i.ONE:
          return {"error": "A star needs a single x and y coordinate inside the grid."}
        if result.area.position in data.stars: return {"error": "A cell can only contain one star."}
        data.stars.append(result.area.position)
      "inventory":
        var result := _parse_inventory(body, data.inventory)
        if result.has("error"):
          return result
      "no_build":
        var result := _parse_no_build(body, data.width, data.height)
        if result.has("error"):
          return result
        data.no_build_areas.append(result.area)
      _:
        var result := parse_building(kind, body, data.width, data.height, data.legacy_rates)
        if result.has("error"):
          return result
        data.buildings.append_array(result.entries)
  if data.medals.is_empty() and not old_goals.is_empty():
    data.medals = _medals_from_goals(old_goals)
  elif data.medals.size() != MEDAL_BLOCKS.size() or not old_goals.is_empty():
    return {"error": "Define a throughput_medal, cost_medal and star_medal together."}
  var occupied := {}
  var detector_ids := {}
  for building in data.buildings:
    var cell := Vector2i(building.x, building.y)
    var key := CATALOG.occupancy_key(building.kind, cell, building.facing)
    if occupied.has(key):
      return {"error": "Overlapping buildings at (%d, %d)." % [cell.x, cell.y]}
    occupied[key] = true
    if building.has("id"):
      if building.kind != "detector": return {"error": "Only detectors may have an id."}
      var id := str(building.id)
      if not _valid_detector_id(id): return {"error": "Invalid detector id: " + id}
      if detector_ids.has(id): return {"error": "Duplicate detector id: " + id}
      detector_ids[id] = true
  for id in data.get("clear_ids", []):
    if not detector_ids.has(id): return {"error": "Unknown detector in clear objective: " + id}
  var rules: Array = data.medals.star.duplicate()
  if data.has("throughput_rule"): rules.append(data.throughput_rule)
  for rule in rules:
    for key in rule.periods:
      if "@" in key and not detector_ids.has(key.get_slice("@", 1)):
        return {"error": "Unknown detector in output objective: " + key.get_slice("@", 1)}
  return data

static func _parse_cost_limit(text: String) -> float:
  var value := text.strip_edges()
  if not value.is_valid_float() or not is_finite(float(value)): return -1.0
  return float(value)

static func _valid_detector_id(id: String) -> bool:
  var pattern := RegEx.new()
  pattern.compile("^[a-z][a-z0-9_]*$")
  return id not in ["and", "or", "any"] and pattern.search(id) != null

static func _parse_clear(body: String) -> Dictionary:
  var expression := body.strip_edges().to_lower()
  var pattern := RegEx.new()
  pattern.compile("\\s+")
  var words := pattern.sub(expression, " ", true).split(" ", false)
  if words.size() == 0 or words.size() % 2 == 0:
    return {"error": "Clear needs detector ids separated by AND or OR."}
  var ids: Array[String] = []
  var mode := "and"
  for index in range(words.size()):
    var word := words[index]
    if index % 2 == 0:
      if not _valid_detector_id(word) or word in ids: return {"error": "Invalid or repeated clear detector: " + word}
      ids.append(word)
    elif word not in ["and", "or"] or (index > 1 and word != mode):
      return {"error": "Use either AND or OR between all clear detectors."}
    else:
      mode = word
  return {"clear_ids": ids, "clear_mode": mode}

static func _parse_output_target(target: String) -> Dictionary:
  if "@" in target:
    var parts := target.split("@")
    if parts.size() != 2 or not _valid_detector_id(parts[1].strip_edges().to_lower()):
      return {"error": "Use particle@detector_id for detector output."}
    var id := parts[1].strip_edges().to_lower()
    var base := _parse_output_target(parts[0].strip_edges())
    if base.has("error"): return base
    return {"key": base.key + "@" + id, "target": base.target + "@" + id}
  if target.to_lower() == "any": return {"key": "any", "target": "any"}
  if target.begins_with("[") and target.ends_with("]"):
    var expression := particle_expression(target.substr(1, target.length() - 2))
    if expression.has("error"): return expression
    if expression.accepted.is_empty(): return {"error": "Output expression matches no particle: " + target}
    return {"key": "[" + ",".join(expression.accepted) + "]", "target": PARTICLES.current_expression(target)}
  var name := PARTICLES.current_name(target.to_lower())
  if not _valid_particle(name): return {"error": "Unknown output target: " + target}
  return {"key": name, "target": name}

static func _parse_star_medal(body: String, bare_periods := false) -> Dictionary:
  var rule := {"periods": {}, "targets": {}, "no_buildings": [], "hit_stars": false}
  var seen := {}
  for clause in body.strip_edges().split(";", false):
    if clause.strip_edges().is_empty(): continue
    var parts := clause.split(":", true, 1)
    if parts.size() != 2: return {"error": "Invalid Star medal condition: " + clause}
    var target := parts[0].strip_edges()
    var value := parts[1].strip_edges()
    var key := target.to_lower()
    if key not in ["cost", "no_buildings", "hit_stars", "any"]:
      var output := _parse_output_target(target)
      if output.has("error"): return output
      key = output.key
      rule.targets[key] = output.target
    if seen.has(key): return {"error": "Duplicate Star medal condition: " + target}
    seen[key] = true
    match key:
      "cost":
        var cost_limit := _parse_cost_limit(value)
        if cost_limit < 0.0: return {"error": "The Star medal cost limit must be nonnegative."}
        rule.cost = cost_limit
      "no_buildings":
        for name in value.split(","):
          var kind := building_kind(name.strip_edges())
          if not CATALOG.SCENES.has(kind): return {"error": "Unknown excluded building: " + name.strip_edges()}
          if kind not in rule.no_buildings: rule.no_buildings.append(kind)
      "hit_stars":
        if value.to_lower() != "true": return {"error": "Use hit_stars: true to require every placed star."}
        rule.hit_stars = true
      _:
        var period := _parse_output_period(value, bare_periods)
        if period <= 0.0: return {"error": "Output periods must be finite and positive: " + value}
        rule.periods[key] = period
  if seen.is_empty(): return {"error": "The Star medal needs at least one condition."}
  return rule

static func _medals_from_goals(goals: Array[Dictionary]) -> Dictionary:
  var rate := INF
  var cost_limit := INF
  var alternatives: Array[Dictionary] = []
  for old in goals:
    var lowest := 0.0
    for key in old.goal:
      if key != "cost" and is_finite(old.goal[key][0]): lowest += float(old.goal[key][0])
    if lowest > 0.0: rate = minf(rate, lowest)
    for tier in [2, 1, 0]:
      var periods := {}
      var possible := true
      for key in old.goal:
        if key == "cost": continue
        var amount: float = old.goal[key][tier]
        if is_inf(amount): possible = false
        elif amount > 0.0: periods[key] = 1.0 / amount
      if not possible: continue
      var rule := {"periods": periods, "targets": old.targets, "no_buildings": [], "hit_stars": false}
      if old.goal.has("cost") and is_finite(old.goal.cost[tier]):
        rule.cost = floorf(old.goal.cost[tier])
        cost_limit = minf(cost_limit, rule.cost)
      if periods.is_empty() and not rule.has("cost"): rule.periods["any"] = DEFAULT_PERIOD
      alternatives.append(rule)
      break
  if alternatives.is_empty():
    alternatives.append({"periods": {"any": DEFAULT_PERIOD}, "targets": {}, "no_buildings": [], "hit_stars": false})
  return {"throughput": 1.0 / rate if is_finite(rate) else DEFAULT_PERIOD, "cost": cost_limit if is_finite(cost_limit) else 0.0, "star": alternatives}

static func building_kind(name: String) -> String:
  var kind := name.to_lower()
  match kind:
    "magnetic_field": return "magnet"
    "mirror": return "reflector"
  return kind

static func _parse_goal(body: String) -> Dictionary:
  var goal := {}
  var targets := {}
  for clause in body.split(";", false):
    var parts := clause.split(":", true, 1)
    if parts.size() != 2:
      return {"error": "Invalid goal: " + clause}
    var values := []
    for value in parts[1].split(",", false):
      var token := value.strip_edges().to_lower()
      if token == "inf":
        values.append(INF)
      elif parts[0].strip_edges().to_lower() == "cost" and _parse_cost_limit(token) >= 0.0:
        values.append(float(token))
      elif parts[0].strip_edges().to_lower() != "cost" and _is_period_assignment(token):
        var period := _parse_output_period(token)
        if period <= 0.0: return {"error": "Invalid goal period: " + token}
        values.append(1.0 / period)
      elif parts[0].strip_edges().to_lower() != "cost" and _parse_rate(token) >= 0.0:
        values.append(_parse_rate(token))
      else:
        return {"error": "Invalid goal value: " + token}
    if values.size() != 3:
      return {"error": "Each goal needs three values (one per star)."}
    var target := parts[0].strip_edges()
    if target.to_lower() == "cost":
      goal["cost"] = values
      continue
    var output := _parse_output_target(target)
    if output.has("error"): return output
    goal[output.key] = values
    targets[output.key] = output.target
  if goal.is_empty():
    return {"error": "Empty goal."}
  return {"goal": goal, "targets": targets}

static func _parse_inventory(body: String, inventory: Dictionary) -> Dictionary:
  for item in body.split(",", false):
    var pair := item.split("=", true, 1)
    if pair.size() != 2 or not pair[1].strip_edges().is_valid_int() or int(pair[1]) < 0:
      return {"error": "Invalid inventory entry: " + item}
    var name := building_kind(pair[0].strip_edges())
    if name == "rail": continue
    if not CATALOG.SCENES.has(name):
      return {"error": "Unknown inventory item: " + name}
    inventory[name] = int(pair[1])
  return {}

static func _parse_no_build(body: String, width: int, height: int) -> Dictionary:
  var axes := {}
  for item in body.split(",", false):
    var pair := item.split("=", true, 1)
    var axis := pair[0].strip_edges().to_lower()
    if pair.size() != 2 or axis not in ["x", "y"] or axes.has(axis):
      return {"error": "A no-build area needs one x and one y coordinate or range."}
    var endpoints := _range_endpoints(pair[1].strip_edges())
    if endpoints.is_empty():
      return {"error": "Invalid %s coordinate or range for a no-build area." % axis}
    endpoints.sort()
    axes[axis] = endpoints
  if axes.size() != 2:
    return {"error": "A no-build area needs one x and one y coordinate or range."}
  if axes.x[0] < 0 or axes.x[1] >= width or axes.y[0] < 0 or axes.y[1] >= height:
    return {"error": "A no-build area extends outside the grid."}
  var first := Vector2i(axes.x[0], axes.y[0])
  var last := Vector2i(axes.x[1], axes.y[1])
  return {"area": Rect2i(first, last - first + Vector2i.ONE)}

## Explicit /tick is canonical. Bare values, /step and historical /s
## retain their original meaning so old files remain playable without edits.
static func _parse_rate(value: String, _legacy_bare := false) -> float:
  var token := value.strip_edges().to_lower()
  var per_tick := token.ends_with("/tick")
  token = token.trim_suffix("/tick").trim_suffix("/step").trim_suffix("/s")
  var parts := token.split("/")
  if parts.is_empty() or parts.size() > 2 or not parts[0].is_valid_float(): return -1.0
  var rate := float(parts[0])
  if parts.size() == 2:
    if not parts[1].is_valid_float() or float(parts[1]) <= 0.0: return -1.0
    rate /= float(parts[1])
  if not is_finite(rate): return -1.0
  return rate if per_tick else rate / LEGACY_RATE_DIVISOR

## Explicit period= values are unambiguous even in legacy Star/goal blocks.
## Bare numbers in the new Throughput medal are also periods.
static func _is_period_assignment(value: String) -> bool:
  var pair := value.strip_edges().to_lower().split("=", true, 1)
  return pair.size() == 2 and pair[0].strip_edges() == "period"

static func _parse_output_period(value: String, bare_period := false) -> float:
  var token := value.strip_edges().to_lower()
  if _is_period_assignment(token): return _parse_period(token.get_slice("=", 1))
  if bare_period and not (token.ends_with("/tick") or token.ends_with("/step") or token.ends_with("/s")):
    return _parse_period(token)
  var rate := _parse_rate(token)
  if rate <= 0.0 or not is_finite(1.0 / rate): return -1.0
  return 1.0 / rate

## Fields in the visual editor always represent ticks per particle.
static func editor_period_text(value: String) -> String:
  var token := value.strip_edges()
  if token.is_empty() or _is_period_assignment(token): return token
  var lower := token.to_lower()
  if lower.ends_with("/tick") or lower.ends_with("/step") or lower.ends_with("/s"):
    if _parse_output_period(token) > 0.0: return "period=" + _period_from_rate(token)
    return token
  return "period=" + token

## An emission period is a positive number of grid ticks per particle.
## Fractions are useful for rates which do not have a terminating decimal.
static func _parse_period(value: String) -> float:
  var parts := value.strip_edges().split("/")
  if parts.is_empty() or parts.size() > 2 or not parts[0].strip_edges().is_valid_float(): return -1.0
  var period := float(parts[0])
  if parts.size() == 2:
    if not parts[1].strip_edges().is_valid_float() or float(parts[1]) <= 0.0: return -1.0
    period /= float(parts[1])
  if not is_finite(period) or period <= 0.0 or not is_finite(1.0 / period): return -1.0
  return period

static func format_period(period: float) -> String:
  var decimal := String.num(period, 16)
  if float(decimal) == period: return decimal
  return String.num_scientific(period)

# Prefer a readable decimal, but keep an exact fractional interval when
# the reciprocal would otherwise be rounded appreciably.
static func _period_from_rate(token: String) -> String:
  var rate := _parse_rate(token)
  var period := 1.0 / rate
  var decimal := String.num(period, 16)
  if float(decimal) == period: return decimal
  var lower := token.to_lower()
  var per_tick := lower.ends_with("/tick")
  var parts := lower.trim_suffix("/tick").trim_suffix("/step").trim_suffix("/s").split("/")
  var numerator := float(parts[1]) if parts.size() == 2 else 1.0
  if not per_tick: numerator *= LEGACY_RATE_DIVISOR
  var fraction := format_period(numerator) + "/" + parts[0]
  if _parse_period(fraction) > 0.0 and absf(_parse_period(fraction) / period - 1.0) <= 0.000000000001:
    return fraction
  return format_period(period)

static func _output_period_edit(edits: Array[Dictionary], value: String, offset: int, bare_period := false) -> void:
  var token := value.strip_edges()
  if token.is_empty() or _is_period_assignment(token): return
  var period := _parse_output_period(token, bare_period)
  if period <= 0.0: return
  var lower := token.to_lower()
  var legacy := not bare_period or lower.ends_with("/tick") or lower.ends_with("/step") or lower.ends_with("/s")
  var replacement := "period=" + (_period_from_rate(token) if legacy else token)
  var first := value.find(token)
  edits.append({"start": offset + first, "end": offset + first + token.length(), "text": replacement})

# Reciprocals and legacy goal sums may introduce machine-precision rounding.
# All nonnumeric data must remain identical.
static func _equivalent_migration(before: Variant, after: Variant) -> bool:
  if typeof(before) != typeof(after): return false
  if before == after: return true
  if before is float:
    return is_finite(before) and is_finite(after) and before != 0.0 and absf(after / before - 1.0) <= 0.000000000001
  if before is Dictionary:
    if before.size() != after.size(): return false
    for key in before:
      if not after.has(key) or not _equivalent_migration(before[key], after[key]): return false
    return true
  if before is Array:
    if before.size() != after.size(): return false
    for index in range(before.size()):
      if not _equivalent_migration(before[index], after[index]): return false
    return true
  return false

## Upgrade old emitter and medal rates to periods, preserving comments,
## costs, detector IDs, goal tiers, and all other level data.
static func migrate_rates(source: String) -> String:
  var before := parse(source)
  if before.has("error"): return source
  var edits: Array[Dictionary] = []
  var assignment := RegEx.new()
  assignment.compile("(?i)\\brate\\s*=\\s*([^,}\\s]+)")
  var period_assignment := RegEx.new()
  period_assignment.compile("(?i)\\bperiod\\s*=")
  for block in find_blocks(mask_comments(source)):
    var kind := building_kind(block.get_string(1))
    var body := block.get_string(2)
    var start := block.get_start(2)
    if kind == "emitter":
      var found := assignment.search(body)
      if found != null:
        edits.append({"start": start + found.get_start(), "end": start + found.get_end(),
          "text": "period=" + _period_from_rate(found.get_string(1))})
      elif period_assignment.search(body) == null:
        edits.append({"start": block.get_end(2), "end": block.get_end(2), "text": ", period=4"})
    elif kind in ["goal", "rate_medal", "throughput_medal", "star_medal"]:
      if kind == "rate_medal":
        edits.append({"start": block.get_start(1), "end": block.get_end(1), "text": "throughput_medal"})
      if kind in ["rate_medal", "throughput_medal"] and not ":" in body:
        _output_period_edit(edits, body, start, kind == "throughput_medal")
        continue
      var offset := start
      for clause in body.split(";"):
        var colon := clause.find(":")
        if colon >= 0 and clause.left(colon).strip_edges().to_lower() not in ["cost", "no_buildings", "hit_stars"]:
          var value := clause.substr(colon + 1)
          if kind == "goal":
            var value_offset := offset + colon + 1
            for tier in value.split(","):
              _output_period_edit(edits, tier, value_offset)
              value_offset += tier.length() + 1
          else:
            _output_period_edit(edits, value, offset + colon + 1, kind == "throughput_medal")
        offset += clause.length() + 1
  edits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.start > b.start)
  var updated := source
  for edit in edits:
    updated = updated.left(edit.start) + edit.text + updated.substr(edit.end)
  var after := parse(updated)
  if after.has("error"): return source
  before.erase("legacy_rates")
  after.erase("legacy_rates")
  if not _equivalent_migration(before, after): return source
  return updated

static func parse_building(kind: String, body: String, width: int, height: int, legacy_rates := false) -> Dictionary:
  var entry := {"kind": kind, "facing": CATALOG.default_facing(kind), "fixed": "", "particles": []}
  var list_regex := RegEx.new()
  list_regex.compile("\\[([^]]*)\\]")
  var list_match := list_regex.search(body)
  if list_match:
    if kind == "detector":
      var expression := particle_expression(list_match.get_string(1))
      if expression.has("error"):
        return expression
      entry.particles = expression.particles
      entry.accepted = expression.accepted
      entry.particle_expression = PARTICLES.current_expression(list_match.get_string(1).strip_edges())
    else:
      for value in list_match.get_string(1).split(",", false):
        entry.particles.append(PARTICLES.emission_name(value.strip_edges().to_lower()))
    body = body.substr(0, list_match.get_start()) + body.substr(list_match.get_end())
  for part in body.split(",", false):
    var token := part.strip_edges()
    if token.is_empty():
      continue
    var pair := token.split("=", true, 1)
    if pair.size() == 2:
      var key := pair[0].strip_edges().to_lower()
      var value := pair[1].strip_edges().to_lower()
      entry[key] = value.to_upper() if key == "facing" else value
    elif kind == "magnet" and token in ["+", "-", "+1", "-1"]:
      entry.polarity = token
    else:
      entry.facing = token.to_upper()
  if kind == "magnet" and str(entry.get("polarity", "positive")) not in CATALOG.VALID_POLARITIES:
    return {"error": "Invalid magnetic polarity: " + str(entry.polarity)}
  if not entry.has("x") or not entry.has("y"):
    return {"error": kind + " needs x and y coordinates."}
  if entry.facing not in CATALOG.DIRECTIONS and not (kind == "stray_particle" and entry.facing == CATALOG.STRAY.AT_REST):
    return {"error": "Invalid direction: " + entry.facing}
  if entry.has("rotation"):
    if entry.rotation not in ["4", "8"]:
      return {"error": "Building rotation must be 4 or 8 directions."}
    entry.rotation = int(entry.rotation)
  if kind == "edge_wall" and entry.facing not in CATALOG.CARDINALS:
    return {"error": "An edge wall must face E, S, W or N."}
  if kind == "filter" and entry.get("colour", "red") not in CATALOG.FILTER_COLOURS:
    return {"error": "A filter colour must be red, green or blue."}
  if kind == "gate" and entry.get("open", "false") not in ["true", "false"]:
    return {"error": "Gate open must be true or false."}
  if kind == "emitter":
    if entry.has("rate") and entry.has("period"):
      return {"error": "Use either period or legacy rate for an emitter, not both."}
    if entry.has("rate"):
      var rate := _parse_rate(str(entry.rate), legacy_rates)
      if rate <= 0.0 or not is_finite(1.0 / rate):
        return {"error": "Emitter rate must be finite and positive."}
      entry.period = 1.0 / rate
      entry.erase("rate")
    else:
      entry.period = _parse_period(str(entry.get("period", DEFAULT_PERIOD)))
    if entry.period <= 0.0:
      return {"error": "Emitter period must be a finite positive number of ticks."}
  elif entry.has("rate"):
    entry.rate = _parse_rate(str(entry.rate))
    if entry.rate <= 0.0: return {"error": "Rate must be positive."}
  for name in entry.particles:
    if not _valid_particle(name):
      return {"error": "Unknown particle: " + name}
  if kind == "stray_particle":
    if entry.particles.size() > 1:
      return {"error": "A stray particle needs a single particle type."}
    if entry.particles.is_empty(): entry.particles.append("electron")
  var xs := _range_values(str(entry.x))
  var ys := _range_values(str(entry.y))
  if xs.is_empty() or ys.is_empty():
    return {"error": "Invalid coordinate or range for " + kind}
  var entries: Array[Dictionary] = []
  for x in xs:
    for y in ys:
      if x < 0 or y < 0 or x >= width or y >= height:
        return {"error": "%s coordinate (%d, %d) is outside the grid." % [kind, x, y]}
      var placed: Dictionary = entry.duplicate(true)
      placed.x = x
      placed.y = y
      entries.append(placed)
  return {"entries": entries}

static func _range_endpoints(value: String) -> Array[int]:
  var parts := value.split("..")
  if parts.size() > 2 or not parts[0].strip_edges().is_valid_int() or (parts.size() == 2 and not parts[1].strip_edges().is_valid_int()):
    return []
  var first := int(parts[0])
  return [first, int(parts[1]) if parts.size() == 2 else first]

static func _range_values(value: String) -> Array[int]:
  var result: Array[int] = []
  var endpoints := _range_endpoints(value)
  if endpoints.is_empty(): return result
  var first := endpoints[0]
  var last := endpoints[1]
  var direction := 1 if last >= first else -1
  for number in range(first, last + direction, direction):
    result.append(number)
  return result

static func _valid_particle(name: String) -> bool:
  return PARTICLES.is_selector(name)

# Compile a particle expression into its matching particle names. AND binds
# more tightly than OR; commas retain the original list's OR behavior.
static func particle_expression(source: String) -> Dictionary:
  var lexer := RegEx.new()
  lexer.compile("\\s*(" + PARTICLE_TOKEN + ")")
  var output: Array[String] = []
  var operators: Array[String] = []
  var particles: Array[String] = []
  var pos := 0
  var expect_value := true
  while pos < source.length():
    if source.substr(pos).strip_edges().is_empty(): break
    var match_token := lexer.search(source, pos)
    if match_token == null or match_token.get_start() != pos:
      return {"error": "Invalid particle expression: " + source}
    pos = match_token.get_end()
    var token := PARTICLES.current_name(match_token.get_string(1).to_lower())
    if token == "(":
      if not expect_value: return {"error": "Add AND or OR before the opening bracket."}
      operators.append(token)
    elif token == ")":
      if expect_value: return {"error": "Add a particle before the closing bracket."}
      while not operators.is_empty() and operators.back() != "(":
        output.append(operators.pop_back())
      if operators.is_empty(): return {"error": "Unmatched closing bracket in particle expression."}
      operators.pop_back()
      expect_value = false
    elif token in ["and", "or", ","]:
      if expect_value: return {"error": "Add a particle before AND or OR."}
      if token == ",": token = "or"
      while not operators.is_empty() and operators.back() != "(" and (token == "or" or operators.back() == "and"):
        output.append(operators.pop_back())
      operators.append(token)
      expect_value = true
    else:
      if not expect_value or not _valid_particle(token):
        return {"error": "Invalid particle or missing operator: " + token}
      output.append(token)
      if token not in particles: particles.append(token)
      expect_value = false
  if expect_value: return {"error": "The expression needs a particle."}
  while not operators.is_empty():
    var operator: String = operators.pop_back()
    if operator == "(": return {"error": "Close the open bracket in the particle expression."}
    output.append(operator)
  var accepted: Array[String] = []
  for name in PARTICLES.TYPES:
    var stack: Array[bool] = []
    for token in output:
      if token in ["and", "or"]:
        var right: bool = stack.pop_back()
        var left: bool = stack.pop_back()
        stack.append(left and right if token == "and" else left or right)
      else:
        stack.append(name == token or PARTICLES.family(name) == token)
    if stack[0]: accepted.append(name)
  return {"particles": particles, "accepted": accepted}
