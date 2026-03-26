#!/usr/bin/env bash
set -e

# The script is symlinked to /home/andre, so we need to use the real path
# to find the runner-image directory which is next to the original script.
REAL_SCRIPT_PATH=$(readlink -f "${BASH_SOURCE[0]}")
DIR="$( cd "$( dirname "$REAL_SCRIPT_PATH" )" && pwd )"

echo "Building custom runner image with Maven cache settings..."
cd "$DIR/runner-image"

# Build the image using docker buildx for linux/amd64
docker buildx build --platform linux/amd64 -t ahelberg/hydra-runner:latest --push .

echo "Done! Image ahelberg/hydra-runner:latest is pushed."
echo "Restarting fireactions service to pick up the new image..."
sudo systemctl restart fireactions

