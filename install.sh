#!/usr/bin/env bash
#
# This script verifies host dependencies, creates an `.env` file from
# `.env.example` if necessary, ensures your system meets GPU and CUDA
# requirements, pulls the required container images and starts the Ollama
# service via Docker Compose. It will automatically pull the model
# specified by the `OLLAMA_MODEL` environment variable.

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
			value="${value#"${value%%[![:space:]]*}"}"
			if [[ "$value" =~ ^\"(.*)\"$ ]]; then
				value="${BASH_REMATCH[1]}"
			elif [[ "$value" =~ ^\'(.*)\'$ ]]; then
				value="${BASH_REMATCH[1]}"
			else
				value="${value%%[[:space:]]#*}"
			fi
			printf -v "$key" '%s' "$value"
			export "${key?}"
		else
			echo "WARNING: Ignoring unsupported line in $file: $line" >&2
		fi
	done <"$file"
}

load_env_file "$ENV_FILE"

: "${OLLAMA_MODEL:=llama3.2:3b}"
: "${MIN_CUDA_VERSION:=12.0}"
: "${PORT:=11434}"
: "${GPU_COUNT:=all}"
: "${GPU_DEVICE_IDS:=}"

if ! [[ "$PORT" =~ ^[0-9]+$ ]] || ((PORT < 1 || PORT > 65535)); then
	echo "ERROR: PORT must be an integer between 1 and 65535 (got '$PORT')." >&2
	exit 1
fi

command_exists() {
	command -v "$1" >/dev/null 2>&1
}

version_ge() {
	local left="$1"
	local right="$2"
	[[ "$(printf '%s\n%s\n' "$right" "$left" | sort -V | tail -n1)" == "$left" ]]
}

dump_compose_diagnostics() {
	local exit_code="$1"
	echo "ERROR: model-init failed (exit code: ${exit_code}). Collecting diagnostics..." >&2
	"${compose_cmd[@]}" ps || true
	"${compose_cmd[@]}" logs --tail=100 ollama || true
}

echo "==> Checking dependencies"
if ! command_exists docker; then
	echo "ERROR: Required command 'docker' is not installed." >&2
	exit 1
fi
echo " - docker: OK"

if ! docker info >/dev/null 2>&1; then
	echo "ERROR: Docker daemon is not reachable. Please start Docker and retry." >&2
	exit 1
fi

echo " - docker daemon: OK"

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

if command_exists nvidia-smi && [[ "$GPU_COUNT" != "0" ]]; then
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
"${compose_cmd[@]}" pull

echo "==> Starting Ollama service"
"${compose_cmd[@]}" up -d ollama

if [[ "$GPU_COUNT" != "0" ]]; then
	echo "==> Checking GPU visibility inside the Ollama container"
	if "${compose_cmd[@]}" exec -T ollama nvidia-smi >/dev/null 2>&1; then
		echo " - GPU runtime check: OK"
	else
		echo "WARNING: Unable to run 'nvidia-smi' in ollama container. GPU acceleration may be unavailable."
	fi
fi

echo "==> Waiting for Ollama and pulling model (${OLLAMA_MODEL})"
if "${compose_cmd[@]}" run --rm model-init; then
	:
else
	status=$?
	dump_compose_diagnostics "$status"
	exit "$status"
fi

echo "==> Running local API smoke test"
if command_exists curl; then
	if curl --silent --show-error --fail "http://localhost:${PORT}/api/tags" >/dev/null; then
		echo " - API smoke test: OK"
	else
		echo "WARNING: Could not reach http://localhost:${PORT}/api/tags from the host."
	fi
else
	echo "WARNING: curl not found; skipping API smoke test."
fi

if [[ -n "${HOST_IP:-}" ]]; then
	HOST="$HOST_IP"
else
	if command_exists hostname && hostname -I >/dev/null 2>&1; then
		HOST="$(hostname -I | awk '{print $1}')"
	else
		HOST="$(ip route get 1.1.1.1 2>/dev/null | awk '{ for(i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit} }')"
	fi
fi
HOST="${HOST// /}"
HOST="${HOST:-localhost}"

echo ""
echo "Setup complete."
echo "Inference endpoint (local):  http://localhost:${PORT}"
echo "Inference endpoint (LAN):    http://${HOST}:${PORT}"
echo ""
echo "Example request:"
echo "curl http://localhost:${PORT}/api/generate -d '{\"model\":\"${OLLAMA_MODEL}\",\"prompt\":\"Hello\"}'"
