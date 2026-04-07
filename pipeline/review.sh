#!/bin/bash
# LLM review — asks Claude whether a redacted session is safe to share.
# Modeled after pi-share-hf's three-verdict system.
#
# Usage: pipeline/review.sh <redacted.jsonl> [--model model-name]
# Output: writes verdict to <redacted.jsonl>.review.json
# Exit code: 0 = approved, 1 = rejected, 2 = needs manual review, 3 = error

REDACTED_FILE="$1"
shift

[ ! -f "$REDACTED_FILE" ] && echo "Error: file not found: $REDACTED_FILE" && exit 3

# Parse optional model flag
MODEL=""
while [ $# -gt 0 ]; do
  case "$1" in
    --model) MODEL="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# Check if claude CLI is available
if ! command -v claude &> /dev/null; then
  echo "claude CLI not found. Skipping LLM review." >&2
  # Write a pass-through verdict (no review = approved with caveat)
  cat > "${REDACTED_FILE}.review.json" << 'EOF'
{"shareable": "yes", "missed_sensitive_data": "maybe", "summary": "LLM review skipped (claude CLI not available)", "flagged_parts": [], "review_skipped": true}
EOF
  exit 0
fi

# Serialize redacted JSONL to human-readable text for the LLM
# Truncate to ~100K chars (~20K tokens) to stay within context
TRANSCRIPT_TEXT=$(python3 << 'PYEOF' "$REDACTED_FILE"
import sys, json

lines = []
with open(sys.argv[1]) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
        except:
            continue

        role = entry.get("role", "unknown")
        ts = entry.get("ts", "")

        if role == "user":
            content = entry.get("content", "")[:4000]
            lines.append(f"[User] ({ts}):\n{content}")
        elif role == "assistant":
            content = entry.get("content", "")[:4000]
            lines.append(f"[Assistant] ({ts}):\n{content}")
        elif role == "tool_call":
            tool = entry.get("tool", "unknown")
            inp = entry.get("input", "")[:2000]
            lines.append(f"[Tool call: {tool}] ({ts}):\n{inp}")
        elif role == "tool_result":
            tool = entry.get("tool", "unknown")
            out = entry.get("output", "")[:2000]
            lines.append(f"[Tool result: {tool}] ({ts}):\n{out}")
        else:
            content = str(entry.get("content", entry))[:2000]
            lines.append(f"[{role}] ({ts}):\n{content}")

output = "\n\n".join(lines)
# Cap at ~100K chars
print(output[:100000])
PYEOF
)

[ -z "$TRANSCRIPT_TEXT" ] && echo "Error: empty transcript" >&2 && exit 3

# Build claude command
CLAUDE_ARGS=(-p)
[ -n "$MODEL" ] && CLAUDE_ARGS+=(--model "$MODEL")

# Run LLM review
VERDICT=$(claude "${CLAUDE_ARGS[@]}" "$(cat << PROMPT
You are reviewing a REDACTED coding agent session transcript. The session has already been through deterministic secret redaction (literal secrets replaced with [REDACTED_*] tokens, paths anonymized, emails removed).

Your job is to decide whether this session is safe to publish publicly. Answer with strict JSON only.

Evaluate:
1. shareable: Is this session appropriate to share publicly after redaction?
   - "yes" = safe to publish
   - "no" = contains content that should not be public
   - "manual_review" = uncertain, needs human review

2. missed_sensitive_data: Did the redaction appear to miss any sensitive content?
   - "yes" = likely missed secrets, API keys, passwords, PII, confidential data
   - "no" = redaction appears thorough
   - "maybe" = some content looks suspicious but unclear

3. summary: One-sentence description of what this session was about.

4. flagged_parts: Array of {reason, evidence} for anything concerning.

Guidelines:
- [REDACTED_*] tokens are EXPECTED — they mean redaction worked. Do NOT flag these.
- /home/user/ paths are already anonymized — these are fine.
- [EMAIL] tokens are already anonymized — these are fine.
- Git commit metadata with public emails (noreply@github.com) is fine.
- Code content from OSS projects is fine.
- Focus on: passwords in plaintext, API keys not caught by redaction, internal company names or project names that reveal identity, private infrastructure details.

Return ONLY valid JSON, no markdown fences, no explanation:
{"shareable": "yes|no|manual_review", "missed_sensitive_data": "yes|no|maybe", "summary": "...", "flagged_parts": []}

--- REDACTED TRANSCRIPT ---
${TRANSCRIPT_TEXT}
PROMPT
)" 2>/dev/null)

[ -z "$VERDICT" ] && echo "Error: no response from claude" >&2 && exit 3

# Validate JSON
echo "$VERDICT" | jq '.' > /dev/null 2>&1
if [ $? -ne 0 ]; then
  # Try to extract JSON from response (claude might add extra text)
  VERDICT=$(echo "$VERDICT" | python3 -c "
import sys, re, json
text = sys.stdin.read()
# Find JSON object in text
match = re.search(r'\{.*\}', text, re.DOTALL)
if match:
    try:
        obj = json.loads(match.group())
        print(json.dumps(obj))
    except:
        print('{}')
else:
    print('{}')
")
fi

# Write verdict
echo "$VERDICT" | jq '.' > "${REDACTED_FILE}.review.json" 2>/dev/null || echo "$VERDICT" > "${REDACTED_FILE}.review.json"

# Determine exit code based on verdict
SHAREABLE=$(echo "$VERDICT" | jq -r '.shareable // "no"' 2>/dev/null)
MISSED=$(echo "$VERDICT" | jq -r '.missed_sensitive_data // "maybe"' 2>/dev/null)

if [ "$SHAREABLE" = "yes" ] && [ "$MISSED" = "no" ]; then
  SUMMARY=$(echo "$VERDICT" | jq -r '.summary // "No summary"' 2>/dev/null)
  echo "Approved: $SUMMARY" >&2
  exit 0
elif [ "$SHAREABLE" = "manual_review" ] || [ "$MISSED" = "maybe" ]; then
  echo "Needs manual review" >&2
  exit 2
else
  echo "Rejected: shareable=$SHAREABLE, missed_sensitive=$MISSED" >&2
  exit 1
fi
