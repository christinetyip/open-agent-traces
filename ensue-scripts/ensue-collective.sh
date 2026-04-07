#!/bin/bash
# Ensue Collective Intelligence API wrapper
# Usage: ./scripts/ensue-collective.sh <method> <json_args>

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$(cd "$SCRIPT_DIR" && pwd)/config.sh"

METHOD="$1"
ARGS="$2"

if [ -z "$ENSUE_COLLECTIVE_KEY" ]; then
  echo '{"error":"ENSUE_COLLECTIVE_KEY not set. Run setup first."}'
  exit 1
fi

if [ -z "$METHOD" ]; then
  echo '{"error":"No method specified. Usage: ensue-collective.sh <method> <json_args>"}'
  exit 1
fi

[ -z "$ARGS" ] && ARGS='{}'

curl -s -X POST https://api.ensue-network.ai/ \
  -H "Authorization: Bearer $ENSUE_COLLECTIVE_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"tools/call\",\"params\":{\"name\":\"$METHOD\",\"arguments\":$ARGS},\"id\":1}" \
  | sed 's/^data: //'
