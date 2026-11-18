#!/bin/bash

#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --mem=400G
#SBATCH -t 4-00:00:00
#SBATCH --mail-user=jaileru@unc.edu
#SBATCH --mail-type=BEGIN,END,FAIL

module load r
export PYTHONHASHSEED=0
SERRF=/users/j/a/jaileru/ST002118-Processing/repos/serrf-py

uv run --project "$SERRF" python st002118_batch_effect_correction.py
