#!/bin/bash
# Step 3: build the official ProteoWizard (msconvert + Wine) image as a SIF.
# Run on a compute node (e.g. srun -p interact --mem=16G -t 2:00:00 --pty bash), not the login node.
set -euo pipefail
module load apptainer/1.5.0

PROJ=/users/j/a/jaileru/ST002118
# Keep the layer cache out of $HOME (home quota is nearly full)
export APPTAINER_CACHEDIR=$PROJ/containers/.cache
export APPTAINER_TMPDIR=${TMPDIR:-/tmp}
mkdir -p "$APPTAINER_CACHEDIR"

# The pwiz image is public on Docker Hub. Credentials exported in ~/.bashrc
# (a GitHub token) get sent to Docker Hub and cause "unauthorized" errors.
unset APPTAINER_DOCKER_USERNAME APPTAINER_DOCKER_PASSWORD
unset SINGULARITY_DOCKER_USERNAME SINGULARITY_DOCKER_PASSWORD

IMAGE=docker://proteowizard/pwiz-skyline-i-agree-to-the-vendor-licenses:latest
SIF=$PROJ/containers/pwiz.sif

apptainer build "$SIF" "$IMAGE"

# Record exactly which build we got, for reproducibility
apptainer inspect "$SIF" > "$PROJ/containers/pwiz.sif.inspect.txt"
sha256sum "$SIF" > "$PROJ/containers/pwiz.sif.sha256"
echo "Built $SIF"
