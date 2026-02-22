#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [[ ! -f .env.example ]]; then
  echo "ERROR: .env.example not found" >&2
  exit 1
fi

extract_env_example_keys() {
  awk -F= '
    /^[[:space:]]*$/ { next }
    {
      line=$0
      sub(/^[[:space:]]*#?[[:space:]]*/, "", line)
      if (line ~ /^[A-Za-z_][A-Za-z0-9_]*=/) {
        split(line, parts, "=")
        key=parts[1]
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
        print key
      }
    }
  ' .env.example | sort -u
}

extract_compose_keys() {
  rg -o --no-filename '\$\{[A-Za-z_][A-Za-z0-9_]*(?::-[^}]*)?\}' docker-compose.yml \
    | sed -E 's/^\$\{([A-Za-z_][A-Za-z0-9_]*).*/\1/' \
    | sort -u
}

extract_install_keys() {
  {
    rg --no-filename '^:[[:space:]]*"\$\{[A-Za-z_][A-Za-z0-9_]*:=' install.sh \
      | sed -E 's/^:[[:space:]]*"\$\{([A-Za-z_][A-Za-z0-9_]*):=.*/\1/'

    rg --no-filename '\$\{HOST_IP:-' install.sh >/dev/null && echo HOST_IP || true
  } | sort -u
}

mapfile -t env_keys < <(extract_env_example_keys)
mapfile -t compose_keys < <(extract_compose_keys)
mapfile -t install_keys < <(extract_install_keys)
mapfile -t referenced_keys < <(printf '%s\n' "${compose_keys[@]}" "${install_keys[@]}" | sed '/^$/d' | sort -u)

missing=0

echo "Variables in .env.example:"
printf '  %s\n' "${env_keys[@]}"

echo ""
echo "Variables referenced by docker-compose.yml/install.sh:"
printf '  %s\n' "${referenced_keys[@]}"

echo ""
for key in "${referenced_keys[@]}"; do
  if ! printf '%s\n' "${env_keys[@]}" | grep -Fxq "$key"; then
    echo "ERROR: '$key' is referenced but missing from .env.example" >&2
    missing=1
  fi
done

if [[ "$missing" -ne 0 ]]; then
  exit 1
fi

echo "OK: .env.example covers all referenced variables."
