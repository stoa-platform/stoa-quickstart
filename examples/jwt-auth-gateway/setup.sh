#!/usr/bin/env bash
# Setup: JWT validation + RBAC gateway using Keycloak from base quickstart
set -euo pipefail

STOA_URL="${STOA_URL:-http://localhost:8080}"
KC_URL="${KEYCLOAK_URL:-http://localhost:8081}"
KC_REALM="${KEYCLOAK_REALM:-stoa}"
ADMIN_USER="${STOA_ADMIN_USER:-admin}"
ADMIN_PASS="${STOA_ADMIN_PASS:-admin}"

echo "==> STOA JWT Auth Gateway Setup"
echo "    STOA:     $STOA_URL"
echo "    Keycloak: $KC_URL/realms/$KC_REALM"
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
# Step 2: Create test users in Keycloak (admin + reader)
# ─────────────────────────────────────────────────────────────────
echo "==> [2/7] Creating Keycloak test users..."
KC_ADMIN_TOKEN=$(curl -sf -X POST "$KC_URL/realms/master/protocol/openid-connect/token" \
  -d "grant_type=password&client_id=admin-cli&username=admin&password=admin" \
  | jq -r '.access_token')
KC_AUTH="Authorization: Bearer $KC_ADMIN_TOKEN"

# Create reader role (admin role likely exists already)
curl -sf -X POST "$KC_URL/admin/realms/$KC_REALM/roles" \
  -H "$KC_AUTH" -H "Content-Type: application/json" \
  -d '{"name": "reader", "description": "Read-only access"}' 2>/dev/null || true

# Create reader user
curl -sf -X POST "$KC_URL/admin/realms/$KC_REALM/users" \
  -H "$KC_AUTH" -H "Content-Type: application/json" \
  -d '{
    "username": "reader",
    "email": "reader@example.com",
    "enabled": true,
    "credentials": [{"type": "password", "value": "reader", "temporary": false}]
  }' 2>/dev/null || true

READER_USER_ID=$(curl -sf "$KC_URL/admin/realms/$KC_REALM/users?username=reader" \
  -H "$KC_AUTH" | jq -r '.[0].id')
READER_ROLE_ID=$(curl -sf "$KC_URL/admin/realms/$KC_REALM/roles/reader" \
  -H "$KC_AUTH" | jq -r '.id')

# Assign reader role
curl -sf -X POST "$KC_URL/admin/realms/$KC_REALM/users/$READER_USER_ID/role-mappings/realm" \
  -H "$KC_AUTH" -H "Content-Type: application/json" \
  -d "[{\"id\": \"$READER_ROLE_ID\", \"name\": \"reader\"}]" 2>/dev/null || true

echo "    Users: admin (password: admin), reader (password: reader)"

# ─────────────────────────────────────────────────────────────────
# Step 3: Create tenant and API
# ─────────────────────────────────────────────────────────────────
echo "==> [3/7] Creating tenant and API..."
TENANT_ID=$(curl -sf -X POST "$STOA_URL/v1/tenants" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d '{"name": "jwt-demo", "display_name": "JWT Auth Demo", "plan": "pro"}' \
  | jq -r '.id')

API_ID=$(curl -sf -X POST "$STOA_URL/v1/tenants/$TENANT_ID/apis" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d '{
    "name": "jwt-demo-api",
    "display_name": "JWT Demo API",
    "version": "v1",
    "upstream_url": "http://jwt-demo-backend:8000",
    "base_path": "/jwt-demo",
    "description": "API with JWT auth and RBAC"
  }' | jq -r '.id')
echo "    Tenant: $TENANT_ID | API: $API_ID"
echo "$TENANT_ID" > .tenant_id

# ─────────────────────────────────────────────────────────────────
# Step 4: JWT validation policy
# ─────────────────────────────────────────────────────────────────
echo "==> [4/7] Creating JWT validation policy..."
JWT_POLICY_ID=$(curl -sf -X POST "$STOA_URL/v1/admin/policies" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d "{
    \"name\": \"jwt-validation\",
    \"policy_type\": \"jwt_auth\",
    \"tenant_id\": \"$TENANT_ID\",
    \"scope\": \"api\",
    \"config\": {
      \"jwks_uri\": \"http://keycloak:8080/realms/$KC_REALM/protocol/openid-connect/certs\",
      \"issuer\": \"$KC_URL/realms/$KC_REALM\",
      \"required_claims\": [\"sub\", \"email\"],
      \"claim_headers\": {
        \"sub\": \"X-User-Id\",
        \"email\": \"X-User-Email\",
        \"realm_access.roles\": \"X-Roles\"
      }
    },
    \"priority\": 5,
    \"enabled\": true
  }" | jq -r '.id')

