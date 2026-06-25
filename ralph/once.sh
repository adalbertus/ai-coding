#!/bin/bash

# Ralph loop, GitHub-backed. Two stages so the model can be chosen per issue:
#   1. a cheap selector picks the single next issue number;
#   2. its `complexity:*` label is mapped to a model, and that model implements it.

# 1. Pull open, agent-ready (AFK) issues from GitHub as the task list.
#    The `ready-for-agent` label is the AFK filter (HITL issues won't carry it).
#    PRDs/epics also carry `ready-for-agent` but are excluded here by title prefix,
#    so the loop only ever picks implementable tracer-bullet slices.
echo "Fetching open agent-ready issues from GitHub..."
issues=$(gh issue list --label ready-for-agent --state open \
  --json number,title,body \
  --jq '.[] | select(.title | startswith("PRD") | not) | "## Issue #\(.number): \(.title)\n\n\(.body)\n"' \
  2>/dev/null)

if [ -z "$issues" ]; then
  echo "No open agent-ready issues. Nothing to do."
  exit 0
fi

# 2. Recent history, for both the selector and the worker.
commits=$(git log -n 5 --format="%H%n%ad%n%B---" --date=short 2>/dev/null || echo "No commits found")

# 3. Stage 1 — cheap selector. Picks ONE issue number (or NO_TASK). Tool-free, so it
#    reasons over the issue bodies provided above; runs on the cheapest capable model.
select_prompt=$(cat ralph/select.md)
echo "Asking selector (claude-haiku-4-5) to pick the next issue... (this can take a while)"
selection=$(claude -p --model claude-haiku-4-5-20251001 \
  "Previous commits: $commits Issues: $issues $select_prompt" 2>/dev/null)
num=$(printf '%s' "$selection" | grep -Eo 'NO_TASK|[0-9]+' | head -1)

if [ -z "$num" ] || [ "$num" = "NO_TASK" ]; then
  echo "Selector found no actionable issue (output: '${selection}'). Nothing to do."
  exit 0
fi

echo "Selector picked issue #${num}; resolving complexity label..."

# 4. Map the selected issue's complexity label to a model. Update ONLY this map as the
#    best model per tier changes — the issue labels stay stable (complexity is intrinsic,
#    the model du jour is not). An untagged issue is treated as 'normal' (safe default).
complexity=$(gh issue view "$num" --json labels \
  --jq '[.labels[].name | select(startswith("complexity:"))][0] // "complexity:normal" | sub("complexity:"; "")' \
  2>/dev/null)
complexity="${complexity:-normal}"

case "$complexity" in
  heavy)   model="claude-opus-4-8" ;;
  trivial) model="claude-haiku-4-5-20251001" ;;
  *)       model="claude-sonnet-4-6" ;; # 'normal' + anything unexpected
esac

echo "Selected issue #${num} (complexity:${complexity}) -> ${model}"

# 5. Stage 2 — implement ONLY the selected issue, on the chosen model.
issue=$(gh issue view "$num" --json number,title,body \
  --jq '"## Issue #\(.number): \(.title)\n\n\(.body)\n"' 2>/dev/null)
prompt=$(cat ralph/prompt.md)

echo "Starting implementation of issue #${num} on ${model}..."
claude --permission-mode acceptEdits --model "$model" \
  "Previous commits: $commits Issue to work (work ONLY this one): $issue $prompt"
