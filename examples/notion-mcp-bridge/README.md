# Example: Notion API as an MCP Tool

Expose your Notion workspace to AI agents via STOA's MCP gateway. Claude, GPT-4, and other
MCP-compatible agents can read and write Notion pages without direct API key access.

## What This Example Shows

- Register Notion API as an MCP tool in STOA
- Let AI agents discover and call Notion operations (read page, search, create block)
- Apply RBAC: some agents can read, others can write
- Audit every AI interaction with your Notion workspace

## Prerequisites

- STOA quickstart running (`docker compose up -d` from repo root)
- Notion integration token (get one at https://www.notion.so/my-integrations)
- `curl` and `jq` installed

## Architecture

```
AI Agent (Claude, GPT-4)
   │
   └── MCP Client ──→ STOA MCP Gateway :8080/mcp ──→ Notion API
                              │
                              ├── Tool: notion_read_page
                              ├── Tool: notion_search
                              ├── Tool: notion_create_block
                              └── RBAC: read-only | read-write agents
```

## Quick Start

### 1. Start mock Notion server (offline mode)

```bash
docker compose up -d
```

### 2. Set your Notion token

```bash
cp .env.example .env
# Edit .env: set NOTION_TOKEN=secret_your_token_here
source .env
```

### 3. Configure STOA

```bash
chmod +x setup.sh
./setup.sh
```

### 4. Test MCP tool discovery

```bash
# Discover available tools
curl -s http://localhost:8080/mcp/capabilities | jq '.tools[] | .name'

# Call the search tool
curl -s -X POST http://localhost:8080/mcp/tools/call \
  -H "Content-Type: application/json" \
  -d '{
    "name": "notion_search",
    "arguments": {"query": "meeting notes", "filter": {"object": "page"}}
  }' | jq '.result'
```

### 5. Use with Claude Desktop

Add to `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "notion-via-stoa": {
      "url": "http://localhost:8080/mcp",
      "transport": "streamable-http"
    }
  }
}
```

Restart Claude Desktop. You'll see Notion tools available in Claude's tool palette.

### 6. Audit AI interactions

```bash
TENANT_ID=$(cat .tenant_id)
curl -s "http://localhost:8080/v1/audit/$TENANT_ID?type=mcp_tool_call&limit=20" \
  | jq '.items[] | {timestamp, tool_name: .metadata.tool, agent_id: .consumer_id}'
```

## MCP Tools Registered

| Tool | Description | RBAC |
|------|-------------|------|
| `notion_read_page` | Read a page by ID | read |
| `notion_search` | Search workspace | read |
| `notion_list_databases` | List accessible databases | read |
| `notion_create_block` | Append block to page | write |
| `notion_update_page` | Update page properties | write |

## RBAC Configuration

The setup script creates two agent tiers:

```bash
# Read-only agent (for analysis/Q&A)
POST /v1/consumers/$TENANT_ID
{
  "external_id": "claude-readonly",
  "consumer_metadata": {"mcp_permissions": ["notion:read"]}
}

# Read-write agent (for automation)
POST /v1/consumers/$TENANT_ID
{
  "external_id": "automation-agent",
  "consumer_metadata": {"mcp_permissions": ["notion:read", "notion:write"]}
}
```

## Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Mock Notion server |
| `setup.sh` | STOA + MCP configuration script |
| `.env.example` | Environment variable template |
| `tools/` | MCP tool definition JSON files |

## Next Steps

- [Connecting AI Agents to Enterprise APIs](https://docs.gostoa.dev/blog/connecting-ai-agents-enterprise-apis)
- [OpenAI Proxy Example](../openai-proxy/)
- [JWT Auth Gateway Example](../jwt-auth-gateway/)
