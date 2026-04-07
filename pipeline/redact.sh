#!/bin/bash
# Deterministic secret redaction — modeled after pi-share-hf's approach.
# Reads secrets from env files + explicit sources, replaces literal values.
#
# Usage: pipeline/redact.sh <input.jsonl> <output.jsonl> [--env-file path] [--secrets path]
#
# Outputs:
#   - Redacted JSONL to <output.jsonl>
#   - Report to <output.jsonl>.report.json
#   - Exit code 0 if clean, 1 if secrets were found and redacted

INPUT_FILE="$1"
OUTPUT_FILE="$2"
shift 2

[ ! -f "$INPUT_FILE" ] && echo "Error: input file not found: $INPUT_FILE" && exit 2

# Parse optional args
ENV_FILES=()
SECRET_FILES=()
SECRET_LITERALS=()

# Defaults: scan common env files
for f in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do
  [ -f "$f" ] && ENV_FILES+=("$f")
done
# Also scan .env in cwd if present
[ -f ".env" ] && ENV_FILES+=(".env")

while [ $# -gt 0 ]; do
  case "$1" in
    --env-file) ENV_FILES+=("$2"); shift 2 ;;
    --secrets)
      if [ -f "$2" ]; then
        SECRET_FILES+=("$2")
      else
        SECRET_LITERALS+=("$2")
      fi
      shift 2 ;;
    *) shift ;;
  esac
done

# Use Python for reliable text processing
python3 << 'PYEOF' "$INPUT_FILE" "$OUTPUT_FILE" "${ENV_FILES[*]}" "${SECRET_FILES[*]}" "${SECRET_LITERALS[*]}"
import sys, os, re, json

input_file = sys.argv[1]
output_file = sys.argv[2]
env_files = sys.argv[3].split() if sys.argv[3] else []
secret_files = sys.argv[4].split() if sys.argv[4] else []
secret_literals = sys.argv[5].split() if sys.argv[5] else []

# Collect secrets: name -> value
secrets = {}

# Parse env files for export KEY="value" where key name suggests a secret
SECRET_KEY_PATTERNS = re.compile(
    r'(KEY|TOKEN|SECRET|PASSWORD|PWD|COOKIE|CREDENTIAL|AUTH|API_KEY|PRIVATE)',
    re.IGNORECASE
)

for env_file in env_files:
    if not os.path.exists(env_file):
        continue
    with open(env_file) as f:
        for line in f:
            line = line.strip()
            # Match: export KEY="value" or KEY="value" or KEY=value
            m = re.match(r'^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.+)$', line)
            if not m:
                continue
            name, value = m.group(1), m.group(2)
            if not SECRET_KEY_PATTERNS.search(name):
                continue
            # Strip quotes
            value = value.strip('"').strip("'")
            if len(value) > 4:
                secrets[name] = value

# Read explicit secret files (one secret per line)
for sf in secret_files:
    if not os.path.exists(sf):
        continue
    with open(sf) as f:
        for i, line in enumerate(f):
            val = line.strip()
            if len(val) > 4:
                secrets[f"SECRET_{i}"] = val

# Explicit literals
for i, lit in enumerate(secret_literals):
    if len(lit) > 4:
        secrets[f"LITERAL_{i}"] = lit

