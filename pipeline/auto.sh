#!/bin/bash
# Auto pipeline: redact → trufflehog → review → publish (one shot)
# Called by session-end.sh and pre-compact.sh for automatic flow.
#
# Usage: pipeline/auto.sh <session-id>

SESSION_ID="$1"
[ -z "$SESSION_ID" ] && echo "Error: session-id required" && exit 1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../ensue-scripts/config.sh"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CAPTURE_DIR="$HOME/.agent-traces/captured"
STAGING_DIR="$HOME/.agent-traces/staging"
LOG="$HOME/.agent-traces/auto.log"

INPUT="${CAPTURE_DIR}/${SESSION_ID}.jsonl"
[ ! -s "$INPUT" ] && exit 0

mkdir -p "$STAGING_DIR/${SESSION_ID}"
REDACTED="${STAGING_DIR}/${SESSION_ID}/redacted.jsonl"

# Load org name
ORG=$(cat /tmp/traces-org-${SESSION_ID} 2>/dev/null)
: "${ORG:=$COLLECTIVE_ORG}"
: "${ORG:=unknown}"

AGENT="${DEFAULT_AGENT:-claude-code}"

log() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $1" >> "$LOG"
}

log "Auto pipeline started for session ${SESSION_ID}"

# Step 1: Redact
log "Step 1: Redacting..."
bash "$SCRIPT_DIR/redact.sh" "$INPUT" "$REDACTED" 2>> "$LOG"
REDACT_EXIT=$?
# Exit code 0 = clean, 1 = secrets found but redacted, 2 = error
if [ $REDACT_EXIT -eq 2 ]; then
  log "Redaction error. Aborting."
  exit 1
fi

# Step 2: TruffleHog (optional — skip if not installed)
log "Step 2: TruffleHog scan..."
bash "$SCRIPT_DIR/trufflehog.sh" "$REDACTED" 2>> "$LOG"
TH_EXIT=$?
if [ $TH_EXIT -eq 1 ]; then
  log "TruffleHog found secrets in redacted file. Blocking publish."
  echo "blocked" > "${STAGING_DIR}/${SESSION_ID}/status"
  exit 1
fi
# Exit 2 = not installed, that's fine

# Step 3: LLM Review
REVIEW_ENABLED="${COLLECTIVE_REVIEW:-true}"
if [ "$REVIEW_ENABLED" = "true" ]; then
  log "Step 3: LLM review..."
  bash "$SCRIPT_DIR/review.sh" "$REDACTED" 2>> "$LOG"
  REVIEW_EXIT=$?
  if [ $REVIEW_EXIT -eq 1 ]; then
    log "LLM review rejected session. Not publishing."
    echo "rejected" > "${STAGING_DIR}/${SESSION_ID}/status"
    exit 1
  elif [ $REVIEW_EXIT -eq 2 ]; then
    log "LLM review flagged for manual review. Publishing anyway (auto mode)."
    # In auto mode, we publish "maybe" sessions. Users can set COLLECTIVE_REVIEW_STRICT=true to block these.
    STRICT="${COLLECTIVE_REVIEW_STRICT:-false}"
    if [ "$STRICT" = "true" ]; then
      log "Strict mode: blocking manual_review session."
      echo "manual_review" > "${STAGING_DIR}/${SESSION_ID}/status"
      exit 1
    fi
  fi
else
  log "Step 3: LLM review disabled (COLLECTIVE_REVIEW=false)"
fi

# Step 4: Publish immediately
log "Step 4: Publishing to Ensue..."
bash "$SCRIPT_DIR/publish.sh" "$REDACTED" \
  --org "$ORG" \
  --agent "$AGENT" \
  --session "$SESSION_ID" \
  --extract-knowledge 2>> "$LOG"

if [ $? -eq 0 ]; then
  echo "published" > "${STAGING_DIR}/${SESSION_ID}/status"
  log "Published: agent-traces/${ORG}/${AGENT}/${SESSION_ID}"
else
  echo "publish_failed" > "${STAGING_DIR}/${SESSION_ID}/status"
  log "Publish failed."
fi

# Cleanup temp files
rm -f /tmp/traces-status-${SESSION_ID} \
  /tmp/traces-msgcount-${SESSION_ID} \
  /tmp/traces-meta-${SESSION_ID}.json \
  /tmp/traces-org-${SESSION_ID}

exit 0
