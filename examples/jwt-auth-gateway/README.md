# Example: JWT Validation + RBAC Gateway

Enforce JWT authentication and role-based access control at the gateway layer, before requests
reach your backend. Zero auth code in your services.

## What This Example Shows

- Validate JWTs issued by any OIDC provider (Keycloak, Auth0, Cognito)
- RBAC at gateway level: `admin` role vs `reader` role get different access
- Reject expired, tampered, or missing tokens — 401 before backend sees the request
- Pass verified claims to backend via `X-User-Id`, `X-User-Email`, `X-Roles` headers

## Prerequisites

- STOA quickstart running (includes Keycloak at `http://localhost:8081`)
- `curl` and `jq` installed

## Architecture

```
Client
  │
  └── JWT Bearer Token ──→ STOA Gateway :8080
                                 │
                          [JWT Validation]
                          - Signature verified (JWKS from Keycloak)
                          - exp not past
                          - iss matches
                                 │
                    ┌────────────┴────────────┐
                 admin role               reader role
                    │                         │
            /api/admin/*               /api/data/* only
            /api/data/*                (403 on /admin/*)
                    │
              Backend API :4020
              (receives X-User-Id, X-Roles headers)
```

## Quick Start

### 1. Start mock backend

```bash
docker compose up -d
```

### 2. Configure STOA with JWT policy

```bash
chmod +x setup.sh
./setup.sh
```

### 3. Get test tokens

```bash
source .env.test

# Get admin token
ADMIN_TOKEN=$(curl -sf -X POST \
  "http://localhost:8081/realms/stoa/protocol/openid-connect/token" \
  -d "grant_type=password&client_id=stoa-cli&username=admin&password=admin&scope=openid" \
  | jq -r '.access_token')

# Get reader token
READER_TOKEN=$(curl -sf -X POST \
  "http://localhost:8081/realms/stoa/protocol/openid-connect/token" \
  -d "grant_type=password&client_id=stoa-cli&username=reader&password=reader&scope=openid" \
  | jq -r '.access_token')
```

### 4. Test JWT enforcement

```bash
# No token → 401
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/jwt-demo/api/data
# → 401

# Valid reader token → 200
curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $READER_TOKEN" \
  http://localhost:8080/jwt-demo/api/data
# → 200

# Reader tries admin endpoint → 403
curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $READER_TOKEN" \
  http://localhost:8080/jwt-demo/api/admin/users
# → 403

# Admin token → 200 on admin endpoint
curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  http://localhost:8080/jwt-demo/api/admin/users
# → 200
```

### 5. Verify claim forwarding

```bash
# Backend receives user claims as headers
curl -s \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  http://localhost:8080/jwt-demo/get \
  | jq '.headers | {user_id: ."X-User-Id", email: ."X-User-Email", roles: ."X-Roles"}'
```

## JWT Policy Configuration

```bash
POST /v1/admin/policies
{
  "name": "jwt-validation",
  "policy_type": "jwt_auth",
  "config": {
    "jwks_uri": "http://keycloak:8080/realms/stoa/protocol/openid-connect/certs",
    "issuer": "http://localhost:8081/realms/stoa",
    "audience": ["stoa-api"],
    "required_claims": ["sub", "email"],
    "claim_headers": {
      "sub": "X-User-Id",
      "email": "X-User-Email",
      "realm_access.roles": "X-Roles"
    }
  }
}
```

## RBAC Policy Configuration

```bash
POST /v1/admin/policies
{
  "name": "rbac-admin-path",
  "policy_type": "rbac",
  "config": {
    "rules": [
      {"path": "/api/admin/*", "required_roles": ["admin"], "methods": ["GET", "POST", "PUT", "DELETE"]},
      {"path": "/api/data/*",  "required_roles": ["reader", "admin"], "methods": ["GET"]},
      {"path": "/api/data/*",  "required_roles": ["admin"], "methods": ["POST", "PUT", "DELETE"]}
    ],
    "role_claim": "X-Roles",
    "deny_by_default": true
  }
}
```

## Using Auth0 or AWS Cognito

Change the `jwks_uri` and `issuer` in the JWT policy:

```bash
# Auth0
"jwks_uri": "https://YOUR_DOMAIN.auth0.com/.well-known/jwks.json"
"issuer": "https://YOUR_DOMAIN.auth0.com/"

# AWS Cognito
"jwks_uri": "https://cognito-idp.eu-west-1.amazonaws.com/eu-west-1_POOL_ID/.well-known/jwks.json"
"issuer": "https://cognito-idp.eu-west-1.amazonaws.com/eu-west-1_POOL_ID"
```

## Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Mock backend (httpbin) |
| `setup.sh` | JWT + RBAC policy configuration |
| `keycloak/realm-export.json` | Test realm with admin + reader users |
| `.env.example` | Environment template |

## Next Steps

- [API Security: Rate Limiting](https://docs.gostoa.dev/blog/freelancer-api-security-part-2-rate-limiting)
- [API Security: Audit Trails](https://docs.gostoa.dev/blog/freelancer-api-security-part-3-audit-trails)
- [Multi-Tenant SaaS Example](../multi-tenant-saas/)
