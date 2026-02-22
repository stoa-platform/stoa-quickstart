# Example: Multi-Tenant API Gateway for SaaS

Run a single STOA instance serving multiple isolated tenants. Each tenant gets their own
API catalog, consumers, rate limits, and audit trail — with zero data leakage between tenants.

## What This Example Shows

- Create 3 isolated tenants (startup, scaleup, enterprise) on one gateway
- Per-tenant API catalogs with different upstream backends
- Per-tenant rate limits that match their pricing plan
- Tenant isolation: Consumer A from Tenant 1 cannot access Tenant 2's APIs
- Gateway-level admin API vs tenant-scoped operations

## Prerequisites

- STOA quickstart running (`docker compose up -d` from repo root)
- `curl` and `jq` installed

## Architecture

```
Internet
   │
   └── STOA Gateway :8080
          │
          ├── /tenant-a/* ──→ Startup Backend   :4010
          ├── /tenant-b/* ──→ Scaleup Backend   :4011
          └── /tenant-c/* ──→ Enterprise Backend :4012
                │
                ├── Tenant A: 50 req/min, 2 consumers
                ├── Tenant B: 500 req/min, 10 consumers
                └── Tenant C: unlimited, 100 consumers
```

## Quick Start

### 1. Start mock backends

```bash
docker compose up -d
```

This starts 3 independent HTTP echo servers simulating different tenant backends.

### 2. Provision all tenants

```bash
chmod +x setup.sh
./setup.sh
```

### 3. Verify tenant isolation

```bash
source .env.test

# Tenant A consumer can access Tenant A's API
curl -H "X-API-Key: $TENANT_A_KEY" http://localhost:8080/tenant-a/api/users
# → 200 OK

# Tenant A consumer CANNOT access Tenant B's API
curl -H "X-API-Key: $TENANT_A_KEY" http://localhost:8080/tenant-b/api/users
# → 403 Forbidden (consumer not subscribed to this API)

# Tenant B consumer accesses Tenant B's API
curl -H "X-API-Key: $TENANT_B_KEY" http://localhost:8080/tenant-b/api/users
# → 200 OK
```

### 4. Verify per-tenant rate limits

```bash
# Tenant A (startup plan: 50/min)
for i in $(seq 1 55); do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "X-API-Key: $TENANT_A_KEY" http://localhost:8080/tenant-a/api/ping)
  echo "Request $i: $STATUS"
done
# Request 51+ returns 429

# Tenant B (scaleup plan: 500/min) — same test, no 429 until 501
```

### 5. Per-tenant audit logs

```bash
# Each tenant sees only their own traffic
curl -s "http://localhost:8080/v1/audit/$TENANT_A_ID" | jq '.items | length'
curl -s "http://localhost:8080/v1/audit/$TENANT_B_ID" | jq '.items | length'
```

## Tenant Plans

| Plan | Rate Limit | Max Consumers | SLA |
|------|------------|---------------|-----|
| Startup | 50 req/min | 5 | Best-effort |
| Scaleup | 500 req/min | 50 | 99.5% |
| Enterprise | 5000 req/min | Unlimited | 99.9% |

## Adding a New Tenant

```bash
# The setup.sh --add-tenant flag provisions a new tenant on the fly
./setup.sh --add-tenant my-new-tenant --plan startup --upstream http://my-backend:8000
source .env.test.my-new-tenant
curl -H "X-API-Key: $MY_NEW_TENANT_KEY" http://localhost:8080/my-new-tenant/api/ping
```

## Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | 3 mock backend services |
| `setup.sh` | Tenant provisioning script |
| `.env.example` | Environment template |

## Next Steps

- [JWT Auth Gateway Example](../jwt-auth-gateway/) — add JWT auth per tenant
- [Stripe API Proxy Example](../stripe-api-proxy/) — monetize with per-consumer limits
- [STOA Concepts: Multi-Tenancy](https://docs.gostoa.dev/docs/concepts/multi-tenant)
