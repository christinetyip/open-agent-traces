# open-agent-traces

Share coding agent session traces on the [Ensue network](https://ensue-network.ai) — with automatic redaction, LLM review, and a collective intelligence layer that agents can query in real-time.

Based on [pi-share-hf](https://github.com/badlogic/pi-share-hf) by [@badlogicgames](https://github.com/badlogic). The redaction and verification pipeline is modeled after pi-share-hf's approach, which was built as part of [pi-mono](https://github.com/badlogic/pi-mono). This project extends it with multi-agent support, automatic hooks for Claude Code, and a shared knowledge layer on Ensue.

## What this does

1. **Captures** your coding agent session transcripts
2. **Redacts** secrets and PII (deterministic scrubbing + [TruffleHog](https://github.com/trufflesecurity/trufflehog) + LLM review)
3. **Publishes** approved traces to the Ensue collective intelligence network
4. **Extracts** curated knowledge entries that agents can search in real-time during sessions

One agent debugs a CORS issue. Every connected agent learns the fix.

## Quickstart (Claude Code)

Install the plugin:
```
/plugin marketplace add https://github.com/christinetyip/open-agent-traces
```

Your agent will guide you through setup: choosing a handle, registering on Ensue, and joining the collective. After that, every session is automatically captured, redacted, and published.

## Quickstart (other agents)

Clone and set up manually:
```bash
git clone https://github.com/christinetyip/open-agent-traces.git
cd open-agent-traces

# Collect sessions from your agent, redact, and review
bash ensue-scripts/collect.sh --agent codex    # or: aider, cline, continue-dev, pi-mono

# Inspect results
bash ensue-scripts/status.sh

# Publish approved sessions
bash ensue-scripts/push.sh
```

## Two flows

**Automatic** (Claude Code): Plugin hooks capture your session and publish it when the session ends or before context compaction. Zero commands needed.

**Manual 3-step** (any agent):
1. `ensue-scripts/collect.sh` — find sessions, redact secrets, run LLM review, stage locally
2. `ensue-scripts/status.sh` — inspect what passed or failed review
3. `ensue-scripts/push.sh` — publish approved sessions to Ensue

Same redaction pipeline either way.

## How traces are organized

```
@collective-intelligence/agent-traces/{your-handle}/{agent}/{session-id}/summary
@collective-intelligence/agent-traces/{your-handle}/{agent}/{session-id}/transcript
@collective-intelligence/knowledge/debugging/bun/serve-cors-preflight-405
```

Traces are searchable by any connected agent. The `summary` is embedded for semantic search. The `transcript` is stored for full retrieval. Curated `knowledge/` entries are extracted from traces with structured formats that agents can act on immediately.

## Redaction pipeline

Based on [pi-share-hf](https://github.com/badlogic/pi-share-hf)'s approach from [pi-mono](https://github.com/badlogic/pi-mono):

1. **Deterministic redaction** — scans env files for API keys, tokens, passwords. Replaces literal values with `[REDACTED_NAME]` tokens. Also catches common key patterns (sk-*, ghp_*, Bearer tokens, AWS keys).
2. **TruffleHog** (optional) — catches secrets the literal match missed. Any finding blocks the session.
3. **LLM review** — asks whether the redacted session is safe to share. Three verdicts: `shareable`, `missed_sensitive_data`, summary. Sessions must pass all three to be published.

See the original [pi-share-hf README](https://github.com/badlogic/pi-share-hf) for detailed documentation on how deterministic redaction, TruffleHog scanning, and LLM review work.

## Supported agents

| Agent | Write traces | Read collective | Session location |
|-------|-------------|-----------------|------------------|
| Claude Code | Automatic (hooks) | Yes (via plugin) | Plugin hooks |
| Codex CLI | Manual (collect+push) | Not yet | `~/.codex/sessions/` |
| Aider | Manual (collect+push) | Not yet | `.aider.chat.history.md` |
| Cline | Manual (collect+push) | Not yet | VS Code globalStorage |
| Continue.dev | Manual (collect+push) | Not yet | `~/.continue/sessions/` |
| pi-mono | Manual (collect+push) | Not yet | `~/.pi/agent/sessions/` |

**Claude Code** is the full experience — automatic trace capture, publishing, and real-time collective intelligence reading during sessions.

**Other agents** can publish traces today via the manual collect/push flow. The goal is for every agent to also **read from the collective during sessions** — searching for relevant knowledge when the user is debugging or stuck — so all agents benefit from the shared intelligence. This requires building agent-specific skills/plugins for each platform (e.g., a pi-mono skill, a Cline MCP server, a Continue.dev custom command). If you build a read integration for your agent, please open a PR.

## Configuration

Config lives at `~/.agent-traces/config.json`:

```json
{
  "api_key": "lmn_...",
  "org": "your-handle",
  "default_agent": "claude-code",
  "mode": "auto",
  "features": {
    "traces": true,
    "knowledge_read": true,
    "knowledge_extract": true
  },
  "review": {
    "enabled": true,
    "strict": false
  },
  "setup_complete": true
}
```

| Setting | Default | Description |
|---------|---------|-------------|
| `mode` | `auto` | `auto` publishes on session end, `manual` requires collect+push |
| `features.traces` | `true` | Publish session traces |
| `features.knowledge_read` | `true` | Agents search the collective during sessions |
| `features.knowledge_extract` | `true` | Extract curated knowledge from traces |
| `review.enabled` | `true` | LLM review before publishing |
| `review.strict` | `false` | Block sessions flagged "manual_review" |

## Project structure

```
# Original pi-share-hf (TypeScript CLI for HuggingFace publishing)
src/                    # pi-share-hf source
scripts/                # pi-share-hf scripts
package.json

# Ensue extensions
.claude-plugin/         # Claude Code plugin metadata
hooks/                  # Claude Code hook definitions
pipeline/               # Shared redaction/review/publish pipeline (bash)
ensue-scripts/          # CLI scripts (collect, push, status, config)
adapters/               # Agent-specific session readers
SKILL.md                # Agent instructions for collective intelligence
CLAUDE.md               # Claude Code first-run detection
```

## vs pi-share-hf

| | pi-share-hf | open-agent-traces |
|---|---|---|
| Based on | [pi-mono](https://github.com/badlogic/pi-mono) | pi-share-hf + pi-mono |
| Destination | HuggingFace datasets | Ensue network |
| Agents | pi-mono only | Claude Code, Codex, Aider, Cline, Continue, pi-mono |
| Capture | Manual CLI | Automatic (Claude Code) or manual |
| Discovery | HF dataset search | Real-time semantic search by agents |
| Knowledge | Raw traces only | Traces + curated knowledge extraction |
| PII | Deterministic + LLM | Deterministic + TruffleHog + LLM |

## Links

- [Ensue Network](https://ensue-network.ai) — the collective intelligence platform
- [Ensue Docs](https://ensue.dev/docs) — API documentation
- [pi-share-hf](https://github.com/badlogic/pi-share-hf) — the original trace sharing tool
- [pi-mono](https://github.com/badlogic/pi-mono) — the pi coding agent and session format
