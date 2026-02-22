# Ollama + Llama 3.2 (3B) Auto Setup

This repository provides a **one‑command** workflow for standing up a local
Ollama service and preloading a _Llama 3.2 3B_ model.  It automates the
following tasks:

1. Verifies host dependencies (`docker`, `docker compose`, `curl`) and confirms the Docker daemon is running.
2. Checks for an NVIDIA GPU and enforces a minimum CUDA runtime version.
3. Starts an Ollama Docker container with the API bound to
   `127.0.0.1:11434` by default to limit access to localhost.
4. Pulls a model (default `llama3.2:3b`) automatically via a helper
   container.
5. Exposes the inference endpoint on your local network when configured via
   the `OLLAMA_BIND_ADDRESS` environment variable.

## Requirements

- **Operating system:** A 64‑bit Linux distribution or Windows via WSL2.
- **Docker:** [Docker](https://www.docker.com) 20.10 or later with the
  [Compose plugin](https://docs.docker.com/compose/install/) (`docker compose`)
  or the standalone `docker‑compose` binary.
- **curl:** Used by the installer to test network connectivity.
- **GPU (optional):** An NVIDIA GPU is recommended for better performance.
  If present, you must install the [NVIDIA Container Toolkit]
  (https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html).
  The 3B model requires roughly 4–6 GB of VRAM.  Without a GPU, the script
  falls back to CPU inference.

## Quick start

```bash
git clone https://github.com/<your-user>/Ollama-Llama3.2-3G-auto-setup.git
cd Ollama-Llama3.2-3G-auto-setup
./install.sh
```

After setup:

- **Local endpoint:** `http://localhost:11434`
- **LAN endpoint:** `http://<your-host-ip>:11434` (if you override
  `OLLAMA_BIND_ADDRESS` to `0.0.0.0`)

## Configuration

Create a copy of `.env` from `.env.example` and adjust the variables to suit
your environment.  The installer will automatically create `.env` on first
run if it does not exist.

| Variable | Description | Default |
| --- | --- | --- |
| `OLLAMA_VERSION` | Docker image tag for the Ollama container | `latest` |
| `OLLAMA_MODEL` | The model to preload (e.g. `llama3.2:3b`) | `llama3.2:3b` |
| `MIN_CUDA_VERSION` | Minimum CUDA runtime version required | `12.0` |
| `OLLAMA_BIND_ADDRESS` | Address on the host that the API binds to. Use `127.0.0.1` to restrict to localhost or `0.0.0.0` to allow LAN access | `127.0.0.1` |
| `PORT` | Host port to publish the service | `11434` |
| `HOST_IP` | Optional override of the IP advertised at the end of the installer | (auto‑detected) |
| `GPU_COUNT` | Number of GPUs to reserve in Docker Compose. Use `all` for all GPUs or `0` for CPU‑only | `all` |
| `GPU_DEVICE_IDS` | Comma‑separated list of GPU device IDs exposed via the NVIDIA runtime | (blank) |

You can set these variables in `.env` to customise your deployment without
modifying any scripts.  Changes to the `.env` file will take effect the next
time you run `docker compose up` or re‑run `install.sh`.

## Security notes

Ollama exposes an unauthenticated HTTP API.  Changing `OLLAMA_BIND_ADDRESS` to
`0.0.0.0` allows access from any network interface, which means any
computer on your LAN can issue inference and model management requests. Opening
network access introduces risk and should only be done on trusted networks
with firewall controls. If you need remote access, place a reverse
proxy in front of the service and enable authentication (for example HTTP
basic auth or OAuth) and TLS encryption.

## Managing the stack

The installer uses Docker Compose to create and manage the services.  After
the initial run you can control the stack manually:

```bash
# Start or restart the services
docker compose up -d

# View logs from the Ollama container
docker compose logs -f ollama

# Stop and remove the services
docker compose down
```

## Troubleshooting

* **Missing dependencies:** The installer will abort if `docker`,
  `docker compose` or `curl` are missing, or if the Docker daemon is not
  reachable. Install these packages using your distribution’s package manager
  (e.g. `apt install docker.io docker-compose curl`) and start Docker.
* **CUDA version too low:** If the detected CUDA runtime version is lower
  than `MIN_CUDA_VERSION` the installer will exit.  Update your NVIDIA
  drivers or run in CPU mode by setting `GPU_COUNT=0` in `.env`.
* **Port already in use:** Change the `PORT` variable to publish on a different
  host port (e.g. `PORT=11435`).

For additional help or to report bugs, please open an issue on GitHub.