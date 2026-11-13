#!/bin/bash

#SBATCH --job-name=ADAP_BIG_ST002118
#SBATCH --output=/users/j/a/jaileru/ST002118-Processing/logs/adap_big_%j.out
#SBATCH --error=/users/j/a/jaileru/ST002118-Processing/logs/adap_big_%j.err
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=64
#SBATCH --mem=256g
#SBATCH -t 120:00:00
#SBATCH --mail-type=begin,end,fail
# Add your own address to get notifications:
##SBATCH --mail-user=jaileru@unc.edu

# Workflow: background removal step removed (no blanks in ST002118) -- see workflow.xml.
# Factors:  regenerate with  python scripts/generate_metadata_file.py

set -euo pipefail
module purge
module add java/23.0.2

PROJ=/users/j/a/jaileru/ST002118-Processing
ADAP=$PROJ/adap_big
WORKDIR=$ADAP/runs          # ADAP-BIG creates a timestamped project folder in here
mkdir -p "$WORKDIR"
cd "$ADAP"                  # gc log lands here

java \
  -Xms16G \
  -Xmx192G \
  -XX:ActiveProcessorCount=64 \
  -Xlog:gc*:file=$ADAP/gc-${SLURM_JOB_ID}.log:time,uptime,level,tags \
  -jar $ADAP/adap-big-console-app-v1.6.0.jar \
  -d "$WORKDIR" \
  -f $PROJ/mzML \
  --factors $ADAP/ST002118_metadata.csv \
  -w $ADAP/workflow.xml \
  -s $ADAP/settings.xml
