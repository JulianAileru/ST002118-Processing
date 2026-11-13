#!/bin/bash
# Convert a list of .raw files to mzML inside the pwiz container.
# Usage: msconvert_one.sh <outdir> <file1.raw> [file2.raw ...]
# Runs INSIDE the container (called by 04_msconvert_array.sbatch).
set -euo pipefail
if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <outdir> <file1.raw> [file2.raw ...]  (run inside pwiz container)" >&2
    exit 1
fi
OUTDIR=$1; shift

# The image's Wine prefix (/wineprefix64) is root-owned and read-only under Apptainer.
# Give each task its own writable copy on node-local disk so parallel tasks don't collide.
export WINEPREFIX=$(mktemp -d "${TMPDIR:-/tmp}/wine.XXXXXX")
trap 'wineserver -k 2>/dev/null || true; rm -rf "$WINEPREFIX"' EXIT
cp -a /wineprefix64/. "$WINEPREFIX/"
export WINEDEBUG=-all

# Peak-picking filter comes from PEAKPICK_FILTER (set in 04_msconvert_array.sbatch); empty = profile
FILTER_ARGS=()
[[ -n "${PEAKPICK_FILTER:-}" ]] && FILTER_ARGS=(--filter "$PEAKPICK_FILTER")

for RAW in "$@"; do
    BASE=$(basename "${RAW%.*}")
    if [[ -s "$OUTDIR/$BASE.mzML" ]]; then
        echo "SKIP (exists): $BASE"; continue
    fi
    echo "[$(date)] Converting $BASE"
    wine msconvert "$RAW" -o "$OUTDIR" --outfile "$BASE.mzML" \
        --mzML --zlib --64 "${FILTER_ARGS[@]}"
done
