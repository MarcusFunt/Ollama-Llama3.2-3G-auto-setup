#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

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

: "${OLLAMA_MODEL:=llama3.2:3b}"
: "${MIN_CUDA_VERSION:=12.0}"

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

version_ge() {
  local left right
  left="$1"
  right="$2"
  [[ "$(printf '%s\n%s\n' "$right" "$left" | sort -V | tail -n1)" == "$left" ]]
}

echo "==> Checking dependencies"
for cmd in git docker; do
  if ! command_exists "$cmd"; then
    echo "ERROR: Required command '$cmd' is not installed." >&2
    exit 1
  fi
  echo " - $cmd: OK"
done

if docker compose version >/dev/null 2>&1; then
  echo " - docker compose: OK"
elif command_exists docker-compose; then
  echo " - docker-compose: OK"
else
  echo "ERROR: docker compose (plugin or standalone) is required." >&2
  exit 1
fi

GPU_AVAILABLE=false
if command_exists nvidia-smi; then
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
  echo "WARNING: nvidia-smi not found. Continuing with CPU-only fallback."
fi

echo "==> Pulling container images"
docker compose pull

echo "==> Starting Ollama service"
docker compose up -d ollama

if [[ "$GPU_AVAILABLE" == true ]]; then
  echo "==> Waiting for Ollama and pulling model (${OLLAMA_MODEL})"
  docker compose run --rm model-init
else
  echo "==> Pulling model (${OLLAMA_MODEL}) without GPU check"
  docker compose run --rm model-init
fi

HOST_IP="${HOST_IP:-$(hostname -I | awk '{print $1}') }"
HOST_IP="${HOST_IP// /}"

echo ""
echo "Setup complete."
echo "Inference endpoint (local):  http://localhost:11434"
echo "Inference endpoint (Wi-Fi): http://${HOST_IP:-<host-ip>}:11434"
echo ""
echo "Example request:"
echo "curl http://localhost:11434/api/generate -d '{\"model\":\"${OLLAMA_MODEL}\",\"prompt\":\"Hello\"}'"
