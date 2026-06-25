#!/bin/bash

# Self-locate: read the sibling prompt from the shared ralph/ dir (reached via a symlink on
# PATH; `realpath` resolves it), while issues/ and git below operate on the current repo (cwd).
SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"

# Strażnik (fail-closed): refuse to run unless this repo declares a usable "## Ralph" section
# in CLAUDE.md. On halt it prints the reason + how to fix; `|| exit 0` stops the loop cleanly.
"$SCRIPT_DIR/preflight.sh" || exit 0

# 1. Gather all markdown files from the issues directory as the task list
issues=$(cat issues/*.md 2>/dev/null || echo "No issues found")

# 2. Get the last 5 commits to give the AI a sense of recent progress/history
commits=$(git log -n 5 --format="%H%n%ad%n%B---" --date=short 2>/dev/null || echo "No commits found")

# 3. Load the system instructions/persona from the local-files prompt
prompt=$(cat "$SCRIPT_DIR/prompt-local.md")

# 4. Execute Claude with auto-accept permissions to allow it to edit files autonomously
claude --permission-mode acceptEdits \
  "Previous commits: $commits Issues: $issues $prompt"
