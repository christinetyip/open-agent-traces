#!/bin/bash
# Publish a redacted session trace to HuggingFace datasets.
# Called by publish.sh when HF is configured.
#
# Usage: pipeline/publish-hf.sh <redacted.jsonl> --org <org> --agent <agent> --session <id> --hf-repo <repo>
# Requires: HF_TOKEN env var or ~/.cache/huggingface/token

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../ensue-scripts/config.sh"

REDACTED_FILE="$1"
shift

ORG=""
AGENT=""
SESSION_ID=""
HF_REPO=""

while [ $# -gt 0 ]; do
  case "$1" in
    --org) ORG="$2"; shift 2 ;;
    --agent) AGENT="$2"; shift 2 ;;
    --session) SESSION_ID="$2"; shift 2 ;;
    --hf-repo) HF_REPO="$2"; shift 2 ;;
    *) shift ;;
  esac
done

: "${ORG:=$COLLECTIVE_ORG}"
: "${AGENT:=$DEFAULT_AGENT}"
: "${HF_REPO:=$(jq -r '.hf_repo // empty' "$HOME/.agent-traces/config.json" 2>/dev/null)}"

# Skip if HF not enabled or no repo configured
[ "$HF_ENABLED" != "true" ] && [ -z "$HF_REPO" ] && exit 0
[ -z "$HF_REPO" ] && exit 0
[ ! -f "$REDACTED_FILE" ] && exit 1
[ -z "$SESSION_ID" ] && SESSION_ID=$(basename "$REDACTED_FILE" .jsonl | head -c 12)

# Resolve HF token
if [ -z "$HF_TOKEN" ]; then
  TOKEN_FILE="$HOME/.cache/huggingface/token"
  [ -f "$TOKEN_FILE" ] && HF_TOKEN=$(cat "$TOKEN_FILE")
fi

if [ -z "$HF_TOKEN" ]; then
  echo "HF_TOKEN not set and no token at ~/.cache/huggingface/token. Skipping HF upload." >&2
  exit 0
fi

# File path on HF: agent/session-id.jsonl
HF_PATH="${AGENT}/${SESSION_ID}.jsonl"

# Try huggingface-cli first (cleaner), fall back to API
if command -v huggingface-cli &> /dev/null; then
  echo "Uploading to HF via CLI: ${HF_REPO}/${HF_PATH}" >&2
  huggingface-cli upload "$HF_REPO" "$REDACTED_FILE" "$HF_PATH" \
    --repo-type dataset \
    --commit-message "Add session ${SESSION_ID} from ${ORG}/${AGENT}" \
    2>/dev/null

  if [ $? -eq 0 ]; then
    echo "Published to HF: https://huggingface.co/datasets/${HF_REPO}" >&2
    exit 0
  else
    echo "huggingface-cli upload failed, trying API fallback..." >&2
  fi
fi

# Fallback: HuggingFace API via curl
# Step 1: Ensure dataset repo exists
curl -s -o /dev/null -w "%{http_code}" \
  -X POST "https://huggingface.co/api/repos/create" \
  -H "Authorization: Bearer $HF_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"type\":\"dataset\",\"name\":\"$(basename "$HF_REPO")\",\"private\":false}" 2>/dev/null

# Step 2: Upload the file
echo "Uploading to HF via API: ${HF_REPO}/${HF_PATH}" >&2
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X PUT "https://huggingface.co/api/datasets/${HF_REPO}/upload/main/${HF_PATH}" \
  -H "Authorization: Bearer $HF_TOKEN" \
  -H "Content-Type: application/octet-stream" \
  --data-binary "@${REDACTED_FILE}" 2>/dev/null)

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
  echo "Published to HF: https://huggingface.co/datasets/${HF_REPO}" >&2
else
  echo "HF upload failed (HTTP $HTTP_CODE)" >&2
  exit 1
fi

# Step 3: Upload/update dataset card if it doesn't exist
CARD_CHECK=$(curl -s -o /dev/null -w "%{http_code}" \
  "https://huggingface.co/api/datasets/${HF_REPO}/tree/main/README.md" \
  -H "Authorization: Bearer $HF_TOKEN" 2>/dev/null)

if [ "$CARD_CHECK" = "404" ]; then
  CARD=$(cat << CARD_EOF
---
license: mit
task_categories:
  - text-generation
tags:
  - agent-traces
  - coding-agent
  - open-agent-traces
---

# ${HF_REPO}

Coding agent session traces published via [open-agent-traces](https://github.com/christinetyip/open-agent-traces).

## Data description

Each \`.jsonl\` file is a redacted coding agent session. Sessions are stored as JSON Lines where each line is a structured entry with \`role\`, \`content\`, \`ts\`, and optionally \`tool\` fields.

Traces are organized by agent type:
\`\`\`
${AGENT}/
  <session-id>.jsonl
\`\`\`

## Redaction

All sessions have been processed through:
1. Deterministic secret redaction (API keys, tokens, passwords replaced with \`[REDACTED_*]\`)
2. TruffleHog scanning (if available)
3. LLM review for shareability and missed sensitive data

## Source

These traces are also available on the [Ensue collective intelligence network](https://ensue-network.ai) for real-time agent search.

Published with [open-agent-traces](https://github.com/christinetyip/open-agent-traces), based on [pi-share-hf](https://github.com/badlogic/pi-share-hf) from [pi-mono](https://github.com/badlogic/pi-mono).
CARD_EOF
)

  # Upload the README
  echo "$CARD" | curl -s -o /dev/null \
    -X PUT "https://huggingface.co/api/datasets/${HF_REPO}/upload/main/README.md" \
    -H "Authorization: Bearer $HF_TOKEN" \
    -H "Content-Type: application/octet-stream" \
    --data-binary @- 2>/dev/null
fi

exit 0
