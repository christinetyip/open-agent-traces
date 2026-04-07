#!/bin/bash
# Shared config loader — source this from any script.
# Reads ~/.agent-traces/config.json, with env var overrides.
#
# Usage: source "$(dirname "$0")/config.sh"

CONFIG_FILE="$HOME/.agent-traces/config.json"
COLLECTIVE_PREFIX="@collective-intelligence"

if [ -f "$CONFIG_FILE" ]; then
  _cfg() { jq -r "$1" "$CONFIG_FILE" 2>/dev/null; }

  : "${ENSUE_COLLECTIVE_KEY:=$(_cfg '.api_key // empty')}"
  : "${COLLECTIVE_ORG:=$(_cfg '.org // empty')}"

  _MODE=$(_cfg '.mode // "auto"')
  [ "$_MODE" = "auto" ] && : "${COLLECTIVE_AUTO:=true}" || : "${COLLECTIVE_AUTO:=false}"

  : "${COLLECTIVE_REVIEW:=$(_cfg '.review.enabled // "true"')}"
  : "${COLLECTIVE_REVIEW_STRICT:=$(_cfg '.review.strict // "false"')}"
  : "${TRACES_ENABLED:=$(_cfg '.features.traces // "true"')}"
  : "${KNOWLEDGE_READ:=$(_cfg '.features.knowledge_read // "true"')}"
  : "${KNOWLEDGE_EXTRACT:=$(_cfg '.features.knowledge_extract // "true"')}"

  SETUP_COMPLETE=$(_cfg '.setup_complete // "false"')
  DEFAULT_AGENT=$(_cfg '.default_agent // "claude-code"')
fi

# Also try .collective-key file as fallback
if [ -z "$ENSUE_COLLECTIVE_KEY" ]; then
  _SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")" && pwd)"
  _KEY_FILE="$_SCRIPT_DIR/../.collective-key"
  [ -f "$_KEY_FILE" ] && ENSUE_COLLECTIVE_KEY=$(cat "$_KEY_FILE")
fi

# Defaults
: "${COLLECTIVE_AUTO:=true}"
: "${COLLECTIVE_REVIEW:=true}"
: "${COLLECTIVE_REVIEW_STRICT:=false}"
: "${TRACES_ENABLED:=true}"
: "${KNOWLEDGE_READ:=true}"
: "${KNOWLEDGE_EXTRACT:=true}"
: "${SETUP_COMPLETE:=false}"
: "${DEFAULT_AGENT:=claude-code}"
