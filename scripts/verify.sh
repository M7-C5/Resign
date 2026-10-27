#!/bin/bash
set -o pipefail

echo "=========================================="
echo "  Resign Autonomous Verification Gate"
echo "=========================================="

if [ -z "$DEVELOPER_DIR" ] && [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

SCHEME="Resign"
GENERIC_DEST="generic/platform=iOS Simulator"

DEFAULT_SIM="iPhone 17"
if xcrun simctl list devices available | grep -q "$DEFAULT_SIM ("; then
    SIMULATOR_DEST="platform=iOS Simulator,name=$DEFAULT_SIM"
else
    FALLBACK_SIM=$(xcrun simctl list devices available | grep -m 1 -E 'iPhone [0-9]+' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+\(.*//' || true)
    if [ -n "$FALLBACK_SIM" ]; then
        SIMULATOR_DEST="platform=iOS Simulator,name=$FALLBACK_SIM"
    else
        SIMULATOR_DEST="generic/platform=iOS Simulator"
    fi
fi

TEST_PLAN="FastUnitTests"
if [ "$1" == "--ui" ]; then
    TEST_PLAN="FullSuite"
    echo "==> Mode: Full Suite (Unit Tests + UI Tests active)"
else
    echo "==> Mode: Fast Verification Loop (Test Plan: FastUnitTests)"
fi

echo "==> Step 1: Compiling project..."
xcodebuild build \
    -scheme "$SCHEME" \
    -destination "$GENERIC_DEST" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    | grep -E '\*\*( BUILD | TEST )|error:|warning:|passed|failed|fatal error:|Undefined symbol|clang: error:|ld:'

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "=========================================="
    echo "  ❌ Build FAILED! Check compiler errors above."
    echo "=========================================="
    exit 1
fi

echo "==> Step 2: Running Tests via $TEST_PLAN on $SIMULATOR_DEST..."
xcodebuild test \
    -scheme "$SCHEME" \
    -destination "$SIMULATOR_DEST" \
    -testPlan "$TEST_PLAN" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    | grep -E 'Test suite|Test case|\*\* TEST|✘|failed|failure|Expectation|Issue recorded'

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "=========================================="
    echo "  ❌ Test suite FAILED!"
    echo "=========================================="
    exit 1
fi

echo "=========================================="
echo "  ✅ All verification checks PASSED!"
echo "=========================================="
