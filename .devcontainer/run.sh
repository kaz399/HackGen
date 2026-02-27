#!/bin/bash
# Copyright 2026 Yabe Kazuhiro
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

# run.sh - Start (or enter) the HackGen dev container without VS Code.
#
# On first run the Docker image is built and a long-lived container is created.
# On subsequent runs the existing container is started (if stopped) and a new
# shell session is opened with 'docker exec'.  The container persists between
# sessions so you can stop/restart it without losing anything.
#
# Usage:
#   ./run.sh              # Build image if needed, then enter the container
#   ./run.sh --rebuild    # Rebuild the image and recreate the container
#   ./run.sh --stop       # Stop the running container
#   ./run.sh --remove     # Stop and remove the container (keeps the image)
#   ./run.sh --help       # Show this help

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration – mirrors devcontainer.json settings
# ---------------------------------------------------------------------------
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

IMAGE_NAME="hackgen-dev"
CONTAINER_NAME="hackgen-dev"
CONTAINER_USER="vscode"
WORKSPACE="/workspace"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info()  { echo "==> $*"; }
error() { echo "ERROR: $*" >&2; exit 1; }

usage() {
    cat <<EOF
Usage: $(basename "$0") [option]

Start a HackGen build container and open an interactive shell.
The repository root is mounted at ${WORKSPACE} inside the container.

Options:
  -r, --rebuild   Rebuild the Docker image and recreate the container
      --stop      Stop the running container
      --remove    Stop and remove the container (the image is kept)
  -h, --help      Show this help

Examples:
  $(basename "$0")             # Enter the container (builds on first run)
  $(basename "$0") --rebuild   # Rebuild image, then enter
  $(basename "$0") --stop      # Stop the container
  $(basename "$0") --remove    # Remove the container entirely
EOF
}

# Return the container state string, or empty string if it does not exist.
container_state() {
    docker inspect -f '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
MODE="enter"  # enter | stop | remove

while [ $# -gt 0 ]; do
    case "$1" in
        -r|--rebuild) MODE="rebuild"; shift ;;
        --stop)       MODE="stop";    shift ;;
        --remove)     MODE="remove";  shift ;;
        -h|--help)    usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# --stop
# ---------------------------------------------------------------------------
if [ "$MODE" = "stop" ]; then
    STATE=$(container_state)
    if [ "$STATE" = "running" ]; then
        info "Stopping container: $CONTAINER_NAME"
        docker stop "$CONTAINER_NAME" > /dev/null
        echo "Container stopped."
    else
        echo "Container '$CONTAINER_NAME' is not running (state: ${STATE:-not found})."
    fi
    exit 0
fi

# ---------------------------------------------------------------------------
# --remove
# ---------------------------------------------------------------------------
if [ "$MODE" = "remove" ]; then
    STATE=$(container_state)
    if [ -z "$STATE" ]; then
        echo "Container '$CONTAINER_NAME' does not exist."
    else
        info "Removing container: $CONTAINER_NAME"
        docker rm -f "$CONTAINER_NAME" > /dev/null
        echo "Container removed."
    fi
    exit 0
fi

# ---------------------------------------------------------------------------
# Build the image (MODE = enter | rebuild)
# ---------------------------------------------------------------------------
NEED_BUILD=false

if [ "$MODE" = "rebuild" ]; then
    NEED_BUILD=true
elif ! docker image inspect "$IMAGE_NAME" > /dev/null 2>&1; then
    info "Image '$IMAGE_NAME' not found – building for the first time."
    NEED_BUILD=true
fi

if $NEED_BUILD; then
    info "Building Docker image: $IMAGE_NAME"
    # Pass the host UID/GID so that files created inside the container are
    # owned by the same user on the host (mirrors devcontainer.json behaviour).
    docker build \
        --build-arg "USER_UID=$(id -u)" \
        --build-arg "USER_GID=$(id -g)" \
        -t "$IMAGE_NAME" \
        -f "$SCRIPT_DIR/Dockerfile" \
        "$REPO_ROOT"

    # Remove the stale container so it is recreated with the new image.
    STATE=$(container_state)
    if [ -n "$STATE" ]; then
        info "Removing stale container: $CONTAINER_NAME"
        docker rm -f "$CONTAINER_NAME" > /dev/null
    fi
fi

# ---------------------------------------------------------------------------
# Create or start the container
# ---------------------------------------------------------------------------
STATE=$(container_state)

case "$STATE" in
    "")
        info "Creating container: $CONTAINER_NAME"
        # Run as root with 'sleep infinity' so the container stays alive.
        # 'docker exec' below will switch to the unprivileged user.
        docker run -d \
            --name "$CONTAINER_NAME" \
            --mount "type=bind,source=${REPO_ROOT},target=${WORKSPACE},consistency=cached" \
            "$IMAGE_NAME" \
            sleep infinity > /dev/null
        ;;
    running)
        # Already running – nothing to do before exec.
        ;;
    *)
        info "Starting container: $CONTAINER_NAME (was: $STATE)"
        docker start "$CONTAINER_NAME" > /dev/null
        ;;
esac

# ---------------------------------------------------------------------------
# Open an interactive shell inside the container
# ---------------------------------------------------------------------------
info "Entering container '$CONTAINER_NAME' (type 'exit' or Ctrl-D to leave)"
exec docker exec -it \
    --user "$CONTAINER_USER" \
    --workdir "$WORKSPACE" \
    "$CONTAINER_NAME" \
    bash
