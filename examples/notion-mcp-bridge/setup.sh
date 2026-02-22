#!/usr/bin/env bash
# Setup: expose Notion API as MCP tools via STOA gateway
set -euo pipefail

STOA_URL="${STOA_URL:-http://localhost:8080}"
NOTION_TOKEN="${NOTION_TOKEN:-secret_mock_token}"
NOTION_UPSTREAM="${NOTION_UPSTREAM:-http://notion-mock:1080}"
ADMIN_USER="${STOA_ADMIN_USER:-admin}"
ADMIN_PASS="${STOA_ADMIN_PASS:-admin}"

echo "==> STOA Notion MCP Bridge Setup"
echo "    STOA:     $STOA_URL"
echo "    Notion:   $NOTION_UPSTREAM"
echo ""

# ─────────────────────────────────────────────────────────────────
# Step 1: Authenticate
# ─────────────────────────────────────────────────────────────────
echo "==> [1/6] Authenticating..."
TOKEN=$(curl -sf -X POST "$STOA_URL/v1/auth/token" \
  -H "Content-Type: application/json" \
  -d "{\"username\": \"$ADMIN_USER\", \"password\": \"$ADMIN_PASS\"}" \
  | jq -r '.access_token')
AUTH="Authorization: Bearer $TOKEN"

# ─────────────────────────────────────────────────────────────────
# Step 2: Create tenant
# ─────────────────────────────────────────────────────────────────
echo "==> [2/6] Creating tenant..."
TENANT_ID=$(curl -sf -X POST "$STOA_URL/v1/tenants" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d '{"name": "notion-bridge", "display_name": "Notion MCP Bridge", "plan": "pro"}' \
  | jq -r '.id')
echo "    Tenant ID: $TENANT_ID"
echo "$TENANT_ID" > .tenant_id

# ─────────────────────────────────────────────────────────────────
# Step 3: Register Notion API with MCP tool definitions
# ─────────────────────────────────────────────────────────────────
echo "==> [3/6] Registering Notion API with MCP tools..."
API_ID=$(curl -sf -X POST "$STOA_URL/v1/tenants/$TENANT_ID/apis" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d "{
    \"name\": \"notion-api\",
    \"display_name\": \"Notion Workspace API\",
    \"version\": \"v1\",
    \"upstream_url\": \"$NOTION_UPSTREAM\",
    \"base_path\": \"/notion\",
    \"description\": \"Notion workspace exposed as MCP tools for AI agents\",
    \"mcp_enabled\": true,
    \"upstream_headers\": {
      \"Authorization\": \"Bearer $NOTION_TOKEN\",
      \"Notion-Version\": \"2022-06-28\"
    },
    \"mcp_tools\": [
      {
        \"name\": \"notion_search\",
        \"description\": \"Search pages and databases in the Notion workspace\",
        \"method\": \"POST\",
        \"path\": \"/v1/search\",
        \"input_schema\": {
          \"type\": \"object\",
          \"properties\": {
            \"query\": {\"type\": \"string\", \"description\": \"Search query\"},
            \"filter\": {\"type\": \"object\", \"description\": \"Filter by object type\"}
          },
          \"required\": [\"query\"]
        }
      },
      {
        \"name\": \"notion_read_page\",
        \"description\": \"Read a Notion page by its ID\",
        \"method\": \"GET\",
        \"path\": \"/v1/pages/{page_id}\",
        \"input_schema\": {
          \"type\": \"object\",
          \"properties\": {
            \"page_id\": {\"type\": \"string\", \"description\": \"Notion page UUID\"}
          },
          \"required\": [\"page_id\"]
        }
      },
      {
        \"name\": \"notion_create_block\",
        \"description\": \"Append a block (paragraph, bullet, etc.) to a Notion page\",
        \"method\": \"PATCH\",
        \"path\": \"/v1/blocks/{page_id}/children\",
        \"input_schema\": {
          \"type\": \"object\",
          \"properties\": {
            \"page_id\": {\"type\": \"string\", \"description\": \"Page to append to\"},
            \"content\": {\"type\": \"string\", \"description\": \"Text content to append\"},
            \"block_type\": {\"type\": \"string\", \"enum\": [\"paragraph\", \"bulleted_list_item\", \"numbered_list_item\"], \"default\": \"paragraph\"}
          },
          \"required\": [\"page_id\", \"content\"]
        }
      }
    ]
  }" | jq -r '.id')
echo "    API ID: $API_ID"

# ─────────────────────────────────────────────────────────────────
# Step 4: Create read-only and read-write agent consumers
# ─────────────────────────────────────────────────────────────────
echo "==> [4/6] Creating agent consumers..."

READONLY_ID=$(curl -sf -X POST "$STOA_URL/v1/consumers/$TENANT_ID" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d '{
    "external_id": "claude-readonly-agent",
    "name": "Claude Read-Only Agent",
    "email": "claude@ai.local",
    "consumer_metadata": {"mcp_permissions": ["notion:read"], "agent_type": "analysis"}
  }' | jq -r '.id')

READWRITE_ID=$(curl -sf -X POST "$STOA_URL/v1/consumers/$TENANT_ID" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d '{
    "external_id": "automation-agent",
    "name": "Automation Write Agent",
    "email": "automation@ai.local",
    "consumer_metadata": {"mcp_permissions": ["notion:read", "notion:write"], "agent_type": "automation"}
  }' | jq -r '.id')
echo "    Read-only agent: $READONLY_ID"
echo "    Read-write agent: $READWRITE_ID"

# ─────────────────────────────────────────────────────────────────
# Step 5: Create subscriptions
# ─────────────────────────────────────────────────────────────────
echo "==> [5/6] Creating subscriptions..."

READONLY_KEY=$(curl -sf -X POST "$STOA_URL/v1/subscriptions" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d "{\"consumer_id\": \"$READONLY_ID\", \"api_catalog_id\": \"$API_ID\", \"tenant_id\": \"$TENANT_ID\"}" \
  | jq -r '.api_key')

READWRITE_KEY=$(curl -sf -X POST "$STOA_URL/v1/subscriptions" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d "{\"consumer_id\": \"$READWRITE_ID\", \"api_catalog_id\": \"$API_ID\", \"tenant_id\": \"$TENANT_ID\"}" \
  | jq -r '.api_key')

# ─────────────────────────────────────────────────────────────────
# Step 6: Save test env
# ─────────────────────────────────────────────────────────────────
echo "==> [6/6] Saving test environment..."
cat > .env.test <<EOF
STOA_URL=$STOA_URL
TENANT_ID=$TENANT_ID
API_ID=$API_ID
READONLY_API_KEY=$READONLY_KEY
READWRITE_API_KEY=$READWRITE_KEY
EOF

echo ""
echo "✅ Setup complete!"
echo ""
echo "Test MCP tool discovery:"
echo "  curl -s $STOA_URL/mcp/capabilities | jq '.tools[] | .name'"
echo ""
echo "Test search tool (read-only agent):"
echo "  source .env.test"
echo "  curl -X POST $STOA_URL/mcp/tools/call \\"
echo "    -H \"X-API-Key: \$READONLY_API_KEY\" \\"
echo "    -H \"Content-Type: application/json\" \\"
echo "    -d '{\"name\": \"notion_search\", \"arguments\": {\"query\": \"meeting notes\"}}'"
echo ""
echo "Claude Desktop config:"
echo "  Add to ~/Library/Application Support/Claude/claude_desktop_config.json:"
echo "  { \"mcpServers\": { \"notion\": { \"url\": \"$STOA_URL/mcp\", \"transport\": \"streamable-http\" } } }"
