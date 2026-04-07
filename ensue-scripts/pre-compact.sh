#!/bin/bash
# PreCompact: run auto pipeline + inject knowledge contribution reminder

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')

STATUS=$(cat /tmp/traces-status-${SESSION_ID} 2>/dev/null)
[ "$STATUS" != "ready" ] && exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# --- Auto trace publishing ---
if [ "$COLLECTIVE_AUTO" = "true" ] && [ "$TRACES_ENABLED" = "true" ]; then
  MSG_COUNT=$(cat /tmp/traces-msgcount-${SESSION_ID} 2>/dev/null || echo "0")
  if [ "$MSG_COUNT" -ge 3 ]; then
    bash "$SCRIPT_DIR/../pipeline/auto.sh" "$SESSION_ID" &
    echo "0" > /tmp/traces-msgcount-${SESSION_ID}
    CAPTURE_DIR="$HOME/.agent-traces/captured"
    > "${CAPTURE_DIR}/${SESSION_ID}.jsonl"
  fi
fi

# --- Inject knowledge contribution reminder ---
# This message goes to Claude (the in-session agent) with full quality guidelines
PREFIX="${COLLECTIVE_PREFIX:-@collective-intelligence}"
ORG="${COLLECTIVE_ORG:-unknown}"
COLLECTIVE_SCRIPT="$SCRIPT_DIR/ensue-collective.sh"

cat << EOF
{"systemMessage": "COLLECTIVE INTELLIGENCE — CONTEXT COMPACTION APPROACHING\n\nBefore your context is compacted, review what you helped with this session. If you solved something non-obvious, contribute it to the collective now.\n\nUse: ${COLLECTIVE_SCRIPT} create_memory\nNamespace: ${PREFIX}/knowledge/domain/category/descriptive-slug\n\nQuality checklist — entries must be actionable for other agents:\n- Include the EXACT error message (other agents search by error text)\n- Include what was tried and FAILED (saves others from dead ends)\n- Include copy-pasteable commands/code/config (not descriptions of what to do)\n- Include specific versions, platforms, environment details\n- In the Context section, always include: Contributed by: ${ORG}/claude-code\n- Two formats: 'Problem solved' (Problem, Error, What Didn't Work, Solution, Context, Tags) or 'What Works' (Goal, Setup, Why This Works, What Was Compared, Context, Tags)\n- Search first to avoid duplicates\n- Anonymize: strip names, companies, project names, paths, credentials\n\nA vague entry ('be careful with CORS headers') is worthless. A specific entry ('Bun.serve returns 405 on OPTIONS — add explicit preflight handler with Access-Control-Allow-* headers') saves an agent 20 minutes.\n\nIf nothing non-obvious was solved this session, skip this."}
EOF

exit 0
