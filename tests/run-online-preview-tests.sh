#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -D DEBUG AirTalk/OnlinePreview/OnlinePreviewState.swift tests/OnlinePreviewStateTests.swift -o "$TEST_DIR/online-preview-tests"
"$TEST_DIR/online-preview-tests"
