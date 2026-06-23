#!/usr/bin/env bash
#
# check-perf-floors.sh — order-of-magnitude performance regression gate.
#
# Parses the `PERF[name]: N unit/sec ...` lines that PerformanceBaselineTests
# prints into captured test output and fails if any benchmark's throughput is
# below its floor from bitchatTests/Performance/perf-floors.json.
#
# Floor philosophy (see the floors file): floors sit at ~25% of locally
# measured throughput, so they catch algorithmic regressions (O(n) -> O(n^2)),
# never runner variance. Raise floors deliberately after intentional
# improvements; never tune them to chase noise.
#
# Usage: scripts/check-perf-floors.sh <test-output-file> [floors-file]
#
# Skips gracefully (exit 0) when:
#   - BITCHAT_SKIP_PERF_BASELINES=1 (perf tests were skipped), or
#   - the output contains no PERF lines (e.g. package-only matrix entries).
#
# Fails (exit 1) when:
#   - any benchmark reports throughput below its floor, or
#   - PERF lines are present but a floored benchmark is missing
#     (a silently-dropped benchmark must be an explicit floors-file change).

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "usage: $0 <test-output-file> [floors-file]" >&2
    exit 2
fi

OUTPUT_FILE="$1"
FLOORS_FILE="${2:-$(cd "$(dirname "$0")/.." && pwd)/bitchatTests/Performance/perf-floors.json}"

if [[ "${BITCHAT_SKIP_PERF_BASELINES:-}" == "1" ]]; then
    echo "perf-floors: BITCHAT_SKIP_PERF_BASELINES=1 — skipping gate."
    exit 0
fi

if [[ ! -f "$OUTPUT_FILE" ]]; then
    echo "perf-floors: output file '$OUTPUT_FILE' not found — skipping gate." >&2
    exit 0
fi

if [[ ! -f "$FLOORS_FILE" ]]; then
    echo "perf-floors: floors file '$FLOORS_FILE' not found." >&2
    exit 2
fi

if ! grep -q 'PERF\[' "$OUTPUT_FILE"; then
    echo "perf-floors: no PERF lines in '$OUTPUT_FILE' — skipping gate."
    exit 0
fi

OUTPUT_FILE="$OUTPUT_FILE" FLOORS_FILE="$FLOORS_FILE" python3 - <<'PYEOF'
import json
import os
import re
import sys

output_file = os.environ["OUTPUT_FILE"]
floors_file = os.environ["FLOORS_FILE"]

with open(floors_file) as f:
    floors = json.load(f)["floors"]

# PERF[delivery.storeUpdate]: 158862 updates/sec (avg 3.147 ms per pass of 500, 10 passes)
pattern = re.compile(r"PERF\[([^\]]+)\]:\s*([0-9]+(?:\.[0-9]+)?)\s*(\S+)/sec")

measured = {}
with open(output_file, errors="replace") as f:
    for line in f:
        m = pattern.search(line)
        if m:
            # Keep the last reported value if a benchmark prints twice.
            measured[m.group(1)] = (float(m.group(2)), m.group(3))

failures = []
print(f"perf-floors: checking {len(measured)} benchmark(s) against {len(floors)} floor(s)")
for name in sorted(set(floors) | set(measured)):
    floor = floors.get(name)
    if name not in measured:
        failures.append(
            f"  MISSING  {name}: floored benchmark reported no PERF line "
            f"(removed/renamed? update perf-floors.json in the same change)")
        continue
    value, unit = measured[name]
    if floor is None:
        print(f"  NO-FLOOR {name}: {value:.0f} {unit}/sec (consider adding a floor)")
        continue
    status = "OK" if value >= floor else "BELOW"
    line = f"  {status:8} {name}: {value:.0f} {unit}/sec (floor {floor})"
    print(line)
    if value < floor:
        failures.append(
            f"  BELOW    {name}: {value:.0f} {unit}/sec is under floor {floor} "
            f"({value / floor * 100:.0f}% of floor)")

if failures:
    print("\nperf-floors: FAILED — order-of-magnitude-class regression suspected:")
    print("\n".join(failures))
    print("\nFloors are ~25% of healthy local throughput; falling below one means an")
    print("algorithmic regression, not runner noise. If the change is intentional,")
    print("update bitchatTests/Performance/perf-floors.json deliberately.")
    sys.exit(1)

print("perf-floors: all benchmarks at or above their floors.")
PYEOF
