#!/bin/bash
# SessionEnd: trigger auto pipeline if enabled

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')

STATUS=$(cat /tmp/traces-status-${SESSION_ID} 2>/dev/null)
[ "$STATUS" != "ready" ] && exit 0

AUTO="${COLLECTIVE_AUTO:-true}"

if [ "$AUTO" = "true" ]; then
  # Check if session was substantial
  MSG_COUNT=$(cat /tmp/traces-msgcount-${SESSION_ID} 2>/dev/null || echo "0")
  if [ "$MSG_COUNT" -ge 3 ]; then
    # Run auto pipeline in background so session exit isn't blocked
    bash "$SCRIPT_DIR/../pipeline/auto.sh" "$SESSION_ID" &
  fi
fi

exit 0
