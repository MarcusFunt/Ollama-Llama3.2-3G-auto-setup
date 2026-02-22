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

# Load supported KEY=VALUE pairs from env file without executing code.
load_env_file() {
  local file="$1"
  local line key value
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue

    if [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      value="${BASH_REMATCH[2]}"
      value="${value#${value%%[![:space:]]*}}"
      if [[ "$value" =~ ^\"(.*)\"$ ]]; then
        value="${BASH_REMATCH[1]}"
      elif [[ "$value" =~ ^\'(.*)\'$ ]]; then
        value="${BASH_REMATCH[1]}"
      else
        value="${value%%[[:space:]]#*}"
      fi
      printf -v "$key" '%s' "$value"
      export "$key"
    else
      echo "WARNING: Ignoring unsupported line in $file: $line" >&2
    fi
  done <"$file"
}

load_env_file "$ENV_FILE"

# Default values for variables if not set in .env
: "${OLLAMA_MODEL:=llama3.2:3b}"
: "${MIN_CUDA_VERSION:=12.0}"
: "${OLLAMA_BIND_ADDRESS:=127.0.0.1}"
: "${PORT:=11434}"
: "${GPU_COUNT:=all}"
: "${GPU_DEVICE_IDS:=}"

if ! [[ "$PORT" =~ ^[0-9]+$ ]] || ((PORT < 1 || PORT > 65535)); then
  echo "ERROR: PORT must be an integer between 1 and 65535 (got '$PORT')." >&2
  exit 1
fi

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
for cmd in docker curl; do
  if ! command_exists "$cmd"; then
    echo "ERROR: Required command '$cmd' is not installed." >&2
    exit 1
  fi
  echo " - $cmd: OK"
done

if ! docker info >/dev/null 2>&1; then
  echo "ERROR: Docker daemon is not reachable. Please start Docker and retry." >&2
  exit 1
fi

echo " - docker daemon: OK"

# Determine which docker compose command to use
if docker compose version >/dev/null 2>&1; then
  compose_cmd=(docker compose)
  echo " - docker compose: OK"
elif command_exists docker-compose; then
  compose_cmd=(docker-compose)
  echo " - docker-compose: OK"
else
  echo "ERROR: docker compose (plugin or standalone) is required." >&2
  exit 1
fi

# GPU and CUDA detection
USE_GPU=false
if command_exists nvidia-smi && [[ "$GPU_COUNT" != "0" ]]; then
  CUDA_VERSION="$(nvidia-smi --query-gpu=cuda_version --format=csv,noheader 2>/dev/null | head -n1 | tr -d ' ')"
  DRIVER_VERSION="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -n1 | tr -d ' ')"
  if [[ -z "$CUDA_VERSION" || "$CUDA_VERSION" == "N/A" ]]; then
    echo "WARNING: NVIDIA GPU detected but CUDA runtime version was not reported."
  else
    echo " - NVIDIA CUDA version: $CUDA_VERSION"
    if version_ge "$CUDA_VERSION" "$MIN_CUDA_VERSION"; then
      echo " - CUDA requirement >= ${MIN_CUDA_VERSION}: OK"
      if docker info -f '{{.Runtimes}}' 2>/dev/null | grep -q nvidia; then
        echo " - Docker NVIDIA runtime: OK"
        USE_GPU=true
      else
        echo "WARNING: NVIDIA GPU detected but Docker 'nvidia' runtime is not configured."
        echo "         See: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html"
      fi
    else
      echo "ERROR: CUDA ${CUDA_VERSION} is below required ${MIN_CUDA_VERSION}" >&2
      exit 1
    fi
  fi
  if [[ -n "$DRIVER_VERSION" ]]; then
    echo " - NVIDIA driver version: $DRIVER_VERSION"
  fi
fi

if [[ "$USE_GPU" == "true" ]]; then
  echo "==> Configuring GPU support (docker-compose.override.yml)"
  cat <<EOF >docker-compose.override.yml
services:
  ollama:
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: ${GPU_COUNT:-all}
              capabilities: [gpu]
    environment:
      NVIDIA_VISIBLE_DEVICES: ${GPU_DEVICE_IDS:-all}
EOF
else
  echo "==> Continuing with CPU-only mode"
  rm -f docker-compose.override.yml
fi

echo "==> Pulling container images"
"${compose_cmd[@]}" pull

echo "==> Starting Ollama service"
"${compose_cmd[@]}" up -d ollama

echo "==> Waiting for Ollama and pulling model (${OLLAMA_MODEL})"
"${compose_cmd[@]}" run --rm model-init

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
HOST="${HOST:-localhost}"

echo ""
echo "Setup complete."
echo "Inference endpoint (local):  http://localhost:${PORT}"
if [[ "$OLLAMA_BIND_ADDRESS" == "0.0.0.0" ]]; then
  echo "Inference endpoint (LAN):    http://${HOST}:${PORT}"
elif [[ "$OLLAMA_BIND_ADDRESS" != "127.0.0.1" ]]; then
  echo "Inference endpoint (Bind):   http://${OLLAMA_BIND_ADDRESS}:${PORT}"
fi
echo ""
echo "Example request:"
echo "curl http://localhost:${PORT}/api/generate -d '{\"model\":\"${OLLAMA_MODEL}\",\"prompt\":\"Hello\"}'"
