# Example: Stripe API Proxy with Rate Limiting

Protect your Stripe API usage behind STOA: add per-consumer rate limits, audit every call, and
prevent runaway costs from a single misbehaving client.

## What This Example Shows

- Proxy Stripe's public API through STOA gateway
- Per-consumer rate limits (free tier: 100/min, paid: 1000/min)
- Audit trail of every API call via STOA logs
- API key rotation without client-side changes

## Prerequisites

- STOA quickstart running (`docker compose up -d` from repo root)
- `curl` and `jq` installed
- (Optional) Real Stripe API key for live testing — mock server included for offline use

## Architecture

```
Your App ──→ STOA Gateway :8080/stripe/* ──→ Stripe API (api.stripe.com)
                  │
                  ├── Rate limit: 100 req/min (free-tier consumers)
                  ├── Rate limit: 1000 req/min (paid consumers)
                  └── Audit log: every request recorded
```

## Quick Start

### 1. Start the mock Stripe server (offline mode)

```bash
docker compose up -d
```

This starts a local mock server at `http://localhost:4242` that simulates Stripe responses.

### 2. Configure STOA

```bash
export STOA_URL=http://localhost:8080
chmod +x setup.sh
./setup.sh
```

The setup script:
- Creates a `stripe-proxy` tenant
- Registers the Stripe API in the catalog
- Creates free-tier (100/min) and paid-tier (1000/min) rate limit policies
- Creates two test consumers with API keys

### 3. Test Rate Limiting

```bash
# Free-tier consumer — limited to 100/min
source .env.test
curl -H "X-API-Key: $FREE_API_KEY" "$STOA_URL/stripe/v1/charges"

# Paid-tier consumer — limited to 1000/min
curl -H "X-API-Key: $PAID_API_KEY" "$STOA_URL/stripe/v1/charges"

# Trigger rate limit (run 101 times quickly)
for i in $(seq 1 101); do
  curl -s -o /dev/null -w "%{http_code}\n" \
    -H "X-API-Key: $FREE_API_KEY" \
    "$STOA_URL/stripe/v1/charges"
done
# The 101st request returns 429 Too Many Requests
```

### 4. Check Audit Trail

```bash
TENANT_ID=$(cat .tenant_id)
curl -s "$STOA_URL/v1/audit/$TENANT_ID?limit=10" | jq '.items[] | {timestamp, method, path, status_code, consumer_id}'
```

### 5. Rotate API Key Without Downtime

```bash
SUB_ID=$(cat .subscription_id)
NEW_KEY=$(curl -s -X POST "$STOA_URL/v1/subscriptions/$SUB_ID/rotate-key" | jq -r '.api_key')
echo "New key: $NEW_KEY"
# Old key continues working for 5 minutes (grace period)
```

## Real Stripe Integration

To proxy to the actual Stripe API instead of the mock server:

1. Copy `.env.example` to `.env`
2. Set `STRIPE_API_KEY=sk_test_your_key_here`
3. Update `UPSTREAM_URL` in `setup.sh` to `https://api.stripe.com`
4. Re-run `./setup.sh`

```bash
cp .env.example .env
# Edit .env with your Stripe key
./setup.sh --upstream https://api.stripe.com
```

> **Note**: When using the real Stripe API, your STOA instance needs HTTPS. For local testing,
> the mock server is recommended.

## Rate Limit Tiers

| Tier | Rate | Use Case |
|------|------|----------|
| Free | 100 req/min | Prototyping, testing |
| Pro | 500 req/min | Small production apps |
| Enterprise | 1000 req/min | High-volume consumers |
| Custom | Configurable | Enterprise contracts |

## Policy Configuration Reference

The setup script creates these policies:

```bash
# Free-tier policy
POST /v1/admin/policies
{
  "name": "stripe-free-tier",
  "policy_type": "rate_limit",
  "config": {
    "requests_per_minute": 100,
    "burst_size": 20,
    "strategy": "sliding_window"
  }
}

# Bind to API
POST /v1/admin/policies/bindings
{
  "policy_id": "<policy_id>",
  "api_catalog_id": "<api_id>",
  "tenant_id": "<tenant_id>"
}
```

## Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Mock Stripe server (httpbin) |
| `setup.sh` | STOA configuration script |
| `.env.example` | Environment variable template |
| `stripe-mock/` | Mock response definitions |

## Next Steps

- [STOA Security Tutorial: Rate Limiting Deep-Dive](/blog/freelancer-api-security-part-2-rate-limiting)
- [Hello World: Your First API Gateway](/blog/hello-world-api-gateway-freelancer)
- [Multi-Tenant SaaS Example](../multi-tenant-saas/)
