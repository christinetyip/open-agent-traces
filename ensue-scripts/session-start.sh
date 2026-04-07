#!/bin/bash
# SessionStart: load config, validate key, detect first-run, initialize capture

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
SOURCE=$(echo "$INPUT" | jq -r '.source')

# --- No config or setup incomplete → trigger onboarding ---
if [ "$SETUP_COMPLETE" != "true" ] || [ -z "$ENSUE_COLLECTIVE_KEY" ]; then
  echo "needs_setup" > /tmp/traces-status-${SESSION_ID}
  if [ "$SOURCE" = "startup" ]; then
    echo '{"systemMessage": "\n\u001b[38;2;255;200;80m    agent-traces-ensue: not configured yet. Ask your agent to run setup.\u001b[0m\n"}'
  fi
  exit 0
fi

# --- Persist env var for subagents ---
if [ -n "$CLAUDE_ENV_FILE" ]; then
  echo "export ENSUE_COLLECTIVE_KEY=\"$ENSUE_COLLECTIVE_KEY\"" >> "$CLAUDE_ENV_FILE"
  [ -n "$COLLECTIVE_ORG" ] && echo "export COLLECTIVE_ORG=\"$COLLECTIVE_ORG\"" >> "$CLAUDE_ENV_FILE"
fi

# Cache key for script access
echo "$ENSUE_COLLECTIVE_KEY" > "$SCRIPT_DIR/../.collective-key"
chmod 600 "$SCRIPT_DIR/../.collective-key"

# --- Initialize capture ---
CAPTURE_DIR="$HOME/.agent-traces/captured"
mkdir -p "$CAPTURE_DIR"
echo "0" > /tmp/traces-msgcount-${SESSION_ID}
> "${CAPTURE_DIR}/${SESSION_ID}.jsonl"
echo "$COLLECTIVE_ORG" > /tmp/traces-org-${SESSION_ID}

# Store session metadata
echo "{\"session_id\":\"$SESSION_ID\",\"agent\":\"claude-code\",\"org\":\"$COLLECTIVE_ORG\",\"started\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"cwd\":\"$(pwd)\"}" > /tmp/traces-meta-${SESSION_ID}.json

# --- Connectivity check on startup ---
if [ "$SOURCE" = "startup" ]; then
  RESPONSE=$(curl -s --max-time 5 -X POST https://api.ensue-network.ai/ \
    -H "Authorization: Bearer $ENSUE_COLLECTIVE_KEY" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"list_keys","arguments":{"limit":1}},"id":1}')

  JSON_RESPONSE=$(echo "$RESPONSE" | sed 's/^data: //')
  HAS_ERROR=$(echo "$JSON_RESPONSE" | jq -r '.error // .result.isError // false' 2>/dev/null)

  if [ "$HAS_ERROR" != "false" ] && [ "$HAS_ERROR" != "null" ] && [ -n "$HAS_ERROR" ]; then
    echo "error" > /tmp/traces-status-${SESSION_ID}
    echo '{"systemMessage": "\n\u001b[38;2;255;180;100m    agent-traces: API key invalid or connection failed.\u001b[0m\n"}'
  else
    echo "ready" > /tmp/traces-status-${SESSION_ID}
    if [ "$COLLECTIVE_AUTO" = "true" ]; then
      echo '{"systemMessage": "\n\u001b[38;2;121;192;255m    agent-traces: connected as '"$COLLECTIVE_ORG"' (auto-publish)\u001b[0m\n"}'
    else
      echo '{"systemMessage": "\n\u001b[38;2;121;192;255m    agent-traces: connected as '"$COLLECTIVE_ORG"' (manual mode)\u001b[0m\n"}'
    fi
  fi
fi

exit 0