# Also add common API key patterns as regex-based redaction
PATTERN_REDACTIONS = [
    (re.compile(r'sk-[a-zA-Z0-9]{20,}'), '[REDACTED_API_KEY]'),
    (re.compile(r'sk-ant-[a-zA-Z0-9\-]{20,}'), '[REDACTED_ANTHROPIC_KEY]'),
    (re.compile(r'sk-proj-[a-zA-Z0-9\-]{20,}'), '[REDACTED_OPENAI_KEY]'),
    (re.compile(r'ghp_[a-zA-Z0-9]{36,}'), '[REDACTED_GITHUB_TOKEN]'),
    (re.compile(r'gho_[a-zA-Z0-9]{36,}'), '[REDACTED_GITHUB_OAUTH]'),
    (re.compile(r'github_pat_[a-zA-Z0-9_]{22,}'), '[REDACTED_GITHUB_PAT]'),
    (re.compile(r'xoxb-[a-zA-Z0-9\-]+'), '[REDACTED_SLACK_TOKEN]'),
    (re.compile(r'xoxp-[a-zA-Z0-9\-]+'), '[REDACTED_SLACK_TOKEN]'),
    (re.compile(r'Bearer\s+[a-zA-Z0-9\-_.]{20,}'), 'Bearer [REDACTED_BEARER]'),
    (re.compile(r'AKIA[0-9A-Z]{16}'), '[REDACTED_AWS_KEY]'),
    (re.compile(r'[a-zA-Z0-9+/]{40}(?=\s|$|")'), '[REDACTED_POSSIBLE_SECRET]'),  # base64-ish 40+ chars
]

# Path redaction: /Users/<username>/... -> /home/user/...
username = os.environ.get('USER', os.environ.get('USERNAME', 'user'))
HOME_PATH_RE = re.compile(re.escape(f'/Users/{username}') + r'(/[^\s"\'\\]*)')
LINUX_HOME_RE = re.compile(re.escape(f'/home/{username}') + r'(/[^\s"\'\\]*)')

# Email redaction
EMAIL_RE = re.compile(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}')

# Sort secrets by value length (longest first) to avoid partial replacement
sorted_secrets = sorted(secrets.items(), key=lambda x: len(x[1]), reverse=True)

report = {
    "secrets_found": 0,
    "patterns_matched": 0,
    "paths_redacted": 0,
    "emails_redacted": 0,
    "redactions": []
}

def redact_text(text):
    global report

    # 1. Literal secret replacement
    for name, value in sorted_secrets:
        if value in text:
            count = text.count(value)
            text = text.replace(value, f'[REDACTED_{name}]')
            report["secrets_found"] += count
            report["redactions"].append({"type": "literal", "name": name, "count": count})

    # 2. Pattern-based redaction
    for pattern, replacement in PATTERN_REDACTIONS:
        matches = pattern.findall(text)
        if matches:
            text = pattern.sub(replacement, text)
            report["patterns_matched"] += len(matches)
            report["redactions"].append({"type": "pattern", "replacement": replacement, "count": len(matches)})

    # 3. Path redaction
    for path_re in [HOME_PATH_RE, LINUX_HOME_RE]:
        matches = path_re.findall(text)
        if matches:
            text = path_re.sub(r'/home/user\1', text)
            report["paths_redacted"] += len(matches)

    # 4. Email redaction (but keep common public ones)
    PUBLIC_EMAILS = {'noreply@github.com', 'noreply@anthropic.com'}
    def email_replacer(m):
        email = m.group(0)
        if email in PUBLIC_EMAILS:
            return email
        report["emails_redacted"] += 1
        return '[EMAIL]'
    text = EMAIL_RE.sub(email_replacer, text)

    return text

# Process JSONL
with open(input_file) as fin, open(output_file, 'w') as fout:
    for line in fin:
        line = line.strip()
        if not line:
            continue
        # Redact the entire JSON line as text (catches secrets in any field)
        redacted = redact_text(line)
        fout.write(redacted + '\n')

# Write report
report_path = output_file + '.report.json'
with open(report_path, 'w') as f:
    json.dump(report, f, indent=2)

total = report["secrets_found"] + report["patterns_matched"]
if total > 0:
    print(f"Redacted: {report['secrets_found']} literal secrets, {report['patterns_matched']} pattern matches, {report['paths_redacted']} paths, {report['emails_redacted']} emails", file=sys.stderr)
    sys.exit(1)  # secrets were found (but redacted)
else:
    print(f"Clean: no secrets found. {report['paths_redacted']} paths redacted, {report['emails_redacted']} emails redacted.", file=sys.stderr)
    sys.exit(0)
PYEOF
