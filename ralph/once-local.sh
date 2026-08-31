#!/bin/bash

# Self-locate: read the sibling prompt from the shared ralph/ dir (reached via a symlink on
# PATH; `realpath` resolves it), while issues/ and git below operate on the current repo (cwd).
SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

ralph_parse_args ralph-once-local "$@" || exit 1
ralph_require_runtime "$RALPH_RUNTIME" || exit 1

ralph_acquire_lock local || exit 0
trap ralph_release_lock EXIT INT TERM

# Strażnik (fail-closed): refuse to run unless this repo declares a usable "## Ralph" section
# in its selected runtime's native agent contract file. On halt it prints the reason + how to
# fix; `|| exit 0` stops the loop cleanly.
"$SCRIPT_DIR/preflight.sh" "$RALPH_RUNTIME" || exit 0

# 1. Gather all markdown files from the issues directory as the task list
issues=$(cat issues/*.md 2>/dev/null || echo "No issues found")

# 2. Get the last 5 commits to give the AI a sense of recent progress/history
commits=$(git log -n 5 --format="%H%n%ad%n%B---" --date=short 2>/dev/null || echo "No commits found")

# 3. Load the system instructions/persona from the local-files prompt
prompt=$(ralph_render_prompt "$RALPH_RUNTIME" "$SCRIPT_DIR/prompt-local.md")

# 4. Execute the selected runtime in AFK mode so the run needs no approvals — see once.sh for
#    the runtime-specific rationale.
ralph_model_for_complexity "$RALPH_RUNTIME" normal
ralph_run_worker "$RALPH_RUNTIME" "$RALPH_MODEL" "$RALPH_EFFORT" \
  "Previous commits: $commits Issues: $issues $prompt"

# Auto mode denies without prompting, so a run that could not finish (e.g. the commit was
# blocked) now ends quietly. Uncommitted leftovers would poison the NEXT run — say it out loud.
ralph_warn_dirty_tree
