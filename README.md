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

### agentId Isolation

Each agent passes its name as `agentId` when storing/recalling memories. Memories are filtered so agents only see their own memories plus `"shared"` memories. This prevents cross-contamination between agents like Maya (business ops) and Nova (personal assistant).

## Compatibility

- **Newer OpenClaw releases**: Install just copies 3 source files. No dist patching needed.
- **Older OpenClaw releases**: Installer auto-detects and applies dist patches for schema validation bypass.

The installer handles both cases automatically — you don't need to think about it.

## Quick Install

```bash
git clone https://github.com/BitBashBash/openclaw-memory-lancedb-custom.git
cd openclaw-memory-lancedb-custom
chmod +x install.sh
./install.sh
```

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

## Updating OpenClaw

After running `openclaw update`, re-run the installer to reapply custom files:

```bash
cd /path/to/openclaw-memory-lancedb-custom
git pull
./install.sh
```

Or use the automated update script:

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="/home/ubuntu/openclaw-memory-lancedb-custom"
echo "=== OpenClaw Update + Custom LanceDB ==="

# 1. Update OpenClaw
openclaw update --no-restart --yes
echo "Updated to: $(openclaw --version 2>&1 | head -1)"

# 2. Pull + reinstall custom plugin
cd "$REPO_DIR" && git pull --ff-only
./install.sh

# 3. Restart
openclaw gateway restart
echo "=== Done ==="
```

## CLI Commands

```bash
openclaw ltm list              # Count total memories
openclaw ltm search "query"    # Search memories (--limit N)
openclaw ltm stats             # Show statistics
```

## Tools Available to Agents

| Tool | Description |
|------|-------------|
| `memory_recall` | Search memories with optional agentId filtering |
| `memory_store` | Store new memories with agentId tagging and dedup |
| `memory_forget` | Delete memories by ID or search query (GDPR-compliant) |

## Files

| File | Purpose |
|------|---------|
| `index.ts` | Core plugin — tools, lifecycle hooks, agentId isolation |
| `config.ts` | Schema parser, dimensions map, env var resolution |
| `openclaw.plugin.json` | Plugin manifest with configSchema |
| `install.sh` | Smart installer with auto-skip dist patching |

## License

MIT
