#!/bin/bash
# Stop: capture assistant response to transcript

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')

[ -z "$TRANSCRIPT_PATH" ] && exit 0

STATUS=$(cat /tmp/traces-status-${SESSION_ID} 2>/dev/null)
[ "$STATUS" != "ready" ] && exit 0

# Extract last assistant message from Claude's transcript
LAST_RESPONSE=$(jq -r '
  [.[] | select(.type == "assistant")] | last |
  if .message then
    [.message.content[] | select(.type == "text") | .text] | join("\n")
  else
    ""
  end
' "$TRANSCRIPT_PATH" 2>/dev/null | head -c 10000)

[ -z "$LAST_RESPONSE" ] && exit 0

CAPTURE_DIR="$HOME/.agent-traces/captured"
TRANSCRIPT="${CAPTURE_DIR}/${SESSION_ID}.jsonl"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

echo "{\"ts\":\"$TIMESTAMP\",\"role\":\"assistant\",\"content\":$(echo "$LAST_RESPONSE" | jq -Rs '.')}" >> "$TRANSCRIPT"

exit 0
