#!/bin/bash

# ralph-lista [--all]: lists the epics ([PRD] issues) of the current repo with their open sub-issues
# and whose move it is (needs-human-test = waits for acceptance; no ready-for-agent = needs a human),
# then open issues outside any epic. Deterministic: only gh + jq. --all also shows closed epics.
set -o pipefail

state=open
[ "${1:-}" = "--all" ] && state=all

die() { echo "ralph-lista: nie udało się pobrać danych z GitHuba (gh)." >&2; exit 1; }

# All issues (REST also returns pull requests - drop them), then the epics in display order.
issues=$(gh api --paginate "repos/{owner}/{repo}/issues?state=${state}&per_page=100" | jq -s 'add // [] | map(select(has("pull_request") | not))') || die
epics=$(jq -c '[.[] | select(.title | startswith("[PRD]"))]
  | sort_by([(if any(.labels[]?; .name == "needs-human-test") then 0 else 1 end), .number]) | .[]' <<<"$issues") || die

claimed=""   # numbers of all sub-issues of the listed epics
first=1
while IFS= read -r epic; do
  [ -n "$epic" ] || continue
  n=$(jq -r '.number' <<<"$epic")
  subs=$(gh api --paginate "repos/{owner}/{repo}/issues/${n}/sub_issues" | jq -s 'add // []') || die
  [ "$first" = 1 ] || echo
  first=0
  jq -r --argjson subs "$subs" '
    ($subs | length) as $all | ($subs | map(select(.state == "closed")) | length) as $closed
    | "#\(.number) \(.title)   (\($closed)/\($all) zamknięte)"
      + (if any(.labels[]?; .name == "needs-human-test") then "  → czeka na odbiór" else "" end),
      (if $all == 0 then "  (brak sub-issues)" else
        ($subs | sort_by(.number) | .[] | select(.state == "open")
          | "  #\(.number) \(.title)" + (if any(.labels[]?; .name == "ready-for-agent") then "" else "  ⚠ wymaga człowieka" end))
      end)' <<<"$epic"
  claimed="$claimed $(jq -r '.[].number' <<<"$subs" | tr '\n' ' ')"
done <<<"$epics"

loose=$(jq -r --arg claimed "$claimed" '($claimed | split(" ") | map(select(. != "") | tonumber)) as $c
  | map(select(.state == "open" and (.title | startswith("[PRD]") | not) and ([.number] | inside($c) | not)))
  | sort_by(.number) | .[] | "  #\(.number) \(.title)"' <<<"$issues") || die

if [ -n "$loose" ]; then
  [ "$first" = 1 ] || echo
  echo "Bez epica:"
  echo "$loose"
elif [ "$first" = 1 ]; then
  echo "Brak otwartych zadań."
fi
