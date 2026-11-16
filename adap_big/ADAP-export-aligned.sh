#!/bin/bash

#SBATCH --job-name=ADAP_EXPORT_ALIGNED
#SBATCH --output=/users/j/a/jaileru/ST002118-Processing/logs/adap_export_aligned_%j.out
#SBATCH --error=/users/j/a/jaileru/ST002118-Processing/logs/adap_export_aligned_%j.err
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=16
#SBATCH --mem=160g
#SBATCH -t 12:00:00
#SBATCH --mail-type=begin,end,fail

# Export the between-batch aligned features (before normalization / batch-effect correction)
# from an existing ADAP-BIG run to a feature table (.csv) and MS/MS spectra (.msp).
# No reprocessing: runs only ADAP-BIG's OutputModule on
#   <run>/ALL_BATCHES/5.ALIGNED_COMPONENTS/aligned_features.ser
#
# Usage:  sbatch ADAP-export-aligned.sh [run_dir]
#   run_dir defaults to the most recent adap_big/runs/adap-big_* folder.

set -euo pipefail
module purge
module add java/23.0.2

PROJ=/users/j/a/jaileru/ST002118-Processing
ADAP=$PROJ/adap_big
JAR=$ADAP/adap-big-console-app-v1.6.0.jar

RUN=${1:-$(ls -d "$ADAP"/runs/adap-big_* | sort | tail -1)}
INPUT=$RUN/ALL_BATCHES/5.ALIGNED_COMPONENTS/aligned_features.ser
OUTDIR=$RUN/exports
OUT=$OUTDIR/ST002118_aligned_features

[[ -f "$INPUT" ]] || { echo "ERROR: input not found: $INPUT" >&2; exit 1; }
mkdir -p "$OUTDIR"

echo "Run folder : $RUN"
echo "Input      : $INPUT"
echo "Output     : $OUT.*"

# OutputModule writes ONE file per call; the format is taken from the --output extension
# (.csv | .msp | .pdf). --outputlevel (ms1 | ms2, default ms1) only matters for .msp.
export_one () {   # $1 = output file, remaining args = extra options
  local out=$1; shift
  echo "=== Writing $out"
  java \
    -Xms16G \
    -Xmx144G \
    -XX:ActiveProcessorCount=16 \
    -cp "$JAR" org.dulab.adapbig.output.OutputMain \
    --project "$RUN" \
    --multi-batch ALL_BATCHES \
    --type aligned_component \
    --filename aligned_features \
    --output "$out" \
    "$@"
}

export_one "$OUT.csv" --with_ions                    # feature table
export_one "${OUT}_msms.msp" --outputlevel ms2       # MS/MS spectra
# If the MS/MS .msp is empty (no MS2 paired to features), MS1 spectra instead:
# export_one "${OUT}_ms1.msp" --outputlevel ms1

echo "Files written:"
ls -la "$OUTDIR"
# Fallback in case ADAP-BIG resolved the output relative to somewhere else
find "$RUN" "$ADAP" -maxdepth 3 -newer "$INPUT" -name 'ST002118_aligned_features*' -not -path "$OUTDIR/*" 2>/dev/null
