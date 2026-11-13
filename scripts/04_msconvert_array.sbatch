#!/bin/bash
#SBATCH --job-name=ST002118_msconvert
#SBATCH --partition=general
#SBATCH --time=08:00:00
#SBATCH --mem=8G
#SBATCH --cpus-per-task=2
#SBATCH --output=/users/j/a/jaileru/ST002118-Processing/logs/04_msconvert_%A_%a.log
# Step 4: convert .raw -> .mzML as a SLURM array, FILES_PER_TASK files per task.
# Submit with:  N=$(wc -l < raw/raw_files.txt); FPT=10
#               sbatch --array=0-$(( (N+FPT-1)/FPT - 1 ))%40 --export=ALL,FILES_PER_TASK=$FPT scripts/04_msconvert_array.sbatch
# Re-submitting is safe: existing non-empty mzML files are skipped.
set -euo pipefail
module load apptainer/1.5.0

PROJ=/users/j/a/jaileru/ST002118-Processing
SIF=$PROJ/containers/pwiz.sif
LIST=$PROJ/raw/raw_files.txt
OUTDIR=$PROJ/mzML
FPT=${FILES_PER_TASK:-10}

# Centroid all MS levels using the vendor (Thermo) algorithm — what XCMS/MZmine etc. expect.
# Set to "" to keep profile data.
PEAKPICK_FILTER=${PEAKPICK_FILTER-"peakPicking vendor msLevel=1-"}

START=$(( SLURM_ARRAY_TASK_ID * FPT + 1 ))
mapfile -t FILES < <(sed -n "${START},$(( START + FPT - 1 ))p" "$LIST")
[[ ${#FILES[@]} -eq 0 ]] && { echo "No files for task $SLURM_ARRAY_TASK_ID"; exit 0; }

mkdir -p "$OUTDIR"
apptainer exec --cleanenv \
    --env PEAKPICK_FILTER="$PEAKPICK_FILTER" \
    -B "$PROJ" -B "${TMPDIR:-/tmp}" \
    "$SIF" bash "$PROJ/scripts/msconvert_one.sh" "$OUTDIR" "${FILES[@]}"
