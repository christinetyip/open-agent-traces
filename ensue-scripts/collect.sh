#!/bin/bash
# 3-step flow: Step 1 — Collect sessions, redact, review, stage locally.
# Does NOT publish. Use push.sh after reviewing with status.sh.
#
# Usage: scripts/collect.sh --agent <agent-type> [--session <file>] [--env-file <path>] [--secrets <path>]
#
# Agents: claude-code, codex, aider, cline, continue-dev, pi-mono

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STAGING_DIR="$HOME/.agent-traces/staging"
CAPTURE_DIR="$HOME/.agent-traces/captured"

AGENT=""
SESSION_FILE=""
EXTRA_ARGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --agent) AGENT="$2"; shift 2 ;;
    --session) SESSION_FILE="$2"; shift 2 ;;
    --env-file|--secrets) EXTRA_ARGS+=("$1" "$2"); shift 2 ;;
    *) shift ;;
  esac
done

[ -z "$AGENT" ] && echo "Error: --agent required (claude-code, codex, aider, cline, continue-dev, pi-mono)" && exit 1

# Find session files based on agent type
SESSION_FILES=()

if [ -n "$SESSION_FILE" ]; then
  # Explicit session file
  SESSION_FILES=("$SESSION_FILE")
else
  case "$AGENT" in
    claude-code)
      # Captured by hooks to ~/.agent-traces/captured/
      for f in "$CAPTURE_DIR"/*.jsonl; do
        [ -f "$f" ] && SESSION_FILES+=("$f")
      done
      ;;
    codex)
      # Codex sessions at ~/.codex/sessions/
      for f in "$HOME/.codex/sessions"/*.jsonl; do
        [ -f "$f" ] && SESSION_FILES+=("$f")
      done
      ;;
    aider)
      # Aider saves chat history in the repo as .aider.chat.history.md
      if [ -f ".aider.chat.history.md" ]; then
        SESSION_FILES+=(".aider.chat.history.md")
      fi
      # Also check parent dirs
      DIR="$(pwd)"
      while [ "$DIR" != "/" ]; do
        [ -f "$DIR/.aider.chat.history.md" ] && SESSION_FILES+=("$DIR/.aider.chat.history.md") && break
        DIR="$(dirname "$DIR")"
      done
      ;;
    cline)
      # Cline tasks at globalStorage
      CLINE_DIR="$HOME/Library/Application Support/Code/User/globalStorage/saoudrizwan.claude-dev/tasks"
      if [ -d "$CLINE_DIR" ]; then
        for d in "$CLINE_DIR"/*/; do
          [ -f "$d/api_conversation_history.json" ] && SESSION_FILES+=("$d/api_conversation_history.json")
        done
      fi
      ;;
    continue-dev)
      # Continue sessions at ~/.continue/sessions/
      for f in "$HOME/.continue/sessions"/*.json; do
        [ -f "$f" ] && SESSION_FILES+=("$f")
      done
      ;;
    pi-mono)
      # Pi sessions at ~/.pi/agent/sessions/
      for d in "$HOME/.pi/agent/sessions"/*/; do
        for f in "$d"*.jsonl; do
          [ -f "$f" ] && SESSION_FILES+=("$f")
        done
      done
      ;;
    *)
      echo "Error: unknown agent '$AGENT'. Supported: claude-code, codex, aider, cline, continue-dev, pi-mono"
      exit 1
      ;;
  esac
fi

if [ ${#SESSION_FILES[@]} -eq 0 ]; then
  echo "No sessions found for agent '$AGENT'."
  exit 0
fi

echo "Found ${#SESSION_FILES[@]} session(s) for $AGENT"
echo ""

mkdir -p "$STAGING_DIR"

APPROVED=0
REJECTED=0
MANUAL=0
ERRORS=0

for FILE in "${SESSION_FILES[@]}"; do
  BASENAME=$(basename "$FILE" | sed 's/\.[^.]*$//')
  SESSION_STAGE="${STAGING_DIR}/${BASENAME}"

  # Skip if already processed
  if [ -f "${SESSION_STAGE}/status" ]; then
    EXISTING_STATUS=$(cat "${SESSION_STAGE}/status")
    echo "  Skip: $BASENAME (already $EXISTING_STATUS)"
    continue
  fi

  echo "  Processing: $BASENAME"
  mkdir -p "$SESSION_STAGE"

  # Copy original
  cp "$FILE" "${SESSION_STAGE}/original.jsonl" 2>/dev/null || cp "$FILE" "${SESSION_STAGE}/original.json"

  # Normalize if needed (non-JSONL formats)
  NORMALIZED="${SESSION_STAGE}/normalized.jsonl"
  ADAPTER="$PLUGIN_ROOT/adapters/$AGENT/normalize.sh"
  if [ -f "$ADAPTER" ]; then
    bash "$ADAPTER" "$FILE" "$NORMALIZED" 2>/dev/null
  else
    # Default: assume JSONL, just copy
    cp "$FILE" "$NORMALIZED"
  fi

  # Step 1: Redact
  REDACTED="${SESSION_STAGE}/redacted.jsonl"
  bash "$PLUGIN_ROOT/pipeline/redact.sh" "$NORMALIZED" "$REDACTED" "${EXTRA_ARGS[@]}" 2>/dev/null
  if [ $? -eq 2 ]; then
    echo "    Error: redaction failed"
    echo "error" > "${SESSION_STAGE}/status"
    ERRORS=$((ERRORS + 1))
    continue
  fi

  # Step 2: TruffleHog
  bash "$PLUGIN_ROOT/pipeline/trufflehog.sh" "$REDACTED" 2>/dev/null
  if [ $? -eq 1 ]; then
    echo "    Blocked: TruffleHog found secrets"
    echo "blocked_trufflehog" > "${SESSION_STAGE}/status"
    REJECTED=$((REJECTED + 1))
    continue
  fi

  # Step 3: LLM Review
  bash "$PLUGIN_ROOT/pipeline/review.sh" "$REDACTED" 2>/dev/null
  REVIEW_EXIT=$?
  if [ $REVIEW_EXIT -eq 0 ]; then
    echo "    Approved"
    echo "approved" > "${SESSION_STAGE}/status"
    APPROVED=$((APPROVED + 1))
  elif [ $REVIEW_EXIT -eq 1 ]; then
    echo "    Rejected by LLM review"
    echo "rejected" > "${SESSION_STAGE}/status"
    REJECTED=$((REJECTED + 1))
  elif [ $REVIEW_EXIT -eq 2 ]; then
    echo "    Needs manual review"
    echo "manual_review" > "${SESSION_STAGE}/status"
    MANUAL=$((MANUAL + 1))
  else
    echo "    Review error"
    echo "error" > "${SESSION_STAGE}/status"
    ERRORS=$((ERRORS + 1))
  fi
done

echo ""
echo "Results: $APPROVED approved, $REJECTED rejected, $MANUAL manual review, $ERRORS errors"
echo "Run 'scripts/status.sh' to inspect, then 'scripts/push.sh --org <org> --agent $AGENT' to publish."
