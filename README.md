# OpenClaw Memory LanceDB — Custom Edition

> LanceDB-backed long-term memory for OpenClaw with **multi-agent isolation**, extended embedding model support, and any OpenAI-compatible endpoint.

## What This Adds Over Stock

| Feature | Stock | Custom |
|---------|-------|--------|
| Custom embedding endpoint (baseUrl) | ✅ | ✅ |
| Explicit dimensions override | ✅ | ✅ |
| Environment variable resolution (`${ENV_VAR}`) | ✅ | ✅ |
| **Multi-agent memory isolation (agentId)** | ❌ | ✅ |
| **Extended embedding dimensions map (12+ models)** | ❌ (2 models) | ✅ |
| **Graceful 768-dim fallback for unknown models** | ❌ (throws error) | ✅ |

## Requirements

- OpenClaw 2026.2.x+
- Node.js 22+
- An OpenAI-compatible embedding endpoint

## Compatibility

- **Newer OpenClaw releases**: Stock supports baseUrl/dimensions natively — install just copies 3 source files. No dist patching needed.
- **Older OpenClaw releases**: Installer auto-detects and applies dist patches for schema validation bypass.

The installer handles both cases automatically — you don't need to think about it.

## Quick Install

```bash
git clone https://github.com/BitBashBash/openclaw-memory-lancedb-custom.git
cd openclaw-memory-lancedb-custom
chmod +x install.sh
./install.sh
```

The installer auto-detects your OpenClaw install path on both Linux and macOS (Homebrew).

> **macOS note:** If LanceDB fails to install, you may need Xcode Command Line Tools:
> ```bash
> xcode-select --install
> cd "$(npm root -g)/openclaw"
> npm install @lancedb/lancedb --build-from-source --legacy-peer-deps
> ```

## Configuration

Add to `~/.openclaw/openclaw.json`:

```json
{
  "plugins": {
    "slots": { "memory": "memory-lancedb" },
    "entries": {
      "memory-lancedb": {
        "enabled": true,
        "config": {
          "embedding": {
            "apiKey": "ollama",
            "model": "nomic-embed-text-v2-moe",
            "baseUrl": "http://localhost:11434/v1",
            "dimensions": 768
          },
          "autoCapture": false,
          "autoRecall": false
        }
      }
    }
  }
}
```

Then restart: `openclaw gateway restart`

### Config Reference

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `embedding.apiKey` | string | *required* | API key (or `"ollama"` for Ollama). Supports `${ENV_VAR}` |
| `embedding.model` | string | `text-embedding-3-small` | Embedding model name |
| `embedding.baseUrl` | string | OpenAI API | Custom endpoint URL. Supports `${ENV_VAR}` |
| `embedding.dimensions` | number | auto-detected | Explicit vector dimensions (skips model lookup) |
| `dbPath` | string | `~/.openclaw/memory/lancedb` | LanceDB database path |
| `autoCapture` | boolean | `false` | Auto-capture important info from conversations |
| `autoRecall` | boolean | `true` | Auto-inject relevant memories into context |
| `captureMaxChars` | number | `500` | Max message length for auto-capture (100–10000) |

## Embedding Providers

Works with any OpenAI-compatible `/v1/embeddings` endpoint:

| Provider | baseUrl | Example Model |
|----------|---------|---------------|
| **OpenAI** | *(omit — uses default)* | `text-embedding-3-small` |
| **Ollama** | `http://localhost:11434/v1` | `nomic-embed-text-v2-moe` |
| **LM Studio** | `http://localhost:1234/v1` | `nomic-embed-text-v1.5-GGUF` |
| **vLLM** | `http://localhost:8000/v1` | `BAAI/bge-large-en-v1.5` |
| **LocalAI** | `http://localhost:8080/v1` | `bert-cpp-minilm-v6` |
| **text-embeddings-inference** | `http://localhost:8081` | `BAAI/bge-m3` |

### Supported Embedding Models (Built-in Dimensions)

| Model | Dimensions |
|-------|-----------|
| `text-embedding-3-small` | 1536 |
| `text-embedding-3-large` | 3072 |
| `text-embedding-ada-002` | 1536 |
| `gemini-embedding-001` | 3072 |
| `nomic-embed-text` / `v1.5` / `v2-moe` | 768 |
| `mxbai-embed-large` | 1024 |
| `all-minilm` | 384 |
| `bge-large-en-v1.5` / `bge-m3` | 1024 |
| `snowflake-arctic-embed` | 1024 |
| *any other model* | 768 (fallback) |

Use the `dimensions` config field to override for models not in this list.

## Multi-Agent Isolation

If you run multiple agents on one OpenClaw instance, use `agentId` to keep their memories separate.

### How it works

Each memory is tagged with an `agentId` field. When an agent passes their ID to `memory_recall`, they only see:
- Memories tagged with their own ID
- Memories tagged as `"shared"` (no agent specified)

Memories from other agents are filtered out.

### Setup

**1. Disable autoCapture and autoRecall** (they lack agent context):

```json
"memory-lancedb": {
  "config": {
    "autoCapture": false,
    "autoRecall": false
  }
}
```

**2. Add memory rules to each agent's PLAYBOOK.md or SOUL.md:**

```markdown
## Memory Rules
- When using memory_store or memory_recall, ALWAYS pass agentId: "your-agent-name"
```

**3. Test isolation:**

```
# Agent A: "Remember my favorite color is blue"     → stored with agentId: "agent-a"
# Agent B: "What is my favorite color?"              → no results
# Agent A: "What is my favorite color?"              → "blue"
```

### Single agent?

If you only have one agent, ignore agentId entirely — everything works without it. Memories are tagged `"shared"` by default.

## Updating OpenClaw

After running `openclaw update`, re-run the installer to reapply custom files:

```bash
cd /path/to/openclaw-memory-lancedb-custom
git pull
./install.sh
openclaw gateway restart
```

Or use the included update script which handles everything (backup → update → re-apply → restart):

```bash
./scripts/openclaw-update.sh
```

To set up the scripts for first-time use:

```bash
# Copy to your scripts directory
cp scripts/openclaw-update.sh ~/scripts/
cp scripts/pre-update-backup.sh ~/scripts/
chmod +x ~/scripts/openclaw-update.sh ~/scripts/pre-update-backup.sh

# Run future updates with one command
~/scripts/openclaw-update.sh
```

## CLI Commands

```bash
openclaw ltm list              # Count total memories
openclaw ltm search "query"    # Search memories (--limit N)
openclaw ltm stats             # Memory statistics
```

## Tools Available to Agents

| Tool | Description |
|------|-------------|
| `memory_recall` | Search memories with optional agentId filtering |
| `memory_store` | Store new memories with agentId tagging and dedup |
| `memory_forget` | Delete memories by ID or search query (GDPR-compliant) |

## Data Location

- **Vector database:** `~/.openclaw/memory/lancedb/` (configurable via `dbPath`)
- **Format:** LanceDB (Apache Arrow-based columnar storage)
- **Persistence:** On-disk, survives restarts

## Files

| File | Purpose |
|------|---------|
| `index.ts` | Core plugin — tools, lifecycle hooks, agentId isolation |
| `config.ts` | Schema parser, dimensions map, env var resolution |
| `openclaw.plugin.json` | Plugin manifest with configSchema |
| `install.sh` | Smart installer with auto-skip dist patching (Linux + macOS) |
| `scripts/openclaw-update.sh` | Full update pipeline (backup → update → re-apply → restart) |
| `scripts/pre-update-backup.sh` | Pre-update snapshot of plugin, dist, config, and LanceDB data |

## License

MIT
