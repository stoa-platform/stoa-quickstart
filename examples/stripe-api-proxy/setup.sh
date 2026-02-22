#!/usr/bin/env bash
# Setup script: configure STOA as a Stripe API proxy with rate limiting
# Usage: ./setup.sh [--upstream URL]
set -euo pipefail

STOA_URL="${STOA_URL:-http://localhost:8080}"
UPSTREAM_URL="${STRIPE_UPSTREAM_URL:-http://stripe-mock:12111}"
ADMIN_USER="${STOA_ADMIN_USER:-admin}"
ADMIN_PASS="${STOA_ADMIN_PASS:-admin}"

# Parse flags
while [[ $# -gt 0 ]]; do
  case $1 in
    --upstream) UPSTREAM_URL="$2"; shift 2 ;;
    *) echo "Unknown flag: $1"; exit 1 ;;
  esac
done

echo "==> STOA Stripe Proxy Setup"
echo "    STOA:     $STOA_URL"
echo "    Upstream: $UPSTREAM_URL"
echo ""

# ─────────────────────────────────────────────────────────────────
# Step 1: Get admin token
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
echo "==> [2/7] Creating tenant stripe-demo..."
TENANT=$(curl -sf -X POST "$STOA_URL/v1/tenants" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d '{"name": "stripe-demo", "display_name": "Stripe Demo", "plan": "pro"}')
TENANT_ID=$(echo "$TENANT" | jq -r '.id')
echo "    Tenant ID: $TENANT_ID"
echo "$TENANT_ID" > .tenant_id

# ─────────────────────────────────────────────────────────────────
# Step 3: Register Stripe API in catalog
# ─────────────────────────────────────────────────────────────────
echo "==> [3/7] Registering Stripe API..."
API=$(curl -sf -X POST "$STOA_URL/v1/tenants/$TENANT_ID/apis" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d "{
    \"name\": \"stripe-api\",
    \"display_name\": \"Stripe Payment API\",
    \"version\": \"v1\",
    \"upstream_url\": \"$UPSTREAM_URL\",
    \"base_path\": \"/stripe\",
    \"description\": \"Stripe payment processing API with rate limiting\"
  }")
API_ID=$(echo "$API" | jq -r '.id')
echo "    API ID: $API_ID"

# ─────────────────────────────────────────────────────────────────
# Step 4: Create rate limit policies
# ─────────────────────────────────────────────────────────────────
echo "==> [4/7] Creating rate limit policies..."

FREE_POLICY=$(curl -sf -X POST "$STOA_URL/v1/admin/policies" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d "{
    \"name\": \"stripe-free-tier\",
    \"policy_type\": \"rate_limit\",
    \"tenant_id\": \"$TENANT_ID\",
    \"scope\": \"api\",
    \"config\": {
      \"requests_per_minute\": 100,
      \"burst_size\": 20,
      \"strategy\": \"sliding_window\"
    },
    \"priority\": 10,
    \"enabled\": true
  }")
FREE_POLICY_ID=$(echo "$FREE_POLICY" | jq -r '.id')

PAID_POLICY=$(curl -sf -X POST "$STOA_URL/v1/admin/policies" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d "{
    \"name\": \"stripe-paid-tier\",
    \"policy_type\": \"rate_limit\",
    \"tenant_id\": \"$TENANT_ID\",
    \"scope\": \"api\",
    \"config\": {
      \"requests_per_minute\": 1000,
      \"burst_size\": 200,
      \"strategy\": \"sliding_window\"
    },
    \"priority\": 10,
    \"enabled\": true
  }")
PAID_POLICY_ID=$(echo "$PAID_POLICY" | jq -r '.id')

# Bind free-tier policy to API
curl -sf -X POST "$STOA_URL/v1/admin/policies/bindings" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d "{
    \"policy_id\": \"$FREE_POLICY_ID\",
    \"api_catalog_id\": \"$API_ID\",
    \"tenant_id\": \"$TENANT_ID\",
    \"enabled\": true
  }" > /dev/null
echo "    Free policy ($FREE_POLICY_ID) bound"
echo "    Paid policy ($PAID_POLICY_ID) created (bind per-consumer)"

# ─────────────────────────────────────────────────────────────────
# Step 5: Create consumers
# ─────────────────────────────────────────────────────────────────
echo "==> [5/7] Creating consumers..."

FREE_CONSUMER=$(curl -sf -X POST "$STOA_URL/v1/consumers/$TENANT_ID" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d '{
    "external_id": "demo-free-user",
    "name": "Demo Free User",
    "email": "free@example.com",
    "company": "Acme Corp"
  }')
FREE_CONSUMER_ID=$(echo "$FREE_CONSUMER" | jq -r '.id')

PAID_CONSUMER=$(curl -sf -X POST "$STOA_URL/v1/consumers/$TENANT_ID" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d '{
    "external_id": "demo-paid-user",
    "name": "Demo Paid User",
    "email": "paid@example.com",
    "company": "Beta Inc"
  }')
PAID_CONSUMER_ID=$(echo "$PAID_CONSUMER" | jq -r '.id')
echo "    Free consumer: $FREE_CONSUMER_ID"
echo "    Paid consumer: $PAID_CONSUMER_ID"

# ─────────────────────────────────────────────────────────────────
# Step 6: Create subscriptions (generates API keys)
# ─────────────────────────────────────────────────────────────────
echo "==> [6/7] Creating subscriptions and API keys..."

FREE_SUB=$(curl -sf -X POST "$STOA_URL/v1/subscriptions" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d "{
    \"consumer_id\": \"$FREE_CONSUMER_ID\",
    \"api_catalog_id\": \"$API_ID\",
    \"tenant_id\": \"$TENANT_ID\",
    \"plan\": \"free\"
  }")
FREE_API_KEY=$(echo "$FREE_SUB" | jq -r '.api_key')
FREE_SUB_ID=$(echo "$FREE_SUB" | jq -r '.id')

PAID_SUB=$(curl -sf -X POST "$STOA_URL/v1/subscriptions" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d "{
    \"consumer_id\": \"$PAID_CONSUMER_ID\",
    \"api_catalog_id\": \"$API_ID\",
    \"tenant_id\": \"$TENANT_ID\",
    \"plan\": \"pro\"
  }")
PAID_API_KEY=$(echo "$PAID_SUB" | jq -r '.api_key')
echo "$FREE_SUB_ID" > .subscription_id

# ─────────────────────────────────────────────────────────────────
# Step 7: Save test env
# ─────────────────────────────────────────────────────────────────
echo "==> [7/7] Saving test environment..."
cat > .env.test <<EOF
STOA_URL=$STOA_URL
TENANT_ID=$TENANT_ID
API_ID=$API_ID
FREE_API_KEY=$FREE_API_KEY
FREE_SUB_ID=$FREE_SUB_ID
PAID_API_KEY=$PAID_API_KEY
EOF

echo ""
echo "✅ Setup complete!"
echo ""
echo "Test commands:"
echo "  source .env.test"
echo "  curl -H \"X-API-Key: \$FREE_API_KEY\" \$STOA_URL/stripe/v1/charges"
echo "  curl -H \"X-API-Key: \$PAID_API_KEY\" \$STOA_URL/stripe/v1/charges"
echo ""
echo "Rate limit test (free tier, 101 requests):"
echo "  for i in \$(seq 1 101); do"
echo "    curl -s -o /dev/null -w \"%{http_code}\\n\" -H \"X-API-Key: \$FREE_API_KEY\" \$STOA_URL/stripe/v1/charges"
echo "  done"
