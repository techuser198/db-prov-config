# Contributing

## Workflow

1. Run setup once: `./setup.sh`
2. Validate environment: `./validate.sh`
3. Lint shell scripts: `make lint`
4. Test target flow with `-p` when available before mutating infra

## Script Standards

- Use `#!/usr/bin/env bash`
- Use `set -euo pipefail` for operational scripts
- Keep shared logic in `lib.sh`
- Prefer explicit dependency checks with `require_commands`

## Change Safety

- Avoid hardcoding project IDs or region values in scripts
- Do not introduce plaintext credentials
- Keep behavior backward-compatible unless explicitly requested
