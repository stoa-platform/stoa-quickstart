# Example: OpenAI API Proxy with Token Budgets

Stop surprise AI bills. Proxy OpenAI through STOA to enforce per-consumer token budgets,
track usage by project, and get audit logs of every AI call.

## What This Example Shows

- Proxy OpenAI API through STOA with per-consumer rate limiting
- Daily token budget enforcement (free tier: 10K tokens/day, pro: 100K/day)
- Usage tracking per project/consumer via audit logs
- Cost estimation from token counts
- Request/response logging for AI governance

## Prerequisites

- STOA quickstart running (`docker compose up -d` from repo root)
- OpenAI API key (or use mock server included for offline testing)
- `curl` and `jq` installed

## Architecture

```
Your App / Agent
      │
      └── POST /openai/v1/chat/completions ──→ STOA Gateway
                                                      │
                                               [Rate Limit Check]
                                               [Token Budget Check]
                                               [Request Logging]
                                                      │
                                              OpenAI API (or mock)
                                                      │
                                               [Response Logging]
                                               [Token Count Tracking]
                                                      │
                                              Your App receives response
```

## Quick Start

### 1. Start mock OpenAI server

```bash
docker compose up -d
```

### 2. Set your OpenAI key (optional for mock)

```bash
cp .env.example .env
# Edit .env: set OPENAI_API_KEY=sk-your-key for real API
source .env
```

### 3. Configure STOA

```bash
chmod +x setup.sh
./setup.sh
```

### 4. Make your first proxied AI call

```bash
source .env.test

# Free-tier project (10K tokens/day)
curl -s -X POST http://localhost:8080/openai/v1/chat/completions \
  -H "X-API-Key: $FREE_PROJECT_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4o-mini",
    "messages": [{"role": "user", "content": "What is an API gateway?"}],
    "max_tokens": 200
  }' | jq '.choices[0].message.content'
```

### 5. Check token usage

```bash
TENANT_ID=$(cat .tenant_id)

# Per-consumer usage
curl -s "http://localhost:8080/v1/audit/$TENANT_ID?type=ai_completion&limit=10" \
  | jq '.items[] | {
      project: .consumer_id,
      model: .metadata.model,
      tokens_used: .metadata.total_tokens,
      cost_usd: (.metadata.total_tokens * 0.0000015 | . * 1000 | round / 1000)
    }'

# Daily total per project
curl -s "http://localhost:8080/v1/consumers/$TENANT_ID/$FREE_PROJECT_ID/usage" \
  | jq '{daily_tokens: .tokens_today, daily_limit: .token_limit, pct_used: .usage_pct}'
```

### 6. Trigger token budget enforcement

```bash
# Make many large requests until budget is exhausted
for i in $(seq 1 20); do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST http://localhost:8080/openai/v1/chat/completions \
    -H "X-API-Key: $FREE_PROJECT_KEY" \
    -H "Content-Type: application/json" \
    -d '{"model": "gpt-4o-mini", "messages": [{"role":"user","content":"Write a 500-word essay on API gateways"}], "max_tokens": 500}')
  echo "Request $i: $STATUS"
  [[ "$STATUS" == "429" ]] && echo "Budget exhausted!" && break
done
```

## Rate Limit Tiers

| Tier | Requests/min | Daily Tokens | Monthly Est. |
|------|-------------|--------------|-------------|
| Free | 10 | 10,000 | ~$0.015 |
| Pro | 60 | 100,000 | ~$0.15 |
| Team | 200 | 1,000,000 | ~$1.50 |
| Enterprise | 600 | Unlimited | Custom |

## Policy Configuration

```bash
# Request rate limit
POST /v1/admin/policies
{
  "name": "openai-free-requests",
  "policy_type": "rate_limit",
  "config": {
    "requests_per_minute": 10,
    "burst_size": 3,
    "strategy": "sliding_window"
  }
}

# Daily token budget
POST /v1/admin/policies
{
  "name": "openai-free-tokens",
  "policy_type": "token_budget",
  "config": {
    "daily_token_limit": 10000,
    "token_count_header": "X-Token-Count",
    "reset_at": "00:00:00 UTC"
  }
}
```

## AI Governance Use Cases

| Use Case | STOA Feature | Benefit |
|----------|-------------|---------|
| Cost control per team | Token budget per consumer | Stop runaway costs |
| Model access control | RBAC policy on `/v1/chat` vs `/v1/images` | GPT-4 for admins only |
| Prompt audit trail | Request body logging | Compliance, debugging |
| PII in prompts | PII masking policy | GDPR compliance |
| Rate limiting per user | Per-consumer rate limit | Fair use enforcement |

## Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Mock OpenAI server |
| `setup.sh` | STOA configuration script |
| `.env.example` | Environment template |

## Next Steps

- [Notion MCP Bridge Example](../notion-mcp-bridge/) — expose AI tools via MCP
- [Hello World Tutorial](https://docs.gostoa.dev/blog/hello-world-api-gateway-freelancer)
- [API Security: Rate Limiting](https://docs.gostoa.dev/blog/freelancer-api-security-part-2-rate-limiting)
