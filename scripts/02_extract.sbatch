#!/bin/bash
#SBATCH --job-name=ST002118_unzip
#SBATCH --partition=general
#SBATCH --time=12:00:00
#SBATCH --mem=4G
#SBATCH --cpus-per-task=1
#SBATCH --output=/users/j/a/jaileru/ST002118-Processing/logs/02_extract_%j.log
# Step 2: extract the archive and build the list of .raw files to convert.
set -euo pipefail

PROJ=/users/j/a/jaileru/ST002118
ZIP=$PROJ/raw/zip/ST002118_HHEAR_Lichtveld.zip
DEST=$PROJ/raw/extracted

unzip -l "$ZIP" > "$PROJ/raw/zip_contents.txt"
unzip -n -q "$ZIP" -d "$DEST"    # -n: never overwrite, so safe to re-run

# Thermo .raw files (case-insensitive), sorted for a stable array-index mapping
find "$DEST" -type f -iname '*.raw' | sort > "$PROJ/raw/raw_files.txt"
echo "[$(date)] Found $(wc -l < "$PROJ/raw/raw_files.txt") .raw files"
