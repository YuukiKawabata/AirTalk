#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc AirTalk/EncounterPrototype/EncounterRecord.swift tests/EncounterPolicyTests.swift -o "$TEST_DIR/encounter-tests"
"$TEST_DIR/encounter-tests"
