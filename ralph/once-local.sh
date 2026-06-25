#!/bin/bash

# 1. Gather all markdown files from the issues directory as the task list
issues=$(cat issues/*.md 2>/dev/null || echo "No issues found")

# 2. Get the last 5 commits to give the AI a sense of recent progress/history
commits=$(git log -n 5 --format="%H%n%ad%n%B---" --date=short 2>/dev/null || echo "No commits found")

# 3. Load the system instructions/persona from the local-files prompt
prompt=$(cat ralph/prompt-local.md)

# 4. Execute Claude with auto-accept permissions to allow it to edit files autonomously
claude --permission-mode acceptEdits \
  "Previous commits: $commits Issues: $issues $prompt"
