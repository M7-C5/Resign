#!/bin/bash
set -e

HOOK_DIR=".git/hooks"
COMMIT_MSG_HOOK="$HOOK_DIR/commit-msg"

mkdir -p "$HOOK_DIR"

cat << 'EOF' > "$COMMIT_MSG_HOOK"
#!/bin/bash

COMMIT_MSG_FILE="$1"
FIRST_LINE=$(head -n 1 "$COMMIT_MSG_FILE")

# Allow merge commits
if [[ "$FIRST_LINE" =~ ^Merge ]]; then
    exit 0
fi

# Conventional Commits regex
# Format: <type>(<scope>)?: <subject>
CONVENTIONAL_REGEX="^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([a-zA-Z0-9_/-]+\))?(!)?: .{1,}"

if [[ ! "$FIRST_LINE" =~ $CONVENTIONAL_REGEX ]]; then
    echo "================================================================="
    echo "❌ INVALID COMMIT MESSAGE"
    echo "================================================================="
    echo "Your commit message did not follow Conventional Commits format:"
    echo "  \"$FIRST_LINE\""
    echo ""
    echo "Format must be: <type>(<optional-scope>): <description>"
    echo ""
    echo "Allowed types:"
    echo "  feat:     A new user-facing feature"
    echo "  fix:      A bug fix"
    echo "  docs:     Documentation changes"
    echo "  refactor: Code change that neither fixes a bug nor adds a feature"
    echo "  perf:     Performance improvement"
    echo "  test:     Adding or correcting tests"
    echo "  build:    Build system or script changes"
    echo "  chore:    Maintenance, dependencies, or configuration"
    echo ""
    echo "Examples:"
    echo "  feat(model): add SwiftData in-memory container"
    echo "  fix(ui): adjust button touch target to 44pt"
    echo "  docs: update playbook with test plans"
    echo "================================================================="
    exit 1
fi

exit 0
EOF

chmod +x "$COMMIT_MSG_HOOK"
echo "✅ Conventional Commits hook installed successfully at $COMMIT_MSG_HOOK"
