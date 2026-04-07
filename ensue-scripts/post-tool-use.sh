#!/bin/bash
# PostToolUse: capture tool actions to transcript

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name')
TOOL_INPUT=$(echo "$INPUT" | jq -c '.tool_input // empty')

STATUS=$(cat /tmp/traces-status-${SESSION_ID} 2>/dev/null)
[ "$STATUS" != "ready" ] && exit 0

CAPTURE_DIR="$HOME/.agent-traces/captured"
TRANSCRIPT="${CAPTURE_DIR}/${SESSION_ID}.jsonl"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

echo "{\"ts\":\"$TIMESTAMP\",\"role\":\"tool_call\",\"tool\":\"$TOOL_NAME\",\"input\":$(echo "$TOOL_INPUT" | jq -Rs '.[0:2000]')}" >> "$TRANSCRIPT"

exit 0
