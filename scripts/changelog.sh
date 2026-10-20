#!/bin/bash
set -e

CHANGELOG_FILE="CHANGELOG.md"

echo "Inspecting git commits for Conventional Commits..."

FEAT=$(git log --pretty=format:"- %s (%h)" --grep="^feat" -n 30 2>/dev/null || true)
FIX=$(git log --pretty=format:"- %s (%h)" --grep="^fix" -n 30 2>/dev/null || true)
DOCS=$(git log --pretty=format:"- %s (%h)" --grep="^docs" -n 30 2>/dev/null || true)
CHORE=$(git log --pretty=format:"- %s (%h)" --grep="^chore\|^build\|^test" -n 30 2>/dev/null || true)

cat <<EOF > "$CHANGELOG_FILE"
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

EOF

if [ -n "$FEAT" ]; then
    echo "### Added" >> "$CHANGELOG_FILE"
    echo "$FEAT" >> "$CHANGELOG_FILE"
    echo "" >> "$CHANGELOG_FILE"
fi

if [ -n "$FIX" ]; then
    echo "### Fixed" >> "$CHANGELOG_FILE"
    echo "$FIX" >> "$CHANGELOG_FILE"
    echo "" >> "$CHANGELOG_FILE"
fi

if [ -n "$DOCS" ]; then
    echo "### Documentation" >> "$CHANGELOG_FILE"
    echo "$DOCS" >> "$CHANGELOG_FILE"
    echo "" >> "$CHANGELOG_FILE"
fi

if [ -n "$CHORE" ]; then
    echo "### Tooling & Maintenance" >> "$CHANGELOG_FILE"
    echo "$CHORE" >> "$CHANGELOG_FILE"
    echo "" >> "$CHANGELOG_FILE"
fi

echo "✅ Successfully updated $CHANGELOG_FILE"
