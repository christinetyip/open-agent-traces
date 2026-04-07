#!/bin/bash
# Extract curated knowledge entries from a redacted session trace.
# Posts to @collective-intelligence/knowledge/ namespace.
#
# Usage: scripts/extract-knowledge.sh <redacted.jsonl> <org> <agent>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(cd "$SCRIPT_DIR" && pwd)/config.sh"

REDACTED_FILE="$1"
ORG="${2:-$COLLECTIVE_ORG}"
AGENT="${3:-$DEFAULT_AGENT}"

COLLECTIVE="$SCRIPT_DIR/ensue-collective.sh"
PREFIX="${COLLECTIVE_PREFIX:-@collective-intelligence}"
LOG="$HOME/.agent-traces/extract.log"

[ ! -s "$REDACTED_FILE" ] && exit 0
command -v claude &> /dev/null || exit 0

TRANSCRIPT_TEXT=$(python3 << 'PYEOF' "$REDACTED_FILE"
import sys, json
lines = []
with open(sys.argv[1]) as f:
    for line in f:
        line = line.strip()
        if not line: continue
        try: entry = json.loads(line)
        except: continue
        role = entry.get("role", "unknown")
        if role == "user":
            lines.append("USER: " + entry.get("content", "")[:4000])
        elif role == "assistant":
            lines.append("ASSISTANT: " + entry.get("content", "")[:4000])
        elif role == "tool_call":
            tool = entry.get("tool", "?")
            inp = entry.get("input", "")[:1000]
            lines.append(f"TOOL({tool}): {inp}")
print("\n".join(lines)[:50000])
PYEOF
)

[ -z "$TRANSCRIPT_TEXT" ] && exit 0

TOPIC=$(echo "$TRANSCRIPT_TEXT" | head -c 500)
EXISTING=$("$COLLECTIVE" search_memories "{\"query\":$(echo "$TOPIC" | jq -Rs '.[0:200]'),\"limit\":5}" \
  | jq -r '.result.structuredContent.results[]?.key_name // empty' 2>/dev/null)

EXISTING_CONTEXT=""
[ -n "$EXISTING" ] && EXISTING_CONTEXT="
EXISTING ENTRIES ON RELATED TOPICS — do NOT duplicate these:
$EXISTING
"

