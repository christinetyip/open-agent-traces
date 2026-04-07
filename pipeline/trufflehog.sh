#!/bin/bash
# TruffleHog scan — optional second layer after deterministic redaction.
# Catches secrets the literal match missed.
#
# Usage: pipeline/trufflehog.sh <redacted.jsonl>
# Exit code: 0 = clean, 1 = findings (blocks publish), 2 = trufflehog not installed (skip)

REDACTED_FILE="$1"
[ ! -f "$REDACTED_FILE" ] && echo "Error: file not found: $REDACTED_FILE" && exit 2

# Check if TruffleHog is available
if ! command -v trufflehog &> /dev/null; then
  echo "TruffleHog not installed (optional). Skipping." >&2
  exit 2
fi

# Run TruffleHog on the redacted file
FINDINGS=$(trufflehog filesystem "$REDACTED_FILE" -j \
  --results=verified,unknown,unverified \
  --no-color --no-update 2>/dev/null)

if [ -z "$FINDINGS" ]; then
  echo "TruffleHog: clean" >&2
  exit 0
fi

# Parse findings
COUNT=$(echo "$FINDINGS" | jq -s 'length')
VERIFIED=$(echo "$FINDINGS" | jq -s '[.[] | select(.Verified == true)] | length')

echo "TruffleHog: $COUNT findings ($VERIFIED verified)" >&2

# Write findings report
REPORT="${REDACTED_FILE}.trufflehog.json"
echo "$FINDINGS" | jq -s '.' > "$REPORT"

# Any findings block publishing
exit 1
