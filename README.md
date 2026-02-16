# Ollama + Llama 3.2 (3B) Auto Setup

This repository provides a one-command install flow that:

1. Verifies host dependencies (`git`, `docker`, `docker compose`).
2. Checks NVIDIA/CUDA availability and enforces a minimum CUDA version.
3. Starts an Ollama Docker container with the API bound to `0.0.0.0:11434`.
4. Pulls `llama3.2:3b` automatically.
5. Exposes the inference endpoint on your local network (Wi-Fi/LAN).

## Quick start

```bash
git clone https://github.com/<your-user>/Ollama-Llama3.2-3G-auto-setup.git
cd Ollama-Llama3.2-3G-auto-setup
./install.sh
```

After setup:

- Local endpoint: `http://localhost:11434`
- Wi-Fi/LAN endpoint: `http://<your-host-ip>:11434`

## Configuration

Copy and edit `.env` (or let `install.sh` create it from `.env.example`):

- `OLLAMA_VERSION`: Ollama image tag (default `latest`)
- `OLLAMA_MODEL`: model to preload (default `llama3.2:3b`)
- `MIN_CUDA_VERSION`: minimum required CUDA version when NVIDIA GPU is present (default `12.0`)

## Example inference request

```bash
curl http://localhost:11434/api/generate \
  -d '{"model":"llama3.2:3b","prompt":"Explain what Ollama is in one sentence."}'
```

## Managing the stack

```bash
# start / restart
docker compose up -d

# view logs
docker compose logs -f ollama

# stop
docker compose down
```

## Notes

- If `nvidia-smi` is missing, the installer continues in CPU mode.
- Ensure firewall rules allow inbound TCP `11434` from trusted devices on your Wi-Fi/LAN.
