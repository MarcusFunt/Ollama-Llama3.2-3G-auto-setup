#!/usr/bin/env python3
from __future__ import annotations
import re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def env_keys(path: Path) -> set[str]:
    keys = set()
    for raw in path.read_text(encoding='utf-8').splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith('#'):
            line = line[1:].strip()
        m = re.match(r'^([A-Z_][A-Z0-9_]*)\s*=.*$', line)
        if m:
            keys.add(m.group(1))
    return keys


def compose_vars(path: Path) -> set[str]:
    return set(re.findall(r'\$\{([A-Z_][A-Z0-9_]*)', path.read_text(encoding='utf-8')))


def install_vars(path: Path) -> set[str]:
    content = path.read_text(encoding='utf-8')
    return set(re.findall(r':\s*"\$\{([A-Z_][A-Z0-9_]*)[:?=]', content))


def main() -> int:
    documented = env_keys(ROOT / '.env.example')
    used = compose_vars(ROOT / 'docker-compose.yml') | install_vars(ROOT / 'install.sh')
    missing = sorted(used - documented)
    unused = sorted(documented - used)
    if missing:
        print('ERROR: Variables used by project files but missing from .env.example:')
        for k in missing:
            print(f' - {k}')
    if unused:
        print('NOTE: Variables documented in .env.example but not currently detected in install.sh/docker-compose.yml:')
        for k in unused:
            print(f' - {k}')
    if not missing:
        print('Environment variable consistency check passed.')
    return 1 if missing else 0

if __name__ == '__main__':
    raise SystemExit(main())
