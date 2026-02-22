# STOA Examples

Five self-contained examples showing STOA in real-world scenarios.
Each example runs independently — start the base quickstart first, then pick your example.

## Prerequisites

All examples require the base STOA quickstart running:

```bash
# From the repo root
docker compose up -d
# Wait ~30 seconds for all services to start
curl -s http://localhost:8080/health | jq '.status'
# → "ok"
```

## Examples

| Example | Use Case | Key Feature |
|---------|----------|-------------|
| [stripe-api-proxy](./stripe-api-proxy/) | SaaS monetization | Per-consumer rate limits + API key rotation |
| [notion-mcp-bridge](./notion-mcp-bridge/) | AI agent tools | Notion as MCP tool for Claude/GPT agents |
| [multi-tenant-saas](./multi-tenant-saas/) | Platform engineering | Isolated tenants on one gateway instance |
| [jwt-auth-gateway](./jwt-auth-gateway/) | Auth offloading | JWT validation + RBAC without backend code |
| [openai-proxy](./openai-proxy/) | AI cost control | Token budgets + per-project usage tracking |

## How Examples Are Structured

Each example contains:

```
examples/<name>/
├── README.md          — Full guide: setup, test commands, config reference
├── docker-compose.yml — Mock upstream service (Stripe, Notion, OpenAI, etc.)
├── setup.sh           — Configures STOA via CP API (curl-based)
└── .env.example       — Environment variables template
```

The `docker-compose.yml` in each example joins the `stoa-quickstart_default` network
so mock services can be reached by the STOA gateway container.

## Running an Example

```bash
# 1. Start base quickstart (if not already running)
docker compose up -d   # from repo root

# 2. Go to example directory
cd examples/stripe-api-proxy

# 3. Start mock upstream
docker compose up -d

# 4. Configure STOA
cp .env.example .env   # optional: edit for real API keys
chmod +x setup.sh
./setup.sh

# 5. Test
source .env.test
curl -H "X-API-Key: $FREE_API_KEY" http://localhost:8080/stripe/v1/charges
```

## Further Reading

- [Hello World Tutorial](https://docs.gostoa.dev/blog/hello-world-api-gateway-freelancer)
- [API Security Series](https://docs.gostoa.dev/blog/freelancer-api-security-part-1-vulnerabilities)
- [STOA Concepts: Multi-Tenancy](https://docs.gostoa.dev/docs/concepts/multi-tenant)
- [Full Documentation](https://docs.gostoa.dev)
