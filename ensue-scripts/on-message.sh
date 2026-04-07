#!/bin/bash
# UserPromptSubmit: capture user messages to transcript

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
USER_PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty')

[ -z "$USER_PROMPT" ] && exit 0

STATUS=$(cat /tmp/traces-status-${SESSION_ID} 2>/dev/null)
[ "$STATUS" != "ready" ] && exit 0

CAPTURE_DIR="$HOME/.agent-traces/captured"
TRANSCRIPT="${CAPTURE_DIR}/${SESSION_ID}.jsonl"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

echo "{\"ts\":\"$TIMESTAMP\",\"role\":\"user\",\"content\":$(echo "$USER_PROMPT" | jq -Rs '.')}" >> "$TRANSCRIPT"

COUNT=$(cat /tmp/traces-msgcount-${SESSION_ID} 2>/dev/null || echo "0")
echo $((COUNT + 1)) > /tmp/traces-msgcount-${SESSION_ID}

exit 0
