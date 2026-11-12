#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
npm run check --prefix server
npm test --prefix server
./tests/run-encounter-tests.sh
./tests/run-online-preview-tests.sh
git diff --check
