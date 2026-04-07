#!/bin/bash
# 3-step flow: Step 3 — Push approved sessions to Ensue.
#
# Usage: scripts/push.sh --org <org> --agent <agent> [--extract-knowledge]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STAGING_DIR="$HOME/.agent-traces/staging"

ORG=""
AGENT=""
EXTRACT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --org) ORG="$2"; shift 2 ;;
    --agent) AGENT="$2"; shift 2 ;;
    --extract-knowledge) EXTRACT="--extract-knowledge"; shift ;;
    *) shift ;;
  esac
done

: "${ORG:=$COLLECTIVE_ORG}"
: "${AGENT:=$DEFAULT_AGENT}"
[ -z "$ORG" ] && echo "Error: --org required (set in config or pass --org)" && exit 1
[ -z "$AGENT" ] && echo "Error: --agent required (set in config or pass --agent)" && exit 1

if [ ! -d "$STAGING_DIR" ]; then
  echo "No staged sessions. Run 'scripts/collect.sh' first."
  exit 0
fi

PUBLISHED=0
SKIPPED=0

for SESSION_DIR in "$STAGING_DIR"/*/; do
  [ ! -d "$SESSION_DIR" ] && continue
  SESSION=$(basename "$SESSION_DIR")
  STATUS=$(cat "${SESSION_DIR}/status" 2>/dev/null || echo "unknown")

  if [ "$STATUS" != "approved" ]; then
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  REDACTED="${SESSION_DIR}/redacted.jsonl"
  if [ ! -f "$REDACTED" ]; then
    echo "  Skip: $SESSION (no redacted file)"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  echo "  Publishing: $SESSION"
  bash "$PLUGIN_ROOT/pipeline/publish.sh" "$REDACTED" \
    --org "$ORG" \
    --agent "$AGENT" \
    --session "$SESSION" \
    $EXTRACT 2>/dev/null

  if [ $? -eq 0 ]; then
    echo "approved" > "${SESSION_DIR}/status"
    echo "published" > "${SESSION_DIR}/status"
    PUBLISHED=$((PUBLISHED + 1))
  else
    echo "  Error publishing $SESSION"
  fi
done

echo ""
echo "Published: $PUBLISHED, Skipped: $SKIPPED"

if [ $PUBLISHED -gt 0 ]; then
  echo "Traces available at: agent-traces/${ORG}/${AGENT}/"
fi
