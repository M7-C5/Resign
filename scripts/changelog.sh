#!/bin/bash
set -e

CHANGELOG_FILE="CHANGELOG.md"

if [ ! -f "$CHANGELOG_FILE" ]; then
    echo "# Changelog" > "$CHANGELOG_FILE"
    echo "" >> "$CHANGELOG_FILE"
    echo "All notable changes to this project will be documented in this file." >> "$CHANGELOG_FILE"
    echo "" >> "$CHANGELOG_FILE"
    echo "The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)," >> "$CHANGELOG_FILE"
    echo "and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)." >> "$CHANGELOG_FILE"
    echo "" >> "$CHANGELOG_FILE"
    echo "## [Unreleased]" >> "$CHANGELOG_FILE"
    echo "" >> "$CHANGELOG_FILE"
fi

echo "Inspecting git commits for Conventional Commits..."

FEAT=$(git log --pretty=format:"- %s (%h)" --grep="^feat" -n 20 2>/dev/null || true)
FIX=$(git log --pretty=format:"- %s (%h)" --grep="^fix" -n 20 2>/dev/null || true)
DOCS=$(git log --pretty=format:"- %s (%h)" --grep="^docs" -n 20 2>/dev/null || true)
CHORE=$(git log --pretty=format:"- %s (%h)" --grep="^chore\|^build\|^test" -n 20 2>/dev/null || true)

echo "--- Recent Conventional Commits ---"
if [ -n "$FEAT" ]; then
    echo "### Added"
    echo "$FEAT"
fi
if [ -n "$FIX" ]; then
    echo "### Fixed"
    echo "$FIX"
fi
if [ -n "$DOCS" ]; then
    echo "### Documentation"
    echo "$DOCS"
fi
if [ -n "$CHORE" ]; then
    echo "### Tooling & Maintenance"
    echo "$CHORE"
fi
echo "-----------------------------------"
