#!/usr/bin/env bash
#
# This script verifies host dependencies, creates an `.env` file from
# `.env.example` if necessary, ensures your system meets GPU and CUDA
# requirements, pulls the required container images and starts the Ollama
# service via Docker Compose.  It will automatically pull the model
# specified by the `OLLAMA_MODEL` environment variable.

set -euo pipefail

# Resolve the directory where this script resides and change to it
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

# Determine which .env file to load (default: .env)
ENV_FILE="${ENV_FILE:-.env}"
if [[ ! -f "$ENV_FILE" ]]; then
  if [[ -f .env.example ]]; then
    cp .env.example "$ENV_FILE"
    echo "Created $ENV_FILE from .env.example"
  else
    echo "ERROR: missing $ENV_FILE and .env.example" >&2
    exit 1
  fi
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

# Default values for variables if not set in .env
: "${OLLAMA_MODEL:=llama3.2:3b}"
: "${MIN_CUDA_VERSION:=12.0}"
: "${PORT:=11434}"
: "${GPU_COUNT:=all}"
: "${GPU_DEVICE_IDS:=}"

# Check if a command exists on the host
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Compare two version strings (returns true if $1 >= $2)
version_ge() {
  local left="$1"
  local right="$2"
  [[ "$(printf '%s\n%s\n' "$right" "$left" | sort -V | tail -n1)" == "$left" ]]
}

echo "==> Checking dependencies"
for cmd in git docker curl; do
  if ! command_exists "$cmd"; then
    echo "ERROR: Required command '$cmd' is not installed." >&2
    exit 1
  fi
  echo " - $cmd: OK"
done

# Determine which docker compose command to use
if docker compose version >/dev/null 2>&1; then
  compose_cmd="docker compose"
  echo " - docker compose: OK"
elif command_exists docker-compose; then
  compose_cmd="docker-compose"
  echo " - docker-compose: OK"
else
  echo "ERROR: docker compose (plugin or standalone) is required." >&2
  exit 1
fi

# GPU and CUDA detection
GPU_AVAILABLE=false
if command_exists nvidia-smi && [[ "$GPU_COUNT" != "0" ]]; then
  GPU_AVAILABLE=true
  CUDA_VERSION="$(nvidia-smi --query-gpu=cuda_version --format=csv,noheader 2>/dev/null | head -n1 | tr -d ' ')"
  DRIVER_VERSION="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -n1 | tr -d ' ')"
  if [[ -z "$CUDA_VERSION" || "$CUDA_VERSION" == "N/A" ]]; then
    echo "WARNING: NVIDIA GPU detected but CUDA runtime version was not reported."
  else
    echo " - NVIDIA CUDA version: $CUDA_VERSION"
    if version_ge "$CUDA_VERSION" "$MIN_CUDA_VERSION"; then
      echo " - CUDA requirement >= ${MIN_CUDA_VERSION}: OK"
    else
      echo "ERROR: CUDA ${CUDA_VERSION} is below required ${MIN_CUDA_VERSION}" >&2
      exit 1
    fi
  fi
  if [[ -n "$DRIVER_VERSION" ]]; then
    echo " - NVIDIA driver version: $DRIVER_VERSION"
  fi
else
  echo "WARNING: nvidia-smi not found or GPU_COUNT=0. Continuing with CPU-only fallback."
fi

echo "==> Pulling container images"
$compose_cmd pull

echo "==> Starting Ollama service"
$compose_cmd up -d ollama

echo "==> Waiting for Ollama and pulling model (${OLLAMA_MODEL})"
$compose_cmd run --rm model-init

# Determine the host IP to display to the user
if [[ -n "${HOST_IP:-}" ]]; then
  HOST="$HOST_IP"
else
  if command_exists hostname && hostname -I >/dev/null 2>&1; then
    HOST="$(hostname -I | awk '{print $1}')"
  else
    # Fallback: use ip route to determine the outbound IP
    HOST="$(ip route get 1.1.1.1 2>/dev/null | awk '{ for(i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit} }')"
  fi
fi
HOST="${HOST// /}"

echo ""
echo "Setup complete."
echo "Inference endpoint (local):  http://localhost:${PORT}"
echo "Inference endpoint (LAN):    http://${HOST}:${PORT}"
echo ""
echo "Example request:"
echo "curl http://localhost:${PORT}/api/generate -d '{\"model\":\"${OLLAMA_MODEL}\",\"prompt\":\"Hello\"}'"