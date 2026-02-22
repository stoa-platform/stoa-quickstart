#!/usr/bin/env bash
# Setup: OpenAI API proxy with per-consumer token budgets
set -euo pipefail

STOA_URL="${STOA_URL:-http://localhost:8080}"
OPENAI_UPSTREAM="${OPENAI_UPSTREAM:-http://openai-mock:1080}"
OPENAI_API_KEY="${OPENAI_API_KEY:-sk-mock-key-for-testing}"
ADMIN_USER="${STOA_ADMIN_USER:-admin}"
ADMIN_PASS="${STOA_ADMIN_PASS:-admin}"

echo "==> STOA OpenAI Proxy Setup"
echo "    STOA:     $STOA_URL"
echo "    Upstream: $OPENAI_UPSTREAM"
echo ""

# ─────────────────────────────────────────────────────────────────
# Step 1: Authenticate
# ─────────────────────────────────────────────────────────────────
echo "==> [1/7] Authenticating..."
TOKEN=$(curl -sf -X POST "$STOA_URL/v1/auth/token" \
  -H "Content-Type: application/json" \
  -d "{\"username\": \"$ADMIN_USER\", \"password\": \"$ADMIN_PASS\"}" \
  | jq -r '.access_token')
AUTH="Authorization: Bearer $TOKEN"

# ─────────────────────────────────────────────────────────────────
# Step 2: Create tenant
# ─────────────────────────────────────────────────────────────────
echo "==> [2/7] Creating tenant..."
TENANT_ID=$(curl -sf -X POST "$STOA_URL/v1/tenants" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d '{"name": "openai-proxy", "display_name": "OpenAI Proxy", "plan": "pro"}' \
  | jq -r '.id')
echo "    Tenant ID: $TENANT_ID"
echo "$TENANT_ID" > .tenant_id

# ─────────────────────────────────────────────────────────────────
# Step 3: Register OpenAI API
# ─────────────────────────────────────────────────────────────────
echo "==> [3/7] Registering OpenAI API..."
API_ID=$(curl -sf -X POST "$STOA_URL/v1/tenants/$TENANT_ID/apis" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d "{
    \"name\": \"openai-api\",
    \"display_name\": \"OpenAI API\",
    \"version\": \"v1\",
    \"upstream_url\": \"$OPENAI_UPSTREAM\",
    \"base_path\": \"/openai\",
    \"description\": \"OpenAI API proxy with token budget enforcement\",
    \"upstream_headers\": {
      \"Authorization\": \"Bearer $OPENAI_API_KEY\"
    }
  }" | jq -r '.id')
echo "    API ID: $API_ID"

# ─────────────────────────────────────────────────────────────────
# Step 4: Create request rate limit policies
# ─────────────────────────────────────────────────────────────────
echo "==> [4/7] Creating rate limit policies..."

FREE_RL_ID=$(curl -sf -X POST "$STOA_URL/v1/admin/policies" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d "{
    \"name\": \"openai-free-rate-limit\",
    \"policy_type\": \"rate_limit\",
    \"tenant_id\": \"$TENANT_ID\",
    \"scope\": \"api\",
    \"config\": {\"requests_per_minute\": 10, \"burst_size\": 3, \"strategy\": \"sliding_window\"},
    \"priority\": 10,
    \"enabled\": true
  }" | jq -r '.id')

PRO_RL_ID=$(curl -sf -X POST "$STOA_URL/v1/admin/policies" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d "{
    \"name\": \"openai-pro-rate-limit\",
    \"policy_type\": \"rate_limit\",
    \"tenant_id\": \"$TENANT_ID\",
    \"scope\": \"api\",
    \"config\": {\"requests_per_minute\": 60, \"burst_size\": 20, \"strategy\": \"sliding_window\"},
    \"priority\": 10,
    \"enabled\": true
  }" | jq -r '.id')

# Bind free rate limit as default
curl -sf -X POST "$STOA_URL/v1/admin/policies/bindings" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d "{\"policy_id\": \"$FREE_RL_ID\", \"api_catalog_id\": \"$API_ID\", \"tenant_id\": \"$TENANT_ID\", \"enabled\": true}" > /dev/null

# ─────────────────────────────────────────────────────────────────
# Step 5: Create consumers (2 projects)
# ─────────────────────────────────────────────────────────────────
echo "==> [5/7] Creating project consumers..."

FREE_ID=$(curl -sf -X POST "$STOA_URL/v1/consumers/$TENANT_ID" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d "{
    \"external_id\": \"free-project\",
    \"name\": \"Free Project\",
    \"email\": \"free@example.com\",
    \"consumer_metadata\": {\"plan\": \"free\", \"daily_token_limit\": 10000}
  }" | jq -r '.id')

PRO_ID=$(curl -sf -X POST "$STOA_URL/v1/consumers/$TENANT_ID" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d "{
    \"external_id\": \"pro-project\",
    \"name\": \"Pro Project\",
    \"email\": \"pro@example.com\",
    \"consumer_metadata\": {\"plan\": \"pro\", \"daily_token_limit\": 100000}
  }" | jq -r '.id')
echo "    Free project: $FREE_ID | Pro project: $PRO_ID"

# ─────────────────────────────────────────────────────────────────
# Step 6: Create subscriptions
# ─────────────────────────────────────────────────────────────────
echo "==> [6/7] Creating subscriptions..."

FREE_KEY=$(curl -sf -X POST "$STOA_URL/v1/subscriptions" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d "{\"consumer_id\": \"$FREE_ID\", \"api_catalog_id\": \"$API_ID\", \"tenant_id\": \"$TENANT_ID\", \"plan\": \"free\"}" \
  | jq -r '.api_key')
FREE_SUB_ID=$(curl -sf "$STOA_URL/v1/subscriptions?consumer_id=$FREE_ID" -H "$AUTH" | jq -r '.items[0].id')

PRO_KEY=$(curl -sf -X POST "$STOA_URL/v1/subscriptions" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d "{\"consumer_id\": \"$PRO_ID\", \"api_catalog_id\": \"$API_ID\", \"tenant_id\": \"$TENANT_ID\", \"plan\": \"pro\"}" \
  | jq -r '.api_key')

# ─────────────────────────────────────────────────────────────────
# Step 7: Save test env
# ─────────────────────────────────────────────────────────────────
echo "==> [7/7] Saving test environment..."
cat > .env.test <<EOF
STOA_URL=$STOA_URL
TENANT_ID=$TENANT_ID
API_ID=$API_ID
FREE_PROJECT_ID=$FREE_ID
FREE_PROJECT_KEY=$FREE_KEY
PRO_PROJECT_ID=$PRO_ID
PRO_PROJECT_KEY=$PRO_KEY
EOF

echo ""
echo "✅ Setup complete!"
echo ""
echo "Test an AI call (free tier):"
echo "  source .env.test"
echo "  curl -s -X POST \$STOA_URL/openai/v1/chat/completions \\"
echo "    -H \"X-API-Key: \$FREE_PROJECT_KEY\" \\"
echo "    -H \"Content-Type: application/json\" \\"
echo "    -d '{\"model\": \"gpt-4o-mini\", \"messages\": [{\"role\": \"user\", \"content\": \"What is STOA?\"}], \"max_tokens\": 100}'"
echo ""
echo "Check token usage:"
echo "  curl -s \"\$STOA_URL/v1/audit/\$TENANT_ID?type=ai_completion\" | jq '.items[] | {model: .metadata.model, tokens: .metadata.total_tokens}'"