EXTRACTION=$(claude -p "$(cat << 'PROMPT_HEADER'
You are extracting actionable knowledge from a redacted coding agent session. Other AI agents will retrieve these entries in real-time when their users hit similar problems. The entries must be specific enough that an agent can apply the solution immediately.

## What to extract

ONLY extract entries where:
- A non-obvious bug was debugged — especially with a specific error message
- A configuration was discovered through trial and error
- A tool, model, or setup comparison was made with a clear winner
- A useful workaround, gotcha, or integration pattern was found
- A recipe, home automation setup, or life hack was worked through

DO NOT extract:
- Common knowledge easily found in official docs
- Anything user-specific, personal, or identifying
- Solutions that weren't verified to work in the session
- Vague advice without specifics ("be careful with CORS" is useless)

## Entry format — Problem/Fix entries

For bugs, errors, configuration issues:

```markdown
# Clear Title — include the specific error or pattern name

## Problem
What was the issue — described generically. Be specific about symptoms: what the user saw, when it happened, what made it hard to diagnose.

## Error
The EXACT error message, stack trace, or unexpected output — copy-pasted from the transcript, not paraphrased. This is critical: other agents will search by error text. If there's no specific error message, omit this section.

## What Didn't Work
Approaches that were tried and failed, with why each didn't work. This saves other agents from going down the same dead ends. Omit only if the solution was immediate (no failed attempts).

## Solution
The fix that worked. Include exact code, config, or commands — copy-pasteable, not described. Explain the key insight: WHY this works, not just WHAT to do. Someone should be able to read this and fix their problem in under a minute.

## Context
- Verified: YYYY-MM-DD
- Environment: specific tech stack, versions, platform
- Confidence: high (verified fix) or medium (worked but edge cases unknown)

## Tags
Comma-separated keywords. Include: error name, technology names, category of problem.
```

## Entry format — "What Works" entries

For setups, model choices, tool comparisons, configurations that work:

```markdown
# Clear Title — what setup/choice this is about

## Goal
What the user was trying to achieve.

## Setup
The configuration, model, architecture, or tool combination that works. Include specific settings, versions, values, brand names. Not vague recommendations.

## Why This Works
What makes this effective. Include benchmarks or observations if available.

## What Was Compared
Other options tried or considered, and why they were worse. This is what makes the entry valuable — not just "use X" but "X beats Y because Z". Omit if nothing was compared.

## Context
- Verified: YYYY-MM-DD
- Environment: tech stack, versions, platform
- Confidence: high or medium

## Tags
Comma-separated keywords.
```

## Specificity rules

These rules are critical. Vague entries are worthless. Specific entries save real time.

- **Exact error messages** — not "a CORS error" but the full `Access to fetch at ... has been blocked by CORS policy: Response to preflight request doesn't pass access control check`
- **Exact commands** — copy-pasteable, not "run the build command with the platform flag"
- **Exact versions** — not "Node.js" but "Node.js 22+" or "Node.js 20.11.0"
- **Exact config values** — not "increase the timeout" but `timeout: 60000`
- **What was tried and failed** — this is as valuable as the fix itself

If the transcript doesn't contain enough detail for a specific field, omit that field rather than inventing details.

## Output format

For each entry, output a JSON object:
- key_name: starts with PREFIX/knowledge/ then domain/category/descriptive-slug (lowercase, hyphens). The slug should be specific enough that the key name alone tells you what it's about.
- description: "[domain] One-line description of what this solves or teaches"
- value: The full markdown entry following the format above
- embed: true

Key naming examples:
- PREFIX/knowledge/debugging/docker/m1-mac-exec-format-error
- PREFIX/knowledge/debugging/bun/serve-cors-preflight-405
- PREFIX/knowledge/setups/postgres/jsonb-gin-index-for-api-filters
- PREFIX/knowledge/models/coding/claude-sonnet-vs-gpt4o-refactoring
- PREFIX/knowledge/tools/cli/ripgrep-faster-than-grep

If nothing in the transcript is worth extracting, output exactly: []
Output ONLY a valid JSON array. No markdown fences, no explanation.
PROMPT_HEADER

cat << PROMPT_VARS

Replace PREFIX with: ${PREFIX}
Today's date for Verified field: $(date +%Y-%m-%d)

${EXISTING_CONTEXT}

--- REDACTED SESSION TRANSCRIPT ---
${TRANSCRIPT_TEXT}
PROMPT_VARS
)" 2>/dev/null)

[ -z "$EXTRACTION" ] && exit 0

# Validate JSON — try to extract array if claude added extra text
VALID=$(echo "$EXTRACTION" | jq '.' 2>/dev/null)
if [ -z "$VALID" ]; then
  EXTRACTION=$(echo "$EXTRACTION" | python3 -c "
import sys, re, json
text = sys.stdin.read()
match = re.search(r'\[.*\]', text, re.DOTALL)
if match:
    try:
        arr = json.loads(match.group())
        print(json.dumps(arr))
    except:
        print('[]')
else:
    print('[]')
")
fi

ENTRY_COUNT=$(echo "$EXTRACTION" | jq 'length' 2>/dev/null)
[ "$ENTRY_COUNT" = "0" ] || [ -z "$ENTRY_COUNT" ] && exit 0

# Post to collective
RESPONSE=$("$COLLECTIVE" create_memory "{\"items\":$EXTRACTION}" 2>&1)
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Extracted $ENTRY_COUNT knowledge entries: $(echo "$EXTRACTION" | jq -r '.[].key_name' 2>/dev/null | tr '\n' ', ')" >> "$LOG"
exit 0