curl -sf -X POST "$STOA_URL/v1/admin/policies/bindings" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d "{\"policy_id\": \"$JWT_POLICY_ID\", \"api_catalog_id\": \"$API_ID\", \"tenant_id\": \"$TENANT_ID\", \"enabled\": true}" > /dev/null

# ─────────────────────────────────────────────────────────────────
# Step 5: RBAC policy
# ─────────────────────────────────────────────────────────────────
echo "==> [5/7] Creating RBAC policy..."
RBAC_POLICY_ID=$(curl -sf -X POST "$STOA_URL/v1/admin/policies" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d "{
    \"name\": \"rbac-admin-paths\",
    \"policy_type\": \"rbac\",
    \"tenant_id\": \"$TENANT_ID\",
    \"scope\": \"api\",
    \"config\": {
      \"rules\": [
        {\"path\": \"/api/admin/*\", \"required_roles\": [\"admin\"], \"methods\": [\"GET\", \"POST\", \"PUT\", \"DELETE\"]},
        {\"path\": \"/api/data/*\",  \"required_roles\": [\"reader\", \"admin\"], \"methods\": [\"GET\"]},
        {\"path\": \"/api/data/*\",  \"required_roles\": [\"admin\"], \"methods\": [\"POST\", \"PUT\", \"DELETE\"]}
      ],
      \"role_claim\": \"X-Roles\",
      \"deny_by_default\": true
    },
    \"priority\": 10,
    \"enabled\": true
  }" | jq -r '.id')

curl -sf -X POST "$STOA_URL/v1/admin/policies/bindings" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d "{\"policy_id\": \"$RBAC_POLICY_ID\", \"api_catalog_id\": \"$API_ID\", \"tenant_id\": \"$TENANT_ID\", \"enabled\": true}" > /dev/null
echo "    JWT policy: $JWT_POLICY_ID | RBAC policy: $RBAC_POLICY_ID"

# ─────────────────────────────────────────────────────────────────
# Steps 6-7: Consumer + subscription + save env
# ─────────────────────────────────────────────────────────────────
echo "==> [6/7] Creating service account consumer..."
CONSUMER_ID=$(curl -sf -X POST "$STOA_URL/v1/consumers/$TENANT_ID" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d '{"external_id": "service-account", "name": "Service Account", "email": "sa@example.com"}' \
  | jq -r '.id')

API_KEY=$(curl -sf -X POST "$STOA_URL/v1/subscriptions" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d "{\"consumer_id\": \"$CONSUMER_ID\", \"api_catalog_id\": \"$API_ID\", \"tenant_id\": \"$TENANT_ID\"}" \
  | jq -r '.api_key')

echo "==> [7/7] Saving test environment..."
cat > .env.test <<EOF
STOA_URL=$STOA_URL
KC_URL=$KC_URL
KC_REALM=$KC_REALM
TENANT_ID=$TENANT_ID
API_ID=$API_ID
SERVICE_API_KEY=$API_KEY
EOF

echo ""
echo "✅ Setup complete!"
echo ""
echo "Get tokens:"
echo "  source .env.test"
echo "  ADMIN_TOKEN=\$(curl -sf -X POST \$KC_URL/realms/\$KC_REALM/protocol/openid-connect/token \\"
echo "    -d 'grant_type=password&client_id=stoa-cli&username=admin&password=admin&scope=openid' | jq -r '.access_token')"
echo "  READER_TOKEN=\$(curl -sf -X POST \$KC_URL/realms/\$KC_REALM/protocol/openid-connect/token \\"
echo "    -d 'grant_type=password&client_id=stoa-cli&username=reader&password=reader&scope=openid' | jq -r '.access_token')"
echo ""
echo "Test:"
echo "  curl -s -o /dev/null -w '%{http_code}' \$STOA_URL/jwt-demo/get  # → 401 (no token)"
echo "  curl -s -o /dev/null -w '%{http_code}' -H \"Authorization: Bearer \$READER_TOKEN\" \$STOA_URL/jwt-demo/api/data/items  # → 200"
echo "  curl -s -o /dev/null -w '%{http_code}' -H \"Authorization: Bearer \$READER_TOKEN\" \$STOA_URL/jwt-demo/api/admin/users  # → 403"
