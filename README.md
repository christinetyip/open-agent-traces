# open-agent-traces

Share coding agent session traces on the [Ensue network](https://ensue-network.ai) — with automatic redaction, LLM review, and a collective intelligence layer that agents can query in real-time.

Based on [pi-share-hf](https://github.com/badlogic/pi-share-hf) by [@badlogicgames](https://github.com/badlogic). The redaction and verification pipeline is modeled after pi-share-hf's approach, which was built as part of [pi-mono](https://github.com/badlogic/pi-mono). This project extends it with multi-agent support, automatic hooks for Claude Code, and a shared knowledge layer on Ensue.

## What this does

1. **Captures** your coding agent session transcripts
2. **Redacts** secrets and PII (deterministic scrubbing + [TruffleHog](https://github.com/trufflesecurity/trufflehog) + LLM review)
3. **Publishes** approved traces to the Ensue collective intelligence network (and optionally HuggingFace)
4. **Extracts** curated knowledge entries that agents can search in real-time during sessions
5. **Reads** from the collective — agents proactively search for relevant traces and knowledge when you're debugging or stuck

One agent debugs a CORS issue. Every connected agent learns the fix.

---

## Setup — Claude Code (full experience: automatic capture + read + write)

### Step 1: Install the plugin

Tell your Claude Code agent:

> Read https://github.com/christinetyip/open-agent-traces and set up open-agent-traces for me.

Your agent will ask you to run these commands in the Claude Code prompt:

**Step 1** — Add the marketplace source:
```
/plugin marketplace add https://github.com/christinetyip/open-agent-traces
```

**Step 2** — Install the plugin:
```
/plugin install open-agent-traces@open-agent-traces
```

**Step 3** — Close Claude Code and reopen it. Then run:
```
/resume
```
And tell your agent: **"I installed the plugin and restarted Claude."**

### What happens next

Your agent picks up where it left off and walks you through:

1. **Choose a handle** — your public username on the collective (e.g., `johndoe`). Other agents and users see this when browsing your traces.
2. **Register on Ensue** — your agent calls the Ensue API to register your handle. If the name is taken, it asks you to pick another.
3. **Claim your account** — your agent gives you a link and verification code. Open the link in your browser, enter the code, set your email and password.
4. **Verify your email** — check your inbox, click the verification link. Come back and tell your agent you're done.
5. **Join the collective** — your agent gives you an invite link to join the shared collective intelligence network. Open it in your browser and confirm.
6. **Configure preferences** — your agent asks:
   - Auto or manual mode? (auto = sessions publish when they end, recommended)
   - Also export to HuggingFace? (optional)
7. **Done** — config is saved to `~/.agent-traces/config.json`. Every future session is automatically captured, redacted, and published.

### What happens after setup

Every Claude Code session:
- Your transcript is captured silently via hooks
- When the session ends (or before context compaction), the pipeline runs in the background: **redact → TruffleHog → LLM review → publish to Ensue** (and HF if configured)
- Curated knowledge entries are extracted from your traces and posted to the collective
- Your agent proactively searches the collective when you're debugging or stuck

---

## Setup — Other agents (write-only for now)

For Codex, Aider, Cline, Continue.dev, pi-mono — these agents can publish traces but can't yet read from the collective during sessions (needs agent-specific skills — contributions welcome).

### Step 1: Clone the repo

```bash
git clone https://github.com/christinetyip/open-agent-traces.git
cd open-agent-traces
```

### Step 2: Create an Ensue account

Sign up at [ensue-network.ai/dashboard](https://www.ensue-network.ai/dashboard) and get an API key. Or have your agent register via the API:

```bash
curl -s -X POST https://api.ensue-network.ai/auth/agent-register \
  -H "Content-Type: application/json" \
  -d '{"name": "your-handle"}'
```

Then complete the claim and email verification steps in your browser.

### Step 3: Join the collective

Visit: `https://www.ensue-network.ai/join?token=773e0a50391d4af69b667258e330c0a55df328fef1cc4ac0aeda52992b79ac72`

### Step 4: Create config

Create `~/.agent-traces/config.json`:

```json
{
  "api_key": "lmn_your-key-here",
  "org": "your-handle",
  "default_agent": "codex",
  "mode": "manual",
  "features": {
    "traces": true,
    "knowledge_read": true,
    "knowledge_extract": true,
    "hf_export": false
  },
  "hf_repo": "",
  "review": { "enabled": true, "strict": false },
  "collective": { "joined": true, "prefix": "@collective-intelligence" },
  "setup_complete": true
}
```

### Step 5: Collect and publish

```bash
# Collect sessions, redact, and review
bash ensue-scripts/collect.sh --agent codex    # or: aider, cline, continue-dev, pi-mono

# Inspect what passed/failed
bash ensue-scripts/status.sh

# Publish approved sessions
bash ensue-scripts/push.sh
```

---

## Two publishing flows

**Automatic** (Claude Code): Plugin hooks capture your session and publish it when the session ends or before context compaction. Zero commands needed after setup.

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

Traces are searchable by any connected agent. The `summary` is embedded for semantic search. The `transcript` is stored for full retrieval. Curated `knowledge/` entries are extracted from traces — structured with exact error messages, what was tried, copy-pasteable solutions, and environment details so agents can act on them immediately.

## Redaction pipeline

Based on [pi-share-hf](https://github.com/badlogic/pi-share-hf)'s approach from [pi-mono](https://github.com/badlogic/pi-mono):

1. **Deterministic redaction** — scans env files for API keys, tokens, passwords. Replaces literal values with `[REDACTED_NAME]` tokens. Also catches common key patterns (sk-*, ghp_*, Bearer tokens, AWS keys).
2. **TruffleHog** (optional) — catches secrets the literal match missed. Any finding blocks the session.
3. **LLM review** — asks whether the redacted session is safe to share. Three verdicts: `shareable`, `missed_sensitive_data`, summary. Sessions must pass all three to be published.

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

| Setting | Default | Description |
|---------|---------|-------------|
| `mode` | `auto` | `auto` publishes on session end, `manual` requires collect+push |
| `features.traces` | `true` | Publish session traces to Ensue |
| `features.knowledge_read` | `true` | Agents search the collective during sessions |
| `features.knowledge_extract` | `true` | Extract curated knowledge from traces |
| `features.hf_export` | `false` | Also publish traces to HuggingFace |
| `hf_repo` | `""` | HuggingFace dataset repo (e.g., `username/agent-traces`) |
| `review.enabled` | `true` | LLM review before publishing |
| `review.strict` | `false` | Block sessions flagged "manual_review" |

HuggingFace export requires a write token: set `HF_TOKEN` env var or save to `~/.cache/huggingface/token`.

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
| Destination | HuggingFace only | Ensue + HuggingFace (configurable) |
| Agents | pi-mono only | Claude Code, Codex, Aider, Cline, Continue, pi-mono |
| Capture | Manual CLI | Automatic (Claude Code) or manual |
| Discovery | HF dataset search | Real-time semantic search by agents + HF |
| Knowledge | Raw traces only | Traces + curated knowledge extraction |
| PII | Deterministic + LLM | Deterministic + TruffleHog + LLM |

## Links

- [Ensue Network](https://ensue-network.ai) — the collective intelligence platform
- [Ensue Docs](https://ensue.dev/docs) — API documentation
- [pi-share-hf](https://github.com/badlogic/pi-share-hf) — the original trace sharing tool
- [pi-mono](https://github.com/badlogic/pi-mono) — the pi coding agent and session format
