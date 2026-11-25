#!/usr/bin/env python3
"""Compare running Godot CPU time under Linux. Does not measure GPU or battery."""
import argparse
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
HZ = os.sysconf("SC_CLK_TCK")


def cpu_ticks(pid):
    # stat starts with PID followed by the command in parentheses.
    fields = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()
    return int(fields[11]) + int(fields[12])


def run(godot, variant, scenario, seconds, warmup):
    command = [godot, "--headless", "res://Tests/Battery/benchmark.tscn", "--",
               f"variant={variant}", f"scenario={scenario}", f"seconds={seconds}",
               f"warmup={warmup}"]
    with subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE, text=True) as process:
        start = None
        result = None
        for line in process.stdout:
            if line.startswith("VERTEX_BENCH_START "):
                start = cpu_ticks(process.pid)
            elif line.startswith("VERTEX_BENCH_END "):
                end = cpu_ticks(process.pid)
                result = json.loads(line.split(" ", 1)[1])
                if start is not None:
                    result["cpu_ms_per_second"] = round((end - start) * 1000 / HZ /
                                                        result["seconds"], 2)
        if process.wait() or not result or "cpu_ms_per_second" not in result:
            raise RuntimeError(f"Benchmark did not finish: {variant} {scenario}")
        print(json.dumps(result), flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--repeats", type=int, default=2)
    parser.add_argument("--active-seconds", type=float, default=35)
    parser.add_argument("--idle-seconds", type=float, default=8)
    args = parser.parse_args()
    for repeat in range(args.repeats):
        active = ["baseline", "fps30", "forecast64", "combined"]
        idle = ["baseline", "fps30"]
        if repeat % 2:
            active.reverse()
            idle.reverse()
        for variant in active:
            run(args.godot, variant, "active", args.active_seconds, 10)
        for variant in idle:
            run(args.godot, variant, "idle", args.idle_seconds, 2)
