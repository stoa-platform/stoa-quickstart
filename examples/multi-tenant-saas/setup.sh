#!/usr/bin/env bash
# Provision 3 isolated tenants on a single STOA gateway instance
set -euo pipefail

STOA_URL="${STOA_URL:-http://localhost:8080}"
ADMIN_USER="${STOA_ADMIN_USER:-admin}"
ADMIN_PASS="${STOA_ADMIN_PASS:-admin}"

# Parse flags
ADD_TENANT=""
NEW_PLAN="startup"
NEW_UPSTREAM=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --add-tenant) ADD_TENANT="$2"; shift 2 ;;
    --plan)       NEW_PLAN="$2"; shift 2 ;;
    --upstream)   NEW_UPSTREAM="$2"; shift 2 ;;
    *) echo "Unknown flag: $1"; exit 1 ;;
  esac
done

echo "==> STOA Multi-Tenant SaaS Setup"
echo ""

# ─────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────
TOKEN=""
AUTH=""

authenticate() {
  TOKEN=$(curl -sf -X POST "$STOA_URL/v1/auth/token" \
    -H "Content-Type: application/json" \
    -d "{\"username\": \"$ADMIN_USER\", \"password\": \"$ADMIN_PASS\"}" \
    | jq -r '.access_token')
  AUTH="Authorization: Bearer $TOKEN"
}

provision_tenant() {
  local NAME="$1" DISPLAY="$2" UPSTREAM="$3" RATE_LIMIT="$4"

  echo "  → Provisioning $NAME..."

  TENANT_ID=$(curl -sf -X POST "$STOA_URL/v1/tenants" \
    -H "$AUTH" -H "Content-Type: application/json" \
    -d "{\"name\": \"$NAME\", \"display_name\": \"$DISPLAY\", \"plan\": \"pro\"}" \
    | jq -r '.id')

  API_ID=$(curl -sf -X POST "$STOA_URL/v1/tenants/$TENANT_ID/apis" \
    -H "$AUTH" -H "Content-Type: application/json" \
    -d "{
      \"name\": \"${NAME}-api\",
      \"display_name\": \"${DISPLAY} API\",
      \"version\": \"v1\",
      \"upstream_url\": \"$UPSTREAM\",
      \"base_path\": \"/$NAME\",
      \"description\": \"$DISPLAY backend API\"
    }" | jq -r '.id')

  POLICY_ID=$(curl -sf -X POST "$STOA_URL/v1/admin/policies" \
    -H "$AUTH" -H "Content-Type: application/json" \
    -d "{
      \"name\": \"${NAME}-rate-limit\",
      \"policy_type\": \"rate_limit\",
      \"tenant_id\": \"$TENANT_ID\",
      \"scope\": \"api\",
      \"config\": {\"requests_per_minute\": $RATE_LIMIT, \"burst_size\": $(( RATE_LIMIT / 5 )), \"strategy\": \"sliding_window\"},
      \"priority\": 10,
      \"enabled\": true
    }" | jq -r '.id')

  curl -sf -X POST "$STOA_URL/v1/admin/policies/bindings" \
    -H "$AUTH" -H "Content-Type: application/json" \
    -d "{\"policy_id\": \"$POLICY_ID\", \"api_catalog_id\": \"$API_ID\", \"tenant_id\": \"$TENANT_ID\", \"enabled\": true}" > /dev/null

  CONSUMER_ID=$(curl -sf -X POST "$STOA_URL/v1/consumers/$TENANT_ID" \
    -H "$AUTH" -H "Content-Type: application/json" \
    -d "{
      \"external_id\": \"${NAME}-user-1\",
      \"name\": \"${DISPLAY} Demo User\",
      \"email\": \"user@${NAME}.example.com\"
    }" | jq -r '.id')

  API_KEY=$(curl -sf -X POST "$STOA_URL/v1/subscriptions" \
    -H "$AUTH" -H "Content-Type: application/json" \
    -d "{\"consumer_id\": \"$CONSUMER_ID\", \"api_catalog_id\": \"$API_ID\", \"tenant_id\": \"$TENANT_ID\"}" \
    | jq -r '.api_key')

  echo "    ID: $TENANT_ID | API: $API_ID | Key: ${API_KEY:0:8}..."
  echo "TENANT_ID=$TENANT_ID" >> .env.test
  echo "${NAME^^}_KEY=$API_KEY" >> .env.test
  echo "${NAME^^}_ID=$TENANT_ID" >> .env.test
}

# ─────────────────────────────────────────────────────────────────
# Main: provision 3 tenants or add one
# ─────────────────────────────────────────────────────────────────
authenticate

if [[ -n "$ADD_TENANT" ]]; then
  UPSTREAM="${NEW_UPSTREAM:-http://localhost:8000}"
  case "$NEW_PLAN" in
    startup)    RATE=50 ;;
    scaleup)    RATE=500 ;;
    enterprise) RATE=5000 ;;
    *)          RATE=100 ;;
  esac
  > ".env.test.$ADD_TENANT"
  provision_tenant "$ADD_TENANT" "$(echo "$ADD_TENANT" | sed 's/-/ /g' | awk '{for(i=1;i<=NF;i++){$i=toupper(substr($i,1,1)) tolower(substr($i,2))};print}')" "$UPSTREAM" "$RATE"
  echo ""
  echo "✅ Tenant '$ADD_TENANT' provisioned!"
  echo "Test: source .env.test.$ADD_TENANT && curl -H \"X-API-Key: \$${ADD_TENANT^^}_KEY\" $STOA_URL/$ADD_TENANT/get"
else
  echo "==> Provisioning 3 tenants..."
  > .env.test
  provision_tenant "tenant-a" "Startup Corp (Tenant A)"    "http://tenant-a-backend:8000" 50
  provision_tenant "tenant-b" "Scaleup Inc (Tenant B)"     "http://tenant-b-backend:8000" 500
  provision_tenant "tenant-c" "Enterprise Ltd (Tenant C)"  "http://tenant-c-backend:8000" 5000
  echo ""
  echo "✅ 3 tenants provisioned!"
  echo ""
  echo "Verify isolation:"
  echo "  source .env.test"
  echo "  curl -H \"X-API-Key: \$TENANT_A_KEY\" $STOA_URL/tenant-a/get   # 200"
  echo "  curl -H \"X-API-Key: \$TENANT_A_KEY\" $STOA_URL/tenant-b/get   # 403"
  echo ""
  echo "Rate limit test (startup tier: 50/min):"
  echo "  for i in \$(seq 1 55); do curl -s -o /dev/null -w \"%{http_code}\\n\" -H \"X-API-Key: \$TENANT_A_KEY\" $STOA_URL/tenant-a/get; done"
fi
