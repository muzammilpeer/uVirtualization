#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
./scripts/build.sh
codesign --force --sign "${SIGNING_IDENTITY:--}" --entitlements Resources/uvm.entitlements .build/debug/uvm
codesign --verify --strict .build/debug/uvm
