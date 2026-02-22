# Ollama + Llama 3.2 (3B) Auto Setup

This repository provides a **one-command** workflow for standing up a local
Ollama service and preloading a _Llama 3.2 3B_ model.

## What the installer does

1. Verifies host dependencies (`docker`, `docker compose`) and confirms the Docker daemon is running.
2. Checks for an NVIDIA GPU and enforces a minimum CUDA runtime version.
3. Starts an Ollama Docker container with safe defaults:
   - service bind inside container: `0.0.0.0:11434` (required for inter-container networking)
   - host publish interface: `127.0.0.1` (local-only by default)
4. Optionally validates GPU visibility from inside the running `ollama` container.
5. Pulls a model (default `llama3.2:3b`) automatically via a helper container.
6. Runs a host-side API smoke test (`/api/tags`) when `curl` is available.

## Requirements

- **Operating system:** A 64-bit Linux distribution or Windows via WSL2.
- **Docker:** [Docker](https://www.docker.com) 20.10+ with either:
  - the Compose plugin (`docker compose`), or
  - standalone `docker-compose`.
- **GPU (optional):** NVIDIA GPU + [NVIDIA Container Toolkit]
  (https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html).
  The 3B model usually needs about 4-6 GB of VRAM.

## Quick start

```bash
git clone https://github.com/<your-user>/Ollama-Llama3.2-3G-auto-setup.git
cd Ollama-Llama3.2-3G-auto-setup
./install.sh
```

## Configuration

Create `.env` from `.env.example` (or let `install.sh` create it automatically on first run).

| Variable | Description | Default |
| --- | --- | --- |
| `OLLAMA_VERSION` | Docker image tag for Ollama | `latest` |
| `OLLAMA_MODEL` | Model to preload | `llama3.2:3b` |
| `MIN_CUDA_VERSION` | Minimum CUDA runtime required by installer | `12.0` |
| `OLLAMA_HOST` | Bind address **inside container**. Keep `0.0.0.0:11434` for Docker service-to-service access | `0.0.0.0:11434` |
| `HOST_BIND_IP` | Host interface used in `ports` publish (`127.0.0.1` local-only, `0.0.0.0` LAN) | `127.0.0.1` |
| `HOST_IP` | Optional override for printed LAN address | auto-detected |
| `PORT` | Host port to publish | `11434` |
| `GPU_COUNT` | GPU request for Compose (`all`, `0`, or positive integer) | `all` |
| `GPU_DEVICE_IDS` | Comma-separated GPU device IDs for `NVIDIA_VISIBLE_DEVICES` | blank |

### `.env` parser caveats

The installer intentionally parses a safe subset of `.env` syntax (no `source`/`eval`).
Supported format is `KEY=VALUE` with optional single or double quotes and trailing comments.
Unsupported constructs are ignored with a warning, including:

- variable interpolation (`A=${B}`)
- multiline values
- `export KEY=value`
- shell command substitution/backticks

## Security notes

Ollama exposes an unauthenticated HTTP API.

- **Default setup is local-only** because host publish binds to `127.0.0.1`.
- If you set `HOST_BIND_IP=0.0.0.0`, your LAN can reach the API.
- For remote/shared access, place a reverse proxy in front with auth + TLS.

## Managing the stack

```bash
# Start or restart
docker compose up -d

# Show status
docker compose ps

# Logs
docker compose logs -f ollama

# Stop and remove services
docker compose down
```

## Troubleshooting

If model initialization fails during `install.sh`, the script now prints:

- `docker compose ps`
- `docker compose logs --tail=100 ollama`

This should speed up root-cause analysis for startup/model-pull issues.
