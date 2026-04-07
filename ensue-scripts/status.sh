#!/bin/bash
# 3-step flow: Step 2 — Show staging status.
#
# Usage: scripts/status.sh [--filter approved|rejected|manual_review|all]

STAGING_DIR="$HOME/.agent-traces/staging"
FILTER="${1:-all}"

if [ "$1" = "--filter" ]; then
  FILTER="$2"
fi

if [ ! -d "$STAGING_DIR" ] || [ -z "$(ls -A "$STAGING_DIR" 2>/dev/null)" ]; then
  echo "No staged sessions. Run 'scripts/collect.sh' first."
  exit 0
fi

APPROVED=0
REJECTED=0
MANUAL=0
PUBLISHED=0
OTHER=0

echo "Staged sessions in $STAGING_DIR:"
echo ""

for SESSION_DIR in "$STAGING_DIR"/*/; do
  [ ! -d "$SESSION_DIR" ] && continue
  SESSION=$(basename "$SESSION_DIR")
  STATUS=$(cat "${SESSION_DIR}/status" 2>/dev/null || echo "unknown")

  case "$STATUS" in
    approved) APPROVED=$((APPROVED + 1)) ;;
    rejected|blocked_trufflehog) REJECTED=$((REJECTED + 1)) ;;
    manual_review) MANUAL=$((MANUAL + 1)) ;;
    published) PUBLISHED=$((PUBLISHED + 1)) ;;
    *) OTHER=$((OTHER + 1)) ;;
  esac

  # Apply filter
  if [ "$FILTER" != "all" ] && [ "$STATUS" != "$FILTER" ]; then
    continue
  fi

  # Color-code status
  case "$STATUS" in
    approved) COLOR="\033[32m" ;;       # green
    published) COLOR="\033[36m" ;;      # cyan
    rejected|blocked*) COLOR="\033[31m" ;; # red
    manual_review) COLOR="\033[33m" ;;  # yellow
    *) COLOR="\033[37m" ;;              # gray
  esac

  SUMMARY=""
  if [ -f "${SESSION_DIR}/redacted.jsonl.review.json" ]; then
    SUMMARY=$(jq -r '.summary // ""' "${SESSION_DIR}/redacted.jsonl.review.json" 2>/dev/null)
  fi

  echo -e "  ${COLOR}[$STATUS]\033[0m $SESSION"
  [ -n "$SUMMARY" ] && echo "         $SUMMARY"

  # Show flagged parts if manual review
  if [ "$STATUS" = "manual_review" ] && [ -f "${SESSION_DIR}/redacted.jsonl.review.json" ]; then
    FLAGGED=$(jq -r '.flagged_parts[]? | "         ! " + .reason' "${SESSION_DIR}/redacted.jsonl.review.json" 2>/dev/null)
    [ -n "$FLAGGED" ] && echo "$FLAGGED"
  fi
done

echo ""
echo "Summary: $APPROVED approved, $REJECTED rejected, $MANUAL manual review, $PUBLISHED published, $OTHER other"

if [ $APPROVED -gt 0 ]; then
  echo ""
  echo "Run 'scripts/push.sh --org <org> --agent <agent>' to publish approved sessions."
fi

if [ $MANUAL -gt 0 ]; then
  echo ""
  echo "To approve a manual_review session: echo 'approved' > ~/.agent-traces/staging/<session>/status"
  echo "To reject: echo 'rejected' > ~/.agent-traces/staging/<session>/status"
fi
