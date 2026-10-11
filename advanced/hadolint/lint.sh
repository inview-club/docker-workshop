#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
# stdin не требует bind mount каталога компьютера.
docker run --rm -i ghcr.io/hadolint/hadolint:v2.15.1 < "${1:-Dockerfile.good}"
