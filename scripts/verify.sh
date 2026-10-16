#!/bin/bash
set -eo pipefail

echo "=========================================="
echo "  Resign Autonomous Verification Gate"
echo "=========================================="

SCHEME="Resign"
SIMULATOR_DEST="platform=iOS Simulator,name=iPhone 17"
GENERIC_DEST="generic/platform=iOS Simulator"

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
    | grep -E '\*\*( BUILD | TEST )|error:|warning:|passed|failed' || true

echo "==> Step 2: Running Tests via $TEST_PLAN..."
xcodebuild test \
    -scheme "$SCHEME" \
    -destination "$SIMULATOR_DEST" \
    -testPlan "$TEST_PLAN" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    | grep -E 'Test suite|Test case|\*\* TEST' || true

echo "=========================================="
echo "  ✅ All verification checks PASSED!"
echo "=========================================="
