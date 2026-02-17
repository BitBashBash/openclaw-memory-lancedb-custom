# OpenClaw Memory LanceDB — Custom Embedding Edition

Drop-in replacement for OpenClaw's bundled `memory-lancedb` plugin with two key additions:

1. **Custom embedding endpoint** — Use Ollama, LM Studio, vLLM, or any OpenAI-compatible API instead of being locked to OpenAI
2. **Multi-agent memory isolation** — Tag memories with `agentId` so multiple agents sharing one OpenClaw instance can't see each other's data

## Requirements

- OpenClaw 2026.2.x+
- Node.js 22+
- An OpenAI-compatible embedding endpoint

## Quick Start

### 1. Copy plugin files

Replace the bundled plugin source files:

```bash
PLUGIN_DIR="$HOME/.npm-global/lib/node_modules/openclaw/extensions/memory-lancedb"

# Backup originals
cp "$PLUGIN_DIR/index.ts" "$PLUGIN_DIR/index.ts.bak"
cp "$PLUGIN_DIR/config.ts" "$PLUGIN_DIR/config.ts.bak"
cp "$PLUGIN_DIR/openclaw.plugin.json" "$PLUGIN_DIR/openclaw.plugin.json.bak"

# Copy custom files
cp index.ts "$PLUGIN_DIR/index.ts"
cp config.ts "$PLUGIN_DIR/config.ts"
cp openclaw.plugin.json "$PLUGIN_DIR/openclaw.plugin.json"
```

### 2. Install LanceDB dependency

```bash
cd "$HOME/.npm-global/lib/node_modules/openclaw"  # Linux
# or: cd /opt/homebrew/lib/node_modules/openclaw   # macOS (Homebrew)

npm install @lancedb/lancedb apache-arrow --legacy-peer-deps
node -e "require('@lancedb/lancedb'); console.log('OK')"
```

> **Note:** The `--legacy-peer-deps` flag is needed to avoid peer dependency conflicts with OpenClaw's dev dependencies. If the `node` check fails on macOS, try `npm install @lancedb/lancedb --build-from-source --legacy-peer-deps` (requires Xcode Command Line Tools).

### 3. Patch the compiled dist (schema validation)

The bundled `dist/` files contain a compiled schema that rejects custom models and baseUrl. Patch it:

```bash
cd "$HOME/.npm-global/lib/node_modules/openclaw"
for f in dist/manager-*.js; do
  if grep -q "text-embedding-3-small" "$f"; then
    # Remove model enum restriction
    sed -i 's/"enum":\["text-embedding-3-small","text-embedding-3-large"\]/"type":"string"/g' "$f"
    # Add baseUrl as accepted property
    sed -i 's/"additionalProperties":false,"properties":{"apiKey":{"type":"string"},"model"/"properties":{"apiKey":{"type":"string"},"baseUrl":{"type":"string"},"model"/g' "$f"
    # Remove required apiKey constraint
    sed -i 's/"required":\["apiKey"\]/"required":[]/g' "$f"
    echo "Patched: $f"
  fi
done
```

### 4. Configure in openclaw.json

```json
{
  "plugins": {
    "slots": { "memory": "memory-lancedb" },
    "entries": {
      "memory-lancedb": {
        "enabled": true,
        "config": {
          "embedding": {
            "apiKey": "your-api-key",
            "model": "nomic-embed-text-v2-moe",
            "baseUrl": "https://your-ollama-server:11434/v1"
          },
          "autoCapture": true,
          "autoRecall": true
        }
      }
    }
  }
}
```

### 5. Restart

```bash
openclaw gateway restart
```

### 6. Verify

```bash
# Check plugin loaded
grep "memory-lancedb" /tmp/openclaw-1000/openclaw-$(date +%Y-%m-%d).log | tail -5

# Should show:
# memory-lancedb: plugin registered (db: ..., lazy init)
# memory-lancedb: initialized (db: ..., model: nomic-embed-text-v2-moe)
```

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

### Known Embedding Dimensions (auto-detected)

| Model | Dimensions |
|-------|------------|
| `text-embedding-3-small` | 1536 |
| `text-embedding-3-large` | 3072 |
| `nomic-embed-text-v2-moe` | 768 |
| `nomic-embed-text` / `v1.5` | 768 |
| `mxbai-embed-large` | 1024 |
| `bge-large-en-v1.5` / `bge-m3` | 1024 |
| `all-minilm` | 384 |
| Unknown models | 768 (default) |

If your model uses different dimensions, it will still work — LanceDB adapts to the actual vector size on first write.

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

## CLI Commands

```bash
openclaw ltm list              # Count total memories
openclaw ltm search "query"    # Search memories
openclaw ltm stats             # Memory statistics
```

## Tools

The plugin registers three tools available to your agents:

| Tool | Description |
|------|-------------|
| `memory_recall` | Search memories by semantic similarity |
| `memory_store` | Save new information (with deduplication) |
| `memory_forget` | Delete memories by ID or search (GDPR) |

## Data Location

- **Vector database:** `~/.openclaw/memory/lancedb/` (configurable via `dbPath`)
- **Format:** LanceDB (Apache Arrow-based columnar storage)
- **Persistence:** On-disk, survives restarts

## Updating OpenClaw

When you update OpenClaw (`npm update -g openclaw`), the plugin source files and `@lancedb/lancedb` dependency will be overwritten. To restore:

```bash
PLUGIN_DIR="$HOME/.npm-global/lib/node_modules/openclaw/extensions/memory-lancedb"

# Restore plugin files
cp /path/to/this/repo/index.ts "$PLUGIN_DIR/index.ts"
cp /path/to/this/repo/config.ts "$PLUGIN_DIR/config.ts"
cp /path/to/this/repo/openclaw.plugin.json "$PLUGIN_DIR/openclaw.plugin.json"

# Reinstall LanceDB
cd "$HOME/.npm-global/lib/node_modules/openclaw"  # or /opt/homebrew/lib/node_modules/openclaw on macOS
npm install @lancedb/lancedb apache-arrow --legacy-peer-deps

# Re-patch dist
for f in dist/manager-*.js; do
  if grep -q "text-embedding-3-small" "$f"; then
    sed -i 's/"enum":\["text-embedding-3-small","text-embedding-3-large"\]/"type":"string"/g' "$f"
    sed -i 's/"additionalProperties":false,"properties":{"apiKey":{"type":"string"},"model"/"properties":{"apiKey":{"type":"string"},"baseUrl":{"type":"string"},"model"/g' "$f"
    sed -i 's/"required":\["apiKey"\]/"required":[]/g' "$f"
    echo "Patched: $f"
  fi
done

openclaw gateway restart
```

## License

MIT
