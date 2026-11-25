#!/usr/bin/env bash
# Prerequisites: Godot 4.7.2, Android SDK and Godot export templates.
# Configure Android SDK and Java in Godot, and set GODOT_ANDROID_KEYSTORE_DEBUG_PATH,
# GODOT_ANDROID_KEYSTORE_DEBUG_USER and GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD.
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
out="$(realpath -m -- "${1:-vertex-battery-benchmark.apk}")"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
# Export from a copy so the normal Vertex app and export preset stay unchanged.
tar -C "$root" --exclude=.git --exclude=.godot --exclude=build --exclude=builds \
  --exclude='*.apk' -cf - . | tar -C "$tmp" -xf -
cd "$tmp"
python3 - <<'PY'
from pathlib import Path
p = Path("project.godot")
text = p.read_text()
old = 'run/main_scene="res://MainScene/level_select.tscn"'
assert text.count(old) == 1
text = text.replace(old, 'run/main_scene="res://Tests/Battery/benchmark.tscn"')
p.write_text(text)
p = Path("export_presets.cfg")
text = p.read_text()
old = 'package/unique_name="com.example.$genname"'
assert text.count(old) == 1
p.write_text(text.replace(old, 'package/unique_name="com.breakerchap.vertexbattery"')
             .replace('package/name=""', 'package/name="Vertex Battery Test"'))
PY
"${GODOT:-godot}" --headless --import
"${GODOT:-godot}" --headless --export-debug Android "$out"
test -s "$out"
