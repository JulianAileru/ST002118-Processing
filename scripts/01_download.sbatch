#!/bin/bash
#SBATCH --job-name=ST002118_dl
#SBATCH --partition=datamover
#SBATCH --time=2-00:00:00
#SBATCH --mem=4G
#SBATCH --cpus-per-task=2
#SBATCH --output=/users/j/a/jaileru/ST002118-Processing/logs/01_download_%j.log
# Step 1: download the ST002118 raw-data archive (87.1 GB) from Metabolomics Workbench FTP.
# Resumable: re-submitting continues a partial download (wget -c).
set -euo pipefail

PROJ=/users/j/a/jaileru/ST002118
URL=ftp://www.metabolomicsworkbench.org/Studies/ST002118_HHEAR_Lichtveld.zip
OUT=$PROJ/raw/zip/ST002118_HHEAR_Lichtveld.zip
EXPECTED_BYTES=87122217392   # Content-Length reported by the FTP server

mkdir -p "$(dirname "$OUT")"
echo "[$(date)] Downloading $URL"
wget -c --tries=20 --waitretry=60 --read-timeout=300 --progress=dot:giga -O "$OUT" "$URL"

ACTUAL=$(stat -c %s "$OUT")
echo "[$(date)] Size: $ACTUAL (expected $EXPECTED_BYTES)"
if [[ "$ACTUAL" -ne "$EXPECTED_BYTES" ]]; then
    echo "ERROR: size mismatch; re-submit this job to resume." >&2
    exit 1
fi
unzip -tq "$OUT" && echo "[$(date)] Zip integrity test passed."
