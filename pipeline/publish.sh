#!/bin/bash
# Publish an approved, redacted session trace to the collective on Ensue.
# Posts both a searchable summary and the full transcript.
#
# Usage: pipeline/publish.sh <redacted.jsonl> --org <org> --agent <agent> --session <id>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../ensue-scripts/config.sh"

REDACTED_FILE="$1"
shift

[ ! -f "$REDACTED_FILE" ] && echo "Error: file not found: $REDACTED_FILE" && exit 1

# Parse args
ORG=""
AGENT=""
SESSION_ID=""
EXTRACT_KNOWLEDGE="false"

while [ $# -gt 0 ]; do
  case "$1" in
    --org) ORG="$2"; shift 2 ;;
    --agent) AGENT="$2"; shift 2 ;;
    --session) SESSION_ID="$2"; shift 2 ;;
    --extract-knowledge) EXTRACT_KNOWLEDGE="true"; shift ;;
    *) shift ;;
  esac
done

: "${ORG:=$COLLECTIVE_ORG}"
: "${AGENT:=$DEFAULT_AGENT}"

[ -z "$ORG" ] && echo "Error: --org required (or set in config)" && exit 1
[ -z "$AGENT" ] && echo "Error: --agent required" && exit 1
[ -z "$SESSION_ID" ] && SESSION_ID=$(basename "$REDACTED_FILE" .jsonl | head -c 12)

COLLECTIVE="$SCRIPT_DIR/../ensue-scripts/ensue-collective.sh"
PREFIX="${COLLECTIVE_PREFIX:-@collective-intelligence}"

# Load review summary if available
REVIEW_FILE="${REDACTED_FILE}.review.json"
SUMMARY=""
[ -f "$REVIEW_FILE" ] && SUMMARY=$(jq -r '.summary // ""' "$REVIEW_FILE" 2>/dev/null)

# Generate structured summary using heuristics
STATS=$(python3 << 'PYEOF' "$REDACTED_FILE" "$SUMMARY"
import sys, json
from collections import Counter

redacted_file = sys.argv[1]
review_summary = sys.argv[2] if len(sys.argv) > 2 else ""

roles = Counter()
tools = Counter()
errors = []
first_ts = None
last_ts = None

with open(redacted_file) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
        except:
            continue
        role = entry.get("role", "unknown")
        roles[role] += 1
        ts = entry.get("ts", "")
        if first_ts is None:
            first_ts = ts
        last_ts = ts
        if role == "tool_call":
            tools[entry.get("tool", "unknown")] += 1
        content = str(entry.get("content", "")) + str(entry.get("input", ""))
        for kw in ["Error:", "error:", "ECONNREFUSED", "ENOENT", "TypeError", "SyntaxError", "FATAL", "failed"]:
            if kw in content:
                idx = content.find(kw)
                snippet = content[max(0,idx-20):idx+80].strip()
                if snippet and len(errors) < 5:
                    errors.append(snippet[:120])

print(json.dumps({
    "summary": review_summary or "Coding agent session",
    "started": first_ts or "",
    "ended": last_ts or "",
    "message_count": sum(roles.values()),
    "user_messages": roles.get("user", 0),
    "assistant_messages": roles.get("assistant", 0),
    "tool_calls": dict(tools.most_common(10)),
    "errors_encountered": errors[:5],
}))
PYEOF
)

# Build namespace with collective prefix
NS="${PREFIX}/agent-traces/${ORG}/${AGENT}/${SESSION_ID}"

TRANSCRIPT_CONTENT=$(cat "$REDACTED_FILE" | jq -Rs '.')

SUMMARY_MD=$(echo "$STATS" | python3 -c "
import sys, json
s = json.load(sys.stdin)
lines = ['# Session Trace', '', f'**{s[\"summary\"]}**', '']
lines.append(f'- Started: {s[\"started\"]}')
lines.append(f'- Ended: {s[\"ended\"]}')
lines.append(f'- Messages: {s[\"message_count\"]} ({s[\"user_messages\"]} user, {s[\"assistant_messages\"]} assistant)')
lines.append('')
if s['tool_calls']:
    lines.append('## Tools used')
    for tool, count in sorted(s['tool_calls'].items(), key=lambda x: -x[1]):
        lines.append(f'- {tool}: {count}')
    lines.append('')
if s['errors_encountered']:
    lines.append('## Errors encountered')
    for err in s['errors_encountered']:
        lines.append(f'- \`{err}\`')
    lines.append('')
print('\n'.join(lines))
")

SUMMARY_DESC=$(echo "$STATS" | jq -r '"[trace] " + .summary + " (" + (.message_count|tostring) + " messages)"')

# Post summary (embed: true — searchable)
echo "Publishing summary to ${NS}/summary..." >&2
"$COLLECTIVE" create_memory "{\"items\":[{
  \"key_name\":\"${NS}/summary\",
  \"description\":$(echo "$SUMMARY_DESC" | jq -Rs '.'),
  \"value\":$(echo "$SUMMARY_MD" | jq -Rs '.'),
  \"embed\":true
}]}" > /dev/null 2>&1

# Post transcript (embed: false — stored for retrieval only)
echo "Publishing transcript to ${NS}/transcript..." >&2
"$COLLECTIVE" create_memory "{\"items\":[{
  \"key_name\":\"${NS}/transcript\",
  \"description\":\"Full redacted transcript for session ${SESSION_ID}\",
  \"value\":${TRANSCRIPT_CONTENT},
  \"embed\":false
}]}" > /dev/null 2>&1

echo "Published: ${NS}" >&2

# Optionally extract knowledge
if [ "$EXTRACT_KNOWLEDGE" = "true" ] && [ "$KNOWLEDGE_EXTRACT" = "true" ]; then
  EXTRACT_SCRIPT="$SCRIPT_DIR/../ensue-scripts/extract-knowledge.sh"
  [ -f "$EXTRACT_SCRIPT" ] && bash "$EXTRACT_SCRIPT" "$REDACTED_FILE" "$ORG" "$AGENT" &
fi

exit 0
